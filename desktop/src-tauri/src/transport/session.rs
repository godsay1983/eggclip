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

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TransportFrameError {
    FrameTooLarge {
        actual_bytes: usize,
        max_bytes: usize,
    },
    UnexpectedPlaintext,
    ProtocolRejected(ProtocolError),
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
            TransportFrameError::UnexpectedPlaintext => {
                formatter.write_str("authenticated transport requires encrypted frames")
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
pub struct AuthenticatedTransportSession {
    inbound: ProtocolInboundSession,
    inbound_direction: SessionDirection,
    inbound_key: [u8; AES_256_KEY_BYTES],
    outbound_direction: SessionDirection,
    outbound_key: [u8; AES_256_KEY_BYTES],
    next_outbound_counter: u64,
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
        }
    }

    pub fn state(&self) -> ProtocolSessionState {
        self.inbound.state()
    }

    pub fn next_outbound_counter(&self) -> u64 {
        self.next_outbound_counter
    }

    pub fn encode_business_frame(
        &mut self,
        message_type: MessageType,
        message_id: String,
        payload: &Value,
    ) -> Result<String, TransportFrameError> {
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

    pub fn accept_text_frame(&mut self, text: &str) -> Result<Value, TransportFrameError> {
        if text.len() > MAX_FRAME_BYTES {
            return Err(TransportFrameError::FrameTooLarge {
                actual_bytes: text.len(),
                max_bytes: MAX_FRAME_BYTES,
            });
        }

        let envelope = parse_envelope(text)?;
        self.inbound.accept_envelope(&envelope)?;
        let encrypted = match envelope {
            ProtocolEnvelope::Encrypted(envelope) => envelope,
            ProtocolEnvelope::PreAuth(_) => return Err(TransportFrameError::UnexpectedPlaintext),
        };
        self.decrypt_envelope(&encrypted)
    }

    fn decrypt_envelope(&self, envelope: &EncryptedEnvelope) -> Result<Value, TransportFrameError> {
        decrypt_encrypted_payload(envelope, self.inbound_direction, self.inbound_key)
            .map_err(TransportFrameError::ProtocolRejected)
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
    }
}
