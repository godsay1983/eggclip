use std::{fmt, net::Ipv4Addr};

use rusqlite::{Connection, OptionalExtension};
use serde::Deserialize;
use uuid::Uuid;
use zeroize::Zeroize;

use super::{
    local_device_display_name, space_key_ref, trusted_device_default_display_name,
    ACTIVE_SYNC_SPACE_ID_KEY, SPACE_KEY_BYTES,
};
use crate::{
    crypto::{decode_base64url, fixed_bytes},
    protocol::MessageType,
    secret_store::SecretBytesStore,
    storage::repositories::{
        DeviceRecord, DeviceRepository, DisplayNameOrigin, SettingsRepository, SpaceRecord,
        SpaceRepository, TrustedDeviceRoute,
    },
    sync::{
        Device, DeviceConnectionState, DeviceTrustState, LocalSpaceRole, Space, SpaceState,
        TrustedRouteRole,
    },
    transport::AuthenticatedTransportSession,
};

const INITIAL_KEY_DELIVERY: &str = "pairing-v1";
const ROTATED_KEY_DELIVERY: &str = "rotation-v1";

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum PairingJoinCommitError {
    MissingConnectedEndpoint,
    Timeout,
    UnexpectedInitialMessage,
    InvalidSpaceKeyPayload,
    SpaceKeyVersionMismatch,
    AlreadyJoined,
    SpaceConflict,
    DeviceIdentityMismatch,
    CredentialConflict,
    CredentialStore,
    Database,
    CompensationFailed,
}

impl fmt::Display for PairingJoinCommitError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        let message = match self {
            Self::MissingConnectedEndpoint => "connected endpoint is unavailable",
            Self::Timeout => "initial space key delivery timed out",
            Self::UnexpectedInitialMessage => "initial encrypted message is not a space key",
            Self::InvalidSpaceKeyPayload => "initial space key payload is invalid",
            Self::SpaceKeyVersionMismatch => "space key version does not match invitation",
            Self::AlreadyJoined => "space has already been joined",
            Self::SpaceConflict => "space conflicts with an existing local space",
            Self::DeviceIdentityMismatch => "coordinator device identity does not match",
            Self::CredentialConflict => "space key credential already exists",
            Self::CredentialStore => "space key credential operation failed",
            Self::Database => "joined space database transaction failed",
            Self::CompensationFailed => "joined space rollback could not remove the credential",
        };
        formatter.write_str(message)
    }
}

impl std::error::Error for PairingJoinCommitError {}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct PairingJoinCommitSummary {
    pub space_id: Uuid,
    pub coordinator_device_id: Uuid,
    pub key_version: u32,
    pub space_key_ref: String,
}

pub(crate) struct PairingClientReadySession {
    pub summary: PairingJoinCommitSummary,
    pub transport: AuthenticatedTransportSession,
}

pub(crate) struct PairingClientPendingJoin {
    pub(super) space_id: Uuid,
    pub(super) expected_key_version: u32,
    pub(super) coordinator_device_id: Uuid,
    pub(super) coordinator_identity_public_key: String,
    pub(super) local_device_id: Uuid,
    pub(super) local_identity_public_key: String,
    pub(super) connected_endpoint: Option<(Ipv4Addr, u16)>,
    pub(super) deadline_ms: u64,
    pub(super) transport: AuthenticatedTransportSession,
}

impl PairingClientPendingJoin {
    pub(crate) fn accept_initial_space_key<S: SecretBytesStore>(
        mut self,
        frame: &str,
        connection: &mut Connection,
        secret_store: &mut S,
        accepted_at: u64,
    ) -> Result<PairingClientReadySession, PairingJoinCommitError> {
        let result =
            self.accept_initial_space_key_inner(frame, connection, secret_store, accepted_at);
        if result.is_err() {
            self.transport.close();
        }
        result.map(|summary| PairingClientReadySession {
            summary,
            transport: self.transport,
        })
    }

