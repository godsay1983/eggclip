mod session;

use std::{
    collections::{HashMap, HashSet},
    net::Ipv4Addr,
    str::FromStr,
    sync::Mutex,
    time::Duration,
};

use crate::{
    clipboard::{ClipboardText, ClipboardTextError},
    crypto::{
        aes256_gcm_decrypt, aes256_gcm_encrypt, decode_base64url, encode_base64url, fixed_bytes,
        SessionDirection, X25519Secret, AES_GCM_NONCE_BYTES, AES_GCM_TAG_BYTES,
        X25519_PRIVATE_KEY_BYTES,
    },
    pairing::{
        accept_pairing_auth_proof, accept_pairing_client_hello, accept_trusted_device_client_hello,
        load_space_key, PairingError, PairingServerAuthProofInput, PairingServerHelloDraft,
    },
    protocol::{
        parse_envelope, ClipboardItem as ProtocolClipboardItem, ContentType as ProtocolContentType,
        HelloPayload, ItemAckPayload, ItemBatchPayload, MessageType, ProtocolEnvelope,
        RequestRange, RequestRangePayload, RetentionGap, SyncHeadsPayload, MAX_BATCH_ITEMS,
        MAX_BATCH_PLAINTEXT_BYTES,
    },
    settings::{database_path, now_ms},
    storage::{
        open_database,
        repositories::{
            persist_local_clipboard_text, retention_expires_at, ClipboardInsertOutcome,
            ClipboardItemRecord, ClipboardRepository, DeviceRecord, DeviceRepository,
            LocalClipboardPersistInput, PairingInvitationRepository, SettingsRepository,
            SpaceRepository, SyncHeadRecord, SyncHeadRepository,
        },
    },
    sync::{
        AppSettings, ContentType as SyncContentType, Device, DeviceConnectionState,
        DeviceTrustState, HlcTimestamp, SpaceState, SyncHead,
    },
};
use futures_util::{SinkExt, StreamExt};
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, Manager, State};
use tokio::{
    io::{AsyncRead, AsyncWrite},
    net::TcpListener,
    sync::{mpsc, oneshot},
    time::{interval, timeout, MissedTickBehavior},
};
use tokio_tungstenite::{connect_async, tungstenite::Message, WebSocketStream};
use uuid::Uuid;

pub use session::{
    AuthenticatedTransportSession, HandshakeFrame, HandshakeFrameOutcome,
    HandshakeTransportSession, TransportFrameError,
};

pub const POC_MAX_FRAME_BYTES: usize = 1024 * 1024;
const POC_CONNECT_TIMEOUT: Duration = Duration::from_secs(8);
const AUTHENTICATED_HEARTBEAT_INTERVAL: Duration = Duration::from_secs(30);
const POC_RECENT_ENDPOINT_KEY: &str = "pocRecentEndpoint";

#[derive(Default)]
pub struct PocTransportRuntime {
    server: Mutex<Option<PocServerHandle>>,
    peers: Mutex<HashMap<String, mpsc::UnboundedSender<Message>>>,
    pairing_handshakes: Mutex<HashMap<String, PairingServerHandshakeRuntimeState>>,
    authenticated_sessions: Mutex<HashMap<String, AuthenticatedPeerSession>>,
    diagnostics: Mutex<PocTransportDiagnostics>,
}

