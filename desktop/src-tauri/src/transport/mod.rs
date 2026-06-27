use std::{collections::HashMap, net::Ipv4Addr, str::FromStr, sync::Mutex, time::Duration};

use crate::clipboard::{ClipboardText, ClipboardTextError};
use futures_util::{SinkExt, StreamExt};
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, Manager, State};
use tokio::{
    io::{AsyncRead, AsyncWrite},
    net::TcpListener,
    sync::{mpsc, oneshot},
    time::timeout,
};
use tokio_tungstenite::{connect_async, tungstenite::Message, WebSocketStream};

pub const POC_MAX_FRAME_BYTES: usize = 1024 * 1024;
const POC_CONNECT_TIMEOUT: Duration = Duration::from_secs(8);

#[derive(Default)]
pub struct PocTransportRuntime {
    server: Mutex<Option<PocServerHandle>>,
    peers: Mutex<HashMap<String, mpsc::UnboundedSender<Message>>>,
    diagnostics: Mutex<PocTransportDiagnostics>,
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
    diagnostics: PocTransportDiagnostics,
    last_error: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PocTransportDiagnostics {
    received_frames: u64,
    accepted_items: u64,
    rejected_frames: u64,
    last_rejection: Option<PocRejectionReason>,
}

impl PocTransportDiagnostics {
    fn record_frame(&mut self, result: Result<(), PocRejectionReason>) {
        self.received_frames = self.received_frames.saturating_add(1);
        match result {
            Ok(()) => {
                self.accepted_items = self.accepted_items.saturating_add(1);
            }
            Err(reason) => {
                self.rejected_frames = self.rejected_frames.saturating_add(1);
                self.last_rejection = Some(reason);
            }
        }
    }

    fn reset(&mut self) {
        *self = Self::default();
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum PocRejectionReason {
    FrameTooLarge,
    InvalidMessage,
    EmptyText,
    TextTooLarge,
    BinaryUnsupported,
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

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq)]
#[serde(tag = "kind", rename_all = "camelCase")]
enum PocClientMessage {
    ClipboardText { text: String },
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq)]
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
    reset_poc_diagnostics(&runtime)?;
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
        diagnostics: PocTransportDiagnostics::default(),
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
    let _ = disconnect_all_poc_peers_with_runtime(&runtime);

