use super::*;

use crate::{
    pairing::{
        client_handshake::{
            PairingClientHandshake, PairingClientHandshakeError, PairingClientHandshakeEvent,
            PairingClientRemoteRejectCode, TrustedClientReadySession,
        },
        client_join::{PairingClientReadySession, PairingJoinCommitError},
        PairingJoinRuntime,
    },
    protocol::{HANDSHAKE_TIMEOUT_SECONDS, IDLE_DISCONNECT_SECONDS, MAX_FRAME_BYTES},
};

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TrustedOutboundConnectionSummary {
    space_id: String,
    device_id: String,
    endpoint: String,
    state: &'static str,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum OutboundCloseReason {
    PeerDisconnected,
    IdleTimeout,
    FrameTooLarge,
    BinaryUnsupported,
    ProtocolRejected,
    ChannelClosed,
}

impl OutboundCloseReason {
    fn wire_value(self) -> &'static str {
        match self {
            Self::PeerDisconnected => "peerDisconnected",
            Self::IdleTimeout => "idleTimeout",
            Self::FrameTooLarge => "frameTooLarge",
            Self::BinaryUnsupported => "binaryUnsupported",
            Self::ProtocolRejected => "protocolRejected",
            Self::ChannelClosed => "outboundChannelClosed",
        }
    }
}

#[tauri::command]
pub async fn connect_trusted_peer(
    app: AppHandle,
    transport_runtime: State<'_, PocTransportRuntime>,
    join_runtime: State<'_, PairingJoinRuntime>,
    attempt_id: String,
    candidate_id: Option<String>,
    manual_host: Option<String>,
    manual_port: Option<u16>,
) -> Result<TrustedOutboundConnectionSummary, String> {
    let (host, port) = if let Some(candidate_id) = candidate_id {
        let candidate = join_runtime
            .endpoint_for_candidate(&attempt_id, &candidate_id, now_ms()?)
            .map_err(crate::pairing::client::describe_join_error)?;
        (candidate.host.to_string(), candidate.port)
    } else {
        (
            manual_host.ok_or_else(|| "请输入桌面端局域网 IPv4 地址".to_string())?,
            manual_port.ok_or_else(|| "请输入桌面端连接端口".to_string())?,
        )
    };
    let endpoint = validate_poc_endpoint(&host, port)
        .map_err(|_| "可信连接地址无效，请重新选择局域网地址".to_string())?;
    let operation_key = attempt_id.clone();
    {
        let mut connecting = transport_runtime
            .formal_connecting
            .lock()
            .map_err(|_| "可信连接状态暂时不可用".to_string())?;
        if !connecting.insert(operation_key.clone()) {
            return Err("该可信连接正在进行".to_string());
        }
    }

    let result =
        connect_trusted_peer_inner(app, &join_runtime, attempt_id, endpoint.clone(), host, port)
            .await;
    if let Ok(mut connecting) = transport_runtime.formal_connecting.lock() {
        connecting.remove(&operation_key);
    }
    result
}

async fn connect_trusted_peer_inner(
    app: AppHandle,
    join_runtime: &PairingJoinRuntime,
    attempt_id: String,
    endpoint: String,
    host: String,
    port: u16,
) -> Result<TrustedOutboundConnectionSummary, String> {
    let url = format!("ws://{endpoint}");
    let (mut websocket, _) = timeout(POC_CONNECT_TIMEOUT, connect_async(&url))
        .await
        .map_err(|_| "连接可信设备超时".to_string())?
        .map_err(|_| "无法连接可信设备，请检查局域网和防火墙".to_string())?;

    let path = database_path(&app)?;
    let mut connection = open_database(path).map_err(|_| "无法打开本地数据库".to_string())?;
    #[cfg(windows)]
    let mut secret_store = crate::secret_store::WindowsCredentialSecretStore;
    #[cfg(not(windows))]
    let mut secret_store = crate::secret_store::UnavailableSecretStore;
    let mut started = PairingClientHandshake::start_from_join_attempt(
        join_runtime,
        &attempt_id,
        &mut connection,
        &mut secret_store,
        now_ms()?,
    )
    .map_err(describe_initial_handshake_error)?;
    let address = Ipv4Addr::from_str(host.trim()).map_err(|_| "可信连接地址无效".to_string())?;
    started.handshake.set_connected_endpoint(address, port);

    let ready = timeout(
        Duration::from_secs(HANDSHAKE_TIMEOUT_SECONDS),
        complete_initial_pairing(&mut websocket, started, &mut connection, &mut secret_store),
    )
    .await
    .map_err(|_| "可信握手超时".to_string())??;
    let space_id = ready.summary.space_id;
    let device_id = ready.summary.coordinator_device_id;
    attach_formal_connection(
        app,
        websocket,
        ready.transport,
        space_id,
        device_id,
        endpoint,
    )
    .await
}

