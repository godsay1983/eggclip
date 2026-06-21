use std::sync::Mutex;

use futures_util::StreamExt;
use serde::Serialize;
use tauri::{AppHandle, Emitter, State};
use tokio::{net::TcpListener, sync::oneshot};
use tokio_tungstenite::tungstenite::Message;

pub const POC_MAX_FRAME_BYTES: usize = 1024 * 1024;

#[derive(Default)]
pub struct PocTransportRuntime {
    server: Mutex<Option<PocServerHandle>>,
}

struct PocServerHandle {
    shutdown: Option<oneshot::Sender<()>>,
    status: PocTransportStatus,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PocTransportStatus {
    state: PocTransportState,
    bind_address: String,
    port: u16,
    last_error: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum PocTransportState {
    Running,
    Stopped,
    Failed,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct PocPeerEvent {
    peer: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct PocTextFrameEvent {
    peer: String,
    byte_len: usize,
}

#[tauri::command]
pub async fn start_poc_transport(
    app: AppHandle,
    runtime: State<'_, PocTransportRuntime>,
    port: Option<u16>,
) -> Result<PocTransportStatus, String> {
    if let Some(status) = current_running_status(&runtime) {
        return Ok(status);
    }

    let requested_port = port.unwrap_or(0);
    let listener = TcpListener::bind(("0.0.0.0", requested_port))
        .await
        .map_err(|error| format!("无法启动 WebSocket POC 服务：{error}"))?;
    let local_addr = listener
        .local_addr()
        .map_err(|error| format!("无法读取 WebSocket POC 监听地址：{error}"))?;

    let (shutdown_tx, shutdown_rx) = oneshot::channel();
    let status = PocTransportStatus {
        state: PocTransportState::Running,
        bind_address: local_addr.ip().to_string(),
        port: local_addr.port(),
        last_error: None,
    };

    {
        let mut server = runtime
            .server
            .lock()
            .map_err(|_| "WebSocket POC 状态锁已损坏".to_owned())?;
        if let Some(existing) = server.as_ref() {
            return Ok(existing.status.clone());
        }
        *server = Some(PocServerHandle {
            shutdown: Some(shutdown_tx),
            status: status.clone(),
        });
    }

    let server_app = app.clone();
    tauri::async_runtime::spawn(async move {
        run_poc_server(server_app, listener, shutdown_rx).await;
    });

    let _ = app.emit("transport://poc-status", status.clone());
    Ok(status)
}

#[tauri::command]
pub fn stop_poc_transport(
    app: AppHandle,
    runtime: State<'_, PocTransportRuntime>,
) -> Result<PocTransportStatus, String> {
    let mut server = runtime
        .server
        .lock()
        .map_err(|_| "WebSocket POC 状态锁已损坏".to_owned())?;

    if let Some(mut handle) = server.take() {
        if let Some(shutdown) = handle.shutdown.take() {
            let _ = shutdown.send(());
        }
    }

    let status = PocTransportStatus {
        state: PocTransportState::Stopped,
        bind_address: "0.0.0.0".to_owned(),
        port: 0,
        last_error: None,
    };
    let _ = app.emit("transport://poc-status", status.clone());
    Ok(status)
}

#[tauri::command]
pub fn get_poc_transport_status(
    runtime: State<'_, PocTransportRuntime>,
) -> Result<PocTransportStatus, String> {
    Ok(
        current_running_status(&runtime).unwrap_or(PocTransportStatus {
            state: PocTransportState::Stopped,
            bind_address: "0.0.0.0".to_owned(),
            port: 0,
            last_error: None,
        }),
    )
}

fn current_running_status(runtime: &State<'_, PocTransportRuntime>) -> Option<PocTransportStatus> {
    runtime
        .server
        .lock()
        .ok()
        .and_then(|server| server.as_ref().map(|handle| handle.status.clone()))
}

async fn run_poc_server(
    app: AppHandle,
    listener: TcpListener,
    mut shutdown_rx: oneshot::Receiver<()>,
) {
    loop {
        tokio::select! {
            _ = &mut shutdown_rx => break,
            accept_result = listener.accept() => {
                let (stream, peer_addr) = match accept_result {
                    Ok(result) => result,
                    Err(error) => {
                        let _ = app.emit("transport://poc-status", PocTransportStatus {
                            state: PocTransportState::Failed,
                            bind_address: "0.0.0.0".to_owned(),
                            port: 0,
                            last_error: Some(format!("WebSocket POC 接收连接失败：{error}")),
                        });
                        break;
                    }
                };

                let peer = peer_addr.to_string();
                let peer_app = app.clone();
                tauri::async_runtime::spawn(async move {
                    handle_poc_peer(peer_app, peer, stream).await;
                });
            }
        }
    }
}

async fn handle_poc_peer(app: AppHandle, peer: String, stream: tokio::net::TcpStream) {
    let websocket = match tokio_tungstenite::accept_async(stream).await {
        Ok(websocket) => websocket,
        Err(error) => {
            let _ = app.emit(
                "transport://poc-status",
                PocTransportStatus {
                    state: PocTransportState::Failed,
                    bind_address: "0.0.0.0".to_owned(),
                    port: 0,
                    last_error: Some(format!("WebSocket POC 握手失败：{error}")),
                },
            );
            return;
        }
    };

    let _ = app.emit(
        "transport://poc-peer-connected",
        PocPeerEvent { peer: peer.clone() },
    );
    let (_write, mut read) = websocket.split();

    while let Some(message_result) = read.next().await {
        let message = match message_result {
            Ok(message) => message,
            Err(_) => break,
        };

        match message {
            Message::Text(text) => {
                let byte_len = text.len();
                if byte_len > POC_MAX_FRAME_BYTES {
                    break;
                }
                let _ = app.emit(
                    "transport://poc-text-frame",
                    PocTextFrameEvent {
                        peer: peer.clone(),
                        byte_len,
                    },
                );
            }
            Message::Binary(bytes) if bytes.len() > POC_MAX_FRAME_BYTES => break,
            Message::Close(_) => break,
            _ => {}
        }
    }

    let _ = app.emit("transport://poc-peer-disconnected", PocPeerEvent { peer });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn poc_frame_limit_is_one_mib() {
        assert_eq!(POC_MAX_FRAME_BYTES, 1024 * 1024);
    }
}
