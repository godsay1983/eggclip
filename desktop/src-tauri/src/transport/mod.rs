use std::{collections::HashMap, sync::Mutex};

use crate::clipboard::ClipboardText;
use futures_util::{SinkExt, StreamExt};
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, Manager, State};
use tokio::{
    net::TcpListener,
    sync::{mpsc, oneshot},
};
use tokio_tungstenite::tungstenite::Message;

pub const POC_MAX_FRAME_BYTES: usize = 1024 * 1024;

#[derive(Default)]
pub struct PocTransportRuntime {
    server: Mutex<Option<PocServerHandle>>,
    peers: Mutex<HashMap<String, mpsc::UnboundedSender<Message>>>,
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
    discovery_published: bool,
    network_addresses: Vec<crate::discovery::PocNetworkAddress>,
    connected_peers: usize,
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

#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
#[serde(tag = "kind", rename_all = "camelCase")]
enum PocClientMessage {
    ClipboardText { text: String },
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(tag = "kind", rename_all = "camelCase")]
enum PocServerMessage {
    ClipboardText { text: String },
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct PocClipboardTextEvent {
    peer: String,
    item: ClipboardText,
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
    let discovery_published = match crate::discovery::publish_poc_service(&app, local_addr.port()) {
        Ok(()) => true,
        Err(error) => {
            let _ = app.emit("discovery://poc-error", error);
            false
        }
    };
    let status = PocTransportStatus {
        state: PocTransportState::Running,
        bind_address: local_addr.ip().to_string(),
        port: local_addr.port(),
        discovery_published,
        network_addresses: crate::discovery::local_ipv4_candidates().unwrap_or_default(),
        connected_peers: 0,
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
    crate::discovery::unpublish_poc_service(&app);

    let status = PocTransportStatus {
        state: PocTransportState::Stopped,
        bind_address: "0.0.0.0".to_owned(),
        port: 0,
        discovery_published: false,
        network_addresses: crate::discovery::local_ipv4_candidates().unwrap_or_default(),
        connected_peers: 0,
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
            discovery_published: false,
            network_addresses: crate::discovery::local_ipv4_candidates().unwrap_or_default(),
            connected_peers: 0,
            last_error: None,
        }),
    )
}

#[tauri::command]
pub fn send_poc_clipboard_text(
    runtime: State<'_, PocTransportRuntime>,
    text: String,
) -> Result<usize, String> {
    let item = ClipboardText::parse(text).map_err(|error| error.to_string())?;
    broadcast_poc_clipboard_item_with_runtime(&runtime, &item)
}

fn broadcast_poc_clipboard_item_with_runtime(
    runtime: &PocTransportRuntime,
    item: &ClipboardText,
) -> Result<usize, String> {
    let message = serialize_poc_server_message(&PocServerMessage::ClipboardText {
        text: item.as_str().to_owned(),
    })?;
    let mut peers = runtime
        .peers
        .lock()
        .map_err(|_| "WebSocket POC peer 状态锁已损坏".to_owned())?;

    let mut sent_count = 0;
    let mut stale_peers = Vec::new();
    for (peer, sender) in peers.iter() {
        if sender.send(Message::Text(message.clone().into())).is_ok() {
            sent_count += 1;
        } else {
            stale_peers.push(peer.clone());
        }
    }
    for peer in stale_peers {
        peers.remove(&peer);
    }
    Ok(sent_count)
}

fn current_running_status(runtime: &State<'_, PocTransportRuntime>) -> Option<PocTransportStatus> {
    let mut status = runtime
        .server
        .lock()
        .ok()
        .and_then(|server| server.as_ref().map(|handle| handle.status.clone()))?;
    status.connected_peers = runtime.peers.lock().map(|peers| peers.len()).unwrap_or(0);
    Some(status)
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
                            discovery_published: false,
                            network_addresses: Vec::new(),
                            connected_peers: 0,
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
    crate::discovery::unpublish_poc_service(&app);
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
                    discovery_published: false,
                    network_addresses: Vec::new(),
                    connected_peers: 0,
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
    let (mut write, mut read) = websocket.split();
    let (outgoing_tx, mut outgoing_rx) = mpsc::unbounded_channel::<Message>();
    if let Ok(mut peers) = app.state::<PocTransportRuntime>().peers.lock() {
        peers.insert(peer.clone(), outgoing_tx);
    }

    let write_peer = peer.clone();
    let write_app = app.clone();
    let write_task = tauri::async_runtime::spawn(async move {
        while let Some(message) = outgoing_rx.recv().await {
            if write.send(message).await.is_err() {
                break;
            }
        }
        let _ = write_app.emit(
            "transport://poc-peer-disconnected",
            PocPeerEvent { peer: write_peer },
        );
    });

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
                if let Ok(PocClientMessage::ClipboardText { text }) =
                    serde_json::from_str::<PocClientMessage>(&text)
                {
                    if let Ok(item) = ClipboardText::parse(text) {
                        let _ = app.emit(
                            "transport://poc-clipboard-text",
                            PocClipboardTextEvent {
                                peer: peer.clone(),
                                item,
                            },
                        );
                    }
                }
            }
            Message::Binary(bytes) if bytes.len() > POC_MAX_FRAME_BYTES => break,
            Message::Close(_) => break,
            _ => {}
        }
    }

    if let Ok(mut peers) = app.state::<PocTransportRuntime>().peers.lock() {
        peers.remove(&peer);
    }
    write_task.abort();
    let _ = app.emit("transport://poc-peer-disconnected", PocPeerEvent { peer });
}

fn serialize_poc_server_message(message: &PocServerMessage) -> Result<String, String> {
    serde_json::to_string(message)
        .map_err(|error| format!("无法序列化 WebSocket POC 消息：{error}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn poc_frame_limit_is_one_mib() {
        assert_eq!(POC_MAX_FRAME_BYTES, 1024 * 1024);
    }

    #[test]
    fn parses_poc_clipboard_text_message() {
        let message = serde_json::from_str::<PocClientMessage>(
            r#"{"kind":"clipboardText","text":"from harmony"}"#,
        )
        .expect("valid poc message");

        assert_eq!(
            message,
            PocClientMessage::ClipboardText {
                text: "from harmony".to_owned(),
            },
        );
    }

    #[test]
    fn serializes_poc_clipboard_text_message() {
        let message = serialize_poc_server_message(&PocServerMessage::ClipboardText {
            text: "from desktop".to_owned(),
        })
        .expect("valid poc server message");

        assert_eq!(message, r#"{"kind":"clipboardText","text":"from desktop"}"#);
    }
}