    let status = PocTransportStatus {
        state: PocTransportState::Stopped,
        bind_address: "0.0.0.0".to_owned(),
        port: 0,
        discovery_published: false,
        network_addresses: crate::discovery::local_ipv4_candidates().unwrap_or_default(),
        connected_peers: 0,
        diagnostics: diagnostics_snapshot(&runtime),
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
            diagnostics: diagnostics_snapshot(&runtime),
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

#[tauri::command]
pub async fn connect_poc_peer(
    app: AppHandle,
    runtime: State<'_, PocTransportRuntime>,
    host: String,
    port: u16,
) -> Result<String, String> {
    let endpoint = validate_poc_endpoint(&host, port)?;
    let peer = format!("desktop-outbound:{endpoint}");
    if runtime
        .peers
        .lock()
        .map_err(|_| "WebSocket POC peer 状态锁已损坏".to_owned())?
        .contains_key(&peer)
    {
        return Err("该桌面 POC 已连接".to_owned());
    }

    let url = format!("ws://{endpoint}");
    let (websocket, _) = timeout(POC_CONNECT_TIMEOUT, connect_async(&url))
        .await
        .map_err(|_| "连接桌面 POC 超时".to_owned())?
        .map_err(|error| format!("无法连接桌面 POC：{error}"))?;

    let connected_endpoint = endpoint.clone();
    tauri::async_runtime::spawn(async move {
        handle_poc_websocket(app, peer, websocket).await;
    });
    Ok(connected_endpoint)
}

#[tauri::command]
pub fn disconnect_all_poc_peers(runtime: State<'_, PocTransportRuntime>) -> Result<usize, String> {
    disconnect_all_poc_peers_with_runtime(&runtime)
}

fn disconnect_all_poc_peers_with_runtime(runtime: &PocTransportRuntime) -> Result<usize, String> {
    let mut peers = runtime
        .peers
        .lock()
        .map_err(|_| "WebSocket POC peer 状态锁已损坏".to_owned())?;
    let count = peers.len();
    for sender in peers.values() {
        let _ = sender.send(Message::Close(None));
    }
    peers.clear();
    Ok(count)
}

fn validate_poc_endpoint(host: &str, port: u16) -> Result<String, String> {
    let address = Ipv4Addr::from_str(host.trim())
        .map_err(|_| "请输入有效的 IPv4 地址，例如 192.168.1.10".to_owned())?;
    if address.is_unspecified() || address.is_multicast() || address.is_broadcast() {
        return Err("该 IPv4 地址不能作为桌面 POC 目标".to_owned());
    }
    if port == 0 {
        return Err("请输入 1 到 65535 之间的端口".to_owned());
    }
    Ok(format!("{address}:{port}"))
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
    status.diagnostics = diagnostics_snapshot(runtime);
    Some(status)
}

fn reset_poc_diagnostics(runtime: &PocTransportRuntime) -> Result<(), String> {
    let mut diagnostics = runtime
        .diagnostics
        .lock()
        .map_err(|_| "WebSocket POC 诊断状态锁已损坏".to_owned())?;
    diagnostics.reset();
    Ok(())
}

fn diagnostics_snapshot(runtime: &PocTransportRuntime) -> PocTransportDiagnostics {
    runtime
        .diagnostics
        .lock()
        .map(|diagnostics| diagnostics.clone())
        .unwrap_or_default()
}

fn record_poc_frame_result(app: &AppHandle, result: Result<(), PocRejectionReason>) {
    let runtime = app.state::<PocTransportRuntime>();
    let snapshot = runtime.diagnostics.lock().ok().map(|mut diagnostics| {
        diagnostics.record_frame(result);
        diagnostics.clone()
    });
    if let Some(snapshot) = snapshot {
        let _ = app.emit("transport://poc-diagnostics", snapshot);
    }
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
                            diagnostics: PocTransportDiagnostics::default(),
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
                    diagnostics: PocTransportDiagnostics::default(),
                    last_error: Some(format!("WebSocket POC 握手失败：{error}")),
                },
            );
            return;
        }
    };

    handle_poc_websocket(app, peer, websocket).await;
}

async fn handle_poc_websocket<S>(app: AppHandle, peer: String, websocket: WebSocketStream<S>)
where
    S: AsyncRead + AsyncWrite + Unpin + Send + 'static,
{
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
                    record_poc_frame_result(&app, Err(PocRejectionReason::FrameTooLarge));
                    break;
                }
                let _ = app.emit(
                    "transport://poc-text-frame",
                    PocTextFrameEvent {
                        peer: peer.clone(),
                        byte_len,
                    },
                );
                match parse_poc_clipboard_text_message(&text) {
                    Ok(item) => {
                        record_poc_frame_result(&app, Ok(()));
                        let _ = app.emit(
                            "transport://poc-clipboard-text",
                            PocClipboardTextEvent {
                                peer: peer.clone(),
                                item,
                            },
                        );
                    }
                    Err(reason) => record_poc_frame_result(&app, Err(reason)),
                }
            }
            Message::Binary(bytes) => {
                let reason = if bytes.len() > POC_MAX_FRAME_BYTES {
                    PocRejectionReason::FrameTooLarge
                } else {
                    PocRejectionReason::BinaryUnsupported
                };
                record_poc_frame_result(&app, Err(reason));
                break;
            }
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

