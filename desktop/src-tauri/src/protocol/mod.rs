use std::{collections::HashSet, fmt};

use crate::crypto::{
    aes256_gcm_decrypt, aes256_gcm_encrypt, decode_base64url, encode_base64url, fixed_bytes,
    session_nonce, SessionDirection, AES_256_KEY_BYTES, AES_GCM_NONCE_BYTES, AES_GCM_TAG_BYTES,
};
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sha2::{Digest, Sha256};

pub const PROTOCOL_VERSION: u16 = 1;
pub const MAX_FRAME_BYTES: usize = 1024 * 1024;
pub const MAX_TEXT_BYTES: usize = 256 * 1024;
pub const MAX_BATCH_ITEMS: usize = 100;
pub const MAX_BATCH_PLAINTEXT_BYTES: usize = 512 * 1024;
pub const HANDSHAKE_TIMEOUT_SECONDS: u64 = 8;
pub const HEARTBEAT_INTERVAL_SECONDS: u64 = 20;
pub const IDLE_DISCONNECT_SECONDS: u64 = 60;
pub const SESSION_KEY_ID_CLIENT_TO_SERVER: &str = "session-v1-client-to-server";
pub const SESSION_KEY_ID_SERVER_TO_CLIENT: &str = "session-v1-server-to-client";

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ProtocolError {
    InvalidJson(String),
    UnsupportedVersion(u16),
    UnknownMessageType(String),
    MissingPayload(MessageType),
    MissingCiphertext(MessageType),
    PlaintextAfterAuth(MessageType),
    CiphertextBeforeAuth(MessageType),
    DuplicateMessageId,
    ReplayCounter {
        counter: u64,
        highest_seen: u64,
    },
    InvalidState {
        state: ProtocolSessionState,
        message_type: MessageType,
    },
    InvalidField(&'static str),
    CryptoFailed,
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
            ProtocolError::DuplicateMessageId => write!(formatter, "duplicate message id"),
            ProtocolError::ReplayCounter {
                counter,
                highest_seen,
            } => write!(
                formatter,
                "replayed or old session counter {counter}, highest seen {highest_seen}"
            ),
            ProtocolError::InvalidState {
                state,
                message_type,
            } => {
                write!(
                    formatter,
                    "{message_type} is not valid while session state is {state}"
                )
            }
            ProtocolError::InvalidField(field) => write!(formatter, "invalid field {field}"),
            ProtocolError::CryptoFailed => formatter.write_str("cryptographic operation failed"),
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

impl ProtocolEnvelope {
    pub fn message_type(&self) -> MessageType {
        match self {
            ProtocolEnvelope::PreAuth(envelope) => envelope.message_type,
            ProtocolEnvelope::Encrypted(envelope) => envelope.message_type,
        }
    }

    pub fn message_id(&self) -> &str {
        match self {
            ProtocolEnvelope::PreAuth(envelope) => &envelope.message_id,
            ProtocolEnvelope::Encrypted(envelope) => &envelope.message_id,
        }
    }

    pub fn session_counter(&self) -> u64 {
        match self {
            ProtocolEnvelope::PreAuth(envelope) => envelope.session_counter,
            ProtocolEnvelope::Encrypted(envelope) => envelope.session_counter,
        }
    }
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
pub enum AuthRole {
    Client,
    Server,
}

impl fmt::Display for AuthRole {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            AuthRole::Client => formatter.write_str("client"),
            AuthRole::Server => formatter.write_str("server"),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AuthProofPayload {
    pub role: AuthRole,
    pub signature_algorithm: SignatureAlgorithm,
    pub transcript_hash: String,
    pub signature: String,
}

impl AuthProofPayload {
    pub fn validate(&self) -> Result<(), ProtocolError> {
        validate_base64url(&self.transcript_hash, "transcriptHash")?;
        validate_base64url(&self.signature, "signature")
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum SignatureAlgorithm {
    Ed25519,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AuthTranscriptInput {
    pub role: AuthRole,
    pub space_id: String,
    pub local_device_id: String,
    pub remote_device_id: String,
    pub local_identity_public_key: String,
    pub remote_identity_public_key: String,
    pub local_ephemeral_public_key: String,
    pub remote_ephemeral_public_key: String,
    pub pairing_context: String,
}

impl AuthTranscriptInput {
    pub fn validate(&self) -> Result<(), ProtocolError> {
        validate_uuid(&self.space_id, "spaceId")?;
        validate_uuid(&self.local_device_id, "localDeviceId")?;
        validate_uuid(&self.remote_device_id, "remoteDeviceId")?;
        validate_base64url(&self.local_identity_public_key, "localIdentityPublicKey")?;
        validate_base64url(&self.remote_identity_public_key, "remoteIdentityPublicKey")?;
        validate_base64url(&self.local_ephemeral_public_key, "localEphemeralPublicKey")?;
        validate_base64url(
            &self.remote_ephemeral_public_key,
            "remoteEphemeralPublicKey",
        )?;
        validate_transcript_field(&self.pairing_context, "pairingContext")
    }
}

pub fn canonical_auth_transcript(input: &AuthTranscriptInput) -> Result<String, ProtocolError> {
    input.validate()?;
    Ok(format!(
        "EggClip v1 auth transcript\n\
         role={}\n\
         spaceId={}\n\
         localDeviceId={}\n\
         remoteDeviceId={}\n\
         localIdentityPublicKey={}\n\
         remoteIdentityPublicKey={}\n\
         localEphemeralPublicKey={}\n\
         remoteEphemeralPublicKey={}\n\
         pairingContext={}\n",
        input.role,
        input.space_id,
        input.local_device_id,
        input.remote_device_id,
        input.local_identity_public_key,
        input.remote_identity_public_key,
        input.local_ephemeral_public_key,
        input.remote_ephemeral_public_key,
        input.pairing_context
    ))
}

pub fn auth_transcript_hash_base64url(
    input: &AuthTranscriptInput,
) -> Result<String, ProtocolError> {
    let transcript = canonical_auth_transcript(input)?;
    Ok(URL_SAFE_NO_PAD.encode(Sha256::digest(transcript.as_bytes())))
}

pub fn session_key_id(direction: SessionDirection) -> &'static str {
    match direction {
        SessionDirection::ClientToServer => SESSION_KEY_ID_CLIENT_TO_SERVER,
        SessionDirection::ServerToClient => SESSION_KEY_ID_SERVER_TO_CLIENT,
    }
}

pub fn canonical_encrypted_aad(
    message_type: MessageType,
    message_id: &str,
    session_counter: u64,
    key_id: &str,
) -> Result<String, ProtocolError> {
    if !message_type.is_encrypted_allowed() {
        return Err(ProtocolError::CiphertextBeforeAuth(message_type));
    }
    validate_uuid(message_id, "messageId")?;
    validate_ciphertext_key_id(key_id)?;
    Ok(format!(
        "EggClip v1 ciphertext aad\n\
         version={}\n\
         type={}\n\
         messageId={}\n\
         sessionCounter={}\n\
         algorithm=AES-256-GCM\n\
         keyId={}\n",
        PROTOCOL_VERSION, message_type, message_id, session_counter, key_id
    ))
}

pub fn build_encrypted_envelope(
    message_type: MessageType,
    message_id: String,
    session_counter: u64,
    direction: SessionDirection,
    key: [u8; AES_256_KEY_BYTES],
    payload: &Value,
) -> Result<EncryptedEnvelope, ProtocolError> {
    if !payload.is_object() {
        return Err(ProtocolError::InvalidField("payload"));
    }

    let key_id = session_key_id(direction);
    let aad = canonical_encrypted_aad(message_type, &message_id, session_counter, key_id)?;
    let plaintext =
        serde_json::to_vec(payload).map_err(|_| ProtocolError::InvalidField("payload"))?;
    if plaintext.len() > MAX_BATCH_PLAINTEXT_BYTES {
        return Err(ProtocolError::TextTooLarge {
            actual_bytes: plaintext.len(),
            max_bytes: MAX_BATCH_PLAINTEXT_BYTES,
        });
    }

    let nonce = session_nonce(direction, session_counter);
    let (body, tag) = aes256_gcm_encrypt(key, nonce, aad.as_bytes(), &plaintext)
        .map_err(|_| ProtocolError::CryptoFailed)?;

    Ok(EncryptedEnvelope {
        message_type,
        message_id,
        session_counter,
        ciphertext: CiphertextFrame {
            algorithm: AeadAlgorithm::Aes256Gcm,
            key_id: key_id.to_owned(),
            nonce: encode_base64url(&nonce),
            aad: encode_base64url(aad.as_bytes()),
            body: encode_base64url(&body),
            tag: encode_base64url(&tag),
        },
    })
}

pub fn decrypt_encrypted_payload(
    envelope: &EncryptedEnvelope,
    direction: SessionDirection,
    key: [u8; AES_256_KEY_BYTES],
) -> Result<Value, ProtocolError> {
    validate_ciphertext(&envelope.ciphertext)?;

    let expected_key_id = session_key_id(direction);
    if envelope.ciphertext.key_id != expected_key_id {
        return Err(ProtocolError::CryptoFailed);
    }

    let expected_nonce = session_nonce(direction, envelope.session_counter);
    let nonce = fixed_bytes::<AES_GCM_NONCE_BYTES>(
        &decode_base64url(&envelope.ciphertext.nonce)
            .map_err(|_| ProtocolError::InvalidField("ciphertext.nonce"))?,
        "ciphertext.nonce",
    )
    .map_err(|_| ProtocolError::InvalidField("ciphertext.nonce"))?;
    if nonce != expected_nonce {
        return Err(ProtocolError::CryptoFailed);
    }

    let expected_aad = canonical_encrypted_aad(
        envelope.message_type,
        &envelope.message_id,
        envelope.session_counter,
        &envelope.ciphertext.key_id,
    )?;
    let aad = decode_base64url(&envelope.ciphertext.aad)
        .map_err(|_| ProtocolError::InvalidField("ciphertext.aad"))?;
    if aad != expected_aad.as_bytes() {
        return Err(ProtocolError::CryptoFailed);
    }

    let body = decode_base64url(&envelope.ciphertext.body)
        .map_err(|_| ProtocolError::InvalidField("ciphertext.body"))?;
    let tag = fixed_bytes::<AES_GCM_TAG_BYTES>(
        &decode_base64url(&envelope.ciphertext.tag)
            .map_err(|_| ProtocolError::InvalidField("ciphertext.tag"))?,
        "ciphertext.tag",
    )
    .map_err(|_| ProtocolError::InvalidField("ciphertext.tag"))?;

    let plaintext = aes256_gcm_decrypt(key, nonce, expected_aad.as_bytes(), &body, tag)
        .map_err(|_| ProtocolError::CryptoFailed)?;
    let payload: Value =
        serde_json::from_slice(&plaintext).map_err(|_| ProtocolError::CryptoFailed)?;
    if !payload.is_object() {
        return Err(ProtocolError::CryptoFailed);
    }
    Ok(payload)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ProtocolSessionState {
    Disconnected,
    Connecting,
    Handshaking,
    Authenticated,
    Syncing,
    Ready,
    Failed,
}

impl fmt::Display for ProtocolSessionState {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        let value = serde_json::to_string(self).map_err(|_| fmt::Error)?;
        formatter.write_str(value.trim_matches('"'))
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProtocolSessionGate {
    state: ProtocolSessionState,
}

impl Default for ProtocolSessionGate {
    fn default() -> Self {
        Self {
            state: ProtocolSessionState::Disconnected,
        }
    }
}

impl ProtocolSessionGate {
    pub fn state(&self) -> ProtocolSessionState {
        self.state
    }

    pub fn connect(&mut self) -> ProtocolSessionState {
        self.state = ProtocolSessionState::Connecting;
        self.state
    }

    pub fn start_handshake(&mut self) -> ProtocolSessionState {
        self.state = ProtocolSessionState::Handshaking;
        self.state
    }

    pub fn mark_ready(&mut self) -> Result<ProtocolSessionState, ProtocolError> {
        if matches!(
            self.state,
            ProtocolSessionState::Authenticated
                | ProtocolSessionState::Syncing
                | ProtocolSessionState::Ready
        ) {
            self.state = ProtocolSessionState::Ready;
            Ok(self.state)
        } else {
            Err(ProtocolError::InvalidState {
                state: self.state,
                message_type: MessageType::SyncHeads,
            })
        }
    }

    pub fn fail(&mut self) -> ProtocolSessionState {
        self.state = ProtocolSessionState::Failed;
        self.state
    }

    pub fn accept_envelope(
        &mut self,
        envelope: &ProtocolEnvelope,
    ) -> Result<ProtocolSessionState, ProtocolError> {
        match envelope {
            ProtocolEnvelope::PreAuth(envelope) => self.accept_pre_auth(envelope.message_type),
            ProtocolEnvelope::Encrypted(envelope) => self.accept_encrypted(envelope.message_type),
        }
    }

    fn accept_pre_auth(
        &mut self,
        message_type: MessageType,
    ) -> Result<ProtocolSessionState, ProtocolError> {
        match self.state {
            ProtocolSessionState::Connecting | ProtocolSessionState::Handshaking => {
                self.accept_handshake_message(message_type)
            }
            ProtocolSessionState::Authenticated
            | ProtocolSessionState::Syncing
            | ProtocolSessionState::Ready => {
                if matches!(message_type, MessageType::AuthError | MessageType::Error) {
                    self.state = ProtocolSessionState::Failed;
                    Ok(self.state)
                } else {
                    Err(ProtocolError::PlaintextAfterAuth(message_type))
                }
            }
            ProtocolSessionState::Disconnected | ProtocolSessionState::Failed => {
                Err(ProtocolError::InvalidState {
                    state: self.state,
                    message_type,
                })
            }
        }
    }

    fn accept_handshake_message(
        &mut self,
        message_type: MessageType,
    ) -> Result<ProtocolSessionState, ProtocolError> {
        match message_type {
            MessageType::ClientHello | MessageType::ServerHello | MessageType::AuthProof => {
                self.state = ProtocolSessionState::Handshaking;
                Ok(self.state)
            }
            MessageType::AuthOk => {
                self.state = ProtocolSessionState::Authenticated;
                Ok(self.state)
            }
            MessageType::AuthError | MessageType::Error => {
                self.state = ProtocolSessionState::Failed;
                Ok(self.state)
            }
            _ => Err(ProtocolError::PlaintextAfterAuth(message_type)),
        }
    }

    fn accept_encrypted(
        &mut self,
        message_type: MessageType,
    ) -> Result<ProtocolSessionState, ProtocolError> {
        match self.state {
            ProtocolSessionState::Authenticated
            | ProtocolSessionState::Syncing
            | ProtocolSessionState::Ready => {
                self.state = match message_type {
                    MessageType::SyncHeads | MessageType::RequestRange | MessageType::ItemBatch => {
                        ProtocolSessionState::Syncing
                    }
                    MessageType::DeviceRevoked | MessageType::SpaceKeyRotated => {
                        ProtocolSessionState::Authenticated
                    }
                    _ => ProtocolSessionState::Ready,
                };
                Ok(self.state)
            }
            ProtocolSessionState::Connecting | ProtocolSessionState::Handshaking => {
                Err(ProtocolError::CiphertextBeforeAuth(message_type))
            }
            ProtocolSessionState::Disconnected | ProtocolSessionState::Failed => {
                Err(ProtocolError::InvalidState {
                    state: self.state,
                    message_type,
                })
            }
        }
    }
}

#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct ProtocolReplayGuard {
    seen_message_ids: HashSet<String>,
    highest_counter: Option<u64>,
}

impl ProtocolReplayGuard {
    pub fn accept_envelope(&mut self, envelope: &ProtocolEnvelope) -> Result<(), ProtocolError> {
        let message_id = envelope.message_id();
        if self.seen_message_ids.contains(message_id) {
            return Err(ProtocolError::DuplicateMessageId);
        }

        let counter = envelope.session_counter();
        if let Some(highest_seen) = self.highest_counter {
            if counter <= highest_seen {
                return Err(ProtocolError::ReplayCounter {
                    counter,
                    highest_seen,
                });
            }
        }

        self.seen_message_ids.insert(message_id.to_owned());
        self.highest_counter = Some(counter);
        Ok(())
    }
}

#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct ProtocolInboundSession {
    gate: ProtocolSessionGate,
    replay_guard: ProtocolReplayGuard,
}

impl ProtocolInboundSession {
    pub fn state(&self) -> ProtocolSessionState {
        self.gate.state()
    }

    pub fn connect(&mut self) -> ProtocolSessionState {
        self.gate.connect()
    }

    pub fn start_handshake(&mut self) -> ProtocolSessionState {
        self.gate.start_handshake()
    }

    pub fn accept_envelope(
        &mut self,
        envelope: &ProtocolEnvelope,
    ) -> Result<ProtocolSessionState, ProtocolError> {
        self.replay_guard.accept_envelope(envelope)?;
        self.gate.accept_envelope(envelope)
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
    validate_ciphertext_key_id(&ciphertext.key_id)?;
    validate_base64url(&ciphertext.nonce, "ciphertext.nonce")?;
    validate_base64url(&ciphertext.aad, "ciphertext.aad")?;
    validate_base64url(&ciphertext.body, "ciphertext.body")?;
    validate_base64url(&ciphertext.tag, "ciphertext.tag")
}

fn validate_ciphertext_key_id(key_id: &str) -> Result<(), ProtocolError> {
    if key_id.is_empty() || key_id.len() > 128 || key_id.contains('\n') || key_id.contains('\r') {
        return Err(ProtocolError::InvalidField("ciphertext.keyId"));
    }
    Ok(())
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

fn validate_transcript_field(value: &str, field: &'static str) -> Result<(), ProtocolError> {
    if value.is_empty() || value.contains('\n') || value.contains('\r') {
        Err(ProtocolError::InvalidField(field))
    } else {
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::crypto::verify_ed25519_signature;
    use serde::Deserialize;
    use std::{fs, path::PathBuf};

    #[derive(Debug, Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct AuthProofTranscriptVector {
        role: AuthRole,
        space_id: String,
        local_device_id: String,
        remote_device_id: String,
        local_identity_public_key: String,
        remote_identity_public_key: String,
        local_ephemeral_public_key: String,
        remote_ephemeral_public_key: String,
        pairing_context: String,
        canonical_transcript: String,
        transcript_hash: String,
        signature: String,
    }

    #[derive(Debug, Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct SessionKeysVector {
        client_to_server_key: String,
        server_to_client_key: String,
        counter: u64,
        client_to_server_nonce: String,
        server_to_client_nonce: String,
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

    fn read_vector(parts: &[&str]) -> String {
        fs::read_to_string(vector_path(parts)).expect("test vector should be readable")
    }

    fn read_json_vector<T: for<'de> Deserialize<'de>>(parts: &[&str]) -> T {
        serde_json::from_str(&read_vector(parts)).expect("test vector should deserialize")
    }

    fn decoded_fixed<const N: usize>(value: &str, field: &'static str) -> [u8; N] {
        fixed_bytes(
            &decode_base64url(value).expect("base64url should decode"),
            field,
        )
        .expect("fixed value should have expected length")
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
    fn parses_auth_proof_fixture() {
        let fixture = read_vector(&["test-vectors", "handshake", "auth-proof.valid.json"]);
        let ProtocolEnvelope::PreAuth(envelope) =
            parse_envelope(&fixture).expect("auth proof should parse")
        else {
            panic!("auth proof should be pre-auth");
        };

        assert_eq!(envelope.message_type, MessageType::AuthProof);
        let payload: AuthProofPayload =
            serde_json::from_value(envelope.payload).expect("auth proof should deserialize");
        payload.validate().expect("auth proof should validate");
        assert_eq!(payload.role, AuthRole::Client);
        assert_eq!(payload.signature_algorithm, SignatureAlgorithm::Ed25519);
    }

    #[test]
    fn session_gate_accepts_handshake_then_encrypted_business() {
        let client_hello = parse_envelope(&read_vector(&[
            "test-vectors",
            "handshake",
            "client-hello.valid.json",
        ]))
        .expect("client hello should parse");
        let auth_proof = parse_envelope(&read_vector(&[
            "test-vectors",
            "handshake",
            "auth-proof.valid.json",
        ]))
        .expect("auth proof should parse");
        let auth_ok = parse_envelope(
            r#"{
              "version": 1,
              "type": "AUTH_OK",
              "messageId": "018ff6f1-25f0-7c09-a4cf-3d683ebfae33",
              "sessionCounter": 3,
              "payload": {}
            }"#,
        )
        .expect("auth ok should parse");
        let item_live = parse_envelope(&read_vector(&[
            "test-vectors",
            "sync",
            "encrypted-item-live-envelope.valid.json",
        ]))
        .expect("item live should parse");

        let mut gate = ProtocolSessionGate::default();
        assert_eq!(gate.connect(), ProtocolSessionState::Connecting);
        assert_eq!(
            gate.accept_envelope(&client_hello).expect("hello accepted"),
            ProtocolSessionState::Handshaking
        );
        assert_eq!(
            gate.accept_envelope(&auth_proof)
                .expect("auth proof accepted"),
            ProtocolSessionState::Handshaking
        );
        assert_eq!(
            gate.accept_envelope(&auth_ok).expect("auth ok accepted"),
            ProtocolSessionState::Authenticated
        );
        assert_eq!(
            gate.accept_envelope(&item_live)
                .expect("item live accepted"),
            ProtocolSessionState::Ready
        );
    }

    #[test]
    fn session_gate_rejects_business_before_auth() {
        let item_live = parse_envelope(&read_vector(&[
            "test-vectors",
            "sync",
            "encrypted-item-live-envelope.valid.json",
        ]))
        .expect("item live should parse");
        let mut gate = ProtocolSessionGate::default();
        gate.start_handshake();

        assert_eq!(
            gate.accept_envelope(&item_live).unwrap_err(),
            ProtocolError::CiphertextBeforeAuth(MessageType::ItemLive)
        );
    }

    #[test]
    fn session_gate_rejects_plaintext_after_auth() {
        let client_hello = parse_envelope(&read_vector(&[
            "test-vectors",
            "handshake",
            "client-hello.valid.json",
        ]))
        .expect("client hello should parse");
        let mut gate = ProtocolSessionGate {
            state: ProtocolSessionState::Authenticated,
        };

        assert_eq!(
            gate.accept_envelope(&client_hello).unwrap_err(),
            ProtocolError::PlaintextAfterAuth(MessageType::ClientHello)
        );
    }

    #[test]
    fn replay_guard_rejects_duplicate_message_ids() {
        let client_hello = parse_envelope(&read_vector(&[
            "test-vectors",
            "handshake",
            "client-hello.valid.json",
        ]))
        .expect("client hello should parse");
        let mut guard = ProtocolReplayGuard::default();

        guard
            .accept_envelope(&client_hello)
            .expect("first message should pass");
        assert_eq!(
            guard.accept_envelope(&client_hello).unwrap_err(),
            ProtocolError::DuplicateMessageId
        );
    }

    #[test]
    fn replay_guard_rejects_old_or_repeated_counters() {
        let auth_proof = parse_envelope(&read_vector(&[
            "test-vectors",
            "handshake",
            "auth-proof.valid.json",
        ]))
        .expect("auth proof should parse");
        let auth_ok_old_counter = parse_envelope(
            r#"{
              "version": 1,
              "type": "AUTH_OK",
              "messageId": "018ff6f1-25f0-7c09-a4cf-3d683ebfae33",
              "sessionCounter": 1,
              "payload": {}
            }"#,
        )
        .expect("auth ok should parse");
        let mut guard = ProtocolReplayGuard::default();

        guard
            .accept_envelope(&auth_proof)
            .expect("first message should pass");
        assert_eq!(
            guard.accept_envelope(&auth_ok_old_counter).unwrap_err(),
            ProtocolError::ReplayCounter {
                counter: 1,
                highest_seen: 2
            }
        );
    }

    #[test]
    fn inbound_session_applies_replay_guard_before_state_gate() {
        let client_hello = parse_envelope(&read_vector(&[
            "test-vectors",
            "handshake",
            "client-hello.valid.json",
        ]))
        .expect("client hello should parse");
        let mut session = ProtocolInboundSession::default();
        session.connect();

        assert_eq!(
            session
                .accept_envelope(&client_hello)
                .expect("first hello should pass"),
            ProtocolSessionState::Handshaking
        );
        assert_eq!(
            session.accept_envelope(&client_hello).unwrap_err(),
            ProtocolError::DuplicateMessageId
        );
    }

    #[test]
    fn builds_and_verifies_auth_proof_transcript_vector() {
        let vector: AuthProofTranscriptVector =
            read_json_vector(&["test-vectors", "crypto", "auth-proof-transcript.valid.json"]);
        let input = AuthTranscriptInput {
            role: vector.role,
            space_id: vector.space_id,
            local_device_id: vector.local_device_id,
            remote_device_id: vector.remote_device_id,
            local_identity_public_key: vector.local_identity_public_key,
            remote_identity_public_key: vector.remote_identity_public_key,
            local_ephemeral_public_key: vector.local_ephemeral_public_key,
            remote_ephemeral_public_key: vector.remote_ephemeral_public_key,
            pairing_context: vector.pairing_context,
        };

        assert_eq!(
            canonical_auth_transcript(&input).expect("transcript should build"),
            vector.canonical_transcript
        );
        assert_eq!(
            auth_transcript_hash_base64url(&input).expect("hash should build"),
            vector.transcript_hash
        );
        let public_key = fixed_bytes::<32>(
            &decode_base64url(&input.local_identity_public_key).expect("public key should decode"),
            "publicKey",
        )
        .expect("public key should be fixed");
        let signature = fixed_bytes::<64>(
            &decode_base64url(&vector.signature).expect("signature should decode"),
            "signature",
        )
        .expect("signature should be fixed");
        verify_ed25519_signature(
            public_key,
            vector.canonical_transcript.as_bytes(),
            signature,
        )
        .expect("auth proof signature should verify");
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
    fn builds_and_decrypts_encrypted_business_payload() {
        let vector: SessionKeysVector =
            read_json_vector(&["test-vectors", "crypto", "session-keys.valid.json"]);
        let key = decoded_fixed::<32>(&vector.client_to_server_key, "clientToServerKey");
        let message_id = "018ff6f3-0d8c-7d1e-a38a-f308c64de79f".to_owned();
        let payload = serde_json::json!({
            "content": "EggClip encrypted payload",
            "contentType": "text/plain"
        });

        let envelope = build_encrypted_envelope(
            MessageType::ItemLive,
            message_id.clone(),
            vector.counter,
            SessionDirection::ClientToServer,
            key,
            &payload,
        )
        .expect("encrypted envelope should build");

        assert_eq!(envelope.message_type, MessageType::ItemLive);
        assert_eq!(envelope.ciphertext.key_id, SESSION_KEY_ID_CLIENT_TO_SERVER);
        assert_eq!(envelope.ciphertext.nonce, vector.client_to_server_nonce);
        assert_ne!(envelope.ciphertext.nonce, vector.server_to_client_nonce);
        let expected_aad = canonical_encrypted_aad(
            MessageType::ItemLive,
            &message_id,
            vector.counter,
            SESSION_KEY_ID_CLIENT_TO_SERVER,
        )
        .expect("aad should build");
        assert_eq!(
            decode_base64url(&envelope.ciphertext.aad).expect("aad should decode"),
            expected_aad.as_bytes()
        );

        let decrypted = decrypt_encrypted_payload(&envelope, SessionDirection::ClientToServer, key)
            .expect("payload should decrypt");
        assert_eq!(decrypted, payload);
    }

    #[test]
    fn encrypted_payload_rejects_wrong_direction_and_tampered_tag() {
        let vector: SessionKeysVector =
            read_json_vector(&["test-vectors", "crypto", "session-keys.valid.json"]);
        let client_key = decoded_fixed::<32>(&vector.client_to_server_key, "clientToServerKey");
        let server_key = decoded_fixed::<32>(&vector.server_to_client_key, "serverToClientKey");
        let payload = serde_json::json!({"content": "EggClip encrypted payload"});
        let envelope = build_encrypted_envelope(
            MessageType::ItemLive,
            "018ff6f3-0d8c-7d1e-a38a-f308c64de79f".to_owned(),
            vector.counter,
            SessionDirection::ClientToServer,
            client_key,
            &payload,
        )
        .expect("encrypted envelope should build");

        assert_eq!(
            decrypt_encrypted_payload(&envelope, SessionDirection::ServerToClient, server_key)
                .unwrap_err(),
            ProtocolError::CryptoFailed
        );

        let mut tampered = envelope.clone();
        tampered.ciphertext.tag = encode_base64url(&[0u8; AES_GCM_TAG_BYTES]);
        assert_eq!(
            decrypt_encrypted_payload(&tampered, SessionDirection::ClientToServer, client_key)
                .unwrap_err(),
            ProtocolError::CryptoFailed
        );
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
