use std::fmt;

use rusqlite::Connection;
use serde::Deserialize;
use uuid::Uuid;
use zeroize::Zeroize;

use super::{
    build_pairing_secret_proof_from_secret,
    client::ParsedPairingInvitation,
    client_join::PairingClientPendingJoin,
    join_runtime::{PairingJoinRuntime, PairingJoinRuntimeError},
};
use crate::{
    crypto::{
        decode_base64url, derive_session_keys, encode_base64url, fixed_bytes,
        verify_ed25519_signature, Ed25519Identity, SessionDirection, SessionKeys, X25519Secret,
        ED25519_PRIVATE_SEED_BYTES, ED25519_PUBLIC_KEY_BYTES, ED25519_SIGNATURE_BYTES,
        X25519_PRIVATE_KEY_BYTES, X25519_PUBLIC_KEY_BYTES,
    },
    identity::{
        ensure_local_device_identity, IdentityError, IdentitySecretStore,
        LocalDeviceIdentitySummary,
    },
    protocol::{
        auth_transcript_hash_base64url, canonical_auth_transcript, serialize_pre_auth_envelope,
        AuthProofPayload, AuthRole, AuthTranscriptInput, Capability, HelloPayload, MessageType,
        PreAuthEnvelope, SignatureAlgorithm, HANDSHAKE_TIMEOUT_SECONDS,
    },
    storage::repositories::{DeviceRecord, SpaceRecord},
    sync::{DeviceTrustState, SpaceState, TrustedRouteRole},
    transport::{
        AuthenticatedTransportSession, HandshakeFrame, HandshakeFrameOutcome,
        HandshakeTransportSession,
    },
};

const PAIRING_CONTEXT_PREFIX: &str = "pairing-invitation:v2:";
const TRUSTED_DEVICE_CONTEXT_PREFIX: &str = "trusted-device:";
const FIRST_CLIENT_BUSINESS_COUNTER: u64 = 0;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum PairingClientHandshakeState {
    WaitingServerHello,
    WaitingServerProof,
    WaitingAuthOk,
    WaitingInitialSpaceKey,
    Failed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum PairingClientRemoteRejectCode {
    InvitationMissing,
    InvitationExpired,
    InvitationConsumed,
    IdentityOrSpaceMismatch,
    AuthProofFailed,
    HandshakeStateMissing,
    InternalError,
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum PairingClientHandshakeError {
    JoinAttempt(PairingJoinRuntimeError),
    InvitationExpired,
    IdentityUnavailable,
    RandomUnavailable,
    InvalidServerHello,
    ServerIdentityMismatch,
    InvalidServerProof,
    ServerAuthenticationFailed,
    RemoteRejected(PairingClientRemoteRejectCode),
    Timeout,
    #[cfg(test)]
    ConnectionClosed,
    UnexpectedFrame,
    ProtocolRejected,
    SessionKeyDerivationFailed,
}

impl fmt::Display for PairingClientHandshakeError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::JoinAttempt(_) => formatter.write_str("pairing join attempt unavailable"),
            Self::InvitationExpired => formatter.write_str("pairing invitation expired"),
            Self::IdentityUnavailable => formatter.write_str("local device identity unavailable"),
            Self::RandomUnavailable => formatter.write_str("secure random unavailable"),
            Self::InvalidServerHello => formatter.write_str("server hello rejected"),
            Self::ServerIdentityMismatch => formatter.write_str("server identity mismatch"),
            Self::InvalidServerProof => formatter.write_str("server auth proof rejected"),
            Self::ServerAuthenticationFailed => {
                formatter.write_str("server identity authentication failed")
            }
            Self::RemoteRejected(code) => write!(formatter, "remote rejected pairing: {code:?}"),
            Self::Timeout => formatter.write_str("pairing handshake timed out"),
            #[cfg(test)]
            Self::ConnectionClosed => formatter.write_str("pairing connection closed"),
            Self::UnexpectedFrame => formatter.write_str("unexpected pairing frame"),
            Self::ProtocolRejected => formatter.write_str("pairing protocol frame rejected"),
            Self::SessionKeyDerivationFailed => {
                formatter.write_str("pairing session key derivation failed")
            }
        }
    }
}

impl std::error::Error for PairingClientHandshakeError {}

pub(crate) struct PairingClientHandshakeStarted {
    pub handshake: PairingClientHandshake,
    pub client_hello_frame: String,
}

pub(crate) enum PairingClientHandshakeEvent {
    SendAuthProof(String),
    ServerProofVerified,
    AwaitingSpaceKey(PairingClientPendingJoin),
    TrustedReady(TrustedClientReadySession),
}

pub(crate) struct TrustedClientReadySession {
    pub space_id: Uuid,
    pub coordinator_device_id: Uuid,
    pub key_version: u32,
    pub transport: AuthenticatedTransportSession,
}

enum PairingClientHandshakeMode {
    InitialJoin {
        expected_space_key_version: u32,
        issuer_device_name: String,
    },
    TrustedReconnect {
        key_version: u32,
    },
}

