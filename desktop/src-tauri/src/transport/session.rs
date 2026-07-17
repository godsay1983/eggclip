use std::fmt;

use crate::{
    crypto::{SessionDirection, AES_256_KEY_BYTES},
    protocol::{
        build_encrypted_envelope, decrypt_encrypted_payload, parse_envelope,
        serialize_encrypted_envelope, EncryptedEnvelope, MessageType, ProtocolEnvelope,
        ProtocolError, ProtocolInboundSession, ProtocolSessionState, MAX_FRAME_BYTES,
    },
};
use serde_json::Value;
use tokio_tungstenite::tungstenite::Message;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TransportFrameError {
    FrameTooLarge {
        actual_bytes: usize,
        max_bytes: usize,
    },
    BinaryUnsupported,
    UnexpectedPlaintext,
    RemoteError,
    SessionClosed,
    ProtocolRejected(ProtocolError),
}

#[derive(Debug, Clone, PartialEq)]
pub struct HandshakeFrame {
    pub message_type: MessageType,
    pub payload: Value,
}

#[derive(Debug, Clone, PartialEq)]
pub enum HandshakeFrameOutcome {
    Continue(HandshakeFrame),
    Authenticated(HandshakeFrame),
    Failed(HandshakeFrame),
}

impl fmt::Display for TransportFrameError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            TransportFrameError::FrameTooLarge {
                actual_bytes,
                max_bytes,
            } => write!(
                formatter,
                "frame is too large: {actual_bytes} bytes, max {max_bytes}"
            ),
            TransportFrameError::BinaryUnsupported => {
                formatter.write_str("authenticated transport only accepts text frames")
            }
            TransportFrameError::UnexpectedPlaintext => {
                formatter.write_str("authenticated transport requires encrypted frames")
            }
            TransportFrameError::RemoteError => {
                formatter.write_str("remote peer sent an encrypted protocol error")
            }
            TransportFrameError::SessionClosed => {
                formatter.write_str("authenticated transport session is closed")
            }
            TransportFrameError::ProtocolRejected(error) => write!(formatter, "{error}"),
        }
    }
}

impl std::error::Error for TransportFrameError {}

impl From<ProtocolError> for TransportFrameError {
    fn from(error: ProtocolError) -> Self {
        Self::ProtocolRejected(error)
    }
}

#[derive(Debug, Clone)]
pub struct HandshakeTransportSession {
    inbound: ProtocolInboundSession,
    closed: bool,
}

impl Default for HandshakeTransportSession {
    fn default() -> Self {
        Self::new()
    }
}

impl HandshakeTransportSession {
    pub fn new() -> Self {
        let mut inbound = ProtocolInboundSession::default();
        inbound.connect();
        inbound.start_handshake();
        Self {
            inbound,
            closed: false,
        }
    }

    pub fn state(&self) -> ProtocolSessionState {
        self.inbound.state()
    }

    pub fn is_closed(&self) -> bool {
        self.closed
    }

    pub fn close(&mut self) {
        self.closed = true;
        self.inbound.fail();
    }

    pub fn accept_websocket_message(
        &mut self,
        message: Message,
    ) -> Result<Option<HandshakeFrameOutcome>, TransportFrameError> {
        if self.closed {
            return Err(TransportFrameError::SessionClosed);
        }
        match message {
            Message::Text(text) => self.accept_text_frame(&text).map(Some),
            Message::Binary(bytes) => {
                if bytes.len() > MAX_FRAME_BYTES {
                    self.fail_with(TransportFrameError::FrameTooLarge {
                        actual_bytes: bytes.len(),
                        max_bytes: MAX_FRAME_BYTES,
                    })
                } else {
                    self.fail_with(TransportFrameError::BinaryUnsupported)
                }
            }
            Message::Close(_) => {
                self.close();
                Ok(None)
            }
            Message::Ping(_) | Message::Pong(_) | Message::Frame(_) => Ok(None),
        }
    }

    pub fn accept_text_frame(
        &mut self,
        text: &str,
    ) -> Result<HandshakeFrameOutcome, TransportFrameError> {
        if self.closed {
            return Err(TransportFrameError::SessionClosed);
        }
        if text.len() > MAX_FRAME_BYTES {
            return self.fail_with(TransportFrameError::FrameTooLarge {
                actual_bytes: text.len(),
                max_bytes: MAX_FRAME_BYTES,
            });
        }

        match self.accept_text_frame_inner(text) {
            Ok(outcome) => Ok(outcome),
            Err(error) => self.fail_with(error),
        }
    }

