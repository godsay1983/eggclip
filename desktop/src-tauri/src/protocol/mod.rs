use std::fmt;

use serde::{Deserialize, Serialize};
use serde_json::Value;

pub const PROTOCOL_VERSION: u16 = 1;
pub const MAX_FRAME_BYTES: usize = 1024 * 1024;
pub const MAX_TEXT_BYTES: usize = 256 * 1024;
pub const MAX_BATCH_ITEMS: usize = 100;
pub const MAX_BATCH_PLAINTEXT_BYTES: usize = 512 * 1024;
pub const HANDSHAKE_TIMEOUT_SECONDS: u64 = 8;
pub const HEARTBEAT_INTERVAL_SECONDS: u64 = 20;
pub const IDLE_DISCONNECT_SECONDS: u64 = 60;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ProtocolError {
    InvalidJson(String),
    UnsupportedVersion(u16),
    UnknownMessageType(String),
    MissingPayload(MessageType),
    MissingCiphertext(MessageType),
    PlaintextAfterAuth(MessageType),
    CiphertextBeforeAuth(MessageType),
    InvalidField(&'static str),
    TextTooLarge {
        actual_bytes: usize,
        max_bytes: usize,
    },
}

impl fmt::Display for ProtocolError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ProtocolError::InvalidJson(error) => write!(formatter, "invalid JSON: {error}"),
            ProtocolError::UnsupportedVersion(version) => {
                write!(formatter, "unsupported protocol version {version}")
            }
            ProtocolError::UnknownMessageType(message_type) => {
                write!(formatter, "unknown message type {message_type}")
            }
            ProtocolError::MissingPayload(message_type) => {
                write!(formatter, "{message_type} requires plaintext payload")
            }
            ProtocolError::MissingCiphertext(message_type) => {
                write!(formatter, "{message_type} requires ciphertext")
            }
            ProtocolError::PlaintextAfterAuth(message_type) => {
                write!(
                    formatter,
                    "{message_type} must not use plaintext after auth"
                )
            }
            ProtocolError::CiphertextBeforeAuth(message_type) => {
                write!(
                    formatter,
                    "{message_type} must not use ciphertext before auth"
                )
            }
            ProtocolError::InvalidField(field) => write!(formatter, "invalid field {field}"),
            ProtocolError::TextTooLarge {
                actual_bytes,
                max_bytes,
            } => write!(
                formatter,
                "text is too large: {actual_bytes} bytes, max {max_bytes}"
            ),
        }
    }
}

impl std::error::Error for ProtocolError {}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum MessageType {
    ClientHello,
    ServerHello,
    AuthProof,
    AuthOk,
    AuthError,
    SyncHeads,
    RequestRange,
    ItemBatch,
    ItemLive,
    ItemAck,
    DeviceRevoked,
    SpaceKeyRotated,
    Ping,
    Pong,
    Error,
}

impl MessageType {
    fn is_pre_auth_allowed(self) -> bool {
        matches!(
            self,
            MessageType::ClientHello
                | MessageType::ServerHello
                | MessageType::AuthProof
                | MessageType::AuthOk
                | MessageType::AuthError
                | MessageType::Error
        )
    }

    fn is_encrypted_allowed(self) -> bool {
        matches!(
            self,
            MessageType::SyncHeads
                | MessageType::RequestRange
                | MessageType::ItemBatch
                | MessageType::ItemLive
                | MessageType::ItemAck
                | MessageType::DeviceRevoked
                | MessageType::SpaceKeyRotated
                | MessageType::Ping
                | MessageType::Pong
                | MessageType::Error
        )
    }
}

