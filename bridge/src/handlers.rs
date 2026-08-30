//! Method dispatch — every `window.phosphor.call(...)` lands here.
//!
//! Each method is a thin adapter around:
//!   - Termux:API (sensors, battery, wifi, bt, camera, flashlight, vibrate,
//!     speech, location, clipboard, share)
//!   - A privileged IPC helper (telephony, SMS, location via fused provider,
//!     screen-idle, brightness, app-launch intents — these all need
//!     signature-level Android perms the bridge can't get standalone)
//!   - DBus direct (when we can — notifications, sensor proxies, etc.)
//!
//! The dispatcher wraps every method's `Result<Value, String>` into a
//! matching `RpcResponse` with the same `id` the caller sent.
use std::sync::Arc;
use std::time::Duration;

use crate::state::{AppState, Geofence};
use crate::{RpcRequest, RpcResponse};
use serde_json::{json, Value};
use tokio::process::Command;

const TERMUX_API: &str = "com.termux.api";
const IPC_BRIDGE_BIN: &str = "/data/local/tmp/phosphor-ipc";

/// Dispatch one RPC request to its handler.
pub async fn dispatch(state: Arc<AppState>, req: RpcRequest) -> RpcResponse {
    let id = req.id.clone();
    let method = req.method.as_str();
    let params = req.params.clone();

    let result: Result<Value, String> = match method {
        // ─── Telephony ─────────────────────────────────────────
        "tel.dial" => call_ipc(state.clone(), "tel.dial", params).await,
        "tel.hangup" => call_ipc(state.clone(), "tel.hangup", json!({})).await,
        "tel.answer" => call_ipc(state.clone(), "tel.answer", json!({})).await,
        "tel.status" => call_ipc(state.clone(), "tel.status", json!({})).await,

        // ─── SMS ───────────────────────────────────────────────
        "sms.send" => call_ipc(state.clone(), "sms.send", params).await,
        "sms.inbox" => call_ipc(state.clone(), "sms.inbox", params).await,

        // ─── Geo / location ────────────────────────────────────
        "geo.get" => call_ipc(state.clone(), "geo.get", json!({ "provider": "fused" })).await,
        "geo.watch" => register_geofence(state.clone(), params).await,
        "geo.unwatch" => unregister_geofence(state.clone(), params).await,

        // ─── WiFi ──────────────────────────────────────────────
        "wifi.status" => call_termux_api("WifiConnectionInfo", json!({})).await,
        "wifi.list" => call_termux_api("WifiScan", json!({})).await,

        // ─── Bluetooth ─────────────────────────────────────────
        "bt.list" => call_termux_api("BluetoothPairedDevices", json!({})).await,
        "bt.connect" => call_termux_api("BluetoothConnect", params).await,

        // ─── Sensors / device state ────────────────────────────
        "sensor.read" => call_termux_api("Sensor", params).await,
        "battery" => call_termux_api("BatteryStatus", json!({})).await,

        // ─── Clipboard ─────────────────────────────────────────
        "clip.read" => call_termux_api("ClipboardGet", json!({})).await,
        "clip.write" => call_termux_api("ClipboardSet", params).await,

        // ─── Notifications / haptics ───────────────────────────
        "notif.set" => call_termux_api("Notification", params).await,
        "notif.cancel" => call_termux_api("NotificationRemove", params).await,
        "vibrate" => call_termux_api("Vibrate", params).await,

        // ─── Flashlight / camera ───────────────────────────────
        "flashlight" => call_termux_api("Torch", params).await,
        "camera.snapshot" => call_termux_api("CameraPhoto", params).await,

        // ─── Display / power ───────────────────────────────────
        "screen.idle" => call_ipc(state.clone(), "screen.idle", params).await,
        "screen.wake" => call_ipc(state.clone(), "screen.wake", json!({})).await,
        "brightness" => call_ipc(state.clone(), "brightness", params).await,

        // ─── Intents / sharing / TTS ───────────────────────────
        "app.open" => call_ipc(state.clone(), "app.open", params).await,
        "app.share" => call_termux_api("Share", params).await,
        "tts.speak" => call_termux_api("TTS", params).await,

        // ─── Web fetch (used by the LLM to embed a result) ─────
        "web.fetch" => web_fetch(params).await,

        // ─── Persisted KV (LLM context memory) ─────────────────
        "kv.get" => kv_get(params).await,
        "kv.set" => kv_set(params).await,

        // ─── Unknown ───────────────────────────────────────────
        _ => Err(format!("unknown method: {method}")),
    };

    match result {
        Ok(v) => RpcResponse::ok(id, v),
        Err(e) => RpcResponse::err(id, -32000, e),
    }
}