    fn accept_initial_space_key_inner<S: SecretBytesStore>(
        &mut self,
        frame: &str,
        connection: &mut Connection,
        secret_store: &mut S,
        accepted_at: u64,
    ) -> Result<PairingJoinCommitSummary, PairingJoinCommitError> {
        let Some((host, port)) = self.connected_endpoint else {
            return Err(PairingJoinCommitError::MissingConnectedEndpoint);
        };
        if accepted_at >= self.deadline_ms {
            return Err(PairingJoinCommitError::Timeout);
        }
        let (message_type, payload) = self
            .transport
            .accept_typed_text_frame(frame)
            .map_err(|_| PairingJoinCommitError::InvalidSpaceKeyPayload)?;
        if message_type != MessageType::SpaceKeyRotated {
            return Err(PairingJoinCommitError::UnexpectedInitialMessage);
        }
        let mut payload: InitialSpaceKeyPayload = serde_json::from_value(payload)
            .map_err(|_| PairingJoinCommitError::InvalidSpaceKeyPayload)?;
        if payload.space_id != self.space_id.to_string() || payload.delivery != INITIAL_KEY_DELIVERY
        {
            return Err(PairingJoinCommitError::InvalidSpaceKeyPayload);
        }
        if payload.key_version != self.expected_key_version {
            return Err(PairingJoinCommitError::SpaceKeyVersionMismatch);
        }
        let decoded_result = decode_base64url(&payload.space_key);
        payload.space_key.zeroize();
        let mut decoded =
            decoded_result.map_err(|_| PairingJoinCommitError::InvalidSpaceKeyPayload)?;
        let key_result = fixed_bytes::<SPACE_KEY_BYTES>(&decoded, "spaceKey");
        decoded.zeroize();
        let mut space_key =
            key_result.map_err(|_| PairingJoinCommitError::InvalidSpaceKeyPayload)?;
        let result = commit_joined_space(
            connection,
            secret_store,
            JoinedSpaceCommitInput {
                space_id: self.space_id,
                key_version: self.expected_key_version,
                coordinator_device_id: self.coordinator_device_id,
                coordinator_identity_public_key: self.coordinator_identity_public_key.clone(),
                local_device_id: self.local_device_id,
                local_identity_public_key: self.local_identity_public_key.clone(),
                connected_host: host,
                connected_port: port,
                accepted_at,
            },
            &space_key,
        );
        space_key.zeroize();
        result
    }
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct InitialSpaceKeyPayload {
    space_id: String,
    key_version: u32,
    space_key: String,
    delivery: String,
}

pub(crate) fn accept_trusted_space_key_rotation<S: SecretBytesStore>(
    payload: serde_json::Value,
    connection: &mut Connection,
    secret_store: &mut S,
    expected_space_id: Uuid,
    accepted_at: u64,
) -> Result<u32, PairingJoinCommitError> {
    let mut payload: InitialSpaceKeyPayload = serde_json::from_value(payload)
        .map_err(|_| PairingJoinCommitError::InvalidSpaceKeyPayload)?;
    if payload.space_id != expected_space_id.to_string()
        || payload.delivery != ROTATED_KEY_DELIVERY
        || payload.key_version == 0
    {
        payload.space_key.zeroize();
        return Err(PairingJoinCommitError::InvalidSpaceKeyPayload);
    }
    let decoded_result = decode_base64url(&payload.space_key);
    payload.space_key.zeroize();
    let mut decoded = decoded_result.map_err(|_| PairingJoinCommitError::InvalidSpaceKeyPayload)?;
    let key_result = fixed_bytes::<SPACE_KEY_BYTES>(&decoded, "spaceKey");
    decoded.zeroize();
    let mut space_key = key_result.map_err(|_| PairingJoinCommitError::InvalidSpaceKeyPayload)?;
    let result = commit_trusted_space_key_rotation(
        connection,
        secret_store,
        expected_space_id,
        payload.key_version,
        accepted_at,
        &space_key,
    );
    space_key.zeroize();
    result
}

fn commit_trusted_space_key_rotation<S: SecretBytesStore>(
    connection: &mut Connection,
    secret_store: &mut S,
    space_id: Uuid,
    key_version: u32,
    accepted_at: u64,
    space_key: &[u8; SPACE_KEY_BYTES],
) -> Result<u32, PairingJoinCommitError> {
    let mut current = SpaceRepository::new(connection)
        .get(space_id)
        .map_err(|_| PairingJoinCommitError::Database)?
        .ok_or(PairingJoinCommitError::SpaceConflict)?;
    if current.space.state != SpaceState::Active
        || current.local_role != LocalSpaceRole::Member
        || current.encrypted_space_key_ref.is_none()
        || key_version <= current.space.key_version
    {
        return Err(PairingJoinCommitError::SpaceKeyVersionMismatch);
    }
    let previous_key_ref = current
        .encrypted_space_key_ref
        .clone()
        .ok_or(PairingJoinCommitError::SpaceConflict)?;
    let next_key_ref = space_key_ref(space_id, key_version);
    let created_next_key = match secret_store
        .load_secret(&next_key_ref)
        .map_err(|_| PairingJoinCommitError::CredentialStore)?
    {
        Some(existing) if existing.as_slice() != space_key => {
            return Err(PairingJoinCommitError::CredentialConflict)
        }
        Some(_) => false,
        None => {
            secret_store
                .save_secret(&next_key_ref, space_key)
                .map_err(|_| PairingJoinCommitError::CredentialStore)?;
            true
        }
    };

    current.space.key_version = key_version;
    current.encrypted_space_key_ref = Some(next_key_ref.clone());
    current.updated_at = accepted_at;
    let commit_result = (|| -> Result<(), PairingJoinCommitError> {
        let transaction = connection
            .transaction()
            .map_err(|_| PairingJoinCommitError::Database)?;
        // History ciphertext and HMAC digests are bound to the previous key.
        // Clear both history and peer heads atomically with the key version so
        // no mixed-key state can be exposed after a restart.
        transaction
            .execute(
                "DELETE FROM clipboard_items WHERE space_id = ?1",
                rusqlite::params![space_id.to_string()],
            )
            .map_err(|_| PairingJoinCommitError::Database)?;
        transaction
            .execute(
                "DELETE FROM sync_heads WHERE space_id = ?1",
                rusqlite::params![space_id.to_string()],
            )
            .map_err(|_| PairingJoinCommitError::Database)?;
        SpaceRepository::new(&transaction)
            .upsert(&current)
            .map_err(|_| PairingJoinCommitError::Database)?;
        transaction
            .commit()
            .map_err(|_| PairingJoinCommitError::Database)
    })();
    if let Err(error) = commit_result {
        if created_next_key {
            let _ = secret_store.delete_secret(&next_key_ref);
        }
        return Err(error);
    }
    if previous_key_ref != next_key_ref {
        let _ = secret_store.delete_secret(&previous_key_ref);
    }
    Ok(key_version)
}

struct JoinedSpaceCommitInput {
    space_id: Uuid,
    key_version: u32,
    coordinator_device_id: Uuid,
    coordinator_identity_public_key: String,
    local_device_id: Uuid,
    local_identity_public_key: String,
    connected_host: Ipv4Addr,
    connected_port: u16,
    accepted_at: u64,
}

fn commit_joined_space<S: SecretBytesStore>(
    connection: &mut Connection,
    secret_store: &mut S,
    input: JoinedSpaceCommitInput,
    space_key: &[u8; SPACE_KEY_BYTES],
) -> Result<PairingJoinCommitSummary, PairingJoinCommitError> {
    if input.local_device_id == input.coordinator_device_id {
        return Err(PairingJoinCommitError::DeviceIdentityMismatch);
    }
    if let Some(existing) = SpaceRepository::new(connection)
        .get(input.space_id)
        .map_err(|_| PairingJoinCommitError::Database)?
    {
        return if existing.local_role == LocalSpaceRole::Member {
            Err(PairingJoinCommitError::AlreadyJoined)
        } else {
            Err(PairingJoinCommitError::SpaceConflict)
        };
    }
    let existing_coordinator_identity: Option<String> = connection
        .query_row(
            "SELECT identity_public_key FROM device_identities WHERE device_id = ?1",
            rusqlite::params![input.coordinator_device_id.to_string()],
            |row| row.get(0),
        )
        .optional()
        .map_err(|_| PairingJoinCommitError::Database)?;
    if existing_coordinator_identity
        .is_some_and(|identity| identity != input.coordinator_identity_public_key)
    {
        return Err(PairingJoinCommitError::DeviceIdentityMismatch);
    }

    let key_ref = space_key_ref(input.space_id, input.key_version);
    if secret_store
        .load_secret(&key_ref)
        .map_err(|_| PairingJoinCommitError::CredentialStore)?
        .is_some()
    {
        return Err(PairingJoinCommitError::CredentialConflict);
    }
    secret_store
        .save_secret(&key_ref, space_key)
        .map_err(|_| PairingJoinCommitError::CredentialStore)?;

    let database_result = (|| -> Result<(), PairingJoinCommitError> {
        let transaction = connection
            .transaction()
            .map_err(|_| PairingJoinCommitError::Database)?;
        let display_suffix: String = input.space_id.to_string().chars().take(8).collect();
        SpaceRepository::new(&transaction)
            .upsert(&SpaceRecord {
                space: Space {
                    space_id: input.space_id,
                    display_name: format!("同步空间 #{display_suffix}"),
                    key_version: input.key_version,
                    state: SpaceState::Active,
                    created_at: input.accepted_at,
                },
                name_origin: DisplayNameOrigin::Generated,
                local_role: LocalSpaceRole::Member,
                encrypted_space_key_ref: Some(key_ref.clone()),
                updated_at: input.accepted_at,
            })
            .map_err(|_| PairingJoinCommitError::Database)?;
        DeviceRepository::new(&transaction)
            .upsert(&DeviceRecord {
                device: Device {
                    device_id: input.local_device_id,
                    space_id: input.space_id,
                    display_name: local_device_display_name(),
                    identity_public_key_ref: input.local_identity_public_key.clone(),
                    trust_state: DeviceTrustState::Trusted,
                    connection_state: DeviceConnectionState::Offline,
                    last_seen_at: None,
                },
                name_origin: DisplayNameOrigin::Generated,
                route: TrustedDeviceRoute::default(),
                paired_at: Some(input.accepted_at),
                revoked_at: None,
            })
            .map_err(|_| PairingJoinCommitError::Database)?;
        DeviceRepository::new(&transaction)
            .upsert(&DeviceRecord {
                device: Device {
                    device_id: input.coordinator_device_id,
                    space_id: input.space_id,
                    display_name: trusted_device_default_display_name(
                        &input.coordinator_identity_public_key,
                    ),
                    identity_public_key_ref: input.coordinator_identity_public_key.clone(),
                    trust_state: DeviceTrustState::Trusted,
                    connection_state: DeviceConnectionState::Online,
                    last_seen_at: Some(input.accepted_at),
                },
                name_origin: DisplayNameOrigin::Generated,
                route: TrustedDeviceRoute {
                    role: TrustedRouteRole::DialCoordinator,
                    last_successful_host: Some(input.connected_host.to_string()),
                    last_successful_port: Some(input.connected_port),
                },
                paired_at: Some(input.accepted_at),
                revoked_at: None,
            })
            .map_err(|_| PairingJoinCommitError::Database)?;
        SettingsRepository::new(&transaction)
            .set(
                ACTIVE_SYNC_SPACE_ID_KEY,
                &input.space_id.to_string(),
                input.accepted_at,
            )
            .map_err(|_| PairingJoinCommitError::Database)?;
        transaction
            .commit()
            .map_err(|_| PairingJoinCommitError::Database)
    })();

    if let Err(error) = database_result {
        if secret_store.delete_secret(&key_ref).is_err() {
            return Err(PairingJoinCommitError::CompensationFailed);
        }
        return Err(error);
    }

    Ok(PairingJoinCommitSummary {
        space_id: input.space_id,
        coordinator_device_id: input.coordinator_device_id,
        key_version: input.key_version,
        space_key_ref: key_ref,
    })
}

#[cfg(test)]
mod tests {
    use std::{collections::HashMap, fs, path::PathBuf};