struct AuthenticatedPeerSession {
    session: AuthenticatedTransportSession,
    space_id: Uuid,
    device_id: Uuid,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct AuthenticatedConnectionStateEvent {
    peer: String,
    device_id: String,
    space_id: String,
    state: &'static str,
}

#[allow(dead_code)]
struct PairingServerHandshakeRuntimeState {
    invitation_id: String,
    space_id: String,
    peer_device_id: String,
    peer_identity_public_key: String,
    peer_ephemeral_public_key: String,
    server_device_id: String,
    server_identity_public_key: String,
    server_ephemeral_public_key: String,
    pairing_context: String,
    server_ephemeral_secret: X25519Secret,
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
    AuthenticatedFrameRejected,
    PairingClientHelloRejected,
    PairingInvitationMissing,
    PairingInvitationExpired,
    PairingInvitationConsumed,
    PairingAuthProofRejected,
    PairingAuthSignatureRejected,
    PairingServerStateMissing,
    PairingInternalError,
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
#[serde(rename_all = "camelCase")]
pub struct PocRecentEndpoint {
    host: String,
    port: u16,
    connected_at_ms: u64,
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

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct PocAuthenticatedFrameEvent {
    peer: String,
    message_type: MessageType,
    payload: serde_json::Value,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct AuthenticatedClipboardTextEvent {
    peer: String,
    item_id: String,
    origin_device_id: String,
    origin_seq: u64,
    item: ClipboardText,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct AuthenticatedLocalBroadcastEvent {
    status: AuthenticatedLocalBroadcastStatus,
    sent_peers: usize,
}

#[derive(Debug, Clone, Copy, Serialize)]
#[serde(rename_all = "camelCase")]
enum AuthenticatedLocalBroadcastStatus {
    Sent,
    SkippedNoAuthenticatedPeer,
    SkippedAmbiguousSpace,
    SkippedByPolicy,
    Failed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum AuthenticatedRemoteHistoryOutcome {
    Inserted,
    Duplicate,
    Conflict,
    SkippedByPolicy,
    SkippedMissingTrustGraph,
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
) -> Result<PocRecentEndpoint, String> {
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
    let recent_endpoint = build_recent_endpoint(&connected_endpoint, now_ms()?)?;
    let _ = save_poc_recent_endpoint_metadata(&app, &recent_endpoint);
    tauri::async_runtime::spawn(async move {
        handle_poc_websocket(app, peer, websocket).await;
    });
    Ok(recent_endpoint)
}

#[tauri::command]
pub fn disconnect_all_poc_peers(runtime: State<'_, PocTransportRuntime>) -> Result<usize, String> {
    disconnect_all_poc_peers_with_runtime(&runtime)
}

#[tauri::command]
pub fn load_poc_recent_endpoint(app: AppHandle) -> Result<Option<PocRecentEndpoint>, String> {
    let path = database_path(&app)?;
    let connection = open_database(path).map_err(|error| format!("无法打开本地数据库：{error}"))?;
    let value = SettingsRepository::new(&connection)
        .get(POC_RECENT_ENDPOINT_KEY)
        .map_err(|error| format!("无法读取最近 POC 地址：{error}"))?;
    let Some(value) = value else {
        return Ok(None);
    };
    let endpoint = match serde_json::from_str::<PocRecentEndpoint>(&value) {
        Ok(endpoint) => endpoint,
        Err(_) => return Ok(None),
    };
    if validate_poc_endpoint(&endpoint.host, endpoint.port).is_err() {
        return Ok(None);
    }
    Ok(Some(endpoint))
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
    if let Ok(mut handshakes) = runtime.pairing_handshakes.lock() {
        handshakes.clear();
    }
    if let Ok(mut sessions) = runtime.authenticated_sessions.lock() {
        for session in sessions.values_mut() {
            session.session.close();
        }
        sessions.clear();
    }
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

fn build_recent_endpoint(
    endpoint: &str,
    connected_at_ms: u64,
) -> Result<PocRecentEndpoint, String> {
    let (host, port_text) = endpoint
        .rsplit_once(':')
        .ok_or_else(|| "POC 地址格式无效".to_owned())?;
    let port = port_text
        .parse::<u16>()
        .map_err(|_| "POC 地址端口无效".to_owned())?;
    validate_poc_endpoint(host, port)?;
    Ok(PocRecentEndpoint {
        host: host.to_owned(),
        port,
        connected_at_ms,
    })
}

fn save_poc_recent_endpoint_metadata(
    app: &AppHandle,
    endpoint: &PocRecentEndpoint,
) -> Result<(), String> {
    let path = database_path(app)?;
    let connection = open_database(path).map_err(|error| format!("无法打开本地数据库：{error}"))?;
    let value = serde_json::to_string(endpoint)
        .map_err(|error| format!("无法序列化最近 POC 地址：{error}"))?;
    SettingsRepository::new(&connection)
        .set(POC_RECENT_ENDPOINT_KEY, &value, endpoint.connected_at_ms)
        .map_err(|error| format!("无法保存最近 POC 地址：{error}"))
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

/// Schedules post-commit ITEM_LIVE processing outside the Windows clipboard
/// listener. A local copy must never wait for database or network work.
pub fn schedule_authenticated_local_clipboard(app: &AppHandle, item: ClipboardText) {
    let worker_app = app.clone();
    let _ = std::thread::Builder::new()
        .name("eggclip-authenticated-item-live".to_owned())
        .spawn(move || {
            let (status, sent_peers) =
                persist_and_broadcast_authenticated_local_clipboard(&worker_app, &item)
                    .unwrap_or((AuthenticatedLocalBroadcastStatus::Failed, 0));
            let _ = worker_app.emit(
                "transport://authenticated-local-broadcast",
                AuthenticatedLocalBroadcastEvent { status, sent_peers },
            );
        });
}

fn persist_and_broadcast_authenticated_local_clipboard(
    app: &AppHandle,
    item: &ClipboardText,
) -> Result<(AuthenticatedLocalBroadcastStatus, usize), ()> {
    let runtime = app.state::<PocTransportRuntime>();
    let (space_id, ambiguous_space) = single_authenticated_space(&runtime)?;
    let Some(space_id) = space_id else {
        let status = if ambiguous_space {
            AuthenticatedLocalBroadcastStatus::SkippedAmbiguousSpace
        } else {
            AuthenticatedLocalBroadcastStatus::SkippedNoAuthenticatedPeer
        };
        persist_local_history_fallback(app, item)?;
        return Ok((status, 0));
    };

    let path = database_path(app).map_err(|_| ())?;
    let mut connection = open_database(path).map_err(|_| ())?;
    let settings = SettingsRepository::new(&connection)
        .load_app_settings()
        .map_err(|_| ())?
        .unwrap_or_default();
    if !settings.sync_enabled {
        persist_local_history_fallback(app, item)?;
        return Ok((AuthenticatedLocalBroadcastStatus::SkippedByPolicy, 0));
    }

    let space = SpaceRepository::new(&connection)
        .get(space_id)
        .map_err(|_| ())?
        .ok_or(())?;
    if space.space.state != SpaceState::Active || space.encrypted_space_key_ref.is_none() {
        return Err(());
    }
    #[cfg(windows)]
    let secret_store = crate::secret_store::WindowsCredentialSecretStore;
    #[cfg(not(windows))]
    let secret_store = crate::secret_store::UnavailableSecretStore;
    let mut space_key = load_space_key(&connection, &secret_store, space_id).map_err(|_| ())?;
    let persisted_payload = (|| -> Result<serde_json::Value, ()> {
        let encrypted_content = encrypt_local_clipboard_content(&space_key, space_id, item)?;
        let captured_at = now_ms().map_err(|_| ())?;
        let result = persist_local_clipboard_text(
            &mut connection,
            LocalClipboardPersistInput {
                space_id,
                text: item.as_str().to_owned(),
                encrypted_content,
                hmac_key: &space_key,
                settings: settings.clone(),
                now_ms: captured_at,
            },
        )
        .map_err(|_| ())?;
        ClipboardRepository::new(&connection)
            .apply_retention(space_id, &settings, captured_at)
            .map_err(|_| ())?;
        authenticated_local_item_payload(&result.record.item).ok_or(())
    })();
    space_key.fill(0);
    let payload = persisted_payload?;
    let sent_peers = broadcast_authenticated_item_live(&runtime, space_id, &payload);
    let status = if sent_peers > 0 {
        AuthenticatedLocalBroadcastStatus::Sent
    } else {
        AuthenticatedLocalBroadcastStatus::Failed
    };
    Ok((status, sent_peers))
}

fn persist_local_history_fallback(app: &AppHandle, item: &ClipboardText) -> Result<(), ()> {
    let path = database_path(app).map_err(|_| ())?;
    let captured_at = now_ms().map_err(|_| ())?;
    crate::history::capture_clipboard_history_text_at_path(
        &path,
        item.as_str().to_owned(),
        captured_at,
    )
    .map_err(|_| ())?;
    Ok(())
}

fn single_authenticated_space(runtime: &PocTransportRuntime) -> Result<(Option<Uuid>, bool), ()> {
    let sessions = runtime.authenticated_sessions.lock().map_err(|_| ())?;
    let spaces: HashSet<Uuid> = sessions.values().map(|session| session.space_id).collect();
    if spaces.len() > 1 {
        return Ok((None, true));
    }
    Ok((spaces.into_iter().next(), false))
}

fn encrypt_local_clipboard_content(
    space_key: &[u8; 32],
    space_id: Uuid,
    item: &ClipboardText,
) -> Result<Vec<u8>, ()> {
    let mut nonce = [0u8; AES_GCM_NONCE_BYTES];
    getrandom::getrandom(&mut nonce).map_err(|_| ())?;
    let aad = format!("EggClip v1 local clipboard storage\nspaceId={space_id}\n");
    let (body, tag) =
        aes256_gcm_encrypt(*space_key, nonce, aad.as_bytes(), item.as_str().as_bytes())
            .map_err(|_| ())?;
    serde_json::to_vec(&serde_json::json!({
        "version": 1,
        "nonce": encode_base64url(&nonce),
        "aad": encode_base64url(aad.as_bytes()),
        "body": encode_base64url(&body),
        "tag": encode_base64url(&tag),
    }))
    .map_err(|_| ())
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct LocalEncryptedClipboardContent {
    version: u8,
    nonce: String,
    aad: String,
    body: String,
    tag: String,
}

fn decrypt_local_clipboard_content(
    space_key: &[u8; 32],
    space_id: Uuid,
    encrypted_content: &[u8],
) -> Result<ClipboardText, ()> {
    let stored: LocalEncryptedClipboardContent =
        serde_json::from_slice(encrypted_content).map_err(|_| ())?;
    if stored.version != 1 {
        return Err(());
    }
    let expected_aad = format!("EggClip v1 local clipboard storage\nspaceId={space_id}\n");
    let aad = decode_base64url(&stored.aad).map_err(|_| ())?;
    if aad != expected_aad.as_bytes() {
        return Err(());
    }
    let nonce = fixed_bytes::<AES_GCM_NONCE_BYTES>(
        &decode_base64url(&stored.nonce).map_err(|_| ())?,
        "nonce",
    )
    .map_err(|_| ())?;
    let tag =
        fixed_bytes::<AES_GCM_TAG_BYTES>(&decode_base64url(&stored.tag).map_err(|_| ())?, "tag")
            .map_err(|_| ())?;
    let body = decode_base64url(&stored.body).map_err(|_| ())?;
    let plaintext = aes256_gcm_decrypt(*space_key, nonce, &aad, &body, tag).map_err(|_| ())?;
    let text = String::from_utf8(plaintext).map_err(|_| ())?;
    ClipboardText::parse(text).map_err(|_| ())
}

fn authenticated_local_item_payload(
    item: &crate::sync::ClipboardItem,
) -> Option<serde_json::Value> {
    let content = item.plaintext.as_ref()?;
    Some(serde_json::json!({
        "itemId": item.item_id,
        "spaceId": item.space_id,
        "originDeviceId": item.origin_device_id,
        "originSeq": item.origin_seq,
        "hlc": item.hlc.to_wire(),
        "contentType": item.content_type.wire_value(),
        "contentLength": item.content_length,
        "contentDigest": item.content_digest,
        "createdAt": item.created_at,
        "content": content,
    }))
}

fn send_authenticated_sync_heads(app: &AppHandle, peer: &str) -> Result<(), ()> {
    let runtime = app.state::<PocTransportRuntime>();
    let space_id = runtime
        .authenticated_sessions
        .lock()
        .map_err(|_| ())?
        .get(peer)
        .map(|entry| entry.space_id)
        .ok_or(())?;
    let payload = build_sync_heads_payload(app, space_id)?;
    send_authenticated_business_payload(app, peer, MessageType::SyncHeads, &payload)
}

fn send_authenticated_business_payload(
    app: &AppHandle,
    peer: &str,
    message_type: MessageType,
    payload: &serde_json::Value,
) -> Result<(), ()> {
    let runtime = app.state::<PocTransportRuntime>();
    let frame = runtime
        .authenticated_sessions
        .lock()
        .map_err(|_| ())?
        .get_mut(peer)
        .ok_or(())?
        .session
        .encode_business_message(message_type, Uuid::now_v7().to_string(), payload)
        .map_err(|_| ())?;
    let sent = runtime
        .peers
        .lock()
        .map_err(|_| ())?
        .get(peer)
        .ok_or(())?
        .send(frame)
        .map_err(|_| ());
    sent
}

fn build_sync_heads_payload(app: &AppHandle, space_id: Uuid) -> Result<serde_json::Value, ()> {
    let path = database_path(app).map_err(|_| ())?;
    let connection = open_database(path).map_err(|_| ())?;
    let heads = ClipboardRepository::new(&connection)
        .summarize_available_sequences(space_id, now_ms().map_err(|_| ())?)
        .map_err(|_| ())?;
    let mut latest = std::collections::BTreeMap::new();
    let mut minimum_available = std::collections::BTreeMap::new();
    for head in heads {
        latest.insert(head.origin_device_id.to_string(), head.latest_origin_seq);
        minimum_available.insert(head.origin_device_id.to_string(), head.minimum_available);
    }
    let payload = SyncHeadsPayload {
        heads: latest,
        minimum_available,
    };
    payload.validate().map_err(|_| ())?;
    serde_json::to_value(payload).map_err(|_| ())
}

fn broadcast_authenticated_item_live(
    runtime: &PocTransportRuntime,
    space_id: Uuid,
    payload: &serde_json::Value,
) -> usize {
    let mut frames = Vec::new();
    let mut stale_sessions = Vec::new();
    if let Ok(mut sessions) = runtime.authenticated_sessions.lock() {
        for (peer, entry) in sessions.iter_mut() {
            if entry.space_id != space_id {
                continue;
            }
            match entry.session.encode_business_message(
                MessageType::ItemLive,
                Uuid::now_v7().to_string(),
                payload,
            ) {
                Ok(frame) => frames.push((peer.clone(), frame)),
                Err(_) => {
                    entry.session.close();
                    stale_sessions.push(peer.clone());
                }
            }
        }
        for peer in &stale_sessions {
            sessions.remove(peer);
        }
    } else {
        return 0;
    }

    let mut sent_peers = 0;
    let mut stale_peers = Vec::new();
    if let Ok(mut peers) = runtime.peers.lock() {
        for (peer, frame) in frames {
            match peers.get(&peer) {
                Some(sender) if sender.send(frame).is_ok() => sent_peers += 1,
                _ => stale_peers.push(peer),
            }
        }
        for peer in &stale_peers {
            peers.remove(peer);
        }
    }
    if !stale_peers.is_empty() {
        if let Ok(mut sessions) = runtime.authenticated_sessions.lock() {
            for peer in &stale_peers {
                if let Some(mut session) = sessions.remove(peer) {
                    session.session.close();
                }
            }
        }
    }
    sent_peers
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
        peers.insert(peer.clone(), outgoing_tx.clone());
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
    let heartbeat_tx = outgoing_tx.clone();
    let heartbeat_task = tauri::async_runtime::spawn(async move {
        let mut ticker = interval(AUTHENTICATED_HEARTBEAT_INTERVAL);
        ticker.set_missed_tick_behavior(MissedTickBehavior::Delay);
        ticker.tick().await;
        loop {
            ticker.tick().await;
            if heartbeat_tx.send(Message::Ping(Vec::new().into())).is_err() {
                break;
            }
        }
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
                match try_accept_authenticated_frame(&app, &peer, &text) {
                    AuthenticatedFrameRoute::Handled => {
                        record_poc_frame_result(&app, Ok(()));
                        continue;
                    }
                    AuthenticatedFrameRoute::Rejected => {
                        record_poc_frame_result(
                            &app,
                            Err(PocRejectionReason::AuthenticatedFrameRejected),
                        );
                        break;
                    }
                    AuthenticatedFrameRoute::NotAuthenticated => {}
                }
                match try_accept_pairing_client_hello(&app, &peer, &text) {
                    PairingClientHelloRoute::Handled(server_hello_frame) => {
                        record_poc_frame_result(&app, Ok(()));
                        let _ = outgoing_tx.send(Message::Text(server_hello_frame.into()));
                        continue;
                    }
                    PairingClientHelloRoute::Rejected(reason) => {
                        record_poc_frame_result(&app, Err(reason));
                        break;
                    }
                    PairingClientHelloRoute::NotPairing => {}
                }
                match try_accept_pairing_auth_proof(&app, &peer, &text) {
                    PairingAuthProofRoute::Handled(frames) => {
                        record_poc_frame_result(&app, Ok(()));
                        for frame in frames {
                            let _ = outgoing_tx.send(Message::Text(frame.into()));
                        }
                        if send_authenticated_sync_heads(&app, &peer).is_err() {
                            record_poc_frame_result(
                                &app,
                                Err(PocRejectionReason::PairingInternalError),
                            );
                            break;
                        }
                        continue;
                    }
                    PairingAuthProofRoute::Rejected(reason) => {
                        record_poc_frame_result(&app, Err(reason));
                        break;
                    }
                    PairingAuthProofRoute::NotPairing => {}
                }
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
            Message::Ping(payload) => {
                let _ = outgoing_tx.send(Message::Pong(payload));
            }
            Message::Close(_) => break,
            _ => {}
        }
    }

    if let Ok(mut peers) = app.state::<PocTransportRuntime>().peers.lock() {
        peers.remove(&peer);
    }
    if let Ok(mut handshakes) = app.state::<PocTransportRuntime>().pairing_handshakes.lock() {
        handshakes.remove(&peer);
    }
    if let Ok(mut sessions) = app
        .state::<PocTransportRuntime>()
        .authenticated_sessions
        .lock()
    {
        if let Some(mut session) = sessions.remove(&peer) {
            let _ = mark_trusted_device_offline(&app, session.device_id);
            let event = AuthenticatedConnectionStateEvent {
                peer: peer.clone(),
                device_id: session.device_id.to_string(),
                space_id: session.space_id.to_string(),
                state: "offline",
            };
            session.session.close();
            let _ = app.emit("transport://authenticated-connection", event);
        }
    }
    heartbeat_task.abort();
    write_task.abort();
    let _ = app.emit("transport://poc-peer-disconnected", PocPeerEvent { peer });
}

enum PairingClientHelloRoute {
    Handled(String),
    Rejected(PocRejectionReason),
    NotPairing,
}

enum PairingAuthProofRoute {
    Handled(Vec<String>),
    Rejected(PocRejectionReason),
    NotPairing,
}

enum AuthenticatedFrameRoute {
    Handled,
    Rejected,
    NotAuthenticated,
}

fn try_accept_pairing_client_hello(
    app: &AppHandle,
    peer: &str,
    text: &str,
) -> PairingClientHelloRoute {
    if !is_pairing_client_hello_frame(text) {
        return PairingClientHelloRoute::NotPairing;
    }

    let path = match database_path(app) {
        Ok(path) => path,
        Err(_) => {
            return PairingClientHelloRoute::Rejected(PocRejectionReason::PairingInternalError)
        }
    };
    let mut connection = match open_database(path) {
        Ok(connection) => connection,
        Err(_) => {
            return PairingClientHelloRoute::Rejected(PocRejectionReason::PairingInternalError)
        }
    };
    #[cfg(windows)]
    let mut store = crate::secret_store::WindowsCredentialSecretStore;
    #[cfg(not(windows))]
    let mut store = crate::secret_store::UnavailableSecretStore;

    let server_ephemeral_secret = match random_x25519_secret() {
        Ok(secret) => secret,
        Err(_) => {
            return PairingClientHelloRoute::Rejected(PocRejectionReason::PairingInternalError)
        }
    };
    let server_ephemeral_public_key = encode_base64url(&server_ephemeral_secret.public_key());
    let message_id = Uuid::now_v7().to_string();
    let timestamp_ms = match now_ms() {
        Ok(timestamp) => timestamp,
        Err(_) => {
            return PairingClientHelloRoute::Rejected(PocRejectionReason::PairingInternalError)
        }
    };

    let accepted = if is_trusted_device_client_hello_frame(text) {
        accept_trusted_device_client_hello(
            &mut connection,
            &mut store,
            text,
            &server_ephemeral_public_key,
            &message_id,
            timestamp_ms,
        )
    } else {
        accept_pairing_client_hello(
            &mut connection,
            &mut store,
            text,
            &server_ephemeral_public_key,
            &message_id,
            timestamp_ms,
        )
    };
    let draft = match accepted {
        Ok(draft) => draft,
        Err(error) => {
            return PairingClientHelloRoute::Rejected(pairing_client_hello_rejection(&error))
        }
    };

    if remember_pairing_handshake(app, peer, &draft, server_ephemeral_secret).is_err() {
        return PairingClientHelloRoute::Rejected(PocRejectionReason::PairingInternalError);
    }
    PairingClientHelloRoute::Handled(draft.server_hello_frame)
}

fn try_accept_pairing_auth_proof(app: &AppHandle, peer: &str, text: &str) -> PairingAuthProofRoute {
    if !is_pairing_auth_proof_frame(text) {
        return PairingAuthProofRoute::NotPairing;
    }
    let Some(handshake) = take_pairing_handshake(app, peer) else {
        return PairingAuthProofRoute::Rejected(PocRejectionReason::PairingServerStateMissing);
    };
    let is_trusted_reconnect = is_trusted_device_pairing_context(&handshake.pairing_context);
    let message_id = Uuid::now_v7().to_string();
    let input = PairingServerAuthProofInput {
        invitation_id: handshake.invitation_id,
        space_id: handshake.space_id,
        peer_device_id: handshake.peer_device_id,
        peer_identity_public_key: handshake.peer_identity_public_key,
        peer_ephemeral_public_key: handshake.peer_ephemeral_public_key,
        server_device_id: handshake.server_device_id,
        server_identity_public_key: handshake.server_identity_public_key,
        server_ephemeral_public_key: handshake.server_ephemeral_public_key,
        pairing_context: handshake.pairing_context,
        server_ephemeral_secret: handshake.server_ephemeral_secret,
    };
    match accept_pairing_auth_proof(input, text, &message_id) {
        Ok(accepted) => {
            let auth_ok_frame = accepted.auth_ok_frame.clone();
            let accepted_at = match now_ms() {
                Ok(timestamp) => timestamp,
                Err(_) => {
                    return PairingAuthProofRoute::Rejected(
                        PocRejectionReason::PairingInternalError,
                    )
                }
            };
            if is_trusted_reconnect {
                if mark_trusted_device_connected(app, &accepted, accepted_at).is_err() {
                    return PairingAuthProofRoute::Rejected(
                        PocRejectionReason::PairingInternalError,
                    );
                }
                if remember_authenticated_session(app, peer, accepted).is_err() {
                    return PairingAuthProofRoute::Rejected(
                        PocRejectionReason::PairingInternalError,
                    );
                }
                PairingAuthProofRoute::Handled(vec![auth_ok_frame])
            } else {
                if persist_trusted_pairing_device(app, &accepted, accepted_at).is_err() {
                    return PairingAuthProofRoute::Rejected(
                        PocRejectionReason::PairingInternalError,
                    );
                }
                let space_key_frame = match build_space_key_delivery_frame(app, &accepted, 4) {
                    Ok(frame) => frame,
                    Err(_) => {
                        return PairingAuthProofRoute::Rejected(
                            PocRejectionReason::PairingInternalError,
                        )
                    }
                };
                if remember_authenticated_session(app, peer, accepted).is_err() {
                    return PairingAuthProofRoute::Rejected(
                        PocRejectionReason::PairingInternalError,
                    );
                }
                PairingAuthProofRoute::Handled(vec![auth_ok_frame, space_key_frame])
            }
        }
        Err(error) => PairingAuthProofRoute::Rejected(pairing_auth_proof_rejection(&error)),
    }
}

fn persist_trusted_pairing_device(
    app: &AppHandle,
    accepted: &crate::pairing::PairingServerAuthProofAccepted,
    accepted_at: u64,
) -> Result<(), ()> {
    let path = database_path(app).map_err(|_| ())?;
    let mut connection = open_database(path).map_err(|_| ())?;
    persist_trusted_pairing_device_in_connection(&mut connection, accepted, accepted_at)
}

fn mark_trusted_device_connected(
    app: &AppHandle,
    accepted: &crate::pairing::PairingServerAuthProofAccepted,
    connected_at: u64,
) -> Result<(), ()> {
    let space_id = Uuid::parse_str(&accepted.space_id).map_err(|_| ())?;
    let peer_device_id = Uuid::parse_str(&accepted.peer_device_id).map_err(|_| ())?;
    let path = database_path(app).map_err(|_| ())?;
    let connection = open_database(path).map_err(|_| ())?;
    let repository = DeviceRepository::new(&connection);
    let mut record = repository.get(peer_device_id).map_err(|_| ())?.ok_or(())?;
    if record.device.space_id != space_id
        || record.device.trust_state != DeviceTrustState::Trusted
        || record.revoked_at.is_some()
        || record.device.identity_public_key_ref != accepted.peer_identity_public_key
    {
        return Err(());
    }
    record.device.connection_state = DeviceConnectionState::Online;
    record.device.last_seen_at = Some(connected_at);
    repository.upsert(&record).map_err(|_| ())
}

fn mark_trusted_device_offline(app: &AppHandle, device_id: Uuid) -> Result<(), ()> {
    let path = database_path(app).map_err(|_| ())?;
    let connection = open_database(path).map_err(|_| ())?;
    let repository = DeviceRepository::new(&connection);
    let mut record = repository.get(device_id).map_err(|_| ())?.ok_or(())?;
    if record.device.trust_state != DeviceTrustState::Trusted || record.revoked_at.is_some() {
        return Err(());
    }
    record.device.connection_state = DeviceConnectionState::Offline;
    repository.upsert(&record).map_err(|_| ())
}

fn build_space_key_delivery_frame(
    app: &AppHandle,
    accepted: &crate::pairing::PairingServerAuthProofAccepted,
    session_counter: u64,
) -> Result<String, ()> {
    let space_id = Uuid::parse_str(&accepted.space_id).map_err(|_| ())?;
    let path = database_path(app).map_err(|_| ())?;
    let connection = open_database(path).map_err(|_| ())?;
    #[cfg(windows)]
    let store = crate::secret_store::WindowsCredentialSecretStore;
    #[cfg(not(windows))]
    let store = crate::secret_store::UnavailableSecretStore;
    let mut space_key = load_space_key(&connection, &store, space_id).map_err(|_| ())?;
    let space = SpaceRepository::new(&connection)
        .get(space_id)
        .map_err(|_| ())?
        .ok_or(())?;
    let payload = serde_json::json!({
        "spaceId": accepted.space_id,
        "keyVersion": space.space.key_version,
        "spaceKey": encode_base64url(&space_key),
        "delivery": "pairing-v1"
    });
    space_key.fill(0);

    let mut session = AuthenticatedTransportSession::new(
        SessionDirection::ClientToServer,
        accepted.session_keys.client_to_server,
        SessionDirection::ServerToClient,
        accepted.session_keys.server_to_client,
        session_counter,
    );
    session
        .encode_business_frame(
            MessageType::SpaceKeyRotated,
            Uuid::now_v7().to_string(),
            &payload,
        )
        .map_err(|_| ())
}

fn persist_trusted_pairing_device_in_connection(
    connection: &mut rusqlite::Connection,
    accepted: &crate::pairing::PairingServerAuthProofAccepted,
    accepted_at: u64,
) -> Result<(), ()> {
    let invitation_id = Uuid::parse_str(&accepted.invitation_id).map_err(|_| ())?;
    let space_id = Uuid::parse_str(&accepted.space_id).map_err(|_| ())?;
    let peer_device_id = Uuid::parse_str(&accepted.peer_device_id).map_err(|_| ())?;
    let transaction = connection.transaction().map_err(|_| ())?;
    if !PairingInvitationRepository::new(&transaction)
        .mark_consumed(invitation_id, peer_device_id, accepted_at)
        .map_err(|_| ())?
    {
        return Err(());
    }
    DeviceRepository::new(&transaction)
        .upsert(&DeviceRecord {
            device: Device {
                device_id: peer_device_id,
                space_id,
                display_name: trusted_pairing_device_display_name(&accepted.peer_device_id),
                identity_public_key_ref: accepted.peer_identity_public_key.clone(),
                trust_state: DeviceTrustState::Trusted,
                connection_state: DeviceConnectionState::Online,
                last_seen_at: Some(accepted_at),
            },
            paired_at: Some(accepted_at),
            revoked_at: None,
        })
        .map_err(|_| ())?;
    transaction.commit().map_err(|_| ())
}

fn trusted_pairing_device_display_name(device_id: &str) -> String {
    let short_id = device_id.get(0..8).unwrap_or("unknown");
    format!("HarmonyOS 设备 #{short_id}")
}

fn pairing_client_hello_rejection(error: &PairingError) -> PocRejectionReason {
    match error {
        PairingError::InvitationMissing => PocRejectionReason::PairingInvitationMissing,
        PairingError::InvitationExpired => PocRejectionReason::PairingInvitationExpired,
        PairingError::InvitationConsumed => PocRejectionReason::PairingInvitationConsumed,
        PairingError::InvalidClientHello | PairingError::InvalidInvitationSecret => {
            PocRejectionReason::PairingClientHelloRejected
        }
        _ => PocRejectionReason::PairingInternalError,
    }
}

fn pairing_auth_proof_rejection(error: &PairingError) -> PocRejectionReason {
    match error {
        PairingError::AuthProofSignatureFailed => PocRejectionReason::PairingAuthSignatureRejected,
        PairingError::InvalidAuthProof => PocRejectionReason::PairingAuthProofRejected,
        _ => PocRejectionReason::PairingInternalError,
    }
}

fn try_accept_authenticated_frame(
    app: &AppHandle,
    peer: &str,
    text: &str,
) -> AuthenticatedFrameRoute {
    let Some(message_type) = authenticated_message_type(text) else {
        return AuthenticatedFrameRoute::NotAuthenticated;
    };
    let payload = {
        let runtime = app.state::<PocTransportRuntime>();
        let mut sessions = match runtime.authenticated_sessions.lock() {
            Ok(sessions) => sessions,
            Err(_) => return AuthenticatedFrameRoute::Rejected,
        };
        let Some(session) = sessions.get_mut(peer) else {
            return AuthenticatedFrameRoute::Rejected;
        };
        match session.session.accept_text_frame(text) {
            Ok(payload) => payload,
            Err(_) => {
                session.session.close();
                sessions.remove(peer);
                return AuthenticatedFrameRoute::Rejected;
            }
        }
    };

    if dispatch_authenticated_payload(app, peer, message_type, &payload).is_err() {
        close_authenticated_session(app, peer);
        return AuthenticatedFrameRoute::Rejected;
    }
    let _ = app.emit(
        "transport://authenticated-payload",
        PocAuthenticatedFrameEvent {
            peer: peer.to_owned(),
            message_type,
            payload,
        },
    );
    AuthenticatedFrameRoute::Handled
}

fn dispatch_authenticated_payload(
    app: &AppHandle,
    peer: &str,
    message_type: MessageType,
    payload: &serde_json::Value,
) -> Result<(), ()> {
    match message_type {
        MessageType::SyncHeads => return handle_remote_sync_heads(app, peer, payload),
        MessageType::RequestRange => return respond_to_request_range(app, peer, payload),
        MessageType::ItemBatch => return handle_inbound_item_batch(app, peer, payload),
        MessageType::ItemAck => {
            let ack: ItemAckPayload = serde_json::from_value(payload.clone()).map_err(|_| ())?;
            ack.validate().map_err(|_| ())?;
            let _ = app.emit("transport://item-ack", ack);
            return Ok(());
        }
        MessageType::ItemLive => {}
        _ => return Ok(()),
    }
    let (protocol_item, clipboard_item) =
        authenticated_clipboard_text_from_payload(message_type, payload)?;
    let settings = load_authenticated_inbound_settings(app)?;
    let policy = crate::sync::apply_authenticated_inbound_item_with_settings(
        app,
        &clipboard_item,
        crate::sync::InboundClipboardEventKind::ItemLive,
        &settings,
    )
    .map_err(|_| ())?;
    if policy.update_history {
        let received_at = now_ms().map_err(|_| ())?;
        let _ = persist_authenticated_remote_history_if_possible(
            app,
            &protocol_item,
            received_at,
            &settings,
        );
    }
    let _ = app.emit(
        "transport://authenticated-clipboard-text",
        AuthenticatedClipboardTextEvent {
            peer: peer.to_owned(),
            item_id: protocol_item.item_id,
            origin_device_id: protocol_item.origin_device_id,
            origin_seq: protocol_item.origin_seq,
            item: clipboard_item,
        },
    );
    Ok(())
}

fn authenticated_peer_context(app: &AppHandle, peer: &str) -> Result<(Uuid, Uuid), ()> {
    let runtime = app.state::<PocTransportRuntime>();
    let context = runtime
        .authenticated_sessions
        .lock()
        .map_err(|_| ())?
        .get(peer)
        .map(|entry| (entry.space_id, entry.device_id))
        .ok_or(());
    context
}

fn handle_remote_sync_heads(
    app: &AppHandle,
    peer: &str,
    payload: &serde_json::Value,
) -> Result<(), ()> {
    let remote: SyncHeadsPayload = serde_json::from_value(payload.clone()).map_err(|_| ())?;
    remote.validate().map_err(|_| ())?;
    let (space_id, peer_device_id) = authenticated_peer_context(app, peer)?;
    let path = database_path(app).map_err(|_| ())?;
    let connection = open_database(path).map_err(|_| ())?;
    let updated_at = now_ms().map_err(|_| ())?;
    for (origin, latest) in &remote.heads {
        let origin_device_id = Uuid::parse_str(origin).map_err(|_| ())?;
        let minimum_available = *remote.minimum_available.get(origin).ok_or(())?;
        SyncHeadRepository::new(&connection)
            .upsert(&SyncHeadRecord {
                head: SyncHead {
                    space_id,
                    origin_device_id,
                    latest_origin_seq: *latest,
                    minimum_available,
                    updated_at,
                },
                peer_device_id,
            })
            .map_err(|_| ())?;
    }
    let local = ClipboardRepository::new(&connection)
        .summarize_available_sequences(space_id, updated_at)
        .map_err(|_| ())?;
    let local_latest: HashMap<String, u64> = local
        .into_iter()
        .map(|head| (head.origin_device_id.to_string(), head.latest_origin_seq))
        .collect();
    let ranges: Vec<RequestRange> = remote
        .heads
        .iter()
        .filter_map(|(origin, latest)| {
            let local_seq = local_latest.get(origin).copied().unwrap_or(0);
            (*latest > local_seq).then(|| RequestRange {
                origin_device_id: origin.clone(),
                from_seq: local_seq.saturating_add(1),
                to_seq: *latest,
            })
        })
        .take(MAX_BATCH_ITEMS)
        .collect();
    if ranges.is_empty() {
        return Ok(());
    }
    let request = RequestRangePayload { ranges };
    request.validate().map_err(|_| ())?;
    let value = serde_json::to_value(request).map_err(|_| ())?;
    send_authenticated_business_payload(app, peer, MessageType::RequestRange, &value)
}

fn handle_inbound_item_batch(
    app: &AppHandle,
    peer: &str,
    payload: &serde_json::Value,
) -> Result<(), ()> {
    let batch: ItemBatchPayload = serde_json::from_value(payload.clone()).map_err(|_| ())?;
    batch.validate().map_err(|_| ())?;
    let (space_id, _) = authenticated_peer_context(app, peer)?;
    let settings = load_authenticated_inbound_settings(app)?;
    let received_at = now_ms().map_err(|_| ())?;
    let mut acked = Vec::new();
    for item in &batch.items {
        if Uuid::parse_str(&item.space_id).map_err(|_| ())? != space_id {
            return Err(());
        }
        match persist_authenticated_remote_history_if_possible(app, item, received_at, &settings)? {
            AuthenticatedRemoteHistoryOutcome::Inserted
            | AuthenticatedRemoteHistoryOutcome::Duplicate => {
                acked.push(item.item_id.clone());
            }
            AuthenticatedRemoteHistoryOutcome::Conflict => return Err(()),
            AuthenticatedRemoteHistoryOutcome::SkippedByPolicy
            | AuthenticatedRemoteHistoryOutcome::SkippedMissingTrustGraph => return Err(()),
        }
    }
    let _ = app.emit("transport://retention-gaps", batch.gaps.clone());
    if acked.is_empty() {
        return Ok(());
    }
    let ack = ItemAckPayload { item_ids: acked };
    ack.validate().map_err(|_| ())?;
    let value = serde_json::to_value(ack).map_err(|_| ())?;
    send_authenticated_business_payload(app, peer, MessageType::ItemAck, &value)
}

fn respond_to_request_range(
    app: &AppHandle,
    peer: &str,
    payload: &serde_json::Value,
) -> Result<(), ()> {
    let request: RequestRangePayload = serde_json::from_value(payload.clone()).map_err(|_| ())?;
    request.validate().map_err(|_| ())?;
    let runtime = app.state::<PocTransportRuntime>();
    let space_id = runtime
        .authenticated_sessions
        .lock()
        .map_err(|_| ())?
        .get(peer)
        .map(|entry| entry.space_id)
        .ok_or(())?;
    let path = database_path(app).map_err(|_| ())?;
    let connection = open_database(path).map_err(|_| ())?;
    #[cfg(windows)]
    let secret_store = crate::secret_store::WindowsCredentialSecretStore;
    #[cfg(not(windows))]
    let secret_store = crate::secret_store::UnavailableSecretStore;
    let mut space_key = load_space_key(&connection, &secret_store, space_id).map_err(|_| ())?;
    let result = (|| -> Result<ItemBatchPayload, ()> {
        let repository = ClipboardRepository::new(&connection);
        let available = repository
            .summarize_available_sequences(space_id, now_ms().map_err(|_| ())?)
            .map_err(|_| ())?;
        let available_by_origin: HashMap<Uuid, (u64, u64)> = available
            .into_iter()
            .map(|head| {
                (
                    head.origin_device_id,
                    (head.minimum_available, head.latest_origin_seq),
                )
            })
            .collect();
        let mut items = Vec::new();
        let mut gaps = Vec::new();
        let mut total_plaintext_bytes = 0usize;
        for range in request.ranges {
            if items.len() >= MAX_BATCH_ITEMS {
                break;
            }
            let origin_device_id = Uuid::parse_str(&range.origin_device_id).map_err(|_| ())?;
            let Some((minimum_available, latest_available)) =
                available_by_origin.get(&origin_device_id).copied()
            else {
                gaps.push(RetentionGap {
                    origin_device_id: range.origin_device_id,
                    requested_from_seq: range.from_seq,
                    minimum_available: range.to_seq.saturating_add(1),
                });
                continue;
            };
            if range.from_seq < minimum_available {
                gaps.push(RetentionGap {
                    origin_device_id: range.origin_device_id.clone(),
                    requested_from_seq: range.from_seq,
                    minimum_available,
                });
            }
            let from_seq = range.from_seq.max(minimum_available);
            let to_seq = range.to_seq.min(latest_available);
            if from_seq > to_seq {
                continue;
            }
            let remaining = (MAX_BATCH_ITEMS - items.len()) as u16;
            let records = repository
                .list_by_origin_range(space_id, origin_device_id, from_seq, to_seq, remaining)
                .map_err(|_| ())?;
            for record in records {
                let text = match decrypt_local_clipboard_content(
                    &space_key,
                    space_id,
                    &record.encrypted_content,
                ) {
                    Ok(text) => text,
                    Err(_) => {
                        gaps.push(RetentionGap {
                            origin_device_id: origin_device_id.to_string(),
                            requested_from_seq: record.item.origin_seq,
                            minimum_available: record.item.origin_seq.saturating_add(1),
                        });
                        continue;
                    }
                };
                let next_total = total_plaintext_bytes.saturating_add(text.as_str().len());
                if next_total > MAX_BATCH_PLAINTEXT_BYTES {
                    break;
                }
                total_plaintext_bytes = next_total;
                items.push(ProtocolClipboardItem {
                    item_id: record.item.item_id.to_string(),
                    space_id: record.item.space_id.to_string(),
                    origin_device_id: record.item.origin_device_id.to_string(),
                    origin_seq: record.item.origin_seq,
                    hlc: record.item.hlc.to_wire(),
                    content_type: ProtocolContentType::TextPlain,
                    content_length: record.item.content_length,
                    content_digest: record.item.content_digest,
                    created_at: record.item.created_at,
                    content: text.as_str().to_owned(),
                });
            }
        }
        let batch = ItemBatchPayload { items, gaps };
        batch.validate().map_err(|_| ())?;
        Ok(batch)
    })();
    space_key.fill(0);
    let batch = result?;
    let value = serde_json::to_value(batch).map_err(|_| ())?;
    send_authenticated_business_payload(app, peer, MessageType::ItemBatch, &value)
}

fn load_authenticated_inbound_settings(app: &AppHandle) -> Result<AppSettings, ()> {
    let path = database_path(app).map_err(|_| ())?;
    let connection = open_database(path).map_err(|_| ())?;
    SettingsRepository::new(&connection)
        .load_app_settings()
        .map_err(|_| ())
        .map(|settings| settings.unwrap_or_default())
}

fn persist_authenticated_remote_history_if_possible(
    app: &AppHandle,
    item: &ProtocolClipboardItem,
    received_at: u64,
    settings: &AppSettings,
) -> Result<AuthenticatedRemoteHistoryOutcome, ()> {
    if !settings.history_enabled || settings.history_limit == 0 {
        return Ok(AuthenticatedRemoteHistoryOutcome::SkippedByPolicy);
    }
    let path = database_path(app).map_err(|_| ())?;
    let connection = open_database(path).map_err(|_| ())?;
    let space_id = uuid::Uuid::parse_str(&item.space_id).map_err(|_| ())?;
    let origin_device_id = uuid::Uuid::parse_str(&item.origin_device_id).map_err(|_| ())?;
    if SpaceRepository::new(&connection)
        .get(space_id)
        .map_err(|_| ())?
        .is_none()
        || DeviceRepository::new(&connection)
            .get(origin_device_id)
            .map_err(|_| ())?
            .is_none()
    {
        return Ok(AuthenticatedRemoteHistoryOutcome::SkippedMissingTrustGraph);
    }

    #[cfg(windows)]
    let secret_store = crate::secret_store::WindowsCredentialSecretStore;
    #[cfg(not(windows))]
    let secret_store = crate::secret_store::UnavailableSecretStore;
    let mut space_key = load_space_key(&connection, &secret_store, space_id).map_err(|_| ())?;
    let plaintext = ClipboardText::parse(item.content.clone()).map_err(|_| ())?;
    let encrypted_content = encrypt_local_clipboard_content(&space_key, space_id, &plaintext);
    space_key.fill(0);
    let record =
        authenticated_remote_clipboard_record(item, received_at, settings, encrypted_content?)?;
    let outcome = ClipboardRepository::new(&connection)
        .insert_deduplicated(&record)
        .map_err(|_| ())?;
    ClipboardRepository::new(&connection)
        .apply_retention(space_id, settings, received_at)
        .map_err(|_| ())?;
    Ok(match outcome {
        ClipboardInsertOutcome::Inserted => AuthenticatedRemoteHistoryOutcome::Inserted,
        ClipboardInsertOutcome::Duplicate => AuthenticatedRemoteHistoryOutcome::Duplicate,
        ClipboardInsertOutcome::Conflict => AuthenticatedRemoteHistoryOutcome::Conflict,
    })
}

fn authenticated_remote_clipboard_record(
    item: &ProtocolClipboardItem,
    received_at: u64,
    settings: &AppSettings,
    encrypted_content: Vec<u8>,
) -> Result<ClipboardItemRecord, ()> {
    item.validate().map_err(|_| ())?;
    let content_type = match item.content_type {
        crate::protocol::ContentType::TextPlain => SyncContentType::TextPlain,
    };
    Ok(ClipboardItemRecord {
        item: crate::sync::ClipboardItem {
            item_id: uuid::Uuid::parse_str(&item.item_id).map_err(|_| ())?,
            space_id: uuid::Uuid::parse_str(&item.space_id).map_err(|_| ())?,
            origin_device_id: uuid::Uuid::parse_str(&item.origin_device_id).map_err(|_| ())?,
            origin_seq: item.origin_seq,
            hlc: HlcTimestamp::from_wire(&item.hlc).ok_or(())?,
            content_type,
            content_length: item.content_length,
            content_digest: item.content_digest.clone(),
            created_at: item.created_at,
            encrypted_content_ref: None,
            plaintext: None,
        },
        encrypted_content,
        received_at,
        expires_at: retention_expires_at(received_at, settings.retention_days).map_err(|_| ())?,
        deleted_at: None,
    })
}

fn authenticated_clipboard_text_from_payload(
    message_type: MessageType,
    payload: &serde_json::Value,
) -> Result<(ProtocolClipboardItem, ClipboardText), ()> {
    if message_type != MessageType::ItemLive {
        return Err(());
    }
    let item: ProtocolClipboardItem = serde_json::from_value(payload.clone()).map_err(|_| ())?;
    item.validate().map_err(|_| ())?;
    let clipboard_text = ClipboardText::parse(item.content.clone()).map_err(|_| ())?;
    Ok((item, clipboard_text))
}

fn is_pairing_client_hello_frame(text: &str) -> bool {
    matches!(
        parse_envelope(text),
        Ok(ProtocolEnvelope::PreAuth(envelope)) if envelope.message_type == MessageType::ClientHello
    )
}

fn is_trusted_device_client_hello_frame(text: &str) -> bool {
    let Ok(ProtocolEnvelope::PreAuth(envelope)) = parse_envelope(text) else {
        return false;
    };
    if envelope.message_type != MessageType::ClientHello {
        return false;
    }
    let Ok(hello) = serde_json::from_value::<HelloPayload>(envelope.payload) else {
        return false;
    };
    is_trusted_device_pairing_context(hello.pairing_context.as_deref().unwrap_or_default())
}

fn is_trusted_device_pairing_context(pairing_context: &str) -> bool {
    pairing_context.starts_with("trusted-device:")
}

fn is_pairing_auth_proof_frame(text: &str) -> bool {
    matches!(
        parse_envelope(text),
        Ok(ProtocolEnvelope::PreAuth(envelope)) if envelope.message_type == MessageType::AuthProof
    )
}

fn authenticated_message_type(text: &str) -> Option<MessageType> {
    match parse_envelope(text) {
        Ok(ProtocolEnvelope::Encrypted(envelope)) => Some(envelope.message_type),
        _ => None,
    }
}

fn random_x25519_secret() -> Result<X25519Secret, ()> {
    let mut private_key = [0u8; X25519_PRIVATE_KEY_BYTES];
    getrandom::getrandom(&mut private_key).map_err(|_| ())?;
    Ok(X25519Secret::from_private_key(private_key))
}

fn remember_pairing_handshake(
    app: &AppHandle,
    peer: &str,
    draft: &PairingServerHelloDraft,
    server_ephemeral_secret: X25519Secret,
) -> Result<(), ()> {
    let runtime = app.state::<PocTransportRuntime>();
    let mut handshakes = runtime.pairing_handshakes.lock().map_err(|_| ())?;
    handshakes.insert(
        peer.to_owned(),
        PairingServerHandshakeRuntimeState {
            invitation_id: draft.invitation_id.clone(),
            space_id: draft.space_id.clone(),
            peer_device_id: draft.peer_device_id.clone(),
            peer_identity_public_key: draft.peer_identity_public_key.clone(),
            peer_ephemeral_public_key: draft.peer_ephemeral_public_key.clone(),
            server_device_id: draft.server_device_id.clone(),
            server_identity_public_key: draft.server_identity_public_key.clone(),
            server_ephemeral_public_key: draft.server_ephemeral_public_key.clone(),
            pairing_context: draft.pairing_context.clone(),
            server_ephemeral_secret,
        },
    );
    Ok(())
}

fn remember_authenticated_session(
    app: &AppHandle,
    peer: &str,
    accepted: crate::pairing::PairingServerAuthProofAccepted,
) -> Result<(), ()> {
    let runtime = app.state::<PocTransportRuntime>();
    let device_id = Uuid::parse_str(&accepted.peer_device_id).map_err(|_| ())?;
    let space_id = Uuid::parse_str(&accepted.space_id).map_err(|_| ())?;
    let mut sessions = runtime.authenticated_sessions.lock().map_err(|_| ())?;
    let displaced: Vec<String> = sessions
        .iter()
        .filter_map(|(existing_peer, entry)| {
            (entry.device_id == device_id && existing_peer != peer).then(|| existing_peer.clone())
        })
        .collect();
    for displaced_peer in &displaced {
        if let Some(mut session) = sessions.remove(displaced_peer) {
            session.session.close();
        }
    }
    sessions.insert(
        peer.to_owned(),
        AuthenticatedPeerSession {
            session: AuthenticatedTransportSession::new(
                SessionDirection::ClientToServer,
                accepted.session_keys.client_to_server,
                SessionDirection::ServerToClient,
                accepted.session_keys.server_to_client,
                5,
            ),
            space_id,
            device_id,
        },
    );
    drop(sessions);
    if let Ok(peers) = runtime.peers.lock() {
        for displaced_peer in &displaced {
            if let Some(sender) = peers.get(displaced_peer) {
                let _ = sender.send(Message::Close(None));
            }
        }
    }
    let _ = app.emit(
        "transport://authenticated-connection",
        AuthenticatedConnectionStateEvent {
            peer: peer.to_owned(),
            device_id: device_id.to_string(),
            space_id: space_id.to_string(),
            state: "online",
        },
    );
    Ok(())
}

fn close_authenticated_session(app: &AppHandle, peer: &str) {
    if let Ok(mut sessions) = app
        .state::<PocTransportRuntime>()
        .authenticated_sessions
        .lock()
    {
        if let Some(mut session) = sessions.remove(peer) {
            let _ = mark_trusted_device_offline(app, session.device_id);
            let event = AuthenticatedConnectionStateEvent {
                peer: peer.to_owned(),
                device_id: session.device_id.to_string(),
                space_id: session.space_id.to_string(),
                state: "offline",
            };
            session.session.close();
            let _ = app.emit("transport://authenticated-connection", event);
        }
    }
}

fn take_pairing_handshake(
    app: &AppHandle,
    peer: &str,
) -> Option<PairingServerHandshakeRuntimeState> {
    let runtime = app.state::<PocTransportRuntime>();
    let mut handshakes = runtime.pairing_handshakes.lock().ok()?;
    handshakes.remove(peer)
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
    fn extracts_authenticated_item_live_clipboard_text() {
        let payload = serde_json::json!({
            "itemId": "018ff6f3-0d8c-7d1e-a38a-f308c64de79f",
            "spaceId": "018ff6ef-c394-7d08-8b99-4b7d10f2767a",
            "originDeviceId": "018ff6f0-4adf-7d31-a987-3ef2b25d0212",
            "originSeq": 7,
            "hlc": "0000018bcfe56864-0001",
            "contentType": "text/plain",
            "contentLength": 26,
            "contentDigest": "eA5jJ_YZ7drWuf4TrzLd5LaQ6mKfMsoQkxzHNXl2f5I",
            "createdAt": 1_700_000_000_000u64,
            "content": "authenticated 桌面同步"
        });

        let (protocol_item, clipboard_item) =
            authenticated_clipboard_text_from_payload(MessageType::ItemLive, &payload)
                .expect("item live should parse");

        assert_eq!(protocol_item.origin_seq, 7);
        assert_eq!(clipboard_item.as_str(), "authenticated 桌面同步");
        assert_eq!(clipboard_item.byte_len(), 26);
    }

    #[test]
    fn builds_authenticated_remote_history_record_without_plaintext() {
        let protocol_item = ProtocolClipboardItem {
            item_id: "018ff6f3-0d8c-7d1e-a38a-f308c64de79f".to_string(),
            space_id: "018ff6ef-c394-7d08-8b99-4b7d10f2767a".to_string(),
            origin_device_id: "018ff6f0-4adf-7d31-a987-3ef2b25d0212".to_string(),
            origin_seq: 7,
            hlc: "0000018bcfe56864-0001".to_string(),
            content_type: crate::protocol::ContentType::TextPlain,
            content_length: 26,
            content_digest: "eA5jJ_YZ7drWuf4TrzLd5LaQ6mKfMsoQkxzHNXl2f5I".to_string(),
            created_at: 1_700_000_000_000,
            content: "authenticated 桌面同步".to_string(),
        };
        let settings = AppSettings {
            retention_days: 7,
            ..AppSettings::default()
        };

        let encrypted_content = b"encrypted-local-content".to_vec();
        let record = authenticated_remote_clipboard_record(
            &protocol_item,
            1_700_000_010_000,
            &settings,
            encrypted_content.clone(),
        )
        .expect("remote history record should build");

        assert_eq!(record.item.item_id.to_string(), protocol_item.item_id);
        assert_eq!(record.item.origin_seq, 7);
        assert_eq!(record.item.plaintext, None);
        assert_eq!(record.encrypted_content, encrypted_content);
        assert_ne!(record.encrypted_content, protocol_item.content.as_bytes());
        assert_eq!(record.received_at, 1_700_000_010_000);
        assert_eq!(record.expires_at, 1_700_604_810_000);
    }

    #[test]
    fn rejects_authenticated_clipboard_payload_for_wrong_type_or_size() {
        let payload = serde_json::json!({
            "itemId": "018ff6f3-0d8c-7d1e-a38a-f308c64de79f",
            "spaceId": "018ff6ef-c394-7d08-8b99-4b7d10f2767a",
            "originDeviceId": "018ff6f0-4adf-7d31-a987-3ef2b25d0212",
            "originSeq": 7,
            "hlc": "0000018bcfe56864-0001",
            "contentType": "text/plain",
            "contentLength": 0,
            "contentDigest": "eA5jJ_YZ7drWuf4TrzLd5LaQ6mKfMsoQkxzHNXl2f5I",
            "createdAt": 1_700_000_000_000u64,
            "content": ""
        });

        assert!(
            authenticated_clipboard_text_from_payload(MessageType::SyncHeads, &payload).is_err()
        );
        assert!(
            authenticated_clipboard_text_from_payload(MessageType::ItemLive, &payload).is_err()
        );
    }

    #[test]
    fn pre_auth_and_poc_frames_are_not_authenticated_messages() {
        let client_hello = r#"{"version":1,"type":"CLIENT_HELLO","messageId":"018ff6f0-2b1f-7cc5-b5d0-7e82c5f70f01","sessionCounter":0,"payload":{}}"#;
        let auth_proof = r#"{"version":1,"type":"AUTH_PROOF","messageId":"018ff6f1-35f0-7c09-a4cf-3d683ebfae33","sessionCounter":2,"payload":{}}"#;
        let poc_clipboard = r#"{"kind":"clipboardText","text":"from harmony"}"#;

        assert_eq!(authenticated_message_type(client_hello), None);
        assert_eq!(authenticated_message_type(auth_proof), None);
        assert_eq!(authenticated_message_type(poc_clipboard), None);
    }

    #[test]
    fn pairing_auth_success_consumes_invitation_and_trusts_device() {
        let mut connection =
            crate::storage::open_in_memory_database().expect("database should initialize");
        let space_id = Uuid::now_v7();
        let invitation_id = Uuid::now_v7();
        let issuer_device_id = Uuid::now_v7();
        let peer_device_id = Uuid::now_v7();
        SpaceRepository::new(&connection)
            .upsert(&crate::storage::repositories::SpaceRecord {
                space: crate::sync::Space {
                    space_id,
                    display_name: "默认空间".to_owned(),
                    key_version: 1,
                    state: crate::sync::SpaceState::Active,
                    created_at: 1_700_000_000_000,
                },
                encrypted_space_key_ref: Some("credential://space-key".to_owned()),
                updated_at: 1_700_000_000_000,
            })
            .expect("space should insert");
        PairingInvitationRepository::new(&connection)
            .insert(&crate::storage::repositories::PairingInvitationRecord {
                invitation_id,
                space_id,
                issuer_device_id,
                secret_verifier: "verifier".to_owned(),
                state: crate::storage::repositories::PairingInvitationState::Active,
                created_at: 1_700_000_000_000,
                expires_at: 1_700_000_300_000,
                consumed_at: None,
                consumed_by_device_id: None,
            })
            .expect("invitation should insert");

        persist_trusted_pairing_device_in_connection(
            &mut connection,
            &crate::pairing::PairingServerAuthProofAccepted {
                invitation_id: invitation_id.to_string(),
                space_id: space_id.to_string(),
                peer_device_id: peer_device_id.to_string(),
                peer_identity_public_key: "peer-public-key".to_owned(),
                transcript_hash: "transcript-hash".to_owned(),
                transcript_salt: [1; 32],
                shared_secret: [2; crate::crypto::X25519_SHARED_SECRET_BYTES],
                session_keys: crate::crypto::SessionKeys {
                    client_to_server: [3; 32],
                    server_to_client: [4; 32],
                },
                auth_ok_frame: "{}".to_owned(),
            },
            1_700_000_001_000,
        )
        .expect("trusted device should persist");

        let invitation = PairingInvitationRepository::new(&connection)
            .get(invitation_id)
            .expect("invitation query should succeed")
            .expect("invitation should exist");
        assert_eq!(
            invitation.state,
            crate::storage::repositories::PairingInvitationState::Consumed
        );
        assert_eq!(invitation.consumed_by_device_id, Some(peer_device_id));

        let device = DeviceRepository::new(&connection)
            .get(peer_device_id)
            .expect("device query should succeed")
            .expect("device should exist");
        assert_eq!(device.device.space_id, space_id);
        assert_eq!(device.device.trust_state, DeviceTrustState::Trusted);
        assert_eq!(
            device.device.connection_state,
            DeviceConnectionState::Online
        );
        assert_eq!(device.device.identity_public_key_ref, "peer-public-key");
        assert_eq!(device.paired_at, Some(1_700_000_001_000));
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
    fn builds_recent_endpoint_without_trust_material() {
        let endpoint = build_recent_endpoint("192.168.1.20:4567", 1_700_000_000_000)
            .expect("recent endpoint should build");

        assert_eq!(
            endpoint,
            PocRecentEndpoint {
                host: "192.168.1.20".to_owned(),
                port: 4567,
                connected_at_ms: 1_700_000_000_000,
            }
        );
        assert!(build_recent_endpoint("example.com:4567", 1_700_000_000_000).is_err());
        assert!(build_recent_endpoint("192.168.1.20:not-a-port", 1_700_000_000_000).is_err());
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

    #[test]
    fn skips_authenticated_local_broadcast_without_an_authenticated_space() {
        let runtime = PocTransportRuntime::default();

        assert_eq!(
            single_authenticated_space(&runtime).expect("runtime lock should be available"),
            (None, false)
        );
    }

    #[test]
    fn builds_item_live_payload_and_encrypts_local_content_separately() {
        let item = crate::sync::ClipboardItem {
            item_id: Uuid::now_v7(),
            space_id: Uuid::now_v7(),
            origin_device_id: Uuid::now_v7(),
            origin_seq: 1,
            hlc: HlcTimestamp::new(1_700_000_000_000, 0),
            content_type: SyncContentType::TextPlain,
            content_length: "outbound text".len(),
            content_digest: "test-digest".to_owned(),
            created_at: 1_700_000_000_000,
            encrypted_content_ref: None,
            plaintext: Some("outbound text".to_owned()),
        };

        let payload = authenticated_local_item_payload(&item).expect("plaintext should be present");
        assert_eq!(payload["contentType"], "text/plain");
        assert_eq!(payload["content"], "outbound text");

        let encrypted = encrypt_local_clipboard_content(
            &[7u8; 32],
            item.space_id,
            &ClipboardText::parse("outbound text").expect("valid text"),
        )
        .expect("local content should encrypt");
        let envelope: serde_json::Value =
            serde_json::from_slice(&encrypted).expect("encrypted envelope should be JSON");
        assert_ne!(encrypted, b"outbound text");
        assert_eq!(envelope["version"], 1);
        assert!(envelope.get("body").is_some());
        assert!(envelope.get("tag").is_some());
    }
}