pub(crate) async fn connect_saved_trusted_peer(
    app: AppHandle,
    space_id: Uuid,
    device_id: Uuid,
    endpoints: Vec<(String, u16)>,
) -> Result<TrustedOutboundConnectionSummary, String> {
    if authenticated_device_peers(&app).contains_key(&(space_id, device_id)) {
        return Err("可信设备已有活动会话".to_string());
    }
    let operation_key = format!("reconnect:{space_id}:{device_id}");
    let runtime = app.state::<PocTransportRuntime>();
    {
        let mut connecting = runtime
            .formal_connecting
            .lock()
            .map_err(|_| "可信重连状态暂时不可用".to_string())?;
        if !connecting.insert(operation_key.clone()) {
            return Err("可信设备正在重连".to_string());
        }
    }
    let mut last_error = "没有可用的可信设备地址".to_string();
    let mut result = Err(last_error.clone());
    for (host, port) in endpoints {
        if authenticated_device_peers(&app).contains_key(&(space_id, device_id)) {
            result = Err("可信设备已有活动会话".to_string());
            break;
        }
        match connect_saved_trusted_peer_at(app.clone(), space_id, device_id, host, port).await {
            Ok(summary) => {
                result = Ok(summary);
                break;
            }
            Err(error) => {
                last_error = error;
                result = Err(last_error.clone());
            }
        }
    }
    if let Ok(mut connecting) = runtime.formal_connecting.lock() {
        connecting.remove(&operation_key);
    }
    result
}

async fn connect_saved_trusted_peer_at(
    app: AppHandle,
    space_id: Uuid,
    device_id: Uuid,
    host: String,
    port: u16,
) -> Result<TrustedOutboundConnectionSummary, String> {
    let endpoint =
        validate_poc_endpoint(&host, port).map_err(|_| "可信重连地址无效".to_string())?;
    let url = format!("ws://{endpoint}");
    let (mut websocket, _) = timeout(POC_CONNECT_TIMEOUT, connect_async(&url))
        .await
        .map_err(|_| "可信重连超时".to_string())?
        .map_err(|_| "可信设备地址当前不可达".to_string())?;
    let path = database_path(&app)?;
    let mut connection = open_database(path).map_err(|_| "无法打开本地数据库".to_string())?;
    let space = SpaceRepository::new(&connection)
        .get(space_id)
        .map_err(|_| "无法读取同步空间".to_string())?
        .ok_or_else(|| "同步空间不存在".to_string())?;
    let coordinator = DeviceRepository::new(&connection)
        .get_in_space(space_id, device_id)
        .map_err(|_| "无法读取可信设备".to_string())?
        .ok_or_else(|| "可信设备不存在".to_string())?;
    #[cfg(windows)]
    let mut secret_store = crate::secret_store::WindowsCredentialSecretStore;
    #[cfg(not(windows))]
    let mut secret_store = crate::secret_store::UnavailableSecretStore;
    let started = PairingClientHandshake::start_from_trusted_device(
        &space,
        &coordinator,
        &mut connection,
        &mut secret_store,
        now_ms()?,
    )
    .map_err(|error| format!("无法开始可信重连：{error}"))?;
    let ready = timeout(
        Duration::from_secs(HANDSHAKE_TIMEOUT_SECONDS),
        complete_trusted_reconnect(&mut websocket, started),
    )
    .await
    .map_err(|_| "可信重连握手超时".to_string())??;
    if ready.space_id != space_id
        || ready.coordinator_device_id != device_id
        || ready.key_version != space.space.key_version
    {
        return Err("可信重连身份与保存路由不一致".to_string());
    }
    mark_saved_route_connected(&connection, space_id, device_id, &host, port, now_ms()?)?;
    attach_formal_connection(
        app,
        websocket,
        ready.transport,
        space_id,
        device_id,
        endpoint,
    )
    .await
}

fn mark_saved_route_connected(
    connection: &rusqlite::Connection,
    space_id: Uuid,
    device_id: Uuid,
    host: &str,
    port: u16,
    connected_at: u64,
) -> Result<(), String> {
    let repository = DeviceRepository::new(connection);
    let mut record = repository
        .get_in_space(space_id, device_id)
        .map_err(|_| "无法读取可信路由".to_string())?
        .ok_or_else(|| "可信路由不存在".to_string())?;
    if record.route.role != crate::sync::TrustedRouteRole::DialCoordinator
        || record.device.trust_state != DeviceTrustState::Trusted
        || record.revoked_at.is_some()
    {
        return Err("可信路由已失效".to_string());
    }
    record.route.last_successful_host = Some(host.to_string());
    record.route.last_successful_port = Some(port);
    record.device.connection_state = DeviceConnectionState::Online;
    record.device.last_seen_at = Some(connected_at);
    repository
        .upsert(&record)
        .map_err(|_| "无法保存可信重连地址".to_string())
}