    use serde_json::json;

    use super::*;
    use crate::{
        crypto::{encode_base64url, SessionDirection},
        secret_store::{SecretBytesStore, SecretStoreError},
        storage::{open_database, open_in_memory_database},
    };

    const NOW_MS: u64 = 1_700_000_000_000;
    const CLIENT_TO_SERVER_KEY: [u8; 32] = [0x31; 32];
    const SERVER_TO_CLIENT_KEY: [u8; 32] = [0x42; 32];

    #[derive(Default)]
    struct TestSecretStore {
        secrets: HashMap<String, Vec<u8>>,
        fail_delete: bool,
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
            if self.fail_delete {
                return Err(SecretStoreError::Unavailable("delete failed".to_string()));
            }
            self.secrets.remove(secret_ref);
            Ok(())
        }
    }

    fn temp_database_path() -> PathBuf {
        std::env::temp_dir().join(format!("eggclip-client-join-{}.db", Uuid::now_v7()))
    }

    fn remove_database(path: &PathBuf) {
        let _ = fs::remove_file(path);
        let _ = fs::remove_file(path.with_extension("db-shm"));
        let _ = fs::remove_file(path.with_extension("db-wal"));
    }

    fn pending_join(space_id: Uuid, key_version: u32) -> PairingClientPendingJoin {
        PairingClientPendingJoin {
            space_id,
            expected_key_version: key_version,
            coordinator_device_id: Uuid::parse_str("018ff6f0-0a3b-7815-a4db-3eb6e23d9338")
                .expect("coordinator id"),
            coordinator_identity_public_key: "coordinator-public-key".to_string(),
            local_device_id: Uuid::parse_str("018ff6f0-4adf-7d31-a987-3ef2b25d0212")
                .expect("local id"),
            local_identity_public_key: "local-public-key".to_string(),
            connected_endpoint: Some((Ipv4Addr::new(192, 168, 1, 8), 41234)),
            deadline_ms: NOW_MS + 8_000,
            transport: AuthenticatedTransportSession::new(
                SessionDirection::ServerToClient,
                SERVER_TO_CLIENT_KEY,
                SessionDirection::ClientToServer,
                CLIENT_TO_SERVER_KEY,
                0,
            ),
        }
    }