// ───────────────────────────────────────────────────────────────────────
// Helper: invoke our privileged IPC helper. It runs as a system app and
// is the only thing that talks directly to `ITelephony`, `LocationManager`,
// `IPowerManager`, `WindowManager.setScreenIdleTimeout`, etc.
//
// Wire format: argv[1] = JSON → stdout = JSON. Trivial, debuggable,
// no IPC libs needed.
// ───────────────────────────────────────────────────────────────────────
async fn call_ipc(state: Arc<AppState>, method: &str, params: Value) -> Result<Value, String> {
    let payload = json!({ "method": method, "params": params });
    let out = Command::new(IPC_BRIDGE_BIN)
        .arg(payload.to_string())
        .output()
        .await
        .map_err(|e| format!("ipc spawn: {e}"))?;
    if !out.status.success() {
        return Err(format!(
            "ipc {} failed: {}",
            out.status,
            String::from_utf8_lossy(&out.stderr).trim()
        ));
    }
    let v: Value = serde_json::from_slice(&out.stdout)
        .map_err(|e| format!("ipc parse: {e} (raw: {})", String::from_utf8_lossy(&out.stdout)))?;

    // Opportunistic device-state cache fill.
    if let Some(batt) = v.get("battery") {
        let mut d = state.device.write().await;
        if let Some(p) = batt.get("percentage").and_then(|p| p.as_u64()) {
            d.battery_pct = Some(p as u8);
        }
        if let Some(s) = batt.get("status").and_then(|s| s.as_str()) {
            d.charging = Some(matches!(s, "CHARGING" | "FULL"));
        }
    }
    Ok(v)
}

// ───────────────────────────────────────────────────────────────────────
// Helper: invoke Termux:API via `am broadcast`.
//
//   am broadcast -a com.termux.api.<ACTION> --es args <base64-json> \
//                -p com.termux.api
// ───────────────────────────────────────────────────────────────────────
async fn call_termux_api(action: &str, params: Value) -> Result<Value, String> {
    let encoded = base64_encode(serde_json::to_string(&params).unwrap_or_default());
    let out = Command::new("am")
        .args([
            "broadcast",
            "-a",
            &format!("com.termux.api.{action}"),
            "--es",
            "args",
            &encoded,
            "-p",
            TERMUX_API,
        ])
        .output()
        .await
        .map_err(|e| format!("am spawn: {e}"))?;
    if !out.status.success() {
        return Err(format!(
            "termux {action}: {}",
            String::from_utf8_lossy(&out.stderr).trim()
        ));
    }
    let stdout = String::from_utf8_lossy(&out.stdout).trim().to_string();
    Ok(json!({ "ok": true, "action": action, "raw": stdout }))
}

// ───────────────────────────────────────────────────────────────────────
// Geofence registry — `geo.watch` stores a fence; a background poller
// checks location every 60s and pushes `geo.fired { id, label }` events
// to every connected browser when the user crosses a boundary.
// ───────────────────────────────────────────────────────────────────────
async fn register_geofence(state: Arc<AppState>, params: Value) -> Result<Value, String> {
    let id = params
        .get("id")
        .and_then(|v| v.as_str())
        .unwrap_or(&uuid::Uuid::new_v4().to_string())
        .to_string();
    let lat = params.get("lat").and_then(|v| v.as_f64()).ok_or("missing lat")?;
    let lng = params.get("lng").and_then(|v| v.as_f64()).ok_or("missing lng")?;
    let radius_m = params
        .get("radius_m")
        .and_then(|v| v.as_f64())
        .unwrap_or(150.0);
    let label = params
        .get("label")
        .and_then(|v| v.as_str())
        .unwrap_or("geofence")
        .to_string();

    let mut fences = state.geofences.write().await;
    fences.push(Geofence { id: id.clone(), lat, lng, radius_m, label, active: false });
    Ok(json!({ "ok": true, "id": id }))
}

async fn unregister_geofence(state: Arc<AppState>, params: Value) -> Result<Value, String> {
    let id = params.get("id").and_then(|v| v.as_str()).ok_or("missing id")?.to_string();
    let mut fences = state.geofences.write().await;
    let before = fences.len();
    fences.retain(|f| f.id != id);
    Ok(json!({ "ok": true, "removed": before - fences.len() }))
}

// ───────────────────────────────────────────────────────────────────────
// HTTP fetch used by the LLM to embed a result. Returns a status, the
// content-type, the body (truncated to `max_bytes` which defaults to 2MB),
// and a `truncated` flag.
// ───────────────────────────────────────────────────────────────────────
async fn web_fetch(params: Value) -> Result<Value, String> {
    let url = params
        .get("url")
        .and_then(|v| v.as_str())
        .ok_or("missing url")?;
    let max_bytes = params
        .get("max_bytes")
        .and_then(|v| v.as_u64())
        .unwrap_or(2_000_000);

    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(10))
        .user_agent("phosphor/0.1")
        .build()
        .map_err(|e| e.to_string())?;
    let resp = client.get(url).send().await.map_err(|e| e.to_string())?;
    let status = resp.status().as_u16();
    let content_type = resp
        .headers()
        .get("content-type")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("")
        .to_string();
    let bytes = resp.bytes().await.map_err(|e| e.to_string())?;
    let truncated = bytes.len() as u64 > max_bytes;
    let slice = if truncated { &bytes[..max_bytes as usize] } else { &bytes[..] };
    let body = String::from_utf8_lossy(slice).to_string();
    Ok(json!({
        "status": status,
        "content_type": content_type,
        "truncated": truncated,
        "body": body,
    }))
}