async fn attach_formal_connection<S>(
    app: AppHandle,
    websocket: WebSocketStream<S>,
    transport: AuthenticatedTransportSession,
    space_id: Uuid,
    device_id: Uuid,
    endpoint: String,
) -> Result<TrustedOutboundConnectionSummary, String>
where
    S: AsyncRead + AsyncWrite + Unpin + Send + 'static,
{
    validate_current_formal_target(&app, space_id, device_id)?;
    let peer = format!("trusted-outbound:{space_id}:{device_id}:{}", Uuid::now_v7());
    let (mut writer, reader) = websocket.split();
    let (outgoing_tx, mut outgoing_rx) = mpsc::unbounded_channel::<Message>();
    let (writer_closed_tx, writer_closed_rx) = oneshot::channel();
    let writer_task = tauri::async_runtime::spawn(async move {
        while let Some(message) = outgoing_rx.recv().await {
            if writer.send(message).await.is_err() {
                break;
            }
        }
        let _ = writer_closed_tx.send(());
    });

    let runtime = app.state::<PocTransportRuntime>();
    runtime
        .formal_outbound_peers
        .lock()
        .map_err(|_| "可信连接状态暂时不可用".to_string())?
        .insert(peer.clone(), outgoing_tx.clone());
    if register_authenticated_session(
        &app,
        &peer,
        transport,
        space_id,
        device_id,
        AuthenticatedConnectionKind::FormalOutbound,
    )
    .is_err()
    {
        runtime
            .formal_outbound_peers
            .lock()
            .ok()
            .and_then(|mut peers| peers.remove(&peer));
        writer_task.abort();
        return Err("无法注册可信连接".to_string());
    }
    if send_authenticated_sync_heads(&app, &peer).is_err() {
        close_authenticated_session_with_reason(&app, &peer, "syncHeadsFailed", true);
        runtime
            .formal_outbound_peers
            .lock()
            .ok()
            .and_then(|mut peers| peers.remove(&peer));
        writer_task.abort();
        return Err("无法启动可信同步".to_string());
    }

    spawn_formal_connection_loop(
        app.clone(),
        peer.clone(),
        reader,
        outgoing_tx,
        writer_task,
        writer_closed_rx,
    );
    let summary = TrustedOutboundConnectionSummary {
        space_id: space_id.to_string(),
        device_id: device_id.to_string(),
        endpoint,
        state: "syncing",
    };
    let _ = app.emit("transport://trusted-outbound-connection", summary.clone());
    Ok(summary)
}

fn validate_current_formal_target(
    app: &AppHandle,
    space_id: Uuid,
    device_id: Uuid,
) -> Result<(), String> {
    let path = database_path(app)?;
    let connection = open_database(path).map_err(|_| "无法打开本地数据库".to_string())?;
    let space = SpaceRepository::new(&connection)
        .get(space_id)
        .map_err(|_| "无法读取同步空间".to_string())?
        .ok_or_else(|| "同步空间已离开或删除".to_string())?;
    let coordinator = DeviceRepository::new(&connection)
        .get_in_space(space_id, device_id)
        .map_err(|_| "无法读取可信设备".to_string())?
        .ok_or_else(|| "可信协调端已移除".to_string())?;
    if space.space.state != SpaceState::Active
        || space.local_role != crate::sync::LocalSpaceRole::Member
        || space.encrypted_space_key_ref.is_none()
        || coordinator.device.trust_state != DeviceTrustState::Trusted
        || coordinator.revoked_at.is_some()
        || coordinator.route.role != crate::sync::TrustedRouteRole::DialCoordinator
    {
        return Err("可信连接目标已失效".to_string());
    }
    Ok(())
}

async fn complete_initial_pairing<S, Store>(
    websocket: &mut WebSocketStream<S>,
    started: crate::pairing::client_handshake::PairingClientHandshakeStarted,
    connection: &mut rusqlite::Connection,
    secret_store: &mut Store,
) -> Result<PairingClientReadySession, String>
where
    S: AsyncRead + AsyncWrite + Unpin,
    Store: crate::identity::IdentitySecretStore + crate::secret_store::SecretBytesStore,
{
    let mut handshake = started.handshake;
    websocket
        .send(Message::Text(started.client_hello_frame.into()))
        .await
        .map_err(|_| "无法发送可信握手".to_string())?;
    loop {
        let frame = next_handshake_text_frame(websocket).await?;
        match handshake
            .accept_server_frame(&frame, now_ms()?)
            .map_err(describe_initial_handshake_error)?
        {
            PairingClientHandshakeEvent::SendAuthProof(proof) => websocket
                .send(Message::Text(proof.into()))
                .await
                .map_err(|_| "无法发送可信认证证明".to_string())?,
            PairingClientHandshakeEvent::ServerProofVerified => {}
            PairingClientHandshakeEvent::AwaitingSpaceKey(pending) => {
                let key_frame = next_handshake_text_frame(websocket).await?;
                return pending
                    .accept_initial_space_key(&key_frame, connection, secret_store, now_ms()?)
                    .map_err(describe_join_commit_error);
            }
            PairingClientHandshakeEvent::TrustedReady(_) => {
                return Err("首次配对意外进入可信重连状态".to_string())
            }
        }
    }
}