    fn accept_text_frame_inner(
        &mut self,
        text: &str,
    ) -> Result<HandshakeFrameOutcome, TransportFrameError> {
        let envelope = parse_envelope(text)?;
        self.inbound.accept_envelope(&envelope)?;
        let pre_auth = match envelope {
            ProtocolEnvelope::PreAuth(envelope) => envelope,
            ProtocolEnvelope::Encrypted(_) => return Err(TransportFrameError::UnexpectedPlaintext),
        };
        let frame = HandshakeFrame {
            message_type: pre_auth.message_type,
            payload: pre_auth.payload,
        };
        match frame.message_type {
            MessageType::AuthOk => Ok(HandshakeFrameOutcome::Authenticated(frame)),
            MessageType::AuthError | MessageType::Error => {
                self.close();
                Ok(HandshakeFrameOutcome::Failed(frame))
            }
            _ => Ok(HandshakeFrameOutcome::Continue(frame)),
        }
    }

    fn fail_with<T>(&mut self, error: TransportFrameError) -> Result<T, TransportFrameError> {
        self.close();
        Err(error)
    }
}

#[derive(Debug, Clone)]
pub struct AuthenticatedTransportSession {
    inbound: ProtocolInboundSession,
    inbound_direction: SessionDirection,
    inbound_key: [u8; AES_256_KEY_BYTES],
    outbound_direction: SessionDirection,
    outbound_key: [u8; AES_256_KEY_BYTES],
    next_outbound_counter: u64,
    closed: bool,
}

impl AuthenticatedTransportSession {
    pub fn new(
        inbound_direction: SessionDirection,
        inbound_key: [u8; AES_256_KEY_BYTES],
        outbound_direction: SessionDirection,
        outbound_key: [u8; AES_256_KEY_BYTES],
        next_outbound_counter: u64,
    ) -> Self {
        Self {
            inbound: ProtocolInboundSession::authenticated(),
            inbound_direction,
            inbound_key,
            outbound_direction,
            outbound_key,
            next_outbound_counter,
            closed: false,
        }
    }

    pub fn state(&self) -> ProtocolSessionState {
        self.inbound.state()
    }

    pub fn next_outbound_counter(&self) -> u64 {
        self.next_outbound_counter
    }

    pub fn is_closed(&self) -> bool {
        self.closed
    }

    pub fn mark_ready(&mut self) -> Result<ProtocolSessionState, TransportFrameError> {
        if self.closed {
            return Err(TransportFrameError::SessionClosed);
        }
        self.inbound
            .mark_ready()
            .map_err(TransportFrameError::ProtocolRejected)
    }

    pub fn close(&mut self) {
        self.fail_and_scrub_keys();
    }

    pub fn encode_business_frame(
        &mut self,
        message_type: MessageType,
        message_id: String,
        payload: &Value,
    ) -> Result<String, TransportFrameError> {
        if self.closed {
            return Err(TransportFrameError::SessionClosed);
        }
        let envelope = build_encrypted_envelope(
            message_type,
            message_id,
            self.next_outbound_counter,
            self.outbound_direction,
            self.outbound_key,
            payload,
        )?;
        let frame = serialize_encrypted_envelope(&envelope)?;
        self.next_outbound_counter = self.next_outbound_counter.saturating_add(1);
        Ok(frame)
    }

    pub fn encode_business_message(
        &mut self,
        message_type: MessageType,
        message_id: String,
        payload: &Value,
    ) -> Result<Message, TransportFrameError> {
        Ok(Message::Text(
            self.encode_business_frame(message_type, message_id, payload)?
                .into(),
        ))
    }

    pub fn accept_websocket_message(
        &mut self,
        message: Message,
    ) -> Result<Option<Value>, TransportFrameError> {
        if self.closed {
            return Err(TransportFrameError::SessionClosed);
        }
        match message {
            Message::Text(text) => self.accept_text_frame(&text).map(Some),
            Message::Binary(bytes) => {
                if bytes.len() > MAX_FRAME_BYTES {
                    self.fail_with(TransportFrameError::FrameTooLarge {
                        actual_bytes: bytes.len(),
                        max_bytes: MAX_FRAME_BYTES,
                    })
                } else {
                    self.fail_with(TransportFrameError::BinaryUnsupported)
                }
            }
            Message::Close(_) => {
                self.close();
                Ok(None)
            }
            Message::Ping(_) | Message::Pong(_) | Message::Frame(_) => Ok(None),
        }
    }