// ───────────────────────────────────────────────────────────────────────
// Tiny persistent KV used as the LLM's "memory". Backed by a single JSON
// file at /data/data/com.phosphor.bridge/files/kv.json
// ───────────────────────────────────────────────────────────────────────
const KV_PATH: &str = "/data/data/com.phosphor.bridge/files/kv.json";

async fn kv_get(params: Value) -> Result<Value, String> {
    let key = params.get("key").and_then(|v| v.as_str()).ok_or("missing key")?;
    let map = read_kv().await?;
    Ok(map.get(key).cloned().unwrap_or(Value::Null))
}

async fn kv_set(params: Value) -> Result<Value, String> {
    let key = params.get("key").and_then(|v| v.as_str()).ok_or("missing key")?;
    let value = params.get("value").cloned().ok_or("missing value")?;
    let mut map = read_kv().await.unwrap_or_default();
    map.insert(key.to_string(), value);
    write_kv(&map).await?;
    Ok(json!({ "ok": true }))
}

async fn read_kv() -> Result<serde_json::Map<String, Value>, String> {
    match tokio::fs::read(KV_PATH).await {
        Ok(b) => serde_json::from_slice(&b).map_err(|e| e.to_string()),
        Err(_) => Ok(serde_json::Map::new()),
    }
}

async fn write_kv(map: &serde_json::Map<String, Value>) -> Result<(), String> {
    if let Some(parent) = std::path::Path::new(KV_PATH).parent() {
        let _ = tokio::fs::create_dir_all(parent).await;
    }
    tokio::fs::write(KV_PATH, serde_json::to_vec_pretty(map).unwrap())
        .await
        .map_err(|e| e.to_string())
}

// ───────────────────────────────────────────────────────────────────────
// Background tasks: keep the device-state cache warm, fire geofences.
// ───────────────────────────────────────────────────────────────────────
pub fn spawn_background_tasks(state: Arc<AppState>) {
    // 1. Battery refresh every 30s.
    {
        let s = state.clone();
        tokio::spawn(async move {
            let mut tick = tokio::time::interval(Duration::from_secs(30));
            loop {
                tick.tick().await;
                let _ = call_termux_api("BatteryStatus", json!({})).await;
                let mut d = s.device.write().await;
                d.last_refresh = Some(std::time::Instant::now());
            }
        });
    }

    // 2. Geofence poller — every 60s check location, fire any fences.
    {
        let s = state.clone();
        tokio::spawn(async move {
            let mut tick = tokio::time::interval(Duration::from_secs(60));
            loop {
                tick.tick().await;
                let Ok(loc) = call_ipc(s.clone(), "geo.get", json!({ "provider": "fused" })).await
                else { continue };

                let (Some(lat), Some(lng)) = (
                    loc.get("lat").and_then(|v| v.as_f64()),
                    loc.get("lng").and_then(|v| v.as_f64()),
                ) else { continue };

                let mut fences = s.geofences.write().await;
                for f in fences.iter_mut() {
                    let d = haversine_m(lat, lng, f.lat, f.lng);
                    if d <= f.radius_m && !f.active {
                        f.active = true;
                        s.broadcast_event(json!({
                            "event": "geo.fired",
                            "id": f.id,
                            "label": f.label,
                            "distance_m": d,
                        }));
                    } else if d > f.radius_m && f.active {
                        f.active = false;
                    }
                }
            }
        });
    }
}

/// Great-circle distance between two lat/lng pairs, in metres.
fn haversine_m(lat1: f64, lon1: f64, lat2: f64, lon2: f64) -> f64 {
    let r = 6_371_000.0_f64;
    let dlat = (lat2 - lat1).to_radians();
    let dlon = (lon2 - lon1).to_radians();
    let a = (dlat / 2.0).sin().powi(2)
        + lat1.to_radians().cos() * lat2.to_radians().cos() * (dlon / 2.0).sin().powi(2);
    let c = 2.0 * a.sqrt().asin();
    r * c
}

/// URL-safe base64 with no padding — avoids pulling the `base64` crate.
fn base64_encode(s: String) -> String {
    const ALPHA: &[u8; 64] =
        b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    let bytes = s.as_bytes();
    let mut out = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for c in bytes.chunks(3) {
        let b0 = c[0];
        let b1 = c.get(1).copied().unwrap_or(0);
        let b2 = c.get(2).copied().unwrap_or(0);
        let n = ((b0 as u32) << 16) | ((b1 as u32) << 8) | (b2 as u32);
        out.push(ALPHA[((n >> 18) & 0x3F) as usize] as char);
        out.push(ALPHA[((n >> 12) & 0x3F) as usize] as char);
        if c.len() > 1 {
            out.push(ALPHA[((n >> 6) & 0x3F) as usize] as char);
        }
        if c.len() > 2 {
            out.push(ALPHA[(n & 0x3F) as usize] as char);
        }
    }
    out
}