fn describe_initial_handshake_error(error: PairingClientHandshakeError) -> String {
    match error {
        PairingClientHandshakeError::JoinAttempt(error) => {
            crate::pairing::client::describe_join_error(error)
        }
        PairingClientHandshakeError::InvitationExpired
        | PairingClientHandshakeError::RemoteRejected(
            PairingClientRemoteRejectCode::InvitationExpired,
        ) => "配对邀请已过期，请在另一台电脑重新生成".to_string(),
        PairingClientHandshakeError::RemoteRejected(
            PairingClientRemoteRejectCode::InvitationConsumed,
        ) => "配对邀请已使用，请在另一台电脑重新生成".to_string(),
        PairingClientHandshakeError::RemoteRejected(
            PairingClientRemoteRejectCode::InvitationMissing,
        ) => "另一台电脑找不到该邀请，请重新生成后再试".to_string(),
        PairingClientHandshakeError::ServerIdentityMismatch
        | PairingClientHandshakeError::RemoteRejected(
            PairingClientRemoteRejectCode::IdentityOrSpaceMismatch,
        ) => "设备身份与邀请不匹配，请确认连接的是生成邀请的电脑".to_string(),
        PairingClientHandshakeError::InvalidServerProof
        | PairingClientHandshakeError::ServerAuthenticationFailed
        | PairingClientHandshakeError::RemoteRejected(
            PairingClientRemoteRejectCode::AuthProofFailed,
        ) => "设备认证失败，请核对确认码并重新生成邀请".to_string(),
        PairingClientHandshakeError::IdentityUnavailable => {
            "无法读取或保存本机设备身份，请重启应用后重试".to_string()
        }
        PairingClientHandshakeError::RandomUnavailable => {
            "无法生成安全握手材料，请重启应用后重试".to_string()
        }
        PairingClientHandshakeError::Timeout => "可信握手超时，请检查局域网连接".to_string(),
        PairingClientHandshakeError::RemoteRejected(_)
        | PairingClientHandshakeError::InvalidServerHello
        | PairingClientHandshakeError::UnexpectedFrame
        | PairingClientHandshakeError::ProtocolRejected
        | PairingClientHandshakeError::SessionKeyDerivationFailed => {
            "设备认证失败，远端返回了无效的握手响应".to_string()
        }
        #[cfg(test)]
        PairingClientHandshakeError::ConnectionClosed => "可信连接在握手期间关闭".to_string(),
    }
}

fn describe_join_commit_error(error: PairingJoinCommitError) -> String {
    match error {
        PairingJoinCommitError::CredentialStore
        | PairingJoinCommitError::CredentialConflict
        | PairingJoinCommitError::CompensationFailed => {
            "空间密钥保存失败，请重启应用后重新配对".to_string()
        }
        PairingJoinCommitError::DeviceIdentityMismatch => {
            "设备身份与本机已有记录不匹配，请移除旧设备后重试".to_string()
        }
        PairingJoinCommitError::AlreadyJoined => "本机已经加入该同步空间，无需重复配对".to_string(),
        PairingJoinCommitError::Database | PairingJoinCommitError::SpaceConflict => {
            "本机数据库写入失败，未保存本次配对".to_string()
        }
        PairingJoinCommitError::MissingConnectedEndpoint
        | PairingJoinCommitError::Timeout
        | PairingJoinCommitError::UnexpectedInitialMessage
        | PairingJoinCommitError::InvalidSpaceKeyPayload
        | PairingJoinCommitError::SpaceKeyVersionMismatch => {
            "空间密钥验证失败，请重新生成邀请后配对".to_string()
        }
    }
}

