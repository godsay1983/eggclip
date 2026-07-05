use std::{fmt, path::Path};

#[cfg(test)]
use std::collections::HashMap;

use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
use qrcode::{render::svg, EcLevel, QrCode};
use rusqlite::Connection;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use uuid::Uuid;

use crate::{
    clipboard,
    crypto::{
        decode_base64url, derive_session_keys, encode_base64url, fixed_bytes,
        verify_ed25519_signature, SessionKeys, X25519Secret, ED25519_PUBLIC_KEY_BYTES,
        ED25519_SIGNATURE_BYTES, X25519_PUBLIC_KEY_BYTES, X25519_SHARED_SECRET_BYTES,
    },
    identity::{ensure_local_device_identity, IdentityError},
    protocol::{
        auth_transcript_hash_base64url, canonical_auth_transcript, parse_envelope,
        serialize_pre_auth_envelope, AuthProofPayload, AuthRole, AuthTranscriptInput, Capability,
        HelloPayload, MessageType, PreAuthEnvelope, ProtocolEnvelope, SignatureAlgorithm,
    },
    secret_store::{SecretBytesStore, SecretStoreError},
    settings::{database_path, now_ms},
    storage::{
        open_database,
        repositories::{
            PairingInvitationRecord, PairingInvitationRepository, PairingInvitationState,
            SpaceRecord, SpaceRepository,
        },
    },
    sync::{Space, SpaceState},
};