fn parse_poc_clipboard_text_message(message: &str) -> Result<ClipboardText, PocRejectionReason> {
    if message.len() > POC_MAX_FRAME_BYTES {
        return Err(PocRejectionReason::FrameTooLarge);
    }
    let PocClientMessage::ClipboardText { text } =
        serde_json::from_str::<PocClientMessage>(message)
            .map_err(|_| PocRejectionReason::InvalidMessage)?;
    ClipboardText::parse(text).map_err(|error| match error {
        ClipboardTextError::Empty => PocRejectionReason::EmptyText,
        ClipboardTextError::TooLarge { .. } => PocRejectionReason::TextTooLarge,
    })
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
        let item =
            parse_poc_clipboard_text_message(r#"{"kind":"clipboardText","text":"from harmony"}"#)
                .expect("valid poc message");

        assert_eq!(item.as_str(), "from harmony");
    }

    #[test]
    fn rejects_invalid_or_out_of_bounds_poc_text() {
        assert_eq!(
            parse_poc_clipboard_text_message("not json").unwrap_err(),
            PocRejectionReason::InvalidMessage
        );
        assert_eq!(
            parse_poc_clipboard_text_message(r#"{"kind":"clipboardText","text":""}"#).unwrap_err(),
            PocRejectionReason::EmptyText
        );

        let exact = serialize_poc_server_message(&PocServerMessage::ClipboardText {
            text: "a".repeat(crate::clipboard::MAX_TEXT_BYTES),
        })
        .expect("valid boundary frame");
        assert!(parse_poc_clipboard_text_message(&exact).is_ok());

        let oversized = serialize_poc_server_message(&PocServerMessage::ClipboardText {
            text: "a".repeat(crate::clipboard::MAX_TEXT_BYTES + 1),
        })
        .expect("serializable oversized frame");
        assert_eq!(
            parse_poc_clipboard_text_message(&oversized).unwrap_err(),
            PocRejectionReason::TextTooLarge
        );
        assert_eq!(
            parse_poc_clipboard_text_message(&"a".repeat(POC_MAX_FRAME_BYTES + 1)).unwrap_err(),
            PocRejectionReason::FrameTooLarge
        );
    }

    #[test]
    fn round_trips_one_hundred_poc_text_messages() {
        for index in 0..100 {
            let expected = format!("POC text {index} · 蛋定🥚");
            let serialized = serialize_poc_server_message(&PocServerMessage::ClipboardText {
                text: expected.clone(),
            })
            .expect("valid poc frame");
            let item = parse_poc_clipboard_text_message(&serialized).expect("round-trip text");

            assert_eq!(item.as_str(), expected);
        }
    }

    #[test]
    fn serializes_poc_clipboard_text_message() {
        let message = serialize_poc_server_message(&PocServerMessage::ClipboardText {
            text: "from desktop".to_owned(),
        })
        .expect("valid poc server message");

        assert_eq!(message, r#"{"kind":"clipboardText","text":"from desktop"}"#);
    }

    #[test]
    fn validates_manual_ipv4_endpoint() {
        assert_eq!(
            validate_poc_endpoint(" 192.168.1.20 ", 4567).expect("valid endpoint"),
            "192.168.1.20:4567"
        );
        assert!(validate_poc_endpoint("example.com", 4567).is_err());
        assert!(validate_poc_endpoint("01.2.3.4", 4567).is_err());
        assert!(validate_poc_endpoint("0.0.0.0", 4567).is_err());
        assert!(validate_poc_endpoint("224.0.0.1", 4567).is_err());
        assert!(validate_poc_endpoint("255.255.255.255", 4567).is_err());
        assert!(validate_poc_endpoint("127.0.0.1", 0).is_err());
    }

    #[test]
    fn records_poc_diagnostics_without_content() {
        let mut diagnostics = PocTransportDiagnostics::default();

        diagnostics.record_frame(Ok(()));
        assert_eq!(diagnostics.received_frames, 1);
        assert_eq!(diagnostics.accepted_items, 1);
        assert_eq!(diagnostics.rejected_frames, 0);
        assert_eq!(diagnostics.last_rejection, None);

        diagnostics.record_frame(Err(PocRejectionReason::InvalidMessage));
        assert_eq!(diagnostics.received_frames, 2);
        assert_eq!(diagnostics.accepted_items, 1);
        assert_eq!(diagnostics.rejected_frames, 1);
        assert_eq!(
            diagnostics.last_rejection,
            Some(PocRejectionReason::InvalidMessage)
        );
    }

    #[test]
    fn resets_poc_diagnostics_for_a_new_session() {
        let mut diagnostics = PocTransportDiagnostics::default();

        diagnostics.record_frame(Ok(()));
        diagnostics.record_frame(Err(PocRejectionReason::TextTooLarge));
        diagnostics.reset();

        assert_eq!(diagnostics.received_frames, 0);
        assert_eq!(diagnostics.accepted_items, 0);
        assert_eq!(diagnostics.rejected_frames, 0);
        assert_eq!(diagnostics.last_rejection, None);
    }
}