async fn complete_trusted_reconnect<S>(
    websocket: &mut WebSocketStream<S>,
    started: crate::pairing::client_handshake::PairingClientHandshakeStarted,
) -> Result<TrustedClientReadySession, String>
where
    S: AsyncRead + AsyncWrite + Unpin,
{
    let mut handshake = started.handshake;
    websocket
        .send(Message::Text(started.client_hello_frame.into()))
        .await
        .map_err(|_| "无法发送可信重连握手".to_string())?;
    loop {
        let frame = next_handshake_text_frame(websocket).await?;
        match handshake
            .accept_server_frame(&frame, now_ms()?)
            .map_err(|error| format!("可信重连握手失败：{error}"))?
        {
            PairingClientHandshakeEvent::SendAuthProof(proof) => websocket
                .send(Message::Text(proof.into()))
                .await
                .map_err(|_| "无法发送可信重连证明".to_string())?,
            PairingClientHandshakeEvent::ServerProofVerified => {}
            PairingClientHandshakeEvent::TrustedReady(ready) => return Ok(ready),
            PairingClientHandshakeEvent::AwaitingSpaceKey(_) => {
                return Err("可信重连意外进入首次密钥下发状态".to_string())
            }
        }
    }
}

async fn next_handshake_text_frame<S>(websocket: &mut WebSocketStream<S>) -> Result<String, String>
where
    S: AsyncRead + AsyncWrite + Unpin,
{
    loop {
        let message = websocket
            .next()
            .await
            .ok_or_else(|| "可信连接在握手期间关闭".to_string())?
            .map_err(|_| "可信连接在握手期间失败".to_string())?;
        match message {
            Message::Text(text) if text.len() <= MAX_FRAME_BYTES => return Ok(text.to_string()),
            Message::Text(_) => return Err("可信握手帧超过大小限制".to_string()),
            Message::Ping(payload) => websocket
                .send(Message::Pong(payload))
                .await
                .map_err(|_| "可信连接心跳失败".to_string())?,
            Message::Pong(_) => {}
            Message::Close(_) => return Err("可信连接在握手期间关闭".to_string()),
            Message::Binary(_) | Message::Frame(_) => {
                return Err("可信握手不接受二进制帧".to_string())
            }
        }
    }
}