    pub fn accept_text_frame(&mut self, text: &str) -> Result<Value, TransportFrameError> {
        self.accept_typed_text_frame(text)
            .map(|(_, payload)| payload)
    }

    pub fn accept_typed_text_frame(
        &mut self,
        text: &str,
    ) -> Result<(MessageType, Value), TransportFrameError> {
        if self.closed {
            return Err(TransportFrameError::SessionClosed);
        }
        if let Err(error) = self.validate_text_frame_size(text) {
            return self.fail_with(error);
        }

        match self.accept_text_frame_inner(text) {
            Ok(payload) => Ok(payload),
            Err(error) => self.fail_with(error),
        }
    }

    fn validate_text_frame_size(&self, text: &str) -> Result<(), TransportFrameError> {
        if text.len() > MAX_FRAME_BYTES {
            return Err(TransportFrameError::FrameTooLarge {
                actual_bytes: text.len(),
                max_bytes: MAX_FRAME_BYTES,
            });
        }
        Ok(())
    }

    fn accept_text_frame_inner(
        &mut self,
        text: &str,
    ) -> Result<(MessageType, Value), TransportFrameError> {
        let envelope = parse_envelope(text)?;
        self.inbound.accept_envelope(&envelope)?;
        let encrypted = match envelope {
            ProtocolEnvelope::Encrypted(envelope) => envelope,
            ProtocolEnvelope::PreAuth(_) => return Err(TransportFrameError::UnexpectedPlaintext),
        };
        let payload = self.decrypt_envelope(&encrypted)?;
        if encrypted.message_type == MessageType::Error {
            return Err(TransportFrameError::RemoteError);
        }
        Ok((encrypted.message_type, payload))
    }

    fn decrypt_envelope(&self, envelope: &EncryptedEnvelope) -> Result<Value, TransportFrameError> {
        decrypt_encrypted_payload(envelope, self.inbound_direction, self.inbound_key)
            .map_err(TransportFrameError::ProtocolRejected)
    }

    fn fail_with<T>(&mut self, error: TransportFrameError) -> Result<T, TransportFrameError> {
        self.fail_and_scrub_keys();
        Err(error)
    }

    fn fail_and_scrub_keys(&mut self) {
        self.closed = true;
        self.inbound.fail();
        self.inbound_key.fill(0);
        self.outbound_key.fill(0);
        self.next_outbound_counter = 0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::crypto::{decode_base64url, fixed_bytes};
    use serde::Deserialize;
    use std::{fs, path::PathBuf};

    #[derive(Debug, Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct SessionKeysVector {
        client_to_server_key: String,
        server_to_client_key: String,
    }

    fn vector_path(parts: &[&str]) -> PathBuf {
        let mut path = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        path.push("..");
        path.push("..");
        path.push("protocol");
        for part in parts {
            path.push(part);
        }
        path
    }

    fn read_json_vector<T: for<'de> Deserialize<'de>>(parts: &[&str]) -> T {
        let data = fs::read_to_string(vector_path(parts)).expect("test vector should be readable");
        serde_json::from_str(&data).expect("test vector should deserialize")
    }

    fn decoded_fixed<const N: usize>(value: &str, field: &'static str) -> [u8; N] {
        fixed_bytes(
            &decode_base64url(value).expect("base64url should decode"),
            field,
        )
        .expect("fixed value should have expected length")
    }

    fn session_pair() -> (AuthenticatedTransportSession, AuthenticatedTransportSession) {
        let vector: SessionKeysVector =
            read_json_vector(&["test-vectors", "crypto", "session-keys.valid.json"]);
        let c2s_key = decoded_fixed::<32>(&vector.client_to_server_key, "clientToServerKey");
        let s2c_key = decoded_fixed::<32>(&vector.server_to_client_key, "serverToClientKey");
        let client = AuthenticatedTransportSession::new(
            SessionDirection::ServerToClient,
            s2c_key,
            SessionDirection::ClientToServer,
            c2s_key,
            12,
        );
        let server = AuthenticatedTransportSession::new(
            SessionDirection::ClientToServer,
            c2s_key,
            SessionDirection::ServerToClient,
            s2c_key,
            12,
        );
        (client, server)
    }