impl fmt::Display for MessageType {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        let value = serde_json::to_string(self).map_err(|_| fmt::Error)?;
        formatter.write_str(value.trim_matches('"'))
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CiphertextFrame {
    algorithm: AeadAlgorithm,
    key_id: String,
    nonce: String,
    aad: String,
    body: String,
    tag: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum AeadAlgorithm {
    #[serde(rename = "AES-256-GCM")]
    Aes256Gcm,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ProtocolEnvelope {
    PreAuth(PreAuthEnvelope),
    Encrypted(EncryptedEnvelope),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PreAuthEnvelope {
    pub message_type: MessageType,
    pub message_id: String,
    pub session_counter: u64,
    pub payload: Value,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EncryptedEnvelope {
    pub message_type: MessageType,
    pub message_id: String,
    pub session_counter: u64,
    pub ciphertext: CiphertextFrame,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawEnvelope {
    version: u16,
    #[serde(rename = "type")]
    message_type: Value,
    message_id: String,
    session_counter: u64,
    payload: Option<Value>,
    ciphertext: Option<CiphertextFrame>,
}

pub fn parse_envelope(input: &str) -> Result<ProtocolEnvelope, ProtocolError> {
    if input.len() > MAX_FRAME_BYTES {
        return Err(ProtocolError::TextTooLarge {
            actual_bytes: input.len(),
            max_bytes: MAX_FRAME_BYTES,
        });
    }

    let raw: RawEnvelope = serde_json::from_str(input)
        .map_err(|error| ProtocolError::InvalidJson(error.to_string()))?;
    validate_version(raw.version)?;
    validate_uuid(&raw.message_id, "messageId")?;
    let message_type = parse_message_type(raw.message_type)?;

    match (raw.payload, raw.ciphertext) {
        (Some(payload), None) => {
            if !message_type.is_pre_auth_allowed() {
                return Err(ProtocolError::PlaintextAfterAuth(message_type));
            }
            if !payload.is_object() {
                return Err(ProtocolError::InvalidField("payload"));
            }
            Ok(ProtocolEnvelope::PreAuth(PreAuthEnvelope {
                message_type,
                message_id: raw.message_id,
                session_counter: raw.session_counter,
                payload,
            }))
        }
        (None, Some(ciphertext)) => {
            if !message_type.is_encrypted_allowed() {
                return Err(ProtocolError::CiphertextBeforeAuth(message_type));
            }
            validate_ciphertext(&ciphertext)?;
            Ok(ProtocolEnvelope::Encrypted(EncryptedEnvelope {
                message_type,
                message_id: raw.message_id,
                session_counter: raw.session_counter,
                ciphertext,
            }))
        }
        (Some(_), Some(_)) => {
            if message_type.is_pre_auth_allowed() {
                Err(ProtocolError::CiphertextBeforeAuth(message_type))
            } else {
                Err(ProtocolError::PlaintextAfterAuth(message_type))
            }
        }
        (None, None) => {
            if message_type.is_pre_auth_allowed() {
                Err(ProtocolError::MissingPayload(message_type))
            } else {
                Err(ProtocolError::MissingCiphertext(message_type))
            }
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HelloPayload {
    pub space_id: String,
    pub device_id: String,
    pub identity_public_key: String,
    pub ephemeral_public_key: String,
    pub capabilities: Vec<Capability>,
}

impl HelloPayload {
    pub fn validate(&self) -> Result<(), ProtocolError> {
        validate_uuid(&self.space_id, "spaceId")?;
        validate_uuid(&self.device_id, "deviceId")?;
        validate_base64url(&self.identity_public_key, "identityPublicKey")?;
        validate_base64url(&self.ephemeral_public_key, "ephemeralPublicKey")?;
        if self.capabilities.is_empty() {
            return Err(ProtocolError::InvalidField("capabilities"));
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum Capability {
    TextPlain,
    SyncHeads,
    ItemBatch,
    ItemLive,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ClipboardItem {
    pub item_id: String,
    pub space_id: String,
    pub origin_device_id: String,
    pub origin_seq: u64,
    pub hlc: String,
    pub content_type: ContentType,
    pub content_length: usize,
    pub content_digest: String,
    pub created_at: u64,
    pub content: String,
}

impl ClipboardItem {
    pub fn validate(&self) -> Result<(), ProtocolError> {
        validate_uuid(&self.item_id, "itemId")?;
        validate_uuid(&self.space_id, "spaceId")?;
        validate_uuid(&self.origin_device_id, "originDeviceId")?;
        validate_base64url(&self.content_digest, "contentDigest")?;
        if self.hlc.is_empty() {
            return Err(ProtocolError::InvalidField("hlc"));
        }
        let actual_bytes = self.content.len();
        if actual_bytes == 0 || actual_bytes != self.content_length {
            return Err(ProtocolError::InvalidField("contentLength"));
        }
        if actual_bytes > MAX_TEXT_BYTES {
            return Err(ProtocolError::TextTooLarge {
                actual_bytes,
                max_bytes: MAX_TEXT_BYTES,
            });
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ContentType {
    #[serde(rename = "text/plain")]
    TextPlain,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncHeadsPayload {
    pub heads: std::collections::BTreeMap<String, u64>,
    pub minimum_available: std::collections::BTreeMap<String, u64>,
}

impl SyncHeadsPayload {
    pub fn validate(&self) -> Result<(), ProtocolError> {
        validate_device_seq_map(&self.heads, "heads")?;
        validate_device_seq_map(&self.minimum_available, "minimumAvailable")?;
        Ok(())
    }
}

fn validate_version(version: u16) -> Result<(), ProtocolError> {
    if version == PROTOCOL_VERSION {
        Ok(())
    } else {
        Err(ProtocolError::UnsupportedVersion(version))
    }
}

fn parse_message_type(value: Value) -> Result<MessageType, ProtocolError> {
    let Some(raw) = value.as_str() else {
        return Err(ProtocolError::InvalidField("type"));
    };
    serde_json::from_value(Value::String(raw.to_owned()))
        .map_err(|_| ProtocolError::UnknownMessageType(raw.to_owned()))
}

fn validate_ciphertext(ciphertext: &CiphertextFrame) -> Result<(), ProtocolError> {
    if ciphertext.key_id.is_empty() || ciphertext.key_id.len() > 128 {
        return Err(ProtocolError::InvalidField("ciphertext.keyId"));
    }
    validate_base64url(&ciphertext.nonce, "ciphertext.nonce")?;
    validate_base64url(&ciphertext.aad, "ciphertext.aad")?;
    validate_base64url(&ciphertext.body, "ciphertext.body")?;
    validate_base64url(&ciphertext.tag, "ciphertext.tag")
}

fn validate_device_seq_map(
    map: &std::collections::BTreeMap<String, u64>,
    field: &'static str,
) -> Result<(), ProtocolError> {
    for key in map.keys() {
        validate_uuid(key, field)?;
    }
    Ok(())
}

fn validate_uuid(value: &str, field: &'static str) -> Result<(), ProtocolError> {
    let bytes = value.as_bytes();
    let is_uuid = bytes.len() == 36
        && matches!(bytes[8], b'-')
        && matches!(bytes[13], b'-')
        && matches!(bytes[18], b'-')
        && matches!(bytes[23], b'-')
        && bytes.iter().enumerate().all(|(index, byte)| {
            matches!(index, 8 | 13 | 18 | 23)
                || byte.is_ascii_hexdigit() && !byte.is_ascii_uppercase()
        });
    if is_uuid {
        Ok(())
    } else {
        Err(ProtocolError::InvalidField(field))
    }
}

fn validate_base64url(value: &str, field: &'static str) -> Result<(), ProtocolError> {
    if !value.is_empty()
        && value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_'))
    {
        Ok(())
    } else {
        Err(ProtocolError::InvalidField(field))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{fs, path::PathBuf};

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

    fn read_vector(parts: &[&str]) -> String {
        fs::read_to_string(vector_path(parts)).expect("test vector should be readable")
    }

    #[test]
    fn constants_match_v1_protocol_limits() {
        assert_eq!(PROTOCOL_VERSION, 1);
        assert_eq!(MAX_FRAME_BYTES, 1024 * 1024);
        assert_eq!(MAX_TEXT_BYTES, 256 * 1024);
        assert_eq!(MAX_BATCH_ITEMS, 100);
        assert_eq!(MAX_BATCH_PLAINTEXT_BYTES, 512 * 1024);
        assert_eq!(HANDSHAKE_TIMEOUT_SECONDS, 8);
        assert_eq!(HEARTBEAT_INTERVAL_SECONDS, 20);
        assert_eq!(IDLE_DISCONNECT_SECONDS, 60);
    }

    #[test]
    fn parses_client_hello_fixture() {
        let fixture = read_vector(&["test-vectors", "handshake", "client-hello.valid.json"]);
        let ProtocolEnvelope::PreAuth(envelope) =
            parse_envelope(&fixture).expect("client hello should parse")
        else {
            panic!("client hello should be pre-auth");
        };

        assert_eq!(envelope.message_type, MessageType::ClientHello);
        let payload: HelloPayload =
            serde_json::from_value(envelope.payload).expect("hello payload should deserialize");
        payload.validate().expect("hello payload should validate");
    }

    #[test]
    fn parses_encrypted_item_live_fixture() {
        let fixture = read_vector(&[
            "test-vectors",
            "sync",
            "encrypted-item-live-envelope.valid.json",
        ]);
        let ProtocolEnvelope::Encrypted(envelope) =
            parse_envelope(&fixture).expect("encrypted item live should parse")
        else {
            panic!("item live should be encrypted");
        };

        assert_eq!(envelope.message_type, MessageType::ItemLive);
        assert_eq!(envelope.session_counter, 12);
        assert_eq!(envelope.ciphertext.algorithm, AeadAlgorithm::Aes256Gcm);
    }

    #[test]
    fn parses_clipboard_item_fixture() {
        let fixture = read_vector(&["test-vectors", "sync", "clipboard-item.valid.json"]);
        let item: ClipboardItem =
            serde_json::from_str(&fixture).expect("clipboard item should deserialize");

        item.validate().expect("clipboard item should validate");
        assert_eq!(item.content_type, ContentType::TextPlain);
        assert_eq!(item.content_length, item.content.len());
    }

    #[test]
    fn rejects_unknown_version_fixture() {
        let fixture = read_vector(&["test-vectors", "errors", "unknown-version.reject.json"]);

        assert_eq!(
            parse_envelope(&fixture).unwrap_err(),
            ProtocolError::UnsupportedVersion(2)
        );
    }

    #[test]
    fn rejects_post_auth_plaintext_fixture() {
        let fixture = read_vector(&["test-vectors", "errors", "post-auth-plaintext.reject.json"]);

        assert_eq!(
            parse_envelope(&fixture).unwrap_err(),
            ProtocolError::PlaintextAfterAuth(MessageType::ItemLive)
        );
    }

    #[test]
    fn rejects_unknown_message_type() {
        let fixture = r#"{
          "version": 1,
          "type": "NOPE",
          "messageId": "018ff6f0-2b1f-7cc5-b5d0-7e82c5f70f01",
          "sessionCounter": 0,
          "payload": {}
        }"#;

        assert_eq!(
            parse_envelope(fixture).unwrap_err(),
            ProtocolError::UnknownMessageType("NOPE".to_owned())
        );
    }

    #[test]
    fn rejects_ciphertext_before_auth() {
        let fixture = r#"{
          "version": 1,
          "type": "CLIENT_HELLO",
          "messageId": "018ff6f0-2b1f-7cc5-b5d0-7e82c5f70f01",
          "sessionCounter": 0,
          "ciphertext": {
            "algorithm": "AES-256-GCM",
            "keyId": "session-v1-client-to-server",
            "nonce": "DDDDDDDDDDDDDDDD",
            "aad": "EEEEEEEEEEEEEEEE",
            "body": "FFFFFFFFFFFFFFFF",
            "tag": "GGGGGGGGGGGGGGGGGGGGGG"
          }
        }"#;

        assert_eq!(
            parse_envelope(fixture).unwrap_err(),
            ProtocolError::CiphertextBeforeAuth(MessageType::ClientHello)
        );
    }
}