pub const SPACE_KEY_BYTES: usize = 32;
pub const PAIRING_SECRET_BYTES: usize = 32;
pub const INITIAL_SPACE_KEY_VERSION: u32 = 1;
pub const PAIRING_INVITATION_TTL_MS: u64 = 5 * 60 * 1000;
pub const DEFAULT_SPACE_DISPLAY_NAME: &str = "默认空间";
const PAIRING_INVITATION_EXPIRY_SWEEP_SECONDS: u64 = 60;
const PAIRING_INVITATION_QR_MIN_DIMENSIONS: u32 = 224;

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncSpaceSummary {
    pub space_id: String,
    pub display_name: String,
    pub key_version: u32,
    pub space_key_ref: String,
    pub created_at_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PairingInvitationSummary {
    pub invitation_id: String,
    pub space_id: String,
    pub space_display_name: String,
    pub invitation: String,
    pub qr_svg: String,
    pub expires_at_ms: u64,
    pub expires_in_seconds: u64,
    pub issuer_device_name: String,
    pub issuer_device_id: String,
    pub issuer_short_fingerprint: String,
    pub confirmation_code: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PairingServerHelloDraft {
    pub invitation_id: String,
    pub space_id: String,
    pub peer_device_id: String,
    pub peer_identity_public_key: String,
    pub peer_ephemeral_public_key: String,
    pub server_device_id: String,
    pub server_identity_public_key: String,
    pub server_ephemeral_public_key: String,
    pub pairing_context: String,
    pub server_hello_frame: String,
}

#[derive(Clone)]
pub struct PairingServerAuthProofInput {
    pub invitation_id: String,
    pub space_id: String,
    pub peer_device_id: String,
    pub peer_identity_public_key: String,
    pub peer_ephemeral_public_key: String,
    pub server_device_id: String,
    pub server_identity_public_key: String,
    pub server_ephemeral_public_key: String,
    pub pairing_context: String,
    pub server_ephemeral_secret: X25519Secret,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PairingServerAuthProofAccepted {
    pub invitation_id: String,
    pub space_id: String,
    pub peer_device_id: String,
    pub peer_identity_public_key: String,
    pub transcript_hash: String,
    pub transcript_salt: [u8; 32],
    pub shared_secret: [u8; X25519_SHARED_SECRET_BYTES],
    pub session_keys: SessionKeys,
    pub auth_ok_frame: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct PairingInvitationPayload {
    app: String,
    version: u16,
    kind: String,
    invitation_id: String,
    space_id: String,
    space_key_version: u32,
    issuer_device_name: String,
    issuer_device_id: String,
    issuer_identity_public_key: String,
    pairing_secret: String,
    expires_at_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PairingError {
    Database(String),
    KeyStore(String),
    RandomUnavailable,
    InvalidDisplayName,
    InvalidSpaceId,
    MissingSpace,
    MissingSpaceKeyRef,
    MissingSpaceKey,
    Identity(String),
    InvalidInvitation,
    InvitationMissing,
    InvitationExpired,
    InvitationConsumed,
    InvalidInvitationSecret,
    InvalidClientHello,
    InvalidAuthProof,
    AuthProofSignatureFailed,
    SessionKeyDerivationFailed,
    QrCode(String),
    Serialize(String),
}

impl fmt::Display for PairingError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            PairingError::Database(message) => write!(formatter, "database error: {message}"),
            PairingError::KeyStore(message) => write!(formatter, "key store error: {message}"),
            PairingError::RandomUnavailable => formatter.write_str("secure random unavailable"),
            PairingError::InvalidDisplayName => formatter.write_str("invalid space display name"),
            PairingError::InvalidSpaceId => formatter.write_str("invalid space id"),
            PairingError::MissingSpace => formatter.write_str("sync space missing"),
            PairingError::MissingSpaceKeyRef => formatter.write_str("space key reference missing"),
            PairingError::MissingSpaceKey => formatter.write_str("space key missing"),
            PairingError::Identity(message) => write!(formatter, "identity error: {message}"),
            PairingError::InvalidInvitation => formatter.write_str("invalid pairing invitation"),
            PairingError::InvitationMissing => formatter.write_str("pairing invitation missing"),
            PairingError::InvitationExpired => formatter.write_str("pairing invitation expired"),
            PairingError::InvitationConsumed => formatter.write_str("pairing invitation consumed"),
            PairingError::InvalidInvitationSecret => {
                formatter.write_str("invalid pairing invitation secret")
            }
            PairingError::InvalidClientHello => formatter.write_str("invalid client hello"),
            PairingError::InvalidAuthProof => formatter.write_str("invalid auth proof"),
            PairingError::AuthProofSignatureFailed => {
                formatter.write_str("auth proof signature verification failed")
            }
            PairingError::SessionKeyDerivationFailed => {
                formatter.write_str("session key derivation failed")
            }
            PairingError::QrCode(message) => write!(formatter, "qr code error: {message}"),
            PairingError::Serialize(message) => write!(formatter, "serialize error: {message}"),
        }
    }
}

impl std::error::Error for PairingError {}

#[tauri::command]
pub fn create_local_sync_space(
    app: tauri::AppHandle,
    display_name: String,
) -> Result<SyncSpaceSummary, String> {
    let path = database_path(&app)?;
    #[cfg(windows)]
    let mut store = crate::secret_store::WindowsCredentialSecretStore;
    #[cfg(not(windows))]
    let mut store = crate::secret_store::UnavailableSecretStore;

    create_sync_space_at_path(&path, &mut store, &display_name, now_ms()?)
        .map_err(|error| format!("无法创建同步空间：{error}"))
}

#[tauri::command]
pub fn list_local_sync_spaces(app: tauri::AppHandle) -> Result<Vec<SyncSpaceSummary>, String> {
    let path = database_path(&app)?;
    list_sync_spaces_at_path(&path).map_err(|error| format!("无法读取同步空间：{error}"))
}

#[tauri::command]
pub fn ensure_default_sync_space(app: tauri::AppHandle) -> Result<SyncSpaceSummary, String> {
    let path = database_path(&app)?;
    #[cfg(windows)]
    let mut store = crate::secret_store::WindowsCredentialSecretStore;
    #[cfg(not(windows))]
    let mut store = crate::secret_store::UnavailableSecretStore;

    ensure_default_sync_space_at_path(&path, &mut store, now_ms()?)
        .map_err(|error| format!("无法初始化默认同步空间：{error}"))
}

#[tauri::command]
pub fn create_pairing_invitation(
    app: tauri::AppHandle,
    space_id: String,
) -> Result<PairingInvitationSummary, String> {
    let path = database_path(&app)?;
    #[cfg(windows)]
    let mut store = crate::secret_store::WindowsCredentialSecretStore;
    #[cfg(not(windows))]
    let mut store = crate::secret_store::UnavailableSecretStore;

    create_pairing_invitation_at_path(&path, &mut store, &space_id, now_ms()?)
        .map_err(|error| format!("无法生成配对邀请：{error}"))
}

#[tauri::command]
pub fn copy_pairing_invitation(app: tauri::AppHandle, invitation: String) -> Result<(), String> {
    validate_pairing_invitation_uri(&invitation)
        .map_err(|error| format!("无法复制配对邀请：{error}"))?;
    clipboard::write_suppressed_clipboard_text(&app, invitation)
        .map_err(|error| format!("无法复制配对邀请：{error}"))
}

pub fn start_pairing_invitation_expiry_task(app: tauri::AppHandle) {
    tauri::async_runtime::spawn(async move {
        let mut interval = tokio::time::interval(std::time::Duration::from_secs(
            PAIRING_INVITATION_EXPIRY_SWEEP_SECONDS,
        ));
        loop {
            interval.tick().await;
            let Ok(timestamp_ms) = now_ms() else {
                continue;
            };
            let Ok(path) = database_path(&app) else {
                continue;
            };
            let _ = expire_pairing_invitations_at_path(&path, timestamp_ms);
        }
    });
}

pub fn create_sync_space_at_path<S: SecretBytesStore>(
    path: &Path,
    secret_store: &mut S,
    display_name: &str,
    now_ms: u64,
) -> Result<SyncSpaceSummary, PairingError> {
    let mut connection =
        open_database(path).map_err(|error| PairingError::Database(error.to_string()))?;
    create_sync_space(&mut connection, secret_store, display_name, now_ms)
}

pub fn create_pairing_invitation_at_path<S: SecretBytesStore>(
    path: &Path,
    secret_store: &mut S,
    space_id: &str,
    now_ms: u64,
) -> Result<PairingInvitationSummary, PairingError> {
    let mut connection =
        open_database(path).map_err(|error| PairingError::Database(error.to_string()))?;
    create_pairing_invitation_for_space(&mut connection, secret_store, space_id, now_ms)
}

pub fn list_sync_spaces_at_path(path: &Path) -> Result<Vec<SyncSpaceSummary>, PairingError> {
    let connection =
        open_database(path).map_err(|error| PairingError::Database(error.to_string()))?;
    list_sync_spaces(&connection)
}

pub fn expire_pairing_invitations_at_path(path: &Path, now_ms: u64) -> Result<usize, PairingError> {
    let connection =
        open_database(path).map_err(|error| PairingError::Database(error.to_string()))?;
    expire_pairing_invitations(&connection, now_ms)
}

pub fn ensure_default_sync_space_at_path<S: SecretBytesStore>(
    path: &Path,
    secret_store: &mut S,
    now_ms: u64,
) -> Result<SyncSpaceSummary, PairingError> {
    let mut connection =
        open_database(path).map_err(|error| PairingError::Database(error.to_string()))?;
    ensure_default_sync_space_in_database(&mut connection, secret_store, now_ms)
}

pub fn ensure_default_sync_space_in_database<S: SecretBytesStore>(
    connection: &mut Connection,
    secret_store: &mut S,
    now_ms: u64,
) -> Result<SyncSpaceSummary, PairingError> {
    let existing = list_sync_spaces(connection)?;
    if let Some(space) = existing.into_iter().next() {
        return Ok(space);
    }
    create_sync_space(connection, secret_store, DEFAULT_SPACE_DISPLAY_NAME, now_ms)
}

pub fn create_sync_space<S: SecretBytesStore>(
    connection: &mut Connection,
    secret_store: &mut S,
    display_name: &str,
    now_ms: u64,
) -> Result<SyncSpaceSummary, PairingError> {
    let display_name = normalize_space_display_name(display_name)?;
    let space_id = Uuid::now_v7();
    let key_version = INITIAL_SPACE_KEY_VERSION;
    let mut space_key = random_space_key()?;
    let space_key_ref = space_key_ref(space_id, key_version);

    secret_store
        .save_secret(&space_key_ref, &space_key)
        .map_err(pairing_secret_store_error)?;
    space_key.fill(0);

    let record = SpaceRecord {
        space: Space {
            space_id,
            display_name: display_name.clone(),
            key_version,
            state: SpaceState::Active,
            created_at: now_ms,
        },
        encrypted_space_key_ref: Some(space_key_ref.clone()),
        updated_at: now_ms,
    };
    SpaceRepository::new(connection)
        .upsert(&record)
        .map_err(|error| PairingError::Database(error.to_string()))?;

    Ok(SyncSpaceSummary {
        space_id: space_id.to_string(),
        display_name,
        key_version,
        space_key_ref,
        created_at_ms: now_ms,
    })
}

pub fn load_space_key<S: SecretBytesStore>(
    connection: &Connection,
    secret_store: &S,
    space_id: Uuid,
) -> Result<[u8; SPACE_KEY_BYTES], PairingError> {
    let space = SpaceRepository::new(connection)
        .get(space_id)
        .map_err(|error| PairingError::Database(error.to_string()))?
        .ok_or(PairingError::MissingSpaceKeyRef)?;
    let space_key_ref = space
        .encrypted_space_key_ref
        .ok_or(PairingError::MissingSpaceKeyRef)?;
    let Some(secret) = secret_store
        .load_secret(&space_key_ref)
        .map_err(pairing_secret_store_error)?
    else {
        return Err(PairingError::MissingSpaceKey);
    };
    if secret.len() != SPACE_KEY_BYTES {
        return Err(PairingError::KeyStore(
            SecretStoreError::InvalidLength {
                actual: secret.len(),
                expected: SPACE_KEY_BYTES,
            }
            .to_string(),
        ));
    }
    let mut key = [0u8; SPACE_KEY_BYTES];
    key.copy_from_slice(&secret);
    Ok(key)
}

pub fn list_sync_spaces(connection: &Connection) -> Result<Vec<SyncSpaceSummary>, PairingError> {
    let records = SpaceRepository::new(connection)
        .list()
        .map_err(|error| PairingError::Database(error.to_string()))?;
    Ok(records
        .into_iter()
        .map(|record| SyncSpaceSummary {
            space_id: record.space.space_id.to_string(),
            display_name: record.space.display_name,
            key_version: record.space.key_version,
            space_key_ref: record.encrypted_space_key_ref.unwrap_or_default(),
            created_at_ms: record.space.created_at,
        })
        .collect())
}

pub fn expire_pairing_invitations(
    connection: &Connection,
    now_ms: u64,
) -> Result<usize, PairingError> {
    PairingInvitationRepository::new(connection)
        .expire_before(now_ms)
        .map_err(|error| PairingError::Database(error.to_string()))
}

pub fn create_pairing_invitation_for_space<S: SecretBytesStore>(
    connection: &mut Connection,
    secret_store: &mut S,
    space_id: &str,
    now_ms: u64,
) -> Result<PairingInvitationSummary, PairingError> {
    let space_id = Uuid::parse_str(space_id).map_err(|_| PairingError::InvalidSpaceId)?;
    let space = SpaceRepository::new(connection)
        .get(space_id)
        .map_err(|error| PairingError::Database(error.to_string()))?
        .ok_or(PairingError::MissingSpace)?;
    if space.encrypted_space_key_ref.is_none() {
        return Err(PairingError::MissingSpaceKeyRef);
    }
    PairingInvitationRepository::new(connection)
        .expire_before(now_ms)
        .map_err(|error| PairingError::Database(error.to_string()))?;
    let identity = ensure_local_device_identity(connection, secret_store, now_ms)
        .map_err(pairing_identity_error)?;
    let issuer_device_id = Uuid::parse_str(&identity.device_id)
        .map_err(|_| PairingError::Identity("local device id is not a UUID".to_string()))?;
    let invitation_id = Uuid::now_v7();
    let mut pairing_secret = random_pairing_secret()?;
    let pairing_secret_encoded = encode_base64url(&pairing_secret);
    let secret_verifier = pairing_secret_verifier(invitation_id, &pairing_secret);
    let expires_at_ms = now_ms.saturating_add(PAIRING_INVITATION_TTL_MS);
    let issuer_device_name = local_device_display_name();
    let payload = PairingInvitationPayload {
        app: "eggclip".to_string(),
        version: 1,
        kind: "pairingInvitation".to_string(),
        invitation_id: invitation_id.to_string(),
        space_id: space.space.space_id.to_string(),
        space_key_version: space.space.key_version,
        issuer_device_name: issuer_device_name.clone(),
        issuer_device_id: identity.device_id.clone(),
        issuer_identity_public_key: identity.identity_public_key.clone(),
        pairing_secret: pairing_secret_encoded,
        expires_at_ms,
    };
    let payload_json =
        serde_json::to_vec(&payload).map_err(|error| PairingError::Serialize(error.to_string()))?;
    let invitation = format!(
        "eggclip://pair?p={}",
        URL_SAFE_NO_PAD.encode(payload_json.as_slice())
    );
    let qr_svg = pairing_invitation_qr_svg(&invitation)?;
    let confirmation_code = confirmation_code(&payload_json);
    pairing_secret.fill(0);
    PairingInvitationRepository::new(connection)
        .insert(&PairingInvitationRecord {
            invitation_id,
            space_id: space.space.space_id,
            issuer_device_id,
            secret_verifier,
            state: PairingInvitationState::Active,
            created_at: now_ms,
            expires_at: expires_at_ms,
            consumed_at: None,
            consumed_by_device_id: None,
        })
        .map_err(|error| PairingError::Database(error.to_string()))?;

    Ok(PairingInvitationSummary {
        invitation_id: invitation_id.to_string(),
        space_id: space.space.space_id.to_string(),
        space_display_name: space.space.display_name,
        invitation,
        qr_svg,
        expires_at_ms,
        expires_in_seconds: PAIRING_INVITATION_TTL_MS / 1000,
        issuer_device_name,
        issuer_device_id: identity.device_id,
        issuer_short_fingerprint: identity.identity_public_key.chars().take(8).collect(),
        confirmation_code,
    })
}

pub fn consume_pairing_invitation(
    connection: &Connection,
    invitation_id: &str,
    pairing_secret: &str,
    consumer_device_id: &str,
    now_ms: u64,
) -> Result<(), PairingError> {
    let invitation_id =
        Uuid::parse_str(invitation_id).map_err(|_| PairingError::InvalidInvitation)?;
    let consumer_device_id =
        Uuid::parse_str(consumer_device_id).map_err(|_| PairingError::InvalidInvitation)?;
    let mut pairing_secret =
        decode_base64url(pairing_secret).map_err(|_| PairingError::InvalidInvitationSecret)?;
    if pairing_secret.len() != PAIRING_SECRET_BYTES {
        return Err(PairingError::InvalidInvitationSecret);
    }
    let mut secret = [0u8; PAIRING_SECRET_BYTES];
    secret.copy_from_slice(&pairing_secret);
    pairing_secret.fill(0);
    let verifier = pairing_secret_verifier(invitation_id, &secret);
    secret.fill(0);

    let repository = PairingInvitationRepository::new(connection);
    let record = repository
        .get(invitation_id)
        .map_err(|error| PairingError::Database(error.to_string()))?
        .ok_or(PairingError::InvitationMissing)?;
    match record.state {
        PairingInvitationState::Consumed => return Err(PairingError::InvitationConsumed),
        PairingInvitationState::Expired => return Err(PairingError::InvitationExpired),
        PairingInvitationState::Active => {}
    }
    if record.expires_at <= now_ms {
        repository
            .expire_before(now_ms)
            .map_err(|error| PairingError::Database(error.to_string()))?;
        return Err(PairingError::InvitationExpired);
    }
    if !constant_time_eq(verifier.as_bytes(), record.secret_verifier.as_bytes()) {
        return Err(PairingError::InvalidInvitationSecret);
    }
    if !repository
        .mark_consumed(invitation_id, consumer_device_id, now_ms)
        .map_err(|error| PairingError::Database(error.to_string()))?
    {
        return Err(PairingError::InvitationConsumed);
    }
    Ok(())
}

pub fn accept_pairing_client_hello<S: SecretBytesStore>(
    connection: &mut Connection,
    secret_store: &mut S,
    client_hello_frame: &str,
    server_ephemeral_public_key: &str,
    server_hello_message_id: &str,
    now_ms: u64,
) -> Result<PairingServerHelloDraft, PairingError> {
    let ProtocolEnvelope::PreAuth(envelope) =
        parse_envelope(client_hello_frame).map_err(|_| PairingError::InvalidClientHello)?
    else {
        return Err(PairingError::InvalidClientHello);
    };
    if envelope.message_type != MessageType::ClientHello {
        return Err(PairingError::InvalidClientHello);
    }
    let client_hello: HelloPayload =
        serde_json::from_value(envelope.payload).map_err(|_| PairingError::InvalidClientHello)?;
    client_hello
        .validate()
        .map_err(|_| PairingError::InvalidClientHello)?;
    let pairing_context = client_hello
        .pairing_context
        .clone()
        .ok_or(PairingError::InvalidClientHello)?;
    let invitation_id = parse_pairing_invitation_context(&pairing_context)?;
    let invitation = PairingInvitationRepository::new(connection)
        .get(invitation_id)
        .map_err(|error| PairingError::Database(error.to_string()))?
        .ok_or(PairingError::InvitationMissing)?;

    match invitation.state {
        PairingInvitationState::Consumed => return Err(PairingError::InvitationConsumed),
        PairingInvitationState::Expired => return Err(PairingError::InvitationExpired),
        PairingInvitationState::Active => {}
    }
    if invitation.expires_at <= now_ms {
        PairingInvitationRepository::new(connection)
            .expire_before(now_ms)
            .map_err(|error| PairingError::Database(error.to_string()))?;
        return Err(PairingError::InvitationExpired);
    }
    let client_space_id =
        Uuid::parse_str(&client_hello.space_id).map_err(|_| PairingError::InvalidClientHello)?;
    if client_space_id != invitation.space_id {
        return Err(PairingError::InvalidClientHello);
    }

    let local_identity = ensure_local_device_identity(connection, secret_store, now_ms)
        .map_err(pairing_identity_error)?;
    if local_identity.device_id != invitation.issuer_device_id.to_string() {
        return Err(PairingError::InvalidClientHello);
    }

    let server_hello = HelloPayload {
        space_id: client_hello.space_id.clone(),
        device_id: local_identity.device_id,
        identity_public_key: local_identity.identity_public_key,
        ephemeral_public_key: server_ephemeral_public_key.to_string(),
        capabilities: vec![
            Capability::TextPlain,
            Capability::SyncHeads,
            Capability::ItemBatch,
            Capability::ItemLive,
        ],
        pairing_context: Some(pairing_context.clone()),
    };
    server_hello
        .validate()
        .map_err(|_| PairingError::InvalidClientHello)?;
    let server_hello_frame = serialize_pre_auth_envelope(&PreAuthEnvelope {
        message_type: MessageType::ServerHello,
        message_id: server_hello_message_id.to_string(),
        session_counter: envelope.session_counter.saturating_add(1),
        payload: serde_json::to_value(&server_hello)
            .map_err(|error| PairingError::Serialize(error.to_string()))?,
    })
    .map_err(|error| PairingError::Serialize(error.to_string()))?;

    Ok(PairingServerHelloDraft {
        invitation_id: invitation_id.to_string(),
        space_id: client_hello.space_id,
        peer_device_id: client_hello.device_id,
        peer_identity_public_key: client_hello.identity_public_key,
        peer_ephemeral_public_key: client_hello.ephemeral_public_key,
        server_device_id: server_hello.device_id,
        server_identity_public_key: server_hello.identity_public_key,
        server_ephemeral_public_key: server_ephemeral_public_key.to_string(),
        pairing_context,
        server_hello_frame,
    })
}

pub fn accept_pairing_auth_proof(
    handshake: PairingServerAuthProofInput,
    auth_proof_frame: &str,
    auth_ok_message_id: &str,
) -> Result<PairingServerAuthProofAccepted, PairingError> {
    let ProtocolEnvelope::PreAuth(envelope) =
        parse_envelope(auth_proof_frame).map_err(|_| PairingError::InvalidAuthProof)?
    else {
        return Err(PairingError::InvalidAuthProof);
    };
    if envelope.message_type != MessageType::AuthProof {
        return Err(PairingError::InvalidAuthProof);
    }
    let proof: AuthProofPayload =
        serde_json::from_value(envelope.payload).map_err(|_| PairingError::InvalidAuthProof)?;
    proof
        .validate()
        .map_err(|_| PairingError::InvalidAuthProof)?;
    if proof.role != AuthRole::Client || proof.signature_algorithm != SignatureAlgorithm::Ed25519 {
        return Err(PairingError::InvalidAuthProof);
    }

    let transcript_input = AuthTranscriptInput {
        role: AuthRole::Client,
        space_id: handshake.space_id.clone(),
        local_device_id: handshake.peer_device_id.clone(),
        remote_device_id: handshake.server_device_id.clone(),
        local_identity_public_key: handshake.peer_identity_public_key.clone(),
        remote_identity_public_key: handshake.server_identity_public_key.clone(),
        local_ephemeral_public_key: handshake.peer_ephemeral_public_key.clone(),
        remote_ephemeral_public_key: handshake.server_ephemeral_public_key.clone(),
        pairing_context: handshake.pairing_context.clone(),
    };
    let canonical_transcript =
        canonical_auth_transcript(&transcript_input).map_err(|_| PairingError::InvalidAuthProof)?;
    let transcript_hash = auth_transcript_hash_base64url(&transcript_input)
        .map_err(|_| PairingError::InvalidAuthProof)?;
    if proof.transcript_hash != transcript_hash {
        return Err(PairingError::InvalidAuthProof);
    }

    let peer_identity_public_key = fixed_bytes::<ED25519_PUBLIC_KEY_BYTES>(
        &decode_base64url(&handshake.peer_identity_public_key)
            .map_err(|_| PairingError::InvalidAuthProof)?,
        "peerIdentityPublicKey",
    )
    .map_err(|_| PairingError::InvalidAuthProof)?;
    let signature = fixed_bytes::<ED25519_SIGNATURE_BYTES>(
        &decode_base64url(&proof.signature).map_err(|_| PairingError::InvalidAuthProof)?,
        "signature",
    )
    .map_err(|_| PairingError::InvalidAuthProof)?;
    verify_ed25519_signature(
        peer_identity_public_key,
        canonical_transcript.as_bytes(),
        signature,
    )
    .map_err(|_| PairingError::AuthProofSignatureFailed)?;

    let peer_ephemeral_public_key = fixed_bytes::<X25519_PUBLIC_KEY_BYTES>(
        &decode_base64url(&handshake.peer_ephemeral_public_key)
            .map_err(|_| PairingError::InvalidAuthProof)?,
        "peerEphemeralPublicKey",
    )
    .map_err(|_| PairingError::InvalidAuthProof)?;
    let shared_secret = handshake
        .server_ephemeral_secret
        .shared_secret(peer_ephemeral_public_key);
    let transcript_salt = fixed_bytes::<32>(
        &decode_base64url(&transcript_hash).map_err(|_| PairingError::InvalidAuthProof)?,
        "transcriptHash",
    )
    .map_err(|_| PairingError::InvalidAuthProof)?;
    let session_keys = derive_session_keys(shared_secret, &transcript_salt)
        .map_err(|_| PairingError::SessionKeyDerivationFailed)?;
    let auth_ok_frame = serialize_pre_auth_envelope(&PreAuthEnvelope {
        message_type: MessageType::AuthOk,
        message_id: auth_ok_message_id.to_string(),
        session_counter: envelope.session_counter.saturating_add(1),
        payload: serde_json::json!({}),
    })
    .map_err(|error| PairingError::Serialize(error.to_string()))?;

    Ok(PairingServerAuthProofAccepted {
        invitation_id: handshake.invitation_id,
        space_id: handshake.space_id,
        peer_device_id: handshake.peer_device_id,
        peer_identity_public_key: handshake.peer_identity_public_key,
        transcript_hash,
        transcript_salt,
        shared_secret,
        session_keys,
        auth_ok_frame,
    })
}

fn normalize_space_display_name(display_name: &str) -> Result<String, PairingError> {
    let normalized = display_name.trim();
    if normalized.is_empty() || normalized.chars().count() > 64 {
        return Err(PairingError::InvalidDisplayName);
    }
    Ok(normalized.to_string())
}

fn parse_pairing_invitation_context(value: &str) -> Result<Uuid, PairingError> {
    let invitation_id = value
        .strip_prefix("pairing-invitation:v1:")
        .ok_or(PairingError::InvalidClientHello)?;
    Uuid::parse_str(invitation_id).map_err(|_| PairingError::InvalidClientHello)
}

fn random_space_key() -> Result<[u8; SPACE_KEY_BYTES], PairingError> {
    let mut key = [0u8; SPACE_KEY_BYTES];
    getrandom::getrandom(&mut key).map_err(|_| PairingError::RandomUnavailable)?;
    Ok(key)
}

fn random_pairing_secret() -> Result<[u8; PAIRING_SECRET_BYTES], PairingError> {
    let mut secret = [0u8; PAIRING_SECRET_BYTES];
    getrandom::getrandom(&mut secret).map_err(|_| PairingError::RandomUnavailable)?;
    Ok(secret)
}

fn space_key_ref(space_id: Uuid, key_version: u32) -> String {
    format!("credential://eggclip/space-key/{space_id}/v{key_version}")
}

fn local_device_display_name() -> String {
    let raw = std::env::var("COMPUTERNAME")
        .or_else(|_| std::env::var("HOSTNAME"))
        .unwrap_or_else(|_| "Windows 桌面".to_string());
    let normalized: String = raw
        .trim()
        .chars()
        .filter(|character| !character.is_control())
        .take(32)
        .collect();
    if normalized.is_empty() {
        "Windows 桌面".to_string()
    } else {
        normalized
    }
}

fn pairing_secret_store_error(error: SecretStoreError) -> PairingError {
    PairingError::KeyStore(error.to_string())
}

fn pairing_identity_error(error: IdentityError) -> PairingError {
    match error {
        IdentityError::Database(message) => PairingError::Database(message),
        IdentityError::KeyStore(message) => PairingError::KeyStore(message),
        IdentityError::RandomUnavailable => PairingError::RandomUnavailable,
        other => PairingError::Identity(other.to_string()),
    }
}

fn confirmation_code(payload_json: &[u8]) -> String {
    let digest = Sha256::digest(payload_json);
    let value = u32::from_be_bytes([digest[0], digest[1], digest[2], digest[3]]) % 1_000_000;
    format!("{value:06}")
}

fn pairing_secret_verifier(
    invitation_id: Uuid,
    pairing_secret: &[u8; PAIRING_SECRET_BYTES],
) -> String {
    let mut hasher = Sha256::new();
    hasher.update(b"EggClip pairing invitation verifier v1\0");
    hasher.update(invitation_id.as_bytes());
    hasher.update(pairing_secret);
    URL_SAFE_NO_PAD.encode(hasher.finalize())
}

fn constant_time_eq(left: &[u8], right: &[u8]) -> bool {
    if left.len() != right.len() {
        return false;
    }
    let mut diff = 0u8;
    for (left, right) in left.iter().zip(right.iter()) {
        diff |= left ^ right;
    }
    diff == 0
}

fn validate_pairing_invitation_uri(invitation: &str) -> Result<(), PairingError> {
    let payload = invitation
        .strip_prefix("eggclip://pair?p=")
        .ok_or(PairingError::InvalidInvitation)?;
    let payload_json = URL_SAFE_NO_PAD
        .decode(payload)
        .map_err(|_| PairingError::InvalidInvitation)?;
    let decoded: PairingInvitationPayload =
        serde_json::from_slice(&payload_json).map_err(|_| PairingError::InvalidInvitation)?;
    if decoded.app != "eggclip"
        || decoded.version != 1
        || decoded.kind != "pairingInvitation"
        || Uuid::parse_str(&decoded.invitation_id).is_err()
        || Uuid::parse_str(&decoded.space_id).is_err()
        || decoded.issuer_device_name.trim().is_empty()
        || decoded.issuer_device_name.chars().count() > 32
        || Uuid::parse_str(&decoded.issuer_device_id).is_err()
        || decode_base64url(&decoded.pairing_secret)
            .map(|secret| secret.len() != PAIRING_SECRET_BYTES)
            .unwrap_or(true)
    {
        return Err(PairingError::InvalidInvitation);
    }
    Ok(())
}

fn pairing_invitation_qr_svg(invitation: &str) -> Result<String, PairingError> {
    let code = QrCode::with_error_correction_level(invitation.as_bytes(), EcLevel::M)
        .map_err(|error| PairingError::QrCode(error.to_string()))?;
    Ok(code
        .render::<svg::Color>()
        .min_dimensions(
            PAIRING_INVITATION_QR_MIN_DIMENSIONS,
            PAIRING_INVITATION_QR_MIN_DIMENSIONS,
        )
        .dark_color(svg::Color("#2f2300"))
        .light_color(svg::Color("#fff8e7"))
        .build())
}

#[cfg(test)]
#[derive(Default)]
struct MemorySecretStore {
    secrets: HashMap<String, Vec<u8>>,
}

#[cfg(test)]
impl SecretBytesStore for MemorySecretStore {
    fn load_secret(&self, secret_ref: &str) -> Result<Option<Vec<u8>>, SecretStoreError> {
        Ok(self.secrets.get(secret_ref).cloned())
    }

    fn save_secret(&mut self, secret_ref: &str, secret: &[u8]) -> Result<(), SecretStoreError> {
        self.secrets.insert(secret_ref.to_string(), secret.to_vec());
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::storage::{open_in_memory_database, repositories::SpaceRepository};

    fn decode_invitation_payload(invitation: &str) -> PairingInvitationPayload {
        let payload = invitation
            .strip_prefix("eggclip://pair?p=")
            .expect("invitation should use eggclip pair scheme");
        let json = URL_SAFE_NO_PAD
            .decode(payload)
            .expect("payload should be base64url");
        serde_json::from_slice(&json).expect("payload should decode")
    }

    #[test]
    fn creates_space_key_in_external_secret_store_and_only_ref_in_sqlite() {
        let mut connection = open_in_memory_database().expect("database should open");
        let mut store = MemorySecretStore::default();

        let space = create_sync_space(&mut connection, &mut store, " 默认空间 ", 1_700_000_000_000)
            .expect("space should be created");

        assert_eq!(space.display_name, "默认空间");
        assert_eq!(space.key_version, INITIAL_SPACE_KEY_VERSION);
        assert!(space
            .space_key_ref
            .starts_with("credential://eggclip/space-key/"));
        assert_eq!(
            store
                .load_secret(&space.space_key_ref)
                .expect("secret store should load")
                .expect("space key should exist")
                .len(),
            SPACE_KEY_BYTES
        );

        let record = SpaceRepository::new(&connection)
            .get(Uuid::parse_str(&space.space_id).expect("space id should parse"))
            .expect("space should query")
            .expect("space should exist");
        assert_eq!(record.encrypted_space_key_ref, Some(space.space_key_ref));
        assert_eq!(record.space.display_name, "默认空间");
    }

    #[test]
    fn load_space_key_returns_secret_from_external_store() {
        let mut connection = open_in_memory_database().expect("database should open");
        let mut store = MemorySecretStore::default();
        let space = create_sync_space(&mut connection, &mut store, "默认空间", 1_700_000_000_000)
            .expect("space should be created");

        let key = load_space_key(
            &connection,
            &store,
            Uuid::parse_str(&space.space_id).expect("space id should parse"),
        )
        .expect("space key should load");

        assert_eq!(key.len(), SPACE_KEY_BYTES);
        assert_eq!(
            key.to_vec(),
            store
                .load_secret(&space.space_key_ref)
                .expect("secret should load")
                .expect("secret should exist")
        );
    }

    #[test]
    fn lists_spaces_without_loading_raw_space_keys() {
        let mut connection = open_in_memory_database().expect("database should open");
        let mut store = MemorySecretStore::default();
        let first = create_sync_space(&mut connection, &mut store, "默认空间", 1_700_000_000_000)
            .expect("first space should be created");
        let second = create_sync_space(&mut connection, &mut store, "临时空间", 1_700_000_000_100)
            .expect("second space should be created");

        let spaces = list_sync_spaces(&connection).expect("spaces should list");

        assert_eq!(spaces.len(), 2);
        assert_eq!(spaces[0].space_id, second.space_id);
        assert_eq!(spaces[1].space_id, first.space_id);
        assert!(spaces
            .iter()
            .all(|space| space.space_key_ref.starts_with("credential://")));
    }

    #[test]
    fn ensures_default_sync_space_once_and_reuses_existing_space() {
        let mut connection = open_in_memory_database().expect("database should open");
        let mut store = MemorySecretStore::default();

        let first =
            ensure_default_sync_space_in_database(&mut connection, &mut store, 1_700_000_000_000)
                .expect("default space should be created");
        let second =
            ensure_default_sync_space_in_database(&mut connection, &mut store, 1_700_000_000_500)
                .expect("existing default space should be reused");
        let spaces = list_sync_spaces(&connection).expect("spaces should list");

        assert_eq!(first.display_name, DEFAULT_SPACE_DISPLAY_NAME);
        assert_eq!(second.space_id, first.space_id);
        assert_eq!(second.created_at_ms, first.created_at_ms);
        assert_eq!(spaces.len(), 1);
        assert_eq!(store.secrets.len(), 1);
    }

    #[test]
    fn creates_pairing_invitation_with_high_entropy_secret_and_expiry() {
        let mut connection = open_in_memory_database().expect("database should open");
        let mut store = MemorySecretStore::default();
        let space = create_sync_space(&mut connection, &mut store, "默认空间", 1_700_000_000_000)
            .expect("space should be created");

        let invitation = create_pairing_invitation_for_space(
            &mut connection,
            &mut store,
            &space.space_id,
            1_700_000_000_500,
        )
        .expect("invitation should be created");
        let payload = decode_invitation_payload(&invitation.invitation);

        assert_eq!(invitation.space_id, space.space_id);
        assert_eq!(invitation.space_display_name, "默认空间");
        assert_eq!(invitation.expires_at_ms, 1_700_000_300_500);
        assert_eq!(invitation.expires_in_seconds, 300);
        assert_eq!(payload.app, "eggclip");
        assert_eq!(payload.version, 1);
        assert_eq!(payload.kind, "pairingInvitation");
        assert_eq!(payload.invitation_id, invitation.invitation_id);
        Uuid::parse_str(&invitation.invitation_id).expect("invitation id should be a UUID");
        assert_eq!(payload.space_id, space.space_id);
        assert_eq!(payload.space_key_version, INITIAL_SPACE_KEY_VERSION);
        assert!(!invitation.issuer_device_name.trim().is_empty());
        assert_eq!(payload.issuer_device_name, invitation.issuer_device_name);
        assert_eq!(
            decode_base64url_pairing_secret(&payload.pairing_secret).len(),
            PAIRING_SECRET_BYTES
        );
        assert_eq!(payload.expires_at_ms, invitation.expires_at_ms);
        assert_eq!(payload.issuer_device_id, invitation.issuer_device_id);
        assert!(payload.issuer_identity_public_key.len() >= 43);
        assert_eq!(invitation.confirmation_code.len(), 6);
        assert!(invitation.qr_svg.contains("<svg"));
        assert!(!invitation.qr_svg.contains(&payload.pairing_secret));

        let stored = PairingInvitationRepository::new(&connection)
            .get(Uuid::parse_str(&invitation.invitation_id).expect("invitation id should parse"))
            .expect("invitation should query")
            .expect("invitation should be registered");
        assert_eq!(stored.state, PairingInvitationState::Active);
        assert_eq!(stored.space_id.to_string(), space.space_id);
        assert_eq!(stored.expires_at, invitation.expires_at_ms);
        assert_ne!(stored.secret_verifier, payload.pairing_secret);
    }

    #[test]
    fn pairing_invitation_secrets_are_not_constant() {
        let mut connection = open_in_memory_database().expect("database should open");
        let mut store = MemorySecretStore::default();
        let space = create_sync_space(&mut connection, &mut store, "默认空间", 1_700_000_000_000)
            .expect("space should be created");

        let first = create_pairing_invitation_for_space(
            &mut connection,
            &mut store,
            &space.space_id,
            1_700_000_000_500,
        )
        .expect("first invitation should be created");
        let second = create_pairing_invitation_for_space(
            &mut connection,
            &mut store,
            &space.space_id,
            1_700_000_000_600,
        )
        .expect("second invitation should be created");

        assert_ne!(
            decode_invitation_payload(&first.invitation).pairing_secret,
            decode_invitation_payload(&second.invitation).pairing_secret
        );
    }

    #[test]
    fn creating_invitation_expires_previous_active_invitations() {
        let mut connection = open_in_memory_database().expect("database should open");
        let mut store = MemorySecretStore::default();
        let space = create_sync_space(&mut connection, &mut store, "默认空间", 1_700_000_000_000)
            .expect("space should be created");

        let first = create_pairing_invitation_for_space(
            &mut connection,
            &mut store,
            &space.space_id,
            1_700_000_000_500,
        )
        .expect("first invitation should be created");
        let second = create_pairing_invitation_for_space(
            &mut connection,
            &mut store,
            &space.space_id,
            first.expires_at_ms,
        )
        .expect("second invitation should be created");
        let invitations = PairingInvitationRepository::new(&connection);
        let first_record = invitations
            .get(Uuid::parse_str(&first.invitation_id).expect("first id should parse"))
            .expect("first invitation should query")
            .expect("first invitation should exist");
        let second_record = invitations
            .get(Uuid::parse_str(&second.invitation_id).expect("second id should parse"))
            .expect("second invitation should query")
            .expect("second invitation should exist");

        assert_eq!(first_record.state, PairingInvitationState::Expired);
        assert_eq!(second_record.state, PairingInvitationState::Active);
    }

    #[test]
    fn expiry_sweep_marks_only_elapsed_active_invitations() {
        let mut connection = open_in_memory_database().expect("database should open");
        let mut store = MemorySecretStore::default();
        let space = create_sync_space(&mut connection, &mut store, "默认空间", 1_700_000_000_000)
            .expect("space should be created");
        let invitation = create_pairing_invitation_for_space(
            &mut connection,
            &mut store,
            &space.space_id,
            1_700_000_000_500,
        )
        .expect("invitation should be created");

        assert_eq!(
            expire_pairing_invitations(&connection, invitation.expires_at_ms - 1)
                .expect("sweep before expiry should run"),
            0
        );
        assert_eq!(
            expire_pairing_invitations(&connection, invitation.expires_at_ms)
                .expect("sweep at expiry should run"),
            1
        );
        let stored = PairingInvitationRepository::new(&connection)
            .get(Uuid::parse_str(&invitation.invitation_id).expect("invitation id should parse"))
            .expect("invitation should query")
            .expect("invitation should exist");

        assert_eq!(stored.state, PairingInvitationState::Expired);
    }

    #[test]
    fn validates_pairing_invitation_uri_before_copy() {
        let mut connection = open_in_memory_database().expect("database should open");
        let mut store = MemorySecretStore::default();
        let space = create_sync_space(&mut connection, &mut store, "默认空间", 1_700_000_000_000)
            .expect("space should be created");
        let invitation = create_pairing_invitation_for_space(
            &mut connection,
            &mut store,
            &space.space_id,
            1_700_000_000_500,
        )
        .expect("invitation should be created");

        validate_pairing_invitation_uri(&invitation.invitation)
            .expect("generated invitation should validate");
        assert_eq!(
            validate_pairing_invitation_uri("https://example.com/not-eggclip"),
            Err(PairingError::InvalidInvitation)
        );
        assert_eq!(
            validate_pairing_invitation_uri("eggclip://pair?p=not-base64url"),
            Err(PairingError::InvalidInvitation)
        );
    }

    #[test]
    fn consumes_pairing_invitation_once_with_matching_secret() {
        let mut connection = open_in_memory_database().expect("database should open");
        let mut store = MemorySecretStore::default();
        let space = create_sync_space(&mut connection, &mut store, "默认空间", 1_700_000_000_000)
            .expect("space should be created");
        let invitation = create_pairing_invitation_for_space(
            &mut connection,
            &mut store,
            &space.space_id,
            1_700_000_000_500,
        )
        .expect("invitation should be created");
        let payload = decode_invitation_payload(&invitation.invitation);
        let consumer_device_id = Uuid::now_v7().to_string();

        consume_pairing_invitation(
            &connection,
            &payload.invitation_id,
            &payload.pairing_secret,
            &consumer_device_id,
            1_700_000_001_000,
        )
        .expect("invitation should consume");
        assert_eq!(
            consume_pairing_invitation(
                &connection,
                &payload.invitation_id,
                &payload.pairing_secret,
                &consumer_device_id,
                1_700_000_001_001,
            ),
            Err(PairingError::InvitationConsumed)
        );

        let stored = PairingInvitationRepository::new(&connection)
            .get(Uuid::parse_str(&payload.invitation_id).expect("invitation id should parse"))
            .expect("invitation should query")
            .expect("invitation should exist");
        assert_eq!(stored.state, PairingInvitationState::Consumed);
        assert_eq!(
            stored
                .consumed_by_device_id
                .map(|device_id| device_id.to_string()),
            Some(consumer_device_id)
        );
    }

    #[test]
    fn accepts_pairing_client_hello_and_builds_server_hello_without_consuming_invitation() {
        let mut connection = open_in_memory_database().expect("database should open");
        let mut store = MemorySecretStore::default();
        let space = create_sync_space(&mut connection, &mut store, "默认空间", 1_700_000_000_000)
            .expect("space should be created");
        let invitation = create_pairing_invitation_for_space(
            &mut connection,
            &mut store,
            &space.space_id,
            1_700_000_000_500,
        )
        .expect("invitation should be created");
        let payload = decode_invitation_payload(&invitation.invitation);
        let client_hello = HelloPayload {
            space_id: payload.space_id.clone(),
            device_id: "018ff6f0-4adf-7d31-a987-3ef2b25d0212".to_string(),
            identity_public_key: encode_base64url(&[1u8; 32]),
            ephemeral_public_key: encode_base64url(&[2u8; 32]),
            capabilities: vec![Capability::TextPlain, Capability::SyncHeads],
            pairing_context: Some(format!("pairing-invitation:v1:{}", payload.invitation_id)),
        };
        let client_hello_frame = serialize_pre_auth_envelope(&PreAuthEnvelope {
            message_type: MessageType::ClientHello,
            message_id: "018ff6f1-0000-7000-8000-000000000001".to_string(),
            session_counter: 0,
            payload: serde_json::to_value(&client_hello).expect("hello should serialize"),
        })
        .expect("client hello should serialize");

        let result = accept_pairing_client_hello(
            &mut connection,
            &mut store,
            &client_hello_frame,
            &encode_base64url(&[3u8; 32]),
            "018ff6f1-0000-7000-8000-000000000002",
            1_700_000_001_000,
        )
        .expect("client hello should be accepted");

        assert_eq!(result.invitation_id, payload.invitation_id);
        assert_eq!(result.peer_device_id, client_hello.device_id);
        assert_eq!(
            result.peer_identity_public_key,
            client_hello.identity_public_key
        );
        assert_eq!(
            result.pairing_context,
            format!("pairing-invitation:v1:{}", payload.invitation_id)
        );
        let ProtocolEnvelope::PreAuth(server_hello_envelope) =
            parse_envelope(&result.server_hello_frame).expect("server hello should parse")
        else {
            panic!("server hello should be pre-auth");
        };
        assert_eq!(server_hello_envelope.message_type, MessageType::ServerHello);
        assert_eq!(server_hello_envelope.session_counter, 1);
        let server_hello: HelloPayload = serde_json::from_value(server_hello_envelope.payload)
            .expect("server hello payload should parse");
        assert_eq!(server_hello.space_id, payload.space_id);
        assert_eq!(server_hello.device_id, payload.issuer_device_id);
        assert_eq!(
            server_hello.pairing_context.as_deref(),
            Some(result.pairing_context.as_str())
        );
        let stored = PairingInvitationRepository::new(&connection)
            .get(Uuid::parse_str(&payload.invitation_id).expect("invitation id should parse"))
            .expect("invitation should query")
            .expect("invitation should exist");
        assert_eq!(stored.state, PairingInvitationState::Active);
    }

    #[test]
    fn accepts_pairing_auth_proof_and_derives_server_session_material() {
        let mut connection = open_in_memory_database().expect("database should open");
        let mut store = MemorySecretStore::default();
        let space = create_sync_space(&mut connection, &mut store, "默认空间", 1_700_000_000_000)
            .expect("space should be created");
        let invitation = create_pairing_invitation_for_space(
            &mut connection,
            &mut store,
            &space.space_id,
            1_700_000_000_500,
        )
        .expect("invitation should be created");
        let payload = decode_invitation_payload(&invitation.invitation);
        let client_identity_seed = [9u8; 32];
        let client_identity = crate::crypto::Ed25519Identity::from_seed(client_identity_seed);
        let client_x25519 = X25519Secret::from_private_key([8u8; 32]);
        let server_x25519 = X25519Secret::from_private_key([7u8; 32]);
        let client_hello = HelloPayload {
            space_id: payload.space_id.clone(),
            device_id: "018ff6f0-4adf-7d31-a987-3ef2b25d0212".to_string(),
            identity_public_key: encode_base64url(&client_identity.public_key()),
            ephemeral_public_key: encode_base64url(&client_x25519.public_key()),
            capabilities: vec![Capability::TextPlain, Capability::SyncHeads],
            pairing_context: Some(format!("pairing-invitation:v1:{}", payload.invitation_id)),
        };
        let client_hello_frame = serialize_pre_auth_envelope(&PreAuthEnvelope {
            message_type: MessageType::ClientHello,
            message_id: "018ff6f1-0000-7000-8000-000000000001".to_string(),
            session_counter: 0,
            payload: serde_json::to_value(&client_hello).expect("hello should serialize"),
        })
        .expect("client hello should serialize");
        let server_hello = accept_pairing_client_hello(
            &mut connection,
            &mut store,
            &client_hello_frame,
            &encode_base64url(&server_x25519.public_key()),
            "018ff6f1-0000-7000-8000-000000000002",
            1_700_000_001_000,
        )
        .expect("client hello should be accepted");

        let transcript_input = AuthTranscriptInput {
            role: AuthRole::Client,
            space_id: server_hello.space_id.clone(),
            local_device_id: server_hello.peer_device_id.clone(),
            remote_device_id: server_hello.server_device_id.clone(),
            local_identity_public_key: server_hello.peer_identity_public_key.clone(),
            remote_identity_public_key: server_hello.server_identity_public_key.clone(),
            local_ephemeral_public_key: server_hello.peer_ephemeral_public_key.clone(),
            remote_ephemeral_public_key: server_hello.server_ephemeral_public_key.clone(),
            pairing_context: server_hello.pairing_context.clone(),
        };
        let canonical_transcript =
            canonical_auth_transcript(&transcript_input).expect("transcript should build");
        let signature = client_identity.sign(canonical_transcript.as_bytes());
        let auth_proof = AuthProofPayload {
            role: AuthRole::Client,
            signature_algorithm: SignatureAlgorithm::Ed25519,
            transcript_hash: auth_transcript_hash_base64url(&transcript_input)
                .expect("hash should build"),
            signature: encode_base64url(&signature),
        };
        let auth_proof_frame = serialize_pre_auth_envelope(&PreAuthEnvelope {
            message_type: MessageType::AuthProof,
            message_id: "018ff6f1-0000-7000-8000-000000000003".to_string(),
            session_counter: 2,
            payload: serde_json::to_value(&auth_proof).expect("proof should serialize"),
        })
        .expect("auth proof should serialize");

        let accepted = accept_pairing_auth_proof(
            PairingServerAuthProofInput {
                invitation_id: server_hello.invitation_id.clone(),
                space_id: server_hello.space_id.clone(),
                peer_device_id: server_hello.peer_device_id.clone(),
                peer_identity_public_key: server_hello.peer_identity_public_key.clone(),
                peer_ephemeral_public_key: server_hello.peer_ephemeral_public_key.clone(),
                server_device_id: server_hello.server_device_id.clone(),
                server_identity_public_key: server_hello.server_identity_public_key.clone(),
                server_ephemeral_public_key: server_hello.server_ephemeral_public_key.clone(),
                pairing_context: server_hello.pairing_context.clone(),
                server_ephemeral_secret: server_x25519.clone(),
            },
            &auth_proof_frame,
            "018ff6f1-0000-7000-8000-000000000004",
        )
        .expect("auth proof should be accepted");

        assert_eq!(accepted.invitation_id, server_hello.invitation_id);
        assert_eq!(accepted.peer_device_id, client_hello.device_id);
        assert_eq!(
            accepted.shared_secret,
            client_x25519.shared_secret(server_x25519.public_key())
        );
        assert_ne!(accepted.session_keys.client_to_server, [0u8; 32]);
        assert_ne!(accepted.session_keys.server_to_client, [0u8; 32]);
        let ProtocolEnvelope::PreAuth(auth_ok) =
            parse_envelope(&accepted.auth_ok_frame).expect("auth ok should parse")
        else {
            panic!("auth ok should be pre-auth");
        };
        assert_eq!(auth_ok.message_type, MessageType::AuthOk);
        assert_eq!(auth_ok.session_counter, 3);
    }

    #[test]
    fn rejects_pairing_auth_proof_with_invalid_signature() {
        let server_x25519 = X25519Secret::from_private_key([7u8; 32]);
        let peer_x25519 = X25519Secret::from_private_key([8u8; 32]);
        let transcript_input = AuthTranscriptInput {
            role: AuthRole::Client,
            space_id: "018ff6ef-c394-7d08-8b99-4b7d10f2767a".to_string(),
            local_device_id: "018ff6f0-4adf-7d31-a987-3ef2b25d0212".to_string(),
            remote_device_id: "018ff6f0-0a3b-7815-a4db-3eb6e23d9338".to_string(),
            local_identity_public_key: encode_base64url(
                &crate::crypto::Ed25519Identity::from_seed([9u8; 32]).public_key(),
            ),
            remote_identity_public_key: encode_base64url(&[3u8; 32]),
            local_ephemeral_public_key: encode_base64url(&peer_x25519.public_key()),
            remote_ephemeral_public_key: encode_base64url(&server_x25519.public_key()),
            pairing_context: "pairing-invitation:v1:018ff6f1-0000-7000-8000-000000000005"
                .to_string(),
        };
        let auth_proof = AuthProofPayload {
            role: AuthRole::Client,
            signature_algorithm: SignatureAlgorithm::Ed25519,
            transcript_hash: auth_transcript_hash_base64url(&transcript_input)
                .expect("hash should build"),
            signature: encode_base64url(&[0u8; 64]),
        };
        let auth_proof_frame = serialize_pre_auth_envelope(&PreAuthEnvelope {
            message_type: MessageType::AuthProof,
            message_id: "018ff6f1-0000-7000-8000-000000000003".to_string(),
            session_counter: 2,
            payload: serde_json::to_value(&auth_proof).expect("proof should serialize"),
        })
        .expect("auth proof should serialize");

        assert_eq!(
            accept_pairing_auth_proof(
                PairingServerAuthProofInput {
                    invitation_id: "018ff6f1-0000-7000-8000-000000000005".to_string(),
                    space_id: transcript_input.space_id,
                    peer_device_id: transcript_input.local_device_id,
                    peer_identity_public_key: transcript_input.local_identity_public_key,
                    peer_ephemeral_public_key: transcript_input.local_ephemeral_public_key,
                    server_device_id: transcript_input.remote_device_id,
                    server_identity_public_key: transcript_input.remote_identity_public_key,
                    server_ephemeral_public_key: transcript_input.remote_ephemeral_public_key,
                    pairing_context: transcript_input.pairing_context,
                    server_ephemeral_secret: server_x25519,
                },
                &auth_proof_frame,
                "018ff6f1-0000-7000-8000-000000000004",
            ),
            Err(PairingError::AuthProofSignatureFailed)
        );
    }

    #[test]
    fn rejects_pairing_client_hello_without_pairing_context() {
        let mut connection = open_in_memory_database().expect("database should open");
        let mut store = MemorySecretStore::default();
        let space = create_sync_space(&mut connection, &mut store, "默认空间", 1_700_000_000_000)
            .expect("space should be created");
        let invitation = create_pairing_invitation_for_space(
            &mut connection,
            &mut store,
            &space.space_id,
            1_700_000_000_500,
        )
        .expect("invitation should be created");
        let payload = decode_invitation_payload(&invitation.invitation);
        let client_hello = HelloPayload {
            space_id: payload.space_id,
            device_id: "018ff6f0-4adf-7d31-a987-3ef2b25d0212".to_string(),
            identity_public_key: encode_base64url(&[1u8; 32]),
            ephemeral_public_key: encode_base64url(&[2u8; 32]),
            capabilities: vec![Capability::TextPlain],
            pairing_context: None,
        };
        let client_hello_frame = serialize_pre_auth_envelope(&PreAuthEnvelope {
            message_type: MessageType::ClientHello,
            message_id: "018ff6f1-0000-7000-8000-000000000001".to_string(),
            session_counter: 0,
            payload: serde_json::to_value(&client_hello).expect("hello should serialize"),
        })
        .expect("client hello should serialize");

        assert_eq!(
            accept_pairing_client_hello(
                &mut connection,
                &mut store,
                &client_hello_frame,
                &encode_base64url(&[3u8; 32]),
                "018ff6f1-0000-7000-8000-000000000002",
                1_700_000_001_000,
            ),
            Err(PairingError::InvalidClientHello)
        );
    }

    #[test]
    fn rejects_expired_or_wrong_secret_invitation_consumption() {
        let mut connection = open_in_memory_database().expect("database should open");
        let mut store = MemorySecretStore::default();
        let space = create_sync_space(&mut connection, &mut store, "默认空间", 1_700_000_000_000)
            .expect("space should be created");
        let wrong_secret = encode_base64url(&[9u8; PAIRING_SECRET_BYTES]);
        let consumer_device_id = Uuid::now_v7().to_string();

        let wrong_secret_invitation = create_pairing_invitation_for_space(
            &mut connection,
            &mut store,
            &space.space_id,
            1_700_000_000_500,
        )
        .expect("invitation should be created");
        let wrong_secret_payload = decode_invitation_payload(&wrong_secret_invitation.invitation);
        assert_eq!(
            consume_pairing_invitation(
                &connection,
                &wrong_secret_payload.invitation_id,
                &wrong_secret,
                &consumer_device_id,
                1_700_000_001_000,
            ),
            Err(PairingError::InvalidInvitationSecret)
        );

        let expired_invitation = create_pairing_invitation_for_space(
            &mut connection,
            &mut store,
            &space.space_id,
            1_700_000_010_000,
        )
        .expect("expired candidate should be created");
        let expired_payload = decode_invitation_payload(&expired_invitation.invitation);
        assert_eq!(
            consume_pairing_invitation(
                &connection,
                &expired_payload.invitation_id,
                &expired_payload.pairing_secret,
                &consumer_device_id,
                expired_invitation.expires_at_ms,
            ),
            Err(PairingError::InvitationExpired)
        );
    }

    #[test]
    fn rejects_pairing_invitation_for_unknown_space() {
        let mut connection = open_in_memory_database().expect("database should open");
        let mut store = MemorySecretStore::default();

        assert_eq!(
            create_pairing_invitation_for_space(
                &mut connection,
                &mut store,
                &Uuid::now_v7().to_string(),
                1_700_000_000_500,
            ),
            Err(PairingError::MissingSpace)
        );
        assert_eq!(
            create_pairing_invitation_for_space(
                &mut connection,
                &mut store,
                "not-a-uuid",
                1_700_000_000_500,
            ),
            Err(PairingError::InvalidSpaceId)
        );
    }

    #[test]
    fn rejects_invalid_space_names_and_missing_keys() {
        let mut connection = open_in_memory_database().expect("database should open");
        let mut store = MemorySecretStore::default();
        assert_eq!(
            create_sync_space(&mut connection, &mut store, " ", 1_700_000_000_000),
            Err(PairingError::InvalidDisplayName)
        );

        let space = create_sync_space(&mut connection, &mut store, "默认空间", 1_700_000_000_000)
            .expect("space should be created");
        let empty_store = MemorySecretStore::default();
        assert_eq!(
            load_space_key(
                &connection,
                &empty_store,
                Uuid::parse_str(&space.space_id).expect("space id should parse"),
            ),
            Err(PairingError::MissingSpaceKey)
        );
    }

    #[test]
    fn generated_space_keys_are_not_constant() {
        let first = random_space_key().expect("random should work");
        let second = random_space_key().expect("random should work");
        assert_ne!(first, second);
    }

    fn decode_base64url_pairing_secret(value: &str) -> Vec<u8> {
        URL_SAFE_NO_PAD
            .decode(value)
            .expect("pairing secret should be base64url")
    }
}