    #[test]
    fn handshake_transport_accepts_plaintext_handshake_then_auth_ok() {
        let mut session = HandshakeTransportSession::new();

        let client_hello = r#"{
          "version": 1,
          "type": "CLIENT_HELLO",
          "messageId": "018ff6f0-2b1f-7cc5-b5d0-7e82c5f70f01",
          "sessionCounter": 0,
          "payload": {
            "spaceId": "018ff6ef-c394-7d08-8b99-4b7d10f2767a"
          }
        }"#;
        let auth_ok = r#"{
          "version": 1,
          "type": "AUTH_OK",
          "messageId": "018ff6f1-25f0-7c09-a4cf-3d683ebfae33",
          "sessionCounter": 1,
          "payload": {}
        }"#;

        let outcome = session
            .accept_text_frame(client_hello)
            .expect("client hello should pass");
        assert!(matches!(
            outcome,
            HandshakeFrameOutcome::Continue(HandshakeFrame {
                message_type: MessageType::ClientHello,
                ..
            })
        ));

        let outcome = session
            .accept_websocket_message(Message::Text(auth_ok.into()))
            .expect("auth ok should pass")
            .expect("auth ok should produce outcome");
        assert!(matches!(
            outcome,
            HandshakeFrameOutcome::Authenticated(HandshakeFrame {
                message_type: MessageType::AuthOk,
                ..
            })
        ));
        assert_eq!(session.state(), ProtocolSessionState::Authenticated);
        assert!(!session.is_closed());
    }

    #[test]
    fn handshake_transport_closes_on_auth_error() {
        let mut session = HandshakeTransportSession::new();
        let auth_error = r#"{
          "version": 1,
          "type": "AUTH_ERROR",
          "messageId": "018ff6f1-25f0-7c09-a4cf-3d683ebfae33",
          "sessionCounter": 1,
          "payload": {
            "code": "authFailed"
          }
        }"#;

        let outcome = session
            .accept_text_frame(auth_error)
            .expect("auth error should parse");

        assert!(matches!(
            outcome,
            HandshakeFrameOutcome::Failed(HandshakeFrame {
                message_type: MessageType::AuthError,
                ..
            })
        ));
        assert!(session.is_closed());
        assert_eq!(session.state(), ProtocolSessionState::Failed);
        assert_eq!(
            session.accept_text_frame(auth_error).unwrap_err(),
            TransportFrameError::SessionClosed
        );
    }

    #[test]
    fn handshake_transport_rejects_encrypted_or_duplicate_frames() {
        let mut session = HandshakeTransportSession::new();
        let encrypted = read_json_vector::<serde_json::Value>(&[
            "test-vectors",
            "sync",
            "encrypted-item-live-envelope.valid.json",
        ])
        .to_string();

        assert_eq!(
            session.accept_text_frame(&encrypted).unwrap_err(),
            TransportFrameError::ProtocolRejected(ProtocolError::CiphertextBeforeAuth(
                MessageType::ItemLive
            ))
        );
        assert!(session.is_closed());

        let mut duplicate_session = HandshakeTransportSession::new();
        let auth_error = r#"{
          "version": 1,
          "type": "AUTH_ERROR",
          "messageId": "018ff6f1-25f0-7c09-a4cf-3d683ebfae33",
          "sessionCounter": 1,
          "payload": {}
        }"#;
        duplicate_session
            .accept_text_frame(auth_error)
            .expect("first auth error should pass");
        assert_eq!(
            duplicate_session.accept_text_frame(auth_error).unwrap_err(),
            TransportFrameError::SessionClosed
        );
    }

    #[test]
    fn authenticated_transport_round_trips_encrypted_business_frame() {
        let (mut client, mut server) = session_pair();
        let payload = serde_json::json!({
            "content": "EggClip transport payload",
            "contentType": "text/plain"
        });

        let frame = client
            .encode_business_frame(
                MessageType::ItemLive,
                "018ff6f3-0d8c-7d1e-a38a-f308c64de79f".to_owned(),
                &payload,
            )
            .expect("client should encode frame");
        let decoded = server
            .accept_text_frame(&frame)
            .expect("server should accept encrypted frame");

        assert_eq!(decoded, payload);
        assert_eq!(client.next_outbound_counter(), 13);
        assert_eq!(server.state(), ProtocolSessionState::Ready);
    }

    #[test]
    fn authenticated_transport_rejects_duplicate_frame_before_dispatch() {
        let (mut client, mut server) = session_pair();
        let payload = serde_json::json!({"content": "duplicate"});
        let frame = client
            .encode_business_frame(
                MessageType::ItemLive,
                "018ff6f3-0d8c-7d1e-a38a-f308c64de79f".to_owned(),
                &payload,
            )
            .expect("client should encode frame");

        server
            .accept_text_frame(&frame)
            .expect("first frame should be accepted");
        assert_eq!(
            server.accept_text_frame(&frame).unwrap_err(),
            TransportFrameError::ProtocolRejected(ProtocolError::DuplicateMessageId)
        );
        assert!(server.is_closed());
        assert_eq!(server.state(), ProtocolSessionState::Failed);
        assert_eq!(
            server.accept_text_frame(&frame).unwrap_err(),
            TransportFrameError::SessionClosed
        );
    }

    #[test]
    fn authenticated_transport_rejects_poc_plaintext_json() {
        let (_client, mut server) = session_pair();

        assert!(matches!(
            server
                .accept_text_frame(r#"{"kind":"clipboardText","text":"not formal protocol"}"#)
                .unwrap_err(),
            TransportFrameError::ProtocolRejected(ProtocolError::InvalidJson(_))
                | TransportFrameError::ProtocolRejected(ProtocolError::InvalidField(_))
        ));
        assert!(server.is_closed());
    }

    #[test]
    fn authenticated_transport_accepts_and_encodes_websocket_messages() {
        let (mut client, mut server) = session_pair();
        let payload = serde_json::json!({"content": "websocket boundary"});

        let message = client
            .encode_business_message(
                MessageType::ItemLive,
                "018ff6f3-0d8c-7d1e-a38a-f308c64de79f".to_owned(),
                &payload,
            )
            .expect("client should encode websocket message");
        let decoded = server
            .accept_websocket_message(message)
            .expect("server should accept websocket message")
            .expect("text message should produce payload");

        assert_eq!(decoded, payload);
        assert_eq!(
            server.accept_websocket_message(Message::Ping(Vec::new().into())),
            Ok(None)
        );
        assert_eq!(
            server.accept_websocket_message(Message::Binary(vec![1, 2, 3].into())),
            Err(TransportFrameError::BinaryUnsupported)
        );
        assert!(server.is_closed());
    }

    #[test]
    fn authenticated_transport_close_message_scrubs_session() {
        let (_client, mut server) = session_pair();

        assert_eq!(
            server.accept_websocket_message(Message::Close(None)),
            Ok(None)
        );
        assert!(server.is_closed());
        assert_eq!(server.state(), ProtocolSessionState::Failed);
        assert_eq!(
            server.accept_websocket_message(Message::Ping(Vec::new().into())),
            Err(TransportFrameError::SessionClosed)
        );
    }

    #[test]
    fn authenticated_transport_decrypts_remote_error_then_closes_session() {
        let (mut client, mut server) = session_pair();
        let frame = client
            .encode_business_frame(
                MessageType::Error,
                "018ff6f4-0d8c-7d1e-a38a-f308c64de79f".to_owned(),
                &serde_json::json!({"code": "authFailed"}),
            )
            .expect("client should encode encrypted error");

        assert_eq!(
            server.accept_text_frame(&frame).unwrap_err(),
            TransportFrameError::RemoteError
        );
        assert!(server.is_closed());
        assert_eq!(server.state(), ProtocolSessionState::Failed);
        assert_eq!(
            server.accept_text_frame(&frame).unwrap_err(),
            TransportFrameError::SessionClosed
        );
    }

    #[test]
    fn authenticated_transport_close_scrubs_keys_and_blocks_sends() {
        let (mut client, _server) = session_pair();

        client.close();

        assert!(client.is_closed());
        assert_eq!(client.state(), ProtocolSessionState::Failed);
        assert_eq!(client.next_outbound_counter(), 0);
        assert_eq!(
            client
                .encode_business_frame(
                    MessageType::ItemLive,
                    "018ff6f3-0d8c-7d1e-a38a-f308c64de79f".to_owned(),
                    &serde_json::json!({"content": "blocked"})
                )
                .unwrap_err(),
            TransportFrameError::SessionClosed
        );
    }
}