pub(crate) struct PairingClientHandshake {
    state: PairingClientHandshakeState,
    inbound: HandshakeTransportSession,
    deadline_ms: u64,
    mode: PairingClientHandshakeMode,
    space_id: String,
    issuer_device_id: String,
    issuer_identity_public_key: String,
    pairing_context: String,
    local_device_id: String,
    local_identity_public_key: String,
    local_identity_private_seed: Option<[u8; ED25519_PRIVATE_SEED_BYTES]>,
    local_ephemeral_public_key: String,
    local_ephemeral_secret: Option<X25519Secret>,
    server_ephemeral_public_key: Option<String>,
    session_keys: Option<SessionKeys>,
    connected_endpoint: Option<(std::net::Ipv4Addr, u16)>,
}

impl PairingClientHandshake {
    pub(crate) fn start_from_join_attempt<S: IdentitySecretStore>(
        runtime: &PairingJoinRuntime,
        attempt_id: &str,
        connection: &mut Connection,
        secret_store: &mut S,
        now_ms: u64,
    ) -> Result<PairingClientHandshakeStarted, PairingClientHandshakeError> {
        let invitation = runtime
            .take_for_handshake(attempt_id, now_ms)
            .map_err(PairingClientHandshakeError::JoinAttempt)?;
        Self::start(invitation, connection, secret_store, now_ms)
    }

    fn start<S: IdentitySecretStore>(
        invitation: ParsedPairingInvitation,
        connection: &mut Connection,
        secret_store: &mut S,
        now_ms: u64,
    ) -> Result<PairingClientHandshakeStarted, PairingClientHandshakeError> {
        let ephemeral_secret = random_x25519_secret()?;
        Self::start_with_ephemeral_secret(
            invitation,
            connection,
            secret_store,
            ephemeral_secret,
            now_ms,
        )
    }

    fn start_with_ephemeral_secret<S: IdentitySecretStore>(
        mut invitation: ParsedPairingInvitation,
        connection: &mut Connection,
        secret_store: &mut S,
        ephemeral_secret: X25519Secret,
        now_ms: u64,
    ) -> Result<PairingClientHandshakeStarted, PairingClientHandshakeError> {
        if invitation.expires_at_ms <= now_ms {
            return Err(PairingClientHandshakeError::InvitationExpired);
        }
        let (identity, identity_private_seed) =
            load_signing_identity(connection, secret_store, now_ms)?;
        let pairing_context = format!("{PAIRING_CONTEXT_PREFIX}{}", invitation.invitation_id);
        let local_ephemeral_public_key = encode_base64url(&ephemeral_secret.public_key());
        let mut client_hello = HelloPayload {
            space_id: invitation.space_id.to_string(),
            device_id: identity.device_id.clone(),
            identity_public_key: identity.identity_public_key.clone(),
            ephemeral_public_key: local_ephemeral_public_key.clone(),
            capabilities: vec![
                Capability::TextPlain,
                Capability::SyncHeads,
                Capability::ItemBatch,
                Capability::ItemLive,
            ],
            pairing_context: Some(pairing_context.clone()),
            pairing_proof: None,
        };
        client_hello.pairing_proof = Some(
            build_pairing_secret_proof_from_secret(
                &invitation.pairing_secret,
                invitation.invitation_id,
                &client_hello.space_id,
                &invitation.issuer_device_id.to_string(),
                &invitation.issuer_identity_public_key,
                &client_hello,
            )
            .map_err(|_| PairingClientHandshakeError::ProtocolRejected)?,
        );
        invitation.pairing_secret.zeroize();
        client_hello
            .validate()
            .map_err(|_| PairingClientHandshakeError::ProtocolRejected)?;
        let client_hello_frame = serialize_pre_auth_envelope(&PreAuthEnvelope {
            message_type: MessageType::ClientHello,
            message_id: Uuid::now_v7().to_string(),
            session_counter: 0,
            payload: serde_json::to_value(client_hello)
                .map_err(|_| PairingClientHandshakeError::ProtocolRejected)?,
        })
        .map_err(|_| PairingClientHandshakeError::ProtocolRejected)?;

        Ok(PairingClientHandshakeStarted {
            client_hello_frame,
            handshake: Self {
                state: PairingClientHandshakeState::WaitingServerHello,
                inbound: HandshakeTransportSession::new(),
                deadline_ms: invitation
                    .expires_at_ms
                    .min(now_ms.saturating_add(HANDSHAKE_TIMEOUT_SECONDS.saturating_mul(1000))),
                mode: PairingClientHandshakeMode::InitialJoin {
                    expected_space_key_version: invitation.space_key_version,
                    issuer_device_name: invitation.issuer_device_name.clone(),
                },
                space_id: invitation.space_id.to_string(),
                issuer_device_id: invitation.issuer_device_id.to_string(),
                issuer_identity_public_key: invitation.issuer_identity_public_key.clone(),
                pairing_context,
                local_device_id: identity.device_id,
                local_identity_public_key: identity.identity_public_key,
                local_identity_private_seed: Some(identity_private_seed),
                local_ephemeral_public_key,
                local_ephemeral_secret: Some(ephemeral_secret),
                server_ephemeral_public_key: None,
                session_keys: None,
                connected_endpoint: invitation
                    .endpoints
                    .first()
                    .map(|endpoint| (endpoint.host, endpoint.port)),
            },
        })
    }

