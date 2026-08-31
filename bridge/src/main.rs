//! Phosphor Bridge
//! ===============
//!
//! Single binary that runs as a long-lived service on the phone.
//! Talks Android System APIs / Termux:API / DBus on one side, exposes
//! a JSON-over-WebSocket surface on the other that `shell.html` calls
//! via `window.phosphor.call(method, params)`.
//!
//! Architecture
//! ------------
//!
//!     ┌──────────────┐   ws://127.0.0.1:7777/ws   ┌────────────────┐
//!     │  shell.html  │ ◀──────────────────────▶│  phosphor-     │
//!     │  (Vanadium)  │     JSON-RPC over WS    │  bridge        │
//!     └──────────────┘                         └───────┬────────┘
//!                                                      │
//!                                  ┌───────────────────┼─────────────┐
//!                                  ▼                   ▼             ▼
//!                            Android System       Termux:API     DBus
//!                            (Telephony/SMS/      (sensors,      (modem
//!                             Location via        battery,      proxy on
//!                             IPC helper)         wifi, bt,     AOSP)
//!                                                  clip)
//!
//! The privileged IPC helper (`phosphor-ipc`) is a separate small Java/Kotlin
//! program that runs as a system app and is the only thing that touches
//! `ITelephony`, `LocationManager`, `WindowManager.setScreenIdleTimeout`,
//! `IPowerManager`, etc. directly — those APIs require either system uid
//! or a signature-level permission the bridge can't get standalone.
//! The bridge spawns that helper as a subprocess and pipes JSON over stdin/stdout.
use std::sync::Arc;

use anyhow::{Context, Result};
use axum::{
    extract::ws::{Message, WebSocket, WebSocketUpgrade},
    response::IntoResponse,
    routing::get,
    Router,
};
use futures_util::{SinkExt, StreamExt};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use tower_http::cors::CorsLayer;
use tokio::sync::mpsc;

mod handlers;
mod state;

use state::AppState;

/// JSON-RPC 2.0 envelope. `id` is optional for notifications.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RpcRequest {
    #[serde(default)]
    pub id: Option<String>,
    pub method: String,
    #[serde(default)]
    pub params: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RpcResponse {
    pub id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<RpcError>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RpcError {
    pub code: i32,
    pub message: String,
}

impl RpcResponse {
    fn ok(id: Option<String>, result: Value) -> Self {
        Self { id, result: Some(result), error: None }
    }
    fn err(id: Option<String>, code: i32, message: impl Into<String>) -> Self {
        Self { id, result: None, error: Some(RpcError { code, message: message.into() }) }
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "phosphor_bridge=info,info".into()),
        )
        .init();

    tracing::info!("phosphor-bridge starting");

    // AppState::new() already returns Arc<AppState> — no second wrap.
    let state = AppState::new()
        .await
        .context("initialising app state (DBus / Termux:API)")?;

    // Periodic background tasks: battery refresh, geofence polling.
    handlers::spawn_background_tasks(state.clone());

    let app = Router::new()
        .route("/ws", get(ws_handler))
        .route("/health", get(health))
        .layer(CorsLayer::permissive()) // localhost only
        .with_state(state);

    let listener = tokio::net::TcpListener::bind("127.0.0.1:7777")
        .await
        .context("binding 127.0.0.1:7777")?;
    tracing::info!("phosphor-bridge listening on ws://127.0.0.1:7777/ws");

    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await?;

    Ok(())
}

async fn shutdown_signal() {
    let _ = tokio::signal::ctrl_c().await;
    tracing::info!("phosphor-bridge shutting down");
}

async fn health() -> impl IntoResponse {
    axum::Json(serde_json::json!({ "status": "ok", "service": "phosphor-bridge" }))
}

/// WebSocket upgrade. One connection = one browser tab.
async fn ws_handler(
    ws: WebSocketUpgrade,
    axum::extract::State(state): axum::extract::State<Arc<AppState>>,
) -> impl IntoResponse {
    ws.on_upgrade(move |socket| handle_socket(socket, state))
}

async fn handle_socket(socket: WebSocket, state: Arc<AppState>) {
    let conn_id = uuid::Uuid::new_v4().to_string();
    let (mut sender, mut receiver) = socket.split();

    // Subscribe to background-task events for the lifetime of this connection.
    let mut events = state.event_tx.subscribe();

    // Per-connection mpsc for *RPC responses only* — background events use the
    // broadcast channel, RPC responses go back to the originating socket so
    // callers don't see each other's replies.
    let (resp_tx, mut resp_rx) = mpsc::channel::<String>(32);

    let writer_conn_id = conn_id.clone();
    let writer = tokio::spawn(async move {
        loop {
            tokio::select! {
                biased;
                // RPC responses for THIS connection only.
                Some(json) = resp_rx.recv() => {
                    if sender.send(Message::Text(json.into())).await.is_err() {
                        break;
                    }
                }
                // Background events (battery refresh, geofence fired, etc.) on
                // the broadcast channel — every browser sees them.
                event = events.recv() => {
                    match event {
                        Ok(value) => {
                            let payload = serde_json::to_string(&value).unwrap_or_default();
                            if sender.send(Message::Text(payload.into())).await.is_err() {
                                break;
                            }
                        }
                        Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
                        Err(_) => break,
                    }
                }
                else => break,
            }
        }
        tracing::info!(conn = %writer_conn_id, "writer exiting");
    });

    tracing::info!(conn = %conn_id, "browser connected");

    while let Some(msg) = receiver.next().await {
        let Ok(msg) = msg else { break };
        match msg {
            Message::Text(t) => {
                let req: RpcRequest = match serde_json::from_str(&t) {
                    Ok(r) => r,
                    Err(e) => {
                        let resp = RpcResponse::err(None, -32700, format!("parse: {e}"));
                        let json = serde_json::to_string(&resp).unwrap_or_default();
                        let _ = resp_tx.send(json).await;
                        continue;
                    }
                };
                // Dispatch + reply go back on THIS socket only.
                let resp = handlers::dispatch(state.clone(), req).await;
                let json = serde_json::to_string(&resp).unwrap_or_default();
                if resp_tx.send(json).await.is_err() {
                    break;
                }
            }
            Message::Close(_) => break,
            _ => {}
        }
    }

    tracing::info!(conn = %conn_id, "browser disconnected");
    writer.abort();
}
