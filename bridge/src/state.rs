//! Shared application state — DBus connection, device cache, event broadcast.
use std::sync::Arc;
use std::time::Instant;

use serde_json::Value;
use tokio::sync::{broadcast, RwLock};
use zbus::Connection;

/// Cached device state that the LLM context can include cheaply.
#[derive(Default)]
pub struct DeviceState {
    pub battery_pct: Option<u8>,
    pub charging: Option<bool>,
    pub wifi_connected: Option<bool>,
    pub wifi_ssid: Option<String>,
    pub cell_signal_dbm: Option<i32>,
    pub cell_operator: Option<String>,
    pub last_geo: Option<Value>,
    pub last_refresh: Option<Instant>,
}

/// Registered geofence.
#[derive(Debug, Clone)]
pub struct Geofence {
    pub id: String,
    pub lat: f64,
    pub lng: f64,
    pub radius_m: f64,
    pub label: String,
    pub active: bool,
}

/// Shared, in-process state across all WS connections.
pub struct AppState {
    pub conn: Connection,                                  // system bus
    pub session: Connection,                               // session bus
    pub device: RwLock<DeviceState>,
    pub geofences: RwLock<Vec<Geofence>>,
    /// Fan-out for events pushed from background tasks to every connected browser.
    /// Capacity of 64 means up to 64 queued events per slow consumer before drop-oldest.
    pub event_tx: broadcast::Sender<Value>,
}

impl AppState {
    pub async fn new() -> anyhow::Result<Arc<Self>> {
        let conn = Connection::system().await?;
        let session = Connection::session().await?;
        let (event_tx, _) = broadcast::channel::<Value>(64);
        Ok(Arc::new(Self {
            conn,
            session,
            device: RwLock::new(DeviceState::default()),
            geofences: RwLock::new(Vec::new()),
            event_tx,
        }))
    }

    /// Push an event to every connected browser. Drops if no one is listening.
    pub fn broadcast_event(&self, payload: Value) {
        let _ = self.event_tx.send(payload);
    }
}