    pub(crate) fn start_from_trusted_device<S: IdentitySecretStore>(
        space: &SpaceRecord,
        coordinator: &DeviceRecord,
        connection: &mut Connection,
        secret_store: &mut S,
        now_ms: u64,
    ) -> Result<PairingClientHandshakeStarted, PairingClientHandshakeError> {
        if space.space.state != SpaceState::Active
            || space.encrypted_space_key_ref.is_none()
            || coordinator.device.space_id != space.space.space_id
            || coordinator.device.trust_state != DeviceTrustState::Trusted
            || coordinator.revoked_at.is_some()
            || coordinator.route.role != TrustedRouteRole::DialCoordinator
            || space.space.key_version == 0
        {
            return Err(PairingClientHandshakeError::IdentityUnavailable);
        }
        let ephemeral_secret = random_x25519_secret()?;
        let (identity, identity_private_seed) =
            load_signing_identity(connection, secret_store, now_ms)?;
        let space_id = space.space.space_id.to_string();
        let pairing_context = format!(
            "{TRUSTED_DEVICE_CONTEXT_PREFIX}{space_id}:key-v{}",
            space.space.key_version
        );
        let local_ephemeral_public_key = encode_base64url(&ephemeral_secret.public_key());
        let client_hello = HelloPayload {
            space_id: space_id.clone(),
            device_id: identity.device_id.clone(),
            identity_public_key: identity.identity_public_key.clone(),
            ephemeral_public_key: local_ephemeral_public_key.clone(),
            capabilities: vec![
                Capability::TextPlain,
                Capability::SyncHeads,
                Capability::ItemBatch,
                Capability::ItemLive,
            ],
            pairing_context: Some(pairing_context.clone()),
            pairing_proof: None,
        };
        client_hello
            .validate()
            .map_err(|_| PairingClientHandshakeError::ProtocolRejected)?;
        let client_hello_frame = serialize_pre_auth_envelope(&PreAuthEnvelope {
            message_type: MessageType::ClientHello,
            message_id: Uuid::now_v7().to_string(),
            session_counter: 0,
            payload: serde_json::to_value(client_hello)
                .map_err(|_| PairingClientHandshakeError::ProtocolRejected)?,
        })
        .map_err(|_| PairingClientHandshakeError::ProtocolRejected)?;

        Ok(PairingClientHandshakeStarted {
            client_hello_frame,
            handshake: Self {
                state: PairingClientHandshakeState::WaitingServerHello,
                inbound: HandshakeTransportSession::new(),
                deadline_ms: now_ms.saturating_add(HANDSHAKE_TIMEOUT_SECONDS.saturating_mul(1000)),
                mode: PairingClientHandshakeMode::TrustedReconnect {
                    key_version: space.space.key_version,
                },
                space_id,
                issuer_device_id: coordinator.device.device_id.to_string(),
                issuer_identity_public_key: coordinator.device.identity_public_key_ref.clone(),
                pairing_context,
                local_device_id: identity.device_id,
                local_identity_public_key: identity.identity_public_key,
                local_identity_private_seed: Some(identity_private_seed),
                local_ephemeral_public_key,
                local_ephemeral_secret: Some(ephemeral_secret),
                server_ephemeral_public_key: None,
                session_keys: None,
                connected_endpoint: None,
            },
        })
    }

    pub(crate) fn set_connected_endpoint(&mut self, host: std::net::Ipv4Addr, port: u16) {
        self.connected_endpoint = Some((host, port));
    }

    #[cfg(test)]
    pub(crate) fn state(&self) -> PairingClientHandshakeState {
        self.state
    }

    pub(crate) fn check_timeout(&mut self, now_ms: u64) -> Result<(), PairingClientHandshakeError> {
        if now_ms < self.deadline_ms {
            return Ok(());
        }
        self.fail(PairingClientHandshakeError::Timeout)
    }

    #[cfg(test)]
    pub(crate) fn connection_closed<T>(&mut self) -> Result<T, PairingClientHandshakeError> {
        self.fail(PairingClientHandshakeError::ConnectionClosed)
    }

    pub(crate) fn accept_server_frame(
        &mut self,
        frame: &str,
        now_ms: u64,
    ) -> Result<PairingClientHandshakeEvent, PairingClientHandshakeError> {
        self.check_timeout(now_ms)?;
        if matches!(
            self.state,
            PairingClientHandshakeState::WaitingInitialSpaceKey
                | PairingClientHandshakeState::Failed
        ) {
            return self.fail(PairingClientHandshakeError::UnexpectedFrame);
        }
        let outcome = match self.inbound.accept_text_frame(frame) {
            Ok(outcome) => outcome,
            Err(_) => return self.fail(PairingClientHandshakeError::ProtocolRejected),
        };
        match outcome {
            HandshakeFrameOutcome::Failed(frame) => self.fail(
                PairingClientHandshakeError::RemoteRejected(remote_reject_code(&frame)),
            ),
            HandshakeFrameOutcome::Continue(frame) => match self.state {
                PairingClientHandshakeState::WaitingServerHello => self.accept_server_hello(frame),
                PairingClientHandshakeState::WaitingServerProof => self.accept_server_proof(frame),
                _ => self.fail(PairingClientHandshakeError::UnexpectedFrame),
            },
            HandshakeFrameOutcome::Authenticated(frame) => self.accept_auth_ok(frame),
        }
    }

    fn accept_server_hello(
        &mut self,
        frame: HandshakeFrame,
    ) -> Result<PairingClientHandshakeEvent, PairingClientHandshakeError> {
        if frame.message_type != MessageType::ServerHello {
            return self.fail(PairingClientHandshakeError::UnexpectedFrame);
        }
        let hello: HelloPayload = match serde_json::from_value(frame.payload) {
            Ok(hello) => hello,
            Err(_) => return self.fail(PairingClientHandshakeError::InvalidServerHello),
        };
        if hello.validate().is_err()
            || hello.space_id != self.space_id
            || hello.pairing_context.as_deref() != Some(self.pairing_context.as_str())
            || hello.pairing_proof.is_some()
            || !hello.capabilities.contains(&Capability::TextPlain)
        {
            return self.fail(PairingClientHandshakeError::InvalidServerHello);
        }
        if hello.device_id != self.issuer_device_id
            || hello.identity_public_key != self.issuer_identity_public_key
        {
            return self.fail(PairingClientHandshakeError::ServerIdentityMismatch);
        }
        let server_ephemeral_public_key = match decode_fixed::<X25519_PUBLIC_KEY_BYTES>(
            &hello.ephemeral_public_key,
            "serverEphemeralPublicKey",
        ) {
            Ok(key) => key,
            Err(error) => return self.fail(error),
        };
        let transcript = AuthTranscriptInput {
            role: AuthRole::Client,
            space_id: self.space_id.clone(),
            local_device_id: self.local_device_id.clone(),
            remote_device_id: self.issuer_device_id.clone(),
            local_identity_public_key: self.local_identity_public_key.clone(),
            remote_identity_public_key: self.issuer_identity_public_key.clone(),
            local_ephemeral_public_key: self.local_ephemeral_public_key.clone(),
            remote_ephemeral_public_key: hello.ephemeral_public_key.clone(),
            pairing_context: self.pairing_context.clone(),
        };
        let canonical = match canonical_auth_transcript(&transcript) {
            Ok(value) => value,
            Err(_) => return self.fail(PairingClientHandshakeError::InvalidServerHello),
        };
        let transcript_hash = match auth_transcript_hash_base64url(&transcript) {
            Ok(value) => value,
            Err(_) => return self.fail(PairingClientHandshakeError::InvalidServerHello),
        };
        let transcript_salt = match decode_fixed::<32>(&transcript_hash, "transcriptHash") {
            Ok(value) => value,
            Err(error) => return self.fail(error),
        };
        let mut identity_private_seed = match self.local_identity_private_seed.take() {
            Some(seed) => seed,
            None => return self.fail(PairingClientHandshakeError::IdentityUnavailable),
        };
        let identity = Ed25519Identity::from_seed(identity_private_seed);
        identity_private_seed.zeroize();
        let signature = identity.sign(canonical.as_bytes());
        let ephemeral_secret = match self.local_ephemeral_secret.take() {
            Some(secret) => secret,
            None => return self.fail(PairingClientHandshakeError::InvalidServerHello),
        };
        let shared_secret = ephemeral_secret.shared_secret(server_ephemeral_public_key);
        if shared_secret == [0u8; 32] {
            return self.fail(PairingClientHandshakeError::InvalidServerHello);
        }
        let session_keys = match derive_session_keys(shared_secret, &transcript_salt) {
            Ok(keys) => keys,
            Err(_) => return self.fail(PairingClientHandshakeError::SessionKeyDerivationFailed),
        };
        let proof = AuthProofPayload {
            role: AuthRole::Client,
            signature_algorithm: SignatureAlgorithm::Ed25519,
            transcript_hash,
            signature: encode_base64url(&signature),
        };
        let proof_frame = match serialize_pre_auth_envelope(&PreAuthEnvelope {
            message_type: MessageType::AuthProof,
            message_id: Uuid::now_v7().to_string(),
            session_counter: 2,
            payload: match serde_json::to_value(proof) {
                Ok(value) => value,
                Err(_) => return self.fail(PairingClientHandshakeError::ProtocolRejected),
            },
        }) {
            Ok(frame) => frame,
            Err(_) => return self.fail(PairingClientHandshakeError::ProtocolRejected),
        };
        self.server_ephemeral_public_key = Some(hello.ephemeral_public_key);
        self.session_keys = Some(session_keys);
        self.state = PairingClientHandshakeState::WaitingServerProof;
        Ok(PairingClientHandshakeEvent::SendAuthProof(proof_frame))
    }

    fn accept_server_proof(
        &mut self,
        frame: HandshakeFrame,
    ) -> Result<PairingClientHandshakeEvent, PairingClientHandshakeError> {
        if frame.message_type != MessageType::AuthProof {
            return self.fail(PairingClientHandshakeError::UnexpectedFrame);
        }
        let proof: AuthProofPayload = match serde_json::from_value(frame.payload) {
            Ok(proof) => proof,
            Err(_) => return self.fail(PairingClientHandshakeError::InvalidServerProof),
        };
        if proof.validate().is_err()
            || proof.role != AuthRole::Server
            || proof.signature_algorithm != SignatureAlgorithm::Ed25519
        {
            return self.fail(PairingClientHandshakeError::InvalidServerProof);
        }
        let Some(server_ephemeral_public_key) = self.server_ephemeral_public_key.as_ref() else {
            return self.fail(PairingClientHandshakeError::InvalidServerProof);
        };
        let transcript = AuthTranscriptInput {
            role: AuthRole::Server,
            space_id: self.space_id.clone(),
            local_device_id: self.issuer_device_id.clone(),
            remote_device_id: self.local_device_id.clone(),
            local_identity_public_key: self.issuer_identity_public_key.clone(),
            remote_identity_public_key: self.local_identity_public_key.clone(),
            local_ephemeral_public_key: server_ephemeral_public_key.clone(),
            remote_ephemeral_public_key: self.local_ephemeral_public_key.clone(),
            pairing_context: self.pairing_context.clone(),
        };
        let canonical = match canonical_auth_transcript(&transcript) {
            Ok(value) => value,
            Err(_) => return self.fail(PairingClientHandshakeError::InvalidServerProof),
        };
        let expected_hash = match auth_transcript_hash_base64url(&transcript) {
            Ok(value) => value,
            Err(_) => return self.fail(PairingClientHandshakeError::InvalidServerProof),
        };
        if proof.transcript_hash != expected_hash {
            return self.fail(PairingClientHandshakeError::InvalidServerProof);
        }
        let server_public_key = match decode_fixed::<ED25519_PUBLIC_KEY_BYTES>(
            &self.issuer_identity_public_key,
            "serverIdentityPublicKey",
        ) {
            Ok(value) => value,
            Err(error) => return self.fail(error),
        };
        let signature =
            match decode_fixed::<ED25519_SIGNATURE_BYTES>(&proof.signature, "serverSignature") {
                Ok(value) => value,
                Err(error) => return self.fail(error),
            };
        if verify_ed25519_signature(server_public_key, canonical.as_bytes(), signature).is_err() {
            return self.fail(PairingClientHandshakeError::ServerAuthenticationFailed);
        }
        self.state = PairingClientHandshakeState::WaitingAuthOk;
        Ok(PairingClientHandshakeEvent::ServerProofVerified)
    }

    fn accept_auth_ok(
        &mut self,
        frame: HandshakeFrame,
    ) -> Result<PairingClientHandshakeEvent, PairingClientHandshakeError> {
        if self.state != PairingClientHandshakeState::WaitingAuthOk
            || frame.message_type != MessageType::AuthOk
            || frame.payload.as_object().is_none()
        {
            return self.fail(PairingClientHandshakeError::UnexpectedFrame);
        }
        let session_keys = match self.session_keys.take() {
            Some(keys) => keys,
            None => return self.fail(PairingClientHandshakeError::SessionKeyDerivationFailed),
        };
        let transport = AuthenticatedTransportSession::new(
            SessionDirection::ServerToClient,
            session_keys.server_to_client,
            SessionDirection::ClientToServer,
            session_keys.client_to_server,
            FIRST_CLIENT_BUSINESS_COUNTER,
        );
        let space_id = Uuid::parse_str(&self.space_id)
            .map_err(|_| PairingClientHandshakeError::ProtocolRejected)?;
        let coordinator_device_id = Uuid::parse_str(&self.issuer_device_id)
            .map_err(|_| PairingClientHandshakeError::ProtocolRejected)?;
        let local_device_id = Uuid::parse_str(&self.local_device_id)
            .map_err(|_| PairingClientHandshakeError::ProtocolRejected)?;
        match &self.mode {
            PairingClientHandshakeMode::InitialJoin {
                expected_space_key_version,
                issuer_device_name,
            } => {
                self.state = PairingClientHandshakeState::WaitingInitialSpaceKey;
                Ok(PairingClientHandshakeEvent::AwaitingSpaceKey(
                    PairingClientPendingJoin {
                        space_id,
                        expected_key_version: *expected_space_key_version,
                        coordinator_device_id,
                        coordinator_device_name: issuer_device_name.clone(),
                        coordinator_identity_public_key: self.issuer_identity_public_key.clone(),
                        local_device_id,
                        local_identity_public_key: self.local_identity_public_key.clone(),
                        connected_endpoint: self.connected_endpoint,
                        deadline_ms: self.deadline_ms,
                        transport,
                    },
                ))
            }
            PairingClientHandshakeMode::TrustedReconnect { key_version } => {
                self.state = PairingClientHandshakeState::WaitingInitialSpaceKey;
                Ok(PairingClientHandshakeEvent::TrustedReady(
                    TrustedClientReadySession {
                        space_id,
                        coordinator_device_id,
                        key_version: *key_version,
                        transport,
                    },
                ))
            }
        }
    }

    fn fail<T>(
        &mut self,
        error: PairingClientHandshakeError,
    ) -> Result<T, PairingClientHandshakeError> {
        self.scrub_secrets();
        self.inbound.close();
        self.state = PairingClientHandshakeState::Failed;
        Err(error)
    }

    fn scrub_secrets(&mut self) {
        if let Some(mut seed) = self.local_identity_private_seed.take() {
            seed.zeroize();
        }
        self.local_ephemeral_secret = None;
        if let Some(mut keys) = self.session_keys.take() {
            keys.client_to_server.zeroize();
            keys.server_to_client.zeroize();
        }
    }
}

impl Drop for PairingClientHandshake {
    fn drop(&mut self) {
        self.scrub_secrets();
    }
}

fn random_x25519_secret() -> Result<X25519Secret, PairingClientHandshakeError> {
    let mut private_key = [0u8; X25519_PRIVATE_KEY_BYTES];
    getrandom::getrandom(&mut private_key)
        .map_err(|_| PairingClientHandshakeError::RandomUnavailable)?;
    let secret = X25519Secret::from_private_key(private_key);
    private_key.zeroize();
    Ok(secret)
}

fn load_signing_identity<S: IdentitySecretStore>(
    connection: &mut Connection,
    secret_store: &mut S,
    now_ms: u64,
) -> Result<
    (LocalDeviceIdentitySummary, [u8; ED25519_PRIVATE_SEED_BYTES]),
    PairingClientHandshakeError,
> {
    let identity = ensure_local_device_identity(connection, secret_store, now_ms)
        .map_err(map_identity_error)?;
    let mut seed = secret_store
        .load_seed(&identity.private_key_ref)
        .map_err(map_identity_error)?
        .ok_or(PairingClientHandshakeError::IdentityUnavailable)?;
    let derived_public_key = encode_base64url(&Ed25519Identity::from_seed(seed).public_key());
    if derived_public_key != identity.identity_public_key {
        seed.zeroize();
        return Err(PairingClientHandshakeError::IdentityUnavailable);
    }
    Ok((identity, seed))
}

fn map_identity_error(error: IdentityError) -> PairingClientHandshakeError {
    match error {
        IdentityError::RandomUnavailable => PairingClientHandshakeError::RandomUnavailable,
        _ => PairingClientHandshakeError::IdentityUnavailable,
    }
}

fn decode_fixed<const N: usize>(
    value: &str,
    field: &'static str,
) -> Result<[u8; N], PairingClientHandshakeError> {
    let decoded =
        decode_base64url(value).map_err(|_| PairingClientHandshakeError::ProtocolRejected)?;
    fixed_bytes::<N>(&decoded, field).map_err(|_| PairingClientHandshakeError::ProtocolRejected)
}

#[derive(Deserialize)]
struct AuthErrorPayload {
    #[serde(default)]
    code: String,
}

fn remote_reject_code(frame: &HandshakeFrame) -> PairingClientRemoteRejectCode {
    let code = serde_json::from_value::<AuthErrorPayload>(frame.payload.clone())
        .map(|payload| payload.code)
        .unwrap_or_default();
    match code.as_str() {
        "invitationMissing" => PairingClientRemoteRejectCode::InvitationMissing,
        "invitationExpired" => PairingClientRemoteRejectCode::InvitationExpired,
        "invitationConsumed" => PairingClientRemoteRejectCode::InvitationConsumed,
        "identityOrSpaceMismatch" => PairingClientRemoteRejectCode::IdentityOrSpaceMismatch,
        "authProofFailed" => PairingClientRemoteRejectCode::AuthProofFailed,
        "handshakeStateMissing" => PairingClientRemoteRejectCode::HandshakeStateMissing,
        "internalError" => PairingClientRemoteRejectCode::InternalError,
        _ => PairingClientRemoteRejectCode::Unknown,
    }
}

#[cfg(test)]
mod tests {
    use std::{collections::HashMap, fs, path::PathBuf};

    use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
    use serde_json::json;

    use super::*;
    use crate::{
        pairing::{
            accept_pairing_auth_proof, accept_pairing_client_hello,
            create_pairing_invitation_for_space, create_sync_space, PairingServerAuthProofAccepted,
            PairingServerAuthProofInput, PairingServerHelloDraft,
        },
        protocol::{parse_envelope, ProtocolEnvelope},
        secret_store::{SecretBytesStore, SecretStoreError},
        storage::open_in_memory_database,
    };

    const NOW_MS: u64 = 1_700_000_000_000;

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

    struct ServerHelloFixture {
        client: PairingClientHandshake,
        server_store: TestSecretStore,
        server_hello: PairingServerHelloDraft,
        server_ephemeral_secret: X25519Secret,
    }

    fn server_hello_fixture() -> ServerHelloFixture {
        let mut server_connection = open_in_memory_database().expect("server database");
        let mut server_store = TestSecretStore::default();
        let space = create_sync_space(
            &mut server_connection,
            &mut server_store,
            "互联空间",
            NOW_MS,
        )
        .expect("server space");
        let invitation = create_pairing_invitation_for_space(
            &mut server_connection,
            &mut server_store,
            &space.space_id,
            NOW_MS + 10,
        )
        .expect("pairing invitation");
        let parsed =
            super::super::client::parse_pairing_invitation(invitation.invitation, NOW_MS + 20)
                .expect("client parses invitation");
        let mut client_connection = open_in_memory_database().expect("client database");
        let mut client_store = TestSecretStore::default();
        let started = PairingClientHandshake::start_with_ephemeral_secret(
            parsed,
            &mut client_connection,
            &mut client_store,
            X25519Secret::from_private_key([0x41; 32]),
            NOW_MS + 30,
        )
        .expect("client handshake starts");
        let server_ephemeral_secret = X25519Secret::from_private_key([0x52; 32]);
        let server_hello = accept_pairing_client_hello(
            &mut server_connection,
            &mut server_store,
            &started.client_hello_frame,
            &encode_base64url(&server_ephemeral_secret.public_key()),
            &Uuid::now_v7().to_string(),
            NOW_MS + 40,
        )
        .expect("server accepts client hello");
        ServerHelloFixture {
            client: started.handshake,
            server_store,
            server_hello,
            server_ephemeral_secret,
        }
    }

    fn advance_to_server_proof() -> (PairingClientHandshake, PairingServerAuthProofAccepted) {
        let mut fixture = server_hello_fixture();
        let event = fixture
            .client
            .accept_server_frame(&fixture.server_hello.server_hello_frame, NOW_MS + 50)
            .expect("client accepts server hello");
        let PairingClientHandshakeEvent::SendAuthProof(client_proof) = event else {
            panic!("client should send auth proof");
        };
        let server_seed = IdentitySecretStore::load_seed(
            &fixture.server_store,
            &fixture.server_hello.server_identity_private_key_ref,
        )
        .expect("server identity lookup")
        .expect("server identity seed");
        let accepted = accept_pairing_auth_proof(
            PairingServerAuthProofInput {
                invitation_id: fixture.server_hello.invitation_id,
                space_id: fixture.server_hello.space_id,
                peer_device_id: fixture.server_hello.peer_device_id,
                peer_identity_public_key: fixture.server_hello.peer_identity_public_key,
                peer_ephemeral_public_key: fixture.server_hello.peer_ephemeral_public_key,
                server_device_id: fixture.server_hello.server_device_id,
                server_identity_public_key: fixture.server_hello.server_identity_public_key,
                server_identity_private_seed: server_seed,
                server_ephemeral_public_key: fixture.server_hello.server_ephemeral_public_key,
                pairing_context: fixture.server_hello.pairing_context,
                server_ephemeral_secret: fixture.server_ephemeral_secret,
            },
            &client_proof,
            &Uuid::now_v7().to_string(),
            &Uuid::now_v7().to_string(),
        )
        .expect("server accepts client proof");
        (fixture.client, accepted)
    }

    #[test]
    fn pairing_proof_generation_consumes_the_shared_vector() {
        let vector: serde_json::Value = serde_json::from_str(include_str!(
            "../../../../protocol/test-vectors/handshake/pairing-proof-v2.valid.json"
        ))
        .expect("shared pairing vector");
        let text = |field: &str| vector[field].as_str().expect("vector string");
        let secret = fixed_bytes::<32>(
            &URL_SAFE_NO_PAD
                .decode(text("pairingSecret"))
                .expect("pairing secret"),
            "pairingSecret",
        )
        .expect("32-byte pairing secret");
        let invitation_id = Uuid::parse_str(text("invitationId")).expect("invitation id");
        let hello = HelloPayload {
            space_id: text("spaceId").to_string(),
            device_id: text("clientDeviceId").to_string(),
            identity_public_key: text("clientIdentityPublicKey").to_string(),
            ephemeral_public_key: text("clientEphemeralPublicKey").to_string(),
            capabilities: vec![Capability::TextPlain],
            pairing_context: Some(format!("{PAIRING_CONTEXT_PREFIX}{invitation_id}")),
            pairing_proof: None,
        };
        assert_eq!(
            build_pairing_secret_proof_from_secret(
                &secret,
                invitation_id,
                text("spaceId"),
                text("issuerDeviceId"),
                text("issuerIdentityPublicKey"),
                &hello,
            )
            .expect("proof"),
            text("proof")
        );
    }

    #[test]
    fn trusted_reconnect_hello_binds_saved_device_and_current_key_version() {
        let mut connection = open_in_memory_database().expect("client database");
        let mut store = TestSecretStore::default();
        let space_id = Uuid::now_v7();
        let coordinator_id = Uuid::now_v7();
        let coordinator_identity = Ed25519Identity::from_seed([0x33; 32]);
        let space = SpaceRecord {
            space: crate::sync::Space {
                space_id,
                display_name: "互联空间".to_string(),
                key_version: 7,
                state: SpaceState::Active,
                created_at: NOW_MS,
            },
            local_role: crate::sync::LocalSpaceRole::Member,
            encrypted_space_key_ref: Some("credential://space/v7".to_string()),
            updated_at: NOW_MS,
        };
        let coordinator = DeviceRecord {
            device: crate::sync::Device {
                device_id: coordinator_id,
                space_id,
                display_name: "Windows A".to_string(),
                identity_public_key_ref: encode_base64url(&coordinator_identity.public_key()),
                trust_state: DeviceTrustState::Trusted,
                connection_state: crate::sync::DeviceConnectionState::Offline,
                last_seen_at: None,
            },
            route: crate::storage::repositories::TrustedDeviceRoute {
                role: TrustedRouteRole::DialCoordinator,
                last_successful_host: Some("192.168.1.8".to_string()),
                last_successful_port: Some(31415),
            },
            paired_at: Some(NOW_MS),
            revoked_at: None,
        };

        let started = PairingClientHandshake::start_from_trusted_device(
            &space,
            &coordinator,
            &mut connection,
            &mut store,
            NOW_MS + 10,
        )
        .expect("trusted reconnect starts");
        let ProtocolEnvelope::PreAuth(envelope) =
            parse_envelope(&started.client_hello_frame).expect("client hello frame")
        else {
            panic!("trusted reconnect hello must be pre-auth");
        };
        let hello: HelloPayload =
            serde_json::from_value(envelope.payload).expect("client hello payload");
        assert_eq!(hello.space_id, space_id.to_string());
        assert_eq!(
            hello.pairing_context.as_deref(),
            Some(format!("trusted-device:{space_id}:key-v7").as_str())
        );
        assert!(hello.pairing_proof.is_none());
        assert_eq!(
            started.handshake.issuer_device_id,
            coordinator_id.to_string()
        );
    }