    fn server_frame(message_type: MessageType, payload: serde_json::Value) -> String {
        let mut server = AuthenticatedTransportSession::new(
            SessionDirection::ClientToServer,
            CLIENT_TO_SERVER_KEY,
            SessionDirection::ServerToClient,
            SERVER_TO_CLIENT_KEY,
            5,
        );
        server
            .encode_business_frame(message_type, Uuid::now_v7().to_string(), &payload)
            .expect("server frame")
    }

    fn space_key_frame(space_id: Uuid, key_version: u32, key: &[u8; SPACE_KEY_BYTES]) -> String {
        server_frame(
            MessageType::SpaceKeyRotated,
            json!({
                "spaceId": space_id.to_string(),
                "keyVersion": key_version,
                "spaceKey": encode_base64url(key),
                "delivery": INITIAL_KEY_DELIVERY,
            }),
        )
    }

    #[test]
    fn commits_joined_space_members_route_and_credential_then_survives_reopen() {
        let path = temp_database_path();
        let mut connection = open_database(&path).expect("database");
        let mut store = TestSecretStore::default();
        let existing_space_id = Uuid::now_v7();
        SpaceRepository::new(&connection)
            .upsert(&SpaceRecord {
                space: Space {
                    space_id: existing_space_id,
                    display_name: "本机原有空间".to_string(),
                    key_version: 3,
                    state: SpaceState::Active,
                    created_at: NOW_MS - 1_000,
                },
                name_origin: DisplayNameOrigin::Custom,
                local_role: LocalSpaceRole::Owner,
                encrypted_space_key_ref: Some("credential://existing".to_string()),
                updated_at: NOW_MS - 1_000,
            })
            .expect("existing space");
        let joined_space_id = Uuid::now_v7();
        let key = [0x73; SPACE_KEY_BYTES];
        let ready = pending_join(joined_space_id, 4)
            .accept_initial_space_key(
                &space_key_frame(joined_space_id, 4, &key),
                &mut connection,
                &mut store,
                NOW_MS,
            )
            .expect("join commits");
        assert_eq!(ready.summary.space_id, joined_space_id);
        assert_eq!(ready.summary.key_version, 4);
        assert!(!ready.transport.is_closed());
        assert_eq!(
            ready.transport.state(),
            crate::protocol::ProtocolSessionState::Authenticated
        );
        drop(connection);

        let reopened = open_database(&path).expect("database reopens");
        let joined = SpaceRepository::new(&reopened)
            .get(joined_space_id)
            .expect("space query")
            .expect("joined space");
        assert_eq!(joined.local_role, LocalSpaceRole::Member);
        assert_eq!(joined.space.key_version, 4);
        assert_eq!(
            joined.encrypted_space_key_ref.as_deref(),
            Some(ready.summary.space_key_ref.as_str())
        );
        assert_eq!(
            store
                .load_secret(&ready.summary.space_key_ref)
                .expect("credential read")
                .expect("credential"),
            key
        );
        let members = DeviceRepository::new(&reopened)
            .list_by_space(joined_space_id)
            .expect("members");
        assert_eq!(members.len(), 2);
        let coordinator = members
            .iter()
            .find(|member| member.device.device_id == ready.summary.coordinator_device_id)
            .expect("coordinator");
        assert_eq!(coordinator.route.role, TrustedRouteRole::DialCoordinator);
        assert_eq!(
            coordinator.route.last_successful_host.as_deref(),
            Some("192.168.1.8")
        );
        assert_eq!(coordinator.route.last_successful_port, Some(41234));
        assert_eq!(
            SettingsRepository::new(&reopened)
                .get(ACTIVE_SYNC_SPACE_ID_KEY)
                .expect("active space"),
            Some(joined_space_id.to_string())
        );
        let existing = SpaceRepository::new(&reopened)
            .get(existing_space_id)
            .expect("existing space query")
            .expect("existing space remains");
        assert_eq!(existing.local_role, LocalSpaceRole::Owner);
        assert!(DeviceRepository::new(&reopened)
            .list_by_space(existing_space_id)
            .expect("existing members")
            .is_empty());
        drop(reopened);
        remove_database(&path);
    }

    #[test]
    fn rejects_wrong_first_message_version_and_timeout_without_persisting() {
        let space_id = Uuid::now_v7();
        let mut connection = open_in_memory_database().expect("database");
        let mut store = TestSecretStore::default();
        assert_eq!(
            pending_join(space_id, 2)
                .accept_initial_space_key(
                    &server_frame(MessageType::Ping, json!({})),
                    &mut connection,
                    &mut store,
                    NOW_MS,
                )
                .err(),
            Some(PairingJoinCommitError::UnexpectedInitialMessage)
        );
        assert_eq!(
            pending_join(space_id, 2)
                .accept_initial_space_key(
                    &space_key_frame(space_id, 3, &[7; SPACE_KEY_BYTES]),
                    &mut connection,
                    &mut store,
                    NOW_MS,
                )
                .err(),
            Some(PairingJoinCommitError::SpaceKeyVersionMismatch)
        );
        assert_eq!(
            pending_join(space_id, 2)
                .accept_initial_space_key(
                    &space_key_frame(space_id, 2, &[7; SPACE_KEY_BYTES]),
                    &mut connection,
                    &mut store,
                    NOW_MS + 8_000,
                )
                .err(),
            Some(PairingJoinCommitError::Timeout)
        );
        assert!(SpaceRepository::new(&connection)
            .get(space_id)
            .expect("space query")
            .is_none());
        assert!(store.secrets.is_empty());
    }

    #[test]
    fn rejects_duplicate_space_conflict_and_coordinator_key_mismatch() {
        let key = [0x19; SPACE_KEY_BYTES];

        let joined_space_id = Uuid::now_v7();
        let mut joined_connection = open_in_memory_database().expect("joined database");
        let mut joined_store = TestSecretStore::default();
        pending_join(joined_space_id, 1)
            .accept_initial_space_key(
                &space_key_frame(joined_space_id, 1, &key),
                &mut joined_connection,
                &mut joined_store,
                NOW_MS,
            )
            .expect("first join");
        assert_eq!(
            pending_join(joined_space_id, 1)
                .accept_initial_space_key(
                    &space_key_frame(joined_space_id, 1, &key),
                    &mut joined_connection,
                    &mut joined_store,
                    NOW_MS + 1,
                )
                .err(),
            Some(PairingJoinCommitError::AlreadyJoined)
        );

        let conflict_space_id = Uuid::now_v7();
        let mut conflict_connection = open_in_memory_database().expect("conflict database");
        SpaceRepository::new(&conflict_connection)
            .upsert(&SpaceRecord {
                space: Space {
                    space_id: conflict_space_id,
                    display_name: "本机空间".to_string(),
                    key_version: 1,
                    state: SpaceState::Active,
                    created_at: NOW_MS,
                },
                name_origin: DisplayNameOrigin::Custom,
                local_role: LocalSpaceRole::Owner,
                encrypted_space_key_ref: Some("credential://owner".to_string()),
                updated_at: NOW_MS,
            })
            .expect("owner space");
        let mut conflict_store = TestSecretStore::default();
        assert_eq!(
            pending_join(conflict_space_id, 1)
                .accept_initial_space_key(
                    &space_key_frame(conflict_space_id, 1, &key),
                    &mut conflict_connection,
                    &mut conflict_store,
                    NOW_MS,
                )
                .err(),
            Some(PairingJoinCommitError::SpaceConflict)
        );

        let mismatch_space_id = Uuid::now_v7();
        let mut mismatch_connection = open_in_memory_database().expect("mismatch database");
        let mismatch_pending = pending_join(mismatch_space_id, 1);
        mismatch_connection
            .execute(
                "INSERT INTO device_identities(device_id, identity_public_key) VALUES(?1, 'other-key')",
                rusqlite::params![mismatch_pending.coordinator_device_id.to_string()],
            )
            .expect("conflicting identity");
        let mut mismatch_store = TestSecretStore::default();
        assert_eq!(
            mismatch_pending
                .accept_initial_space_key(
                    &space_key_frame(mismatch_space_id, 1, &key),
                    &mut mismatch_connection,
                    &mut mismatch_store,
                    NOW_MS,
                )
                .err(),
            Some(PairingJoinCommitError::DeviceIdentityMismatch)
        );
        assert!(mismatch_store.secrets.is_empty());
    }

    #[test]
    fn removes_saved_credential_when_database_transaction_fails() {
        let space_id = Uuid::now_v7();
        let mut connection = open_in_memory_database().expect("database");
        connection
            .execute_batch(
                "CREATE TRIGGER fail_joined_space
                 BEFORE INSERT ON spaces
                 BEGIN
                   SELECT RAISE(ABORT, 'forced join failure');
                 END;",
            )
            .expect("failure trigger");
        let mut store = TestSecretStore::default();
        assert_eq!(
            pending_join(space_id, 1)
                .accept_initial_space_key(
                    &space_key_frame(space_id, 1, &[0x55; SPACE_KEY_BYTES]),
                    &mut connection,
                    &mut store,
                    NOW_MS,
                )
                .err(),
            Some(PairingJoinCommitError::Database)
        );
        assert!(store.secrets.is_empty());
        assert!(SpaceRepository::new(&connection)
            .get(space_id)
            .expect("space query")
            .is_none());
        let member_count: i64 = connection
            .query_row("SELECT COUNT(*) FROM space_members", [], |row| row.get(0))
            .expect("member count");
        assert_eq!(member_count, 0);
    }

    #[test]
    fn trusted_rotation_advances_member_key_and_removes_previous_credential() {
        let space_id = Uuid::now_v7();
        let old_ref = space_key_ref(space_id, 2);
        let next_ref = space_key_ref(space_id, 4);
        let mut connection = open_in_memory_database().expect("database");
        SpaceRepository::new(&connection)
            .upsert(&SpaceRecord {
                space: Space {
                    space_id,
                    display_name: "互联空间".to_string(),
                    key_version: 2,
                    state: SpaceState::Active,
                    created_at: NOW_MS,
                },
                name_origin: DisplayNameOrigin::Custom,
                local_role: LocalSpaceRole::Member,
                encrypted_space_key_ref: Some(old_ref.clone()),
                updated_at: NOW_MS,
            })
            .expect("member space");
        let history_origin = Uuid::now_v7();
        connection
            .execute(
                "INSERT INTO device_identities(device_id, identity_public_key) VALUES(?1, 'history-key')",
                rusqlite::params![history_origin.to_string()],
            )
            .expect("history identity");
        connection
            .execute(
                "INSERT INTO space_members(
                   space_id, device_id, display_name, trust_state, connection_state, route_role
                 ) VALUES(?1, ?2, '历史来源', 'trusted', 'offline', 'acceptOnly')",
                rusqlite::params![space_id.to_string(), history_origin.to_string()],
            )
            .expect("history member");
        connection
            .execute(
                "INSERT INTO clipboard_items(
                   item_id, space_id, origin_device_id, origin_seq, hlc, content_type,
                   content_length, content_digest, encrypted_content, created_at,
                   received_at, expires_at
                 ) VALUES(?1, ?2, ?3, 1, '1-0', 'text/plain', 4, 'digest', X'0102', ?4, ?4, ?5)",
                rusqlite::params![
                    Uuid::now_v7().to_string(),
                    space_id.to_string(),
                    history_origin.to_string(),
                    NOW_MS,
                    NOW_MS + 1000,
                ],
            )
            .expect("history item");
        connection
            .execute(
                "INSERT INTO sync_heads(
                   space_id, peer_device_id, origin_device_id,
                   highest_origin_seq, minimum_available, updated_at
                 ) VALUES(?1, ?2, ?2, 1, 1, ?3)",
                rusqlite::params![space_id.to_string(), history_origin.to_string(), NOW_MS],
            )
            .expect("sync head");
        let mut store = TestSecretStore::default();
        store
            .secrets
            .insert(old_ref.clone(), vec![0x22; SPACE_KEY_BYTES]);
        let next_key = [0x44; SPACE_KEY_BYTES];
        let payload = json!({
            "spaceId": space_id,
            "keyVersion": 4,
            "spaceKey": encode_base64url(&next_key),
            "delivery": "rotation-v1",
        });

        assert_eq!(
            accept_trusted_space_key_rotation(
                payload.clone(),
                &mut connection,
                &mut store,
                space_id,
                NOW_MS + 100,
            ),
            Ok(4)
        );
        let updated = SpaceRepository::new(&connection)
            .get(space_id)
            .expect("space query")
            .expect("space");
        assert_eq!(updated.space.key_version, 4);
        assert_eq!(
            updated.encrypted_space_key_ref.as_deref(),
            Some(next_ref.as_str())
        );
        assert_eq!(store.secrets.get(&next_ref), Some(&next_key.to_vec()));
        assert!(!store.secrets.contains_key(&old_ref));
        let history_count: i64 = connection
            .query_row(
                "SELECT COUNT(*) FROM clipboard_items WHERE space_id = ?1",
                rusqlite::params![space_id.to_string()],
                |row| row.get(0),
            )
            .expect("history count");
        let head_count: i64 = connection
            .query_row(
                "SELECT COUNT(*) FROM sync_heads WHERE space_id = ?1",
                rusqlite::params![space_id.to_string()],
                |row| row.get(0),
            )
            .expect("head count");
        assert_eq!(history_count, 0);
        assert_eq!(head_count, 0);
        assert_eq!(
            accept_trusted_space_key_rotation(
                payload,
                &mut connection,
                &mut store,
                space_id,
                NOW_MS + 101,
            ),
            Err(PairingJoinCommitError::SpaceKeyVersionMismatch)
        );
    }

    #[test]
    fn trusted_rotation_rolls_back_database_and_new_credential_on_failure() {
        let space_id = Uuid::now_v7();
        let old_ref = space_key_ref(space_id, 1);
        let next_ref = space_key_ref(space_id, 2);
        let mut connection = open_in_memory_database().expect("database");
        SpaceRepository::new(&connection)
            .upsert(&SpaceRecord {
                space: Space {
                    space_id,
                    display_name: "互联空间".to_owned(),
                    key_version: 1,
                    state: SpaceState::Active,
                    created_at: NOW_MS,
                },
                name_origin: DisplayNameOrigin::Custom,
                local_role: LocalSpaceRole::Member,
                encrypted_space_key_ref: Some(old_ref.clone()),
                updated_at: NOW_MS,
            })
            .expect("member space");
        connection
            .execute_batch(
                "CREATE TRIGGER fail_space_rotation
                 BEFORE UPDATE ON spaces
                 BEGIN
                   SELECT RAISE(ABORT, 'forced rotation failure');
                 END;",
            )
            .expect("failure trigger");
        let mut store = TestSecretStore::default();
        store
            .secrets
            .insert(old_ref.clone(), vec![0x11; SPACE_KEY_BYTES]);
        let payload = json!({
            "spaceId": space_id,
            "keyVersion": 2,
            "spaceKey": encode_base64url(&[0x22; SPACE_KEY_BYTES]),
            "delivery": "rotation-v1",
        });

        assert_eq!(
            accept_trusted_space_key_rotation(
                payload,
                &mut connection,
                &mut store,
                space_id,
                NOW_MS + 100,
            ),
            Err(PairingJoinCommitError::Database)
        );
        let current = SpaceRepository::new(&connection)
            .get(space_id)
            .expect("space query")
            .expect("space");
        assert_eq!(current.space.key_version, 1);
        assert_eq!(
            current.encrypted_space_key_ref.as_deref(),
            Some(old_ref.as_str())
        );
        assert!(store.secrets.contains_key(&old_ref));
        assert!(!store.secrets.contains_key(&next_ref));
    }
}
