use super::*;

use crate::{
    pairing::{
        client_handshake::{PairingClientHandshake, PairingClientHandshakeEvent},
        client_join::PairingClientReadySession,
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
    host: String,
    port: u16,
) -> Result<TrustedOutboundConnectionSummary, String> {
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
    .map_err(|error| format!("无法开始可信握手：{error}"))?;
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
        ready.transport,
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
            .map_err(|error| format!("可信握手失败：{error}"))?
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
                    .map_err(|error| format!("无法保存可信空间：{error}"));
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
        identity::IdentitySecretStore,
        pairing::{
            accept_pairing_auth_proof, accept_pairing_client_hello,
            create_pairing_invitation_for_space, create_sync_space, PairingServerAuthProofInput,
        },
        secret_store::{SecretBytesStore, SecretStoreError},
        storage::open_in_memory_database,
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
}