    #[test]
    fn rust_client_and_server_complete_mutual_auth_then_wait_for_initial_space_key() {
        let (mut client, accepted) = advance_to_server_proof();
        assert_eq!(
            client.state(),
            PairingClientHandshakeState::WaitingServerProof
        );
        assert!(matches!(
            client
                .accept_server_frame(&accepted.server_auth_proof_frame, NOW_MS + 60)
                .expect("server proof"),
            PairingClientHandshakeEvent::ServerProofVerified
        ));
        let event = client
            .accept_server_frame(&accepted.auth_ok_frame, NOW_MS + 70)
            .expect("auth ok");
        let PairingClientHandshakeEvent::AwaitingSpaceKey(pending) = event else {
            panic!("client should wait for the initial space key");
        };
        assert_eq!(
            client.state(),
            PairingClientHandshakeState::WaitingInitialSpaceKey
        );
        assert_eq!(pending.space_id.to_string(), accepted.space_id);
        assert_eq!(pending.coordinator_device_id.to_string().len(), 36);
        assert_eq!(pending.coordinator_identity_public_key.len(), 43);
        assert_eq!(pending.transport.next_outbound_counter(), 0);
    }

    #[test]
    fn rejects_server_hello_that_does_not_match_the_invitation_issuer() {
        let mut fixture = server_hello_fixture();
        let ProtocolEnvelope::PreAuth(mut envelope) =
            parse_envelope(&fixture.server_hello.server_hello_frame).expect("server hello")
        else {
            panic!("server hello should be plaintext");
        };
        envelope.payload["deviceId"] = json!(Uuid::now_v7().to_string());
        let rebound = serialize_pre_auth_envelope(&envelope).expect("rebound hello");
        assert_eq!(
            fixture
                .client
                .accept_server_frame(&rebound, NOW_MS + 50)
                .err(),
            Some(PairingClientHandshakeError::ServerIdentityMismatch)
        );
        assert_eq!(fixture.client.state(), PairingClientHandshakeState::Failed);
    }

    #[test]
    fn rejects_tampered_server_proof_and_auth_ok_before_server_proof() {
        let (mut client, accepted) = advance_to_server_proof();
        let ProtocolEnvelope::PreAuth(mut proof) =
            parse_envelope(&accepted.server_auth_proof_frame).expect("server proof")
        else {
            panic!("server proof should be plaintext");
        };
        proof.payload["signature"] = json!(encode_base64url(&[0u8; 64]));
        let tampered = serialize_pre_auth_envelope(&proof).expect("tampered proof");
        assert_eq!(
            client.accept_server_frame(&tampered, NOW_MS + 60).err(),
            Some(PairingClientHandshakeError::ServerAuthenticationFailed)
        );

        let (mut client, accepted) = advance_to_server_proof();
        assert_eq!(
            client
                .accept_server_frame(&accepted.auth_ok_frame, NOW_MS + 60)
                .err(),
            Some(PairingClientHandshakeError::UnexpectedFrame)
        );
    }

    #[test]
    fn maps_remote_rejection_timeout_and_abnormal_close_without_exposing_payload() {
        let mut fixture = server_hello_fixture();
        let auth_error = serialize_pre_auth_envelope(&PreAuthEnvelope {
            message_type: MessageType::AuthError,
            message_id: Uuid::now_v7().to_string(),
            session_counter: 1,
            payload: json!({ "code": "invitationExpired", "detail": "must-not-leak" }),
        })
        .expect("auth error");
        assert_eq!(
            fixture
                .client
                .accept_server_frame(&auth_error, NOW_MS + 50)
                .err(),
            Some(PairingClientHandshakeError::RemoteRejected(
                PairingClientRemoteRejectCode::InvitationExpired
            ))
        );

        let mut fixture = server_hello_fixture();
        assert_eq!(
            fixture.client.check_timeout(NOW_MS + 30 + 8_000),
            Err(PairingClientHandshakeError::Timeout)
        );
        assert_eq!(fixture.client.state(), PairingClientHandshakeState::Failed);

        let mut fixture = server_hello_fixture();
        assert_eq!(
            fixture.client.connection_closed::<()>(),
            Err(PairingClientHandshakeError::ConnectionClosed)
        );
        assert_eq!(fixture.client.state(), PairingClientHandshakeState::Failed);
    }

    #[test]
    fn reads_the_client_signing_seed_from_external_identity_storage() {
        let mut connection = open_in_memory_database().expect("database");
        let mut store = TestSecretStore::default();
        let (identity, mut seed) =
            load_signing_identity(&mut connection, &mut store, NOW_MS).expect("identity");
        let stored = store
            .load_secret(&identity.private_key_ref)
            .expect("credential lookup")
            .expect("credential seed");
        assert_eq!(stored, seed);
        assert_eq!(
            identity.identity_public_key,
            encode_base64url(&Ed25519Identity::from_seed(seed).public_key())
        );
        seed.zeroize();
    }

    #[test]
    fn shared_auth_proof_vector_remains_accepted_by_the_common_protocol_parser() {
        let mut path = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        path.extend([
            "..",
            "..",
            "protocol",
            "test-vectors",
            "handshake",
            "auth-proof.valid.json",
        ]);
        let frame = fs::read_to_string(path).expect("auth proof vector");
        let ProtocolEnvelope::PreAuth(envelope) = parse_envelope(&frame).expect("auth proof")
        else {
            panic!("auth proof vector should be plaintext");
        };
        let proof: AuthProofPayload =
            serde_json::from_value(envelope.payload).expect("auth proof payload");
        proof.validate().expect("shared proof remains valid");
        assert_eq!(proof.role, AuthRole::Client);
    }
}