fn spawn_formal_connection_loop<S>(
    app: AppHandle,
    peer: String,
    mut reader: futures_util::stream::SplitStream<WebSocketStream<S>>,
    outgoing_tx: mpsc::UnboundedSender<Message>,
    writer_task: tauri::async_runtime::JoinHandle<()>,
    mut writer_closed_rx: oneshot::Receiver<()>,
) where
    S: AsyncRead + AsyncWrite + Unpin + Send + 'static,
{
    tauri::async_runtime::spawn(async move {
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
        let idle_timeout = Duration::from_secs(IDLE_DISCONNECT_SECONDS);
        let reason = loop {
            let message_result = tokio::select! {
                result = timeout(idle_timeout, reader.next()) => match result {
                    Ok(Some(result)) => result,
                    Ok(None) => break OutboundCloseReason::PeerDisconnected,
                    Err(_) => break OutboundCloseReason::IdleTimeout,
                },
                _ = &mut writer_closed_rx => break OutboundCloseReason::ChannelClosed,
            };
            let message = match message_result {
                Ok(message) => message,
                Err(_) => break OutboundCloseReason::PeerDisconnected,
            };
            match message {
                Message::Text(text) => {
                    if text.len() > MAX_FRAME_BYTES {
                        break OutboundCloseReason::FrameTooLarge;
                    }
                    match try_accept_authenticated_frame(&app, &peer, &text) {
                        AuthenticatedFrameRoute::Handled => {}
                        AuthenticatedFrameRoute::Rejected
                        | AuthenticatedFrameRoute::NotAuthenticated => {
                            break OutboundCloseReason::ProtocolRejected
                        }
                    }
                }
                Message::Binary(_) | Message::Frame(_) => {
                    break OutboundCloseReason::BinaryUnsupported
                }
                Message::Ping(payload) => {
                    if outgoing_tx.send(Message::Pong(payload)).is_err() {
                        break OutboundCloseReason::ChannelClosed;
                    }
                }
                Message::Pong(_) => {}
                Message::Close(_) => break OutboundCloseReason::PeerDisconnected,
            }
        };
        if let Ok(mut peers) = app
            .state::<PocTransportRuntime>()
            .formal_outbound_peers
            .lock()
        {
            peers.remove(&peer);
        }
        close_authenticated_session_with_reason(&app, &peer, reason.wire_value(), false);
        heartbeat_task.abort();
        writer_task.abort();
        let _ = app.emit(
            "transport://trusted-outbound-disconnected",
            serde_json::json!({ "peer": peer, "reason": reason.wire_value() }),
        );
    });
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use tokio::io::duplex;
    use tokio_tungstenite::tungstenite::protocol::Role;

    use super::*;
    use crate::{
        crypto::{encode_base64url, X25519Secret},
        identity::{ensure_local_device_identity, IdentitySecretStore},
        pairing::{
            accept_pairing_auth_proof, accept_pairing_client_hello,
            accept_trusted_device_client_hello, create_pairing_invitation_for_space,
            create_sync_space, PairingServerAuthProofInput,
        },
        secret_store::{SecretBytesStore, SecretStoreError},
        storage::{
            open_in_memory_database,
            repositories::{SpaceRecord, TrustedDeviceRoute},
        },
        sync::{Device, LocalSpaceRole, Space, SpaceState, TrustedRouteRole},
    };

    #[derive(Default)]
    struct TestSecretStore {
        secrets: HashMap<String, Vec<u8>>,
    }

    impl SecretBytesStore for TestSecretStore {
        fn load_secret(&self, secret_ref: &str) -> Result<Option<Vec<u8>>, SecretStoreError> {
            Ok(self.secrets.get(secret_ref).cloned())
        }

        fn save_secret(&mut self, secret_ref: &str, secret: &[u8]) -> Result<(), SecretStoreError> {
            self.secrets.insert(secret_ref.to_string(), secret.to_vec());
            Ok(())
        }

        fn delete_secret(&mut self, secret_ref: &str) -> Result<(), SecretStoreError> {
            self.secrets.remove(secret_ref);
            Ok(())
        }
    }

    #[test]
    fn formal_connection_policy_matches_protocol_limits() {
        assert_eq!(
            POC_CONNECT_TIMEOUT,
            Duration::from_secs(HANDSHAKE_TIMEOUT_SECONDS)
        );
        assert_eq!(MAX_FRAME_BYTES, POC_MAX_FRAME_BYTES);
        assert!(AUTHENTICATED_HEARTBEAT_INTERVAL < Duration::from_secs(IDLE_DISCONNECT_SECONDS));
    }

    #[test]
    fn formal_close_reasons_are_coarse_and_stable() {
        assert_eq!(OutboundCloseReason::IdleTimeout.wire_value(), "idleTimeout");
        assert_eq!(
            OutboundCloseReason::FrameTooLarge.wire_value(),
            "frameTooLarge"
        );
        assert_eq!(
            OutboundCloseReason::ChannelClosed.wire_value(),
            "outboundChannelClosed"
        );
    }

    #[test]
    fn initial_join_errors_map_to_actionable_user_categories() {
        assert_eq!(
            describe_initial_handshake_error(PairingClientHandshakeError::RemoteRejected(
                PairingClientRemoteRejectCode::InvitationConsumed,
            )),
            "配对邀请已使用，请在另一台电脑重新生成"
        );
        assert!(describe_initial_handshake_error(
            PairingClientHandshakeError::ServerIdentityMismatch
        )
        .contains("身份"));
        assert!(describe_initial_handshake_error(
            PairingClientHandshakeError::ServerAuthenticationFailed
        )
        .contains("认证"));
        assert!(
            describe_join_commit_error(PairingJoinCommitError::CredentialStore)
                .contains("密钥保存失败")
        );
        assert!(describe_join_commit_error(PairingJoinCommitError::Database).contains("数据库"));
    }

    #[tokio::test]
    async fn formal_client_completes_real_websocket_handshake_and_initial_key_delivery() {
        let now = now_ms().expect("current time");
        let mut server_connection = open_in_memory_database().expect("server database");
        let mut server_store = TestSecretStore::default();
        let space = create_sync_space(
            &mut server_connection,
            &mut server_store,
            "Windows 互联空间",
            now,
        )
        .expect("server space");
        let invitation = create_pairing_invitation_for_space(
            &mut server_connection,
            &mut server_store,
            &space.space_id,
            now + 10,
        )
        .expect("invitation");
        let join_runtime = PairingJoinRuntime::default();
        let attempt = join_runtime
            .begin(invitation.invitation, now + 20)
            .expect("join attempt");
        let mut client_connection = open_in_memory_database().expect("client database");
        let mut client_store = TestSecretStore::default();
        let mut started = PairingClientHandshake::start_from_join_attempt(
            &join_runtime,
            &attempt.attempt_id,
            &mut client_connection,
            &mut client_store,
            now + 30,
        )
        .expect("client starts");
        started
            .handshake
            .set_connected_endpoint(Ipv4Addr::new(192, 168, 1, 8), 41234);

        let (client_io, server_io) = duplex(128 * 1024);
        let mut client_socket =
            WebSocketStream::from_raw_socket(client_io, Role::Client, None).await;
        let mut server_socket =
            WebSocketStream::from_raw_socket(server_io, Role::Server, None).await;
        let expected_space_id = space.space_id.clone();
        let expected_key_version = space.key_version;
        let server_space_id = expected_space_id.clone();
        let server_space_key_ref = space.space_key_ref.clone();
        let server_task = tokio::spawn(async move {
            let Message::Text(client_hello) = server_socket
                .next()
                .await
                .expect("client hello message")
                .expect("client hello frame")
            else {
                panic!("client hello must be text");
            };
            let server_ephemeral = X25519Secret::from_private_key([0x52; 32]);
            let hello = accept_pairing_client_hello(
                &mut server_connection,
                &mut server_store,
                &client_hello,
                &encode_base64url(&server_ephemeral.public_key()),
                &Uuid::now_v7().to_string(),
                now + 40,
            )
            .expect("server hello");
            server_socket
                .send(Message::Text(hello.server_hello_frame.clone().into()))
                .await
                .expect("send server hello");
            let Message::Text(client_proof) = server_socket
                .next()
                .await
                .expect("client proof message")
                .expect("client proof frame")
            else {
                panic!("client proof must be text");
            };
            let server_seed = IdentitySecretStore::load_seed(
                &server_store,
                &hello.server_identity_private_key_ref,
            )
            .expect("identity lookup")
            .expect("identity seed");
            let accepted = accept_pairing_auth_proof(
                PairingServerAuthProofInput {
                    invitation_id: hello.invitation_id,
                    space_id: hello.space_id,
                    peer_device_id: hello.peer_device_id,
                    peer_identity_public_key: hello.peer_identity_public_key,
                    peer_ephemeral_public_key: hello.peer_ephemeral_public_key,
                    server_device_id: hello.server_device_id,
                    server_identity_public_key: hello.server_identity_public_key,
                    server_identity_private_seed: server_seed,
                    server_ephemeral_public_key: hello.server_ephemeral_public_key,
                    pairing_context: hello.pairing_context,
                    server_ephemeral_secret: server_ephemeral,
                },
                &client_proof,
                &Uuid::now_v7().to_string(),
                &Uuid::now_v7().to_string(),
            )
            .expect("server accepts proof");
            server_socket
                .send(Message::Text(accepted.server_auth_proof_frame.into()))
                .await
                .expect("send server proof");
            server_socket
                .send(Message::Text(accepted.auth_ok_frame.into()))
                .await
                .expect("send auth ok");
            let key = server_store
                .load_secret(&server_space_key_ref)
                .expect("key lookup")
                .expect("space key");
            let mut server_transport = AuthenticatedTransportSession::new(
                SessionDirection::ClientToServer,
                accepted.session_keys.client_to_server,
                SessionDirection::ServerToClient,
                accepted.session_keys.server_to_client,
                5,
            );
            let key_frame = server_transport
                .encode_business_frame(
                    MessageType::SpaceKeyRotated,
                    Uuid::now_v7().to_string(),
                    &serde_json::json!({
                        "spaceId": server_space_id,
                        "keyVersion": expected_key_version,
                        "spaceKey": encode_base64url(&key),
                        "delivery": "pairing-v1",
                    }),
                )
                .expect("space key frame");
            server_socket
                .send(Message::Text(key_frame.into()))
                .await
                .expect("send space key");
        });

        let ready = complete_initial_pairing(
            &mut client_socket,
            started,
            &mut client_connection,
            &mut client_store,
        )
        .await
        .expect("client becomes joined");
        server_task.await.expect("server task");
        assert_eq!(ready.summary.space_id.to_string(), expected_space_id);
        assert_eq!(ready.summary.key_version, expected_key_version);
        assert_eq!(
            ready.transport.state(),
            crate::protocol::ProtocolSessionState::Authenticated
        );
        assert!(client_store
            .load_secret(&ready.summary.space_key_ref)
            .expect("client key lookup")
            .is_some());
    }

    #[tokio::test]
    async fn trusted_client_reconnects_with_saved_identity_and_key_version() {
        let now = now_ms().expect("current time");
        let mut server_connection = open_in_memory_database().expect("server database");
        let mut server_store = TestSecretStore::default();
        let created = create_sync_space(
            &mut server_connection,
            &mut server_store,
            "Windows 互联空间",
            now,
        )
        .expect("server space");
        let server_identity =
            ensure_local_device_identity(&mut server_connection, &mut server_store, now + 1)
                .expect("server identity");
        let mut client_connection = open_in_memory_database().expect("client database");
        let mut client_store = TestSecretStore::default();
        let client_identity =
            ensure_local_device_identity(&mut client_connection, &mut client_store, now + 2)
                .expect("client identity");
        let space_id = Uuid::parse_str(&created.space_id).expect("space id");
        let server_device_id = Uuid::parse_str(&server_identity.device_id).expect("server id");
        let client_device_id = Uuid::parse_str(&client_identity.device_id).expect("client id");
        let space_key = server_store
            .load_secret(&created.space_key_ref)
            .expect("space key lookup")
            .expect("space key");
        let client_key_ref = format!("credential://test/{space_id}/v{}", created.key_version);
        client_store
            .save_secret(&client_key_ref, &space_key)
            .expect("save client key");
        let client_space = SpaceRecord {
            space: Space {
                space_id,
                display_name: "Windows 互联空间".to_string(),
                key_version: created.key_version,
                state: SpaceState::Active,
                created_at: now,
            },
            local_role: LocalSpaceRole::Member,
            encrypted_space_key_ref: Some(client_key_ref),
            updated_at: now + 2,
        };
        SpaceRepository::new(&client_connection)
            .upsert(&client_space)
            .expect("client space");
        let coordinator = DeviceRecord {
            device: Device {
                device_id: server_device_id,
                space_id,
                display_name: "Windows A".to_string(),
                identity_public_key_ref: server_identity.identity_public_key.clone(),
                trust_state: DeviceTrustState::Trusted,
                connection_state: DeviceConnectionState::Offline,
                last_seen_at: None,
            },
            route: TrustedDeviceRoute {
                role: TrustedRouteRole::DialCoordinator,
                last_successful_host: Some("192.168.1.8".to_string()),
                last_successful_port: Some(41234),
            },
            paired_at: Some(now),
            revoked_at: None,
        };
        DeviceRepository::new(&client_connection)
            .upsert(&coordinator)
            .expect("client coordinator");
        DeviceRepository::new(&server_connection)
            .upsert(&DeviceRecord {
                device: Device {
                    device_id: client_device_id,
                    space_id,
                    display_name: "Windows B".to_string(),
                    identity_public_key_ref: client_identity.identity_public_key.clone(),
                    trust_state: DeviceTrustState::Trusted,
                    connection_state: DeviceConnectionState::Offline,
                    last_seen_at: None,
                },
                route: TrustedDeviceRoute::default(),
                paired_at: Some(now),
                revoked_at: None,
            })
            .expect("server trusts client");
        let started = PairingClientHandshake::start_from_trusted_device(
            &client_space,
            &coordinator,
            &mut client_connection,
            &mut client_store,
            now + 10,
        )
        .expect("trusted client starts");

        let (client_io, server_io) = duplex(128 * 1024);
        let mut client_socket =
            WebSocketStream::from_raw_socket(client_io, Role::Client, None).await;
        let mut server_socket =
            WebSocketStream::from_raw_socket(server_io, Role::Server, None).await;
        let server_task = tokio::spawn(async move {
            let Message::Text(client_hello) = server_socket
                .next()
                .await
                .expect("client hello message")
                .expect("client hello frame")
            else {
                panic!("client hello must be text");
            };
            let server_ephemeral = X25519Secret::from_private_key([0x61; 32]);
            let hello = accept_trusted_device_client_hello(
                &mut server_connection,
                &mut server_store,
                &client_hello,
                &encode_base64url(&server_ephemeral.public_key()),
                &Uuid::now_v7().to_string(),
                now + 20,
            )
            .expect("trusted hello accepted");
            assert_eq!(hello.peer_space_key_version, Some(created.key_version));
            server_socket
                .send(Message::Text(hello.server_hello_frame.clone().into()))
                .await
                .expect("send server hello");
            let Message::Text(client_proof) = server_socket
                .next()
                .await
                .expect("client proof message")
                .expect("client proof frame")
            else {
                panic!("client proof must be text");
            };
            let server_seed = IdentitySecretStore::load_seed(
                &server_store,
                &hello.server_identity_private_key_ref,
            )
            .expect("identity lookup")
            .expect("identity seed");
            let accepted = accept_pairing_auth_proof(
                PairingServerAuthProofInput {
                    invitation_id: hello.invitation_id,
                    space_id: hello.space_id,
                    peer_device_id: hello.peer_device_id,
                    peer_identity_public_key: hello.peer_identity_public_key,
                    peer_ephemeral_public_key: hello.peer_ephemeral_public_key,
                    server_device_id: hello.server_device_id,
                    server_identity_public_key: hello.server_identity_public_key,
                    server_identity_private_seed: server_seed,
                    server_ephemeral_public_key: hello.server_ephemeral_public_key,
                    pairing_context: hello.pairing_context,
                    server_ephemeral_secret: server_ephemeral,
                },
                &client_proof,
                &Uuid::now_v7().to_string(),
                &Uuid::now_v7().to_string(),
            )
            .expect("trusted proof accepted");
            server_socket
                .send(Message::Text(accepted.server_auth_proof_frame.into()))
                .await
                .expect("send server proof");
            server_socket
                .send(Message::Text(accepted.auth_ok_frame.into()))
                .await
                .expect("send auth ok");
        });

        let ready = complete_trusted_reconnect(&mut client_socket, started)
            .await
            .expect("trusted reconnect completes");
        server_task.await.expect("server task");
        assert_eq!(ready.space_id, space_id);
        assert_eq!(ready.coordinator_device_id, server_device_id);
        assert_eq!(ready.key_version, created.key_version);
        assert_eq!(
            ready.transport.state(),
            crate::protocol::ProtocolSessionState::Authenticated
        );
    }
}
