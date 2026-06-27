use rusqlite::{params, types::Type, Connection, OptionalExtension};
use uuid::Uuid;

use crate::sync::{
    AppSettings, ClipboardItem, ContentType, Device, DeviceConnectionState, DeviceTrustState,
    HlcTimestamp, Space, SpaceState, SyncHead,
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SpaceRecord {
    pub space: Space,
    pub encrypted_space_key_ref: Option<String>,
    pub updated_at: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DeviceRecord {
    pub device: Device,
    pub paired_at: Option<u64>,
    pub revoked_at: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClipboardItemRecord {
    pub item: ClipboardItem,
    pub encrypted_content: Vec<u8>,
    pub received_at: u64,
    pub expires_at: u64,
    pub deleted_at: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SyncHeadRecord {
    pub head: SyncHead,
    pub peer_device_id: Uuid,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RetentionCleanupResult {
    pub expired_items: usize,
    pub overflow_items: usize,
}

impl RetentionCleanupResult {
    pub fn total(self) -> usize {
        self.expired_items + self.overflow_items
    }
}

pub struct SpaceRepository<'a> {
    connection: &'a Connection,
}

impl<'a> SpaceRepository<'a> {
    pub fn new(connection: &'a Connection) -> Self {
        Self { connection }
    }

    pub fn upsert(&self, record: &SpaceRecord) -> rusqlite::Result<()> {
        self.connection.execute(
            "INSERT INTO spaces(
              space_id, display_name, encrypted_space_key_ref, key_version, state, created_at, updated_at
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
            ON CONFLICT(space_id) DO UPDATE SET
              display_name = excluded.display_name,
              encrypted_space_key_ref = excluded.encrypted_space_key_ref,
              key_version = excluded.key_version,
              state = excluded.state,
              updated_at = excluded.updated_at",
            params![
                record.space.space_id.to_string(),
                record.space.display_name,
                record.encrypted_space_key_ref,
                record.space.key_version,
                space_state_to_db(record.space.state),
                u64_to_i64(record.space.created_at)?,
                u64_to_i64(record.updated_at)?,
            ],
        )?;
        Ok(())
    }

    pub fn get(&self, space_id: Uuid) -> rusqlite::Result<Option<SpaceRecord>> {
        self.connection
            .query_row(
                "SELECT space_id, display_name, encrypted_space_key_ref, key_version, state, created_at, updated_at
                 FROM spaces WHERE space_id = ?1",
                params![space_id.to_string()],
                row_to_space_record,
            )
            .optional()
    }
}

pub struct DeviceRepository<'a> {
    connection: &'a Connection,
}

impl<'a> DeviceRepository<'a> {
    pub fn new(connection: &'a Connection) -> Self {
        Self { connection }
    }

    pub fn upsert(&self, record: &DeviceRecord) -> rusqlite::Result<()> {
        self.connection.execute(
            "INSERT INTO devices(
              device_id, space_id, display_name, identity_public_key, trust_state,
              connection_state, paired_at, last_seen_at, revoked_at
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
            ON CONFLICT(device_id) DO UPDATE SET
              display_name = excluded.display_name,
              identity_public_key = excluded.identity_public_key,
              trust_state = excluded.trust_state,
              connection_state = excluded.connection_state,
              last_seen_at = excluded.last_seen_at,
              revoked_at = excluded.revoked_at",
            params![
                record.device.device_id.to_string(),
                record.device.space_id.to_string(),
                record.device.display_name,
                record.device.identity_public_key_ref,
                trust_state_to_db(record.device.trust_state),
                connection_state_to_db(record.device.connection_state),
                option_u64_to_i64(record.paired_at)?,
                option_u64_to_i64(record.device.last_seen_at)?,
                option_u64_to_i64(record.revoked_at)?,
            ],
        )?;
        Ok(())
    }

    pub fn get(&self, device_id: Uuid) -> rusqlite::Result<Option<DeviceRecord>> {
        self.connection
            .query_row(
                "SELECT device_id, space_id, display_name, identity_public_key, trust_state,
                  connection_state, paired_at, last_seen_at, revoked_at
                 FROM devices WHERE device_id = ?1",
                params![device_id.to_string()],
                row_to_device_record,
            )
            .optional()
    }

    pub fn list_by_space(&self, space_id: Uuid) -> rusqlite::Result<Vec<DeviceRecord>> {
        let mut statement = self.connection.prepare(
            "SELECT device_id, space_id, display_name, identity_public_key, trust_state,
              connection_state, paired_at, last_seen_at, revoked_at
             FROM devices WHERE space_id = ?1 ORDER BY display_name, device_id",
        )?;
        let records = statement
            .query_map(params![space_id.to_string()], row_to_device_record)?
            .collect();
        records
    }
}

pub struct ClipboardRepository<'a> {
    connection: &'a Connection,
}

impl<'a> ClipboardRepository<'a> {
    pub fn new(connection: &'a Connection) -> Self {
        Self { connection }
    }

    pub fn insert(&self, record: &ClipboardItemRecord) -> rusqlite::Result<bool> {
        let affected = self.connection.execute(
            "INSERT OR IGNORE INTO clipboard_items(
              item_id, space_id, origin_device_id, origin_seq, hlc, content_type,
              content_length, content_digest, encrypted_content, created_at, received_at, expires_at, deleted_at
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13)",
            params![
                record.item.item_id.to_string(),
                record.item.space_id.to_string(),
                record.item.origin_device_id.to_string(),
                u64_to_i64(record.item.origin_seq)?,
                record.item.hlc.to_wire(),
                record.item.content_type.wire_value(),
                usize_to_i64(record.item.content_length)?,
                record.item.content_digest,
                record.encrypted_content,
                u64_to_i64(record.item.created_at)?,
                u64_to_i64(record.received_at)?,
                u64_to_i64(record.expires_at)?,
                option_u64_to_i64(record.deleted_at)?,
            ],
        )?;
        Ok(affected == 1)
    }

    pub fn get(&self, item_id: Uuid) -> rusqlite::Result<Option<ClipboardItemRecord>> {
        self.connection
            .query_row(
                "SELECT item_id, space_id, origin_device_id, origin_seq, hlc, content_type,
                  content_length, content_digest, encrypted_content, created_at, received_at, expires_at, deleted_at
                 FROM clipboard_items WHERE item_id = ?1",
                params![item_id.to_string()],
                row_to_clipboard_record,
            )
            .optional()
    }

    pub fn list_recent(
        &self,
        space_id: Uuid,
        limit: u16,
    ) -> rusqlite::Result<Vec<ClipboardItemRecord>> {
        let mut statement = self.connection.prepare(
            "SELECT item_id, space_id, origin_device_id, origin_seq, hlc, content_type,
              content_length, content_digest, encrypted_content, created_at, received_at, expires_at, deleted_at
             FROM clipboard_items
             WHERE space_id = ?1 AND deleted_at IS NULL
             ORDER BY hlc DESC, item_id DESC
             LIMIT ?2",
        )?;
        let records = statement
            .query_map(
                params![space_id.to_string(), i64::from(limit)],
                row_to_clipboard_record,
            )?
            .collect();
        records
    }

    pub fn mark_deleted(&self, item_id: Uuid, deleted_at: u64) -> rusqlite::Result<bool> {
        let affected = self.connection.execute(
            "UPDATE clipboard_items SET deleted_at = ?2
             WHERE item_id = ?1 AND deleted_at IS NULL",
            params![item_id.to_string(), u64_to_i64(deleted_at)?],
        )?;
        Ok(affected == 1)
    }

    pub fn clear_history(&self, space_id: Uuid, deleted_at: u64) -> rusqlite::Result<usize> {
        self.connection.execute(
            "UPDATE clipboard_items SET deleted_at = ?2
             WHERE space_id = ?1 AND deleted_at IS NULL",
            params![space_id.to_string(), u64_to_i64(deleted_at)?],
        )
    }

    pub fn apply_retention(
        &self,
        space_id: Uuid,
        settings: &AppSettings,
        now_ms: u64,
    ) -> rusqlite::Result<RetentionCleanupResult> {
        settings
            .validate()
            .map_err(|error| rusqlite::Error::ToSqlConversionFailure(Box::new(error)))?;
        if !settings.history_enabled || settings.history_limit == 0 {
            let cleared = self.clear_history(space_id, now_ms)?;
            return Ok(RetentionCleanupResult {
                expired_items: 0,
                overflow_items: cleared,
            });
        }

        let expired_items = self.connection.execute(
            "UPDATE clipboard_items SET deleted_at = ?2
             WHERE space_id = ?1 AND deleted_at IS NULL AND expires_at <= ?2",
            params![space_id.to_string(), u64_to_i64(now_ms)?],
        )?;
        let overflow_items = self.connection.execute(
            "UPDATE clipboard_items SET deleted_at = ?3
             WHERE space_id = ?1 AND deleted_at IS NULL AND item_id IN (
               SELECT item_id FROM clipboard_items
               WHERE space_id = ?1 AND deleted_at IS NULL
               ORDER BY hlc DESC, item_id DESC
               LIMIT -1 OFFSET ?2
             )",
            params![
                space_id.to_string(),
                i64::from(settings.history_limit),
                u64_to_i64(now_ms)?,
            ],
        )?;
        Ok(RetentionCleanupResult {
            expired_items,
            overflow_items,
        })
    }

    pub fn active_count(&self, space_id: Uuid) -> rusqlite::Result<usize> {
        let count: i64 = self.connection.query_row(
            "SELECT COUNT(*) FROM clipboard_items
             WHERE space_id = ?1 AND deleted_at IS NULL",
            params![space_id.to_string()],
            |row| row.get(0),
        )?;
        i64_to_usize(count, 0)
    }
}

pub struct SyncHeadRepository<'a> {
    connection: &'a Connection,
}

impl<'a> SyncHeadRepository<'a> {
    pub fn new(connection: &'a Connection) -> Self {
        Self { connection }
    }

    pub fn upsert(&self, record: &SyncHeadRecord) -> rusqlite::Result<()> {
        self.connection.execute(
            "INSERT INTO sync_heads(
              space_id, peer_device_id, origin_device_id, highest_origin_seq, minimum_available, updated_at
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6)
            ON CONFLICT(space_id, peer_device_id, origin_device_id) DO UPDATE SET
              highest_origin_seq = excluded.highest_origin_seq,
              minimum_available = excluded.minimum_available,
              updated_at = excluded.updated_at",
            params![
                record.head.space_id.to_string(),
                record.peer_device_id.to_string(),
                record.head.origin_device_id.to_string(),
                u64_to_i64(record.head.latest_origin_seq)?,
                u64_to_i64(record.head.minimum_available)?,
                u64_to_i64(record.head.updated_at)?,
            ],
        )?;
        Ok(())
    }

    pub fn list_for_peer(
        &self,
        space_id: Uuid,
        peer_device_id: Uuid,
    ) -> rusqlite::Result<Vec<SyncHeadRecord>> {
        let mut statement = self.connection.prepare(
            "SELECT space_id, peer_device_id, origin_device_id, highest_origin_seq, minimum_available, updated_at
             FROM sync_heads WHERE space_id = ?1 AND peer_device_id = ?2
             ORDER BY origin_device_id",
        )?;
        let records = statement
            .query_map(
                params![space_id.to_string(), peer_device_id.to_string()],
                row_to_sync_head_record,
            )?
            .collect();
        records
    }
}

pub struct SettingsRepository<'a> {
    connection: &'a Connection,
}

impl<'a> SettingsRepository<'a> {
    pub fn new(connection: &'a Connection) -> Self {
        Self { connection }
    }

    pub fn save_app_settings(
        &self,
        settings: &AppSettings,
        updated_at: u64,
    ) -> rusqlite::Result<()> {
        settings
            .validate()
            .map_err(|error| rusqlite::Error::ToSqlConversionFailure(Box::new(error)))?;
        let value = serde_json::to_string(settings)
            .map_err(|error| rusqlite::Error::ToSqlConversionFailure(Box::new(error)))?;
        self.set("appSettings", &value, updated_at)
    }

    pub fn load_app_settings(&self) -> rusqlite::Result<Option<AppSettings>> {
        let Some(value) = self.get("appSettings")? else {
            return Ok(None);
        };
        serde_json::from_str(&value).map(Some).map_err(|error| {
            rusqlite::Error::FromSqlConversionFailure(0, Type::Text, Box::new(error))
        })
    }

    pub fn set(&self, key: &str, value: &str, updated_at: u64) -> rusqlite::Result<()> {
        self.connection.execute(
            "INSERT INTO app_metadata(key, value, updated_at) VALUES (?1, ?2, ?3)
             ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at",
            params![key, value, u64_to_i64(updated_at)?],
        )?;
        Ok(())
    }

    pub fn get(&self, key: &str) -> rusqlite::Result<Option<String>> {
        self.connection
            .query_row(
                "SELECT value FROM app_metadata WHERE key = ?1",
                params![key],
                |row| row.get(0),
            )
            .optional()
    }
}

fn row_to_space_record(row: &rusqlite::Row<'_>) -> rusqlite::Result<SpaceRecord> {
    Ok(SpaceRecord {
        space: Space {
            space_id: parse_uuid(row.get::<_, String>(0)?, 0)?,
            display_name: row.get(1)?,
            key_version: row.get::<_, i64>(3)?.try_into().map_err(|_| int_error(3))?,
            state: db_to_space_state(row.get::<_, String>(4)?, 4)?,
            created_at: i64_to_u64(row.get(5)?, 5)?,
        },
        encrypted_space_key_ref: row.get(2)?,
        updated_at: i64_to_u64(row.get(6)?, 6)?,
    })
}

fn row_to_device_record(row: &rusqlite::Row<'_>) -> rusqlite::Result<DeviceRecord> {
    Ok(DeviceRecord {
        device: Device {
            device_id: parse_uuid(row.get::<_, String>(0)?, 0)?,
            space_id: parse_uuid(row.get::<_, String>(1)?, 1)?,
            display_name: row.get(2)?,
            identity_public_key_ref: row.get(3)?,
            trust_state: db_to_trust_state(row.get::<_, String>(4)?, 4)?,
            connection_state: db_to_connection_state(row.get::<_, String>(5)?, 5)?,
            last_seen_at: option_i64_to_u64(row.get(7)?, 7)?,
        },
        paired_at: option_i64_to_u64(row.get(6)?, 6)?,
        revoked_at: option_i64_to_u64(row.get(8)?, 8)?,
    })
}

fn row_to_clipboard_record(row: &rusqlite::Row<'_>) -> rusqlite::Result<ClipboardItemRecord> {
    Ok(ClipboardItemRecord {
        item: ClipboardItem {
            item_id: parse_uuid(row.get::<_, String>(0)?, 0)?,
            space_id: parse_uuid(row.get::<_, String>(1)?, 1)?,
            origin_device_id: parse_uuid(row.get::<_, String>(2)?, 2)?,
            origin_seq: i64_to_u64(row.get(3)?, 3)?,
            hlc: parse_hlc(row.get::<_, String>(4)?, 4)?,
            content_type: db_to_content_type(row.get::<_, String>(5)?, 5)?,
            content_length: i64_to_usize(row.get(6)?, 6)?,
            content_digest: row.get(7)?,
            created_at: i64_to_u64(row.get(9)?, 9)?,
            encrypted_content_ref: None,
            plaintext: None,
        },
        encrypted_content: row.get(8)?,
        received_at: i64_to_u64(row.get(10)?, 10)?,
        expires_at: i64_to_u64(row.get(11)?, 11)?,
        deleted_at: option_i64_to_u64(row.get(12)?, 12)?,
    })
}

fn row_to_sync_head_record(row: &rusqlite::Row<'_>) -> rusqlite::Result<SyncHeadRecord> {
    Ok(SyncHeadRecord {
        head: SyncHead {
            space_id: parse_uuid(row.get::<_, String>(0)?, 0)?,
            origin_device_id: parse_uuid(row.get::<_, String>(2)?, 2)?,
            latest_origin_seq: i64_to_u64(row.get(3)?, 3)?,
            minimum_available: i64_to_u64(row.get(4)?, 4)?,
            updated_at: i64_to_u64(row.get(5)?, 5)?,
        },
        peer_device_id: parse_uuid(row.get::<_, String>(1)?, 1)?,
    })
}

fn space_state_to_db(value: SpaceState) -> &'static str {
    match value {
        SpaceState::Active => "active",
        SpaceState::RotatingKey => "rotatingKey",
        SpaceState::Archived => "archived",
    }
}

fn db_to_space_state(value: String, column: usize) -> rusqlite::Result<SpaceState> {
    match value.as_str() {
        "active" => Ok(SpaceState::Active),
        "rotatingKey" => Ok(SpaceState::RotatingKey),
        "archived" => Ok(SpaceState::Archived),
        _ => Err(text_error(column, "invalid space state")),
    }
}

fn trust_state_to_db(value: DeviceTrustState) -> &'static str {
    match value {
        DeviceTrustState::Trusted => "trusted",
        DeviceTrustState::Revoked => "revoked",
    }
}

fn db_to_trust_state(value: String, column: usize) -> rusqlite::Result<DeviceTrustState> {
    match value.as_str() {
        "trusted" => Ok(DeviceTrustState::Trusted),
        "revoked" => Ok(DeviceTrustState::Revoked),
        _ => Err(text_error(column, "invalid trust state")),
    }
}

fn connection_state_to_db(value: DeviceConnectionState) -> &'static str {
    match value {
        DeviceConnectionState::Offline => "offline",
        DeviceConnectionState::Connecting => "connecting",
        DeviceConnectionState::Online => "online",
        DeviceConnectionState::AuthFailed => "authFailed",
    }
}

fn db_to_connection_state(value: String, column: usize) -> rusqlite::Result<DeviceConnectionState> {
    match value.as_str() {
        "offline" => Ok(DeviceConnectionState::Offline),
        "connecting" => Ok(DeviceConnectionState::Connecting),
        "online" => Ok(DeviceConnectionState::Online),
        "authFailed" => Ok(DeviceConnectionState::AuthFailed),
        _ => Err(text_error(column, "invalid connection state")),
    }
}

fn db_to_content_type(value: String, column: usize) -> rusqlite::Result<ContentType> {
    match value.as_str() {
        "text/plain" => Ok(ContentType::TextPlain),
        _ => Err(text_error(column, "invalid content type")),
    }
}

fn parse_uuid(value: String, column: usize) -> rusqlite::Result<Uuid> {
    Uuid::parse_str(&value).map_err(|error| {
        rusqlite::Error::FromSqlConversionFailure(column, Type::Text, Box::new(error))
    })
}

fn parse_hlc(value: String, column: usize) -> rusqlite::Result<HlcTimestamp> {
    HlcTimestamp::from_wire(&value).ok_or_else(|| text_error(column, "invalid HLC timestamp"))
}

fn u64_to_i64(value: u64) -> rusqlite::Result<i64> {
    value.try_into().map_err(|_| int_error(0))
}

fn usize_to_i64(value: usize) -> rusqlite::Result<i64> {
    value.try_into().map_err(|_| int_error(0))
}

fn option_u64_to_i64(value: Option<u64>) -> rusqlite::Result<Option<i64>> {
    value.map(u64_to_i64).transpose()
}

fn i64_to_u64(value: i64, column: usize) -> rusqlite::Result<u64> {
    value.try_into().map_err(|_| int_error(column))
}

fn i64_to_usize(value: i64, column: usize) -> rusqlite::Result<usize> {
    value.try_into().map_err(|_| int_error(column))
}

fn option_i64_to_u64(value: Option<i64>, column: usize) -> rusqlite::Result<Option<u64>> {
    value.map(|value| i64_to_u64(value, column)).transpose()
}

fn int_error(column: usize) -> rusqlite::Error {
    rusqlite::Error::IntegralValueOutOfRange(column, i64::MAX)
}

fn text_error(column: usize, message: &'static str) -> rusqlite::Error {
    rusqlite::Error::FromSqlConversionFailure(column, Type::Text, message.into())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        storage::open_in_memory_database,
        sync::{build_local_clipboard_item, HlcTimestamp, LocalClipboardItemInput},
    };

    fn seed_space_and_devices(connection: &Connection) -> rusqlite::Result<(Uuid, Uuid, Uuid)> {
        let space_id = Uuid::now_v7();
        let local_device_id = Uuid::now_v7();
        let peer_device_id = Uuid::now_v7();
        let spaces = SpaceRepository::new(connection);
        let devices = DeviceRepository::new(connection);

        spaces.upsert(&SpaceRecord {
            space: Space {
                space_id,
                display_name: "默认空间".to_string(),
                key_version: 1,
                state: SpaceState::Active,
                created_at: 1_700_000_000_000,
            },
            encrypted_space_key_ref: Some("credential://space-key".to_string()),
            updated_at: 1_700_000_000_000,
        })?;

        for (device_id, display_name) in
            [(local_device_id, "Windows"), (peer_device_id, "HarmonyOS")]
        {
            devices.upsert(&DeviceRecord {
                device: Device {
                    device_id,
                    space_id,
                    display_name: display_name.to_string(),
                    identity_public_key_ref: format!("identity://{device_id}"),
                    trust_state: DeviceTrustState::Trusted,
                    connection_state: DeviceConnectionState::Offline,
                    last_seen_at: None,
                },
                paired_at: Some(1_700_000_000_000),
                revoked_at: None,
            })?;
        }
        Ok((space_id, local_device_id, peer_device_id))
    }

    #[test]
    fn repositories_round_trip_space_device_item_and_sync_head() {
        let connection = open_in_memory_database().expect("database should initialize");
        let (space_id, local_device_id, peer_device_id) =
            seed_space_and_devices(&connection).expect("seed should succeed");

        let spaces = SpaceRepository::new(&connection);
        let devices = DeviceRepository::new(&connection);
        let clipboard = ClipboardRepository::new(&connection);
        let sync_heads = SyncHeadRepository::new(&connection);

        let space = spaces
            .get(space_id)
            .expect("space query should succeed")
            .expect("space should exist");
        assert_eq!(space.space.display_name, "默认空间");
        assert_eq!(
            space.encrypted_space_key_ref.as_deref(),
            Some("credential://space-key")
        );

        let device = devices
            .get(local_device_id)
            .expect("device query should succeed")
            .expect("device should exist");
        assert_eq!(
            device.device.connection_state,
            DeviceConnectionState::Offline
        );
        assert_eq!(devices.list_by_space(space_id).unwrap().len(), 2);

        let item = build_local_clipboard_item(
            LocalClipboardItemInput {
                item_id: Uuid::now_v7(),
                space_id,
                origin_device_id: local_device_id,
                origin_seq: 1,
                hlc: HlcTimestamp::new(1_700_000_000_100, 0),
                created_at: 1_700_000_000_100,
                hmac_key: b"space-key-for-tests",
            },
            "蛋定 Clip".to_string(),
        )
        .expect("item should build");
        let record = ClipboardItemRecord {
            item: item.clone(),
            encrypted_content: vec![1, 2, 3],
            received_at: 1_700_000_000_100,
            expires_at: 1_700_604_800_100,
            deleted_at: None,
        };

        assert!(clipboard.insert(&record).expect("insert should succeed"));
        assert!(!clipboard
            .insert(&record)
            .expect("duplicate should be ignored"));
        let stored = clipboard
            .get(item.item_id)
            .expect("item query should succeed")
            .expect("item should exist");
        assert_eq!(stored.item.plaintext, None);
        assert_eq!(stored.item.content_digest, item.content_digest);
        assert_eq!(stored.encrypted_content, vec![1, 2, 3]);
        assert_eq!(clipboard.list_recent(space_id, 10).unwrap().len(), 1);

        sync_heads
            .upsert(&SyncHeadRecord {
                peer_device_id,
                head: SyncHead {
                    space_id,
                    origin_device_id: local_device_id,
                    latest_origin_seq: 1,
                    minimum_available: 1,
                    updated_at: 1_700_000_000_200,
                },
            })
            .expect("sync head upsert should succeed");
        let heads = sync_heads
            .list_for_peer(space_id, peer_device_id)
            .expect("sync head query should succeed");
        assert_eq!(heads.len(), 1);
        assert_eq!(heads[0].head.latest_origin_seq, 1);
    }

    #[test]
    fn clipboard_repository_hides_deleted_items_from_recent_list() {
        let connection = open_in_memory_database().expect("database should initialize");
        let (space_id, local_device_id, _) =
            seed_space_and_devices(&connection).expect("seed should succeed");
        let clipboard = ClipboardRepository::new(&connection);

        let item = build_local_clipboard_item(
            LocalClipboardItemInput {
                item_id: Uuid::now_v7(),
                space_id,
                origin_device_id: local_device_id,
                origin_seq: 1,
                hlc: HlcTimestamp::new(1_700_000_000_100, 0),
                created_at: 1_700_000_000_100,
                hmac_key: b"space-key-for-tests",
            },
            "to delete".to_string(),
        )
        .expect("item should build");
        clipboard
            .insert(&ClipboardItemRecord {
                item: item.clone(),
                encrypted_content: vec![9],
                received_at: 1_700_000_000_100,
                expires_at: 1_700_604_800_100,
                deleted_at: None,
            })
            .expect("insert should succeed");

        assert_eq!(clipboard.list_recent(space_id, 10).unwrap().len(), 1);
        assert!(clipboard
            .mark_deleted(item.item_id, 1_700_000_001_000)
            .expect("delete should succeed"));
        assert!(clipboard.list_recent(space_id, 10).unwrap().is_empty());
        let stored = clipboard
            .get(item.item_id)
            .expect("item query should succeed")
            .expect("item should still exist logically");
        assert_eq!(stored.deleted_at, Some(1_700_000_001_000));
    }

    #[test]
    fn clipboard_repository_applies_count_and_age_retention_idempotently() {
        let connection = open_in_memory_database().expect("database should initialize");
        let (space_id, local_device_id, _) =
            seed_space_and_devices(&connection).expect("seed should succeed");
        let clipboard = ClipboardRepository::new(&connection);
        let now_ms = 1_700_604_800_000;

        for seq in 1..=22 {
            let created_at = now_ms - ((23 - seq) * 1_000);
            let expires_at = if seq == 1 {
                now_ms - 1
            } else {
                now_ms + 60_000
            };
            let item = build_local_clipboard_item(
                LocalClipboardItemInput {
                    item_id: Uuid::now_v7(),
                    space_id,
                    origin_device_id: local_device_id,
                    origin_seq: seq,
                    hlc: HlcTimestamp::new(created_at, 0),
                    created_at,
                    hmac_key: b"space-key-for-tests",
                },
                format!("item {seq}"),
            )
            .expect("item should build");
            clipboard
                .insert(&ClipboardItemRecord {
                    item,
                    encrypted_content: vec![seq as u8],
                    received_at: created_at,
                    expires_at,
                    deleted_at: None,
                })
                .expect("insert should succeed");
        }

        let settings = AppSettings {
            history_limit: 20,
            ..AppSettings::default()
        };
        let result = clipboard
            .apply_retention(space_id, &settings, now_ms)
            .expect("retention should succeed");
        assert_eq!(
            result,
            RetentionCleanupResult {
                expired_items: 1,
                overflow_items: 1,
            }
        );
        assert_eq!(clipboard.active_count(space_id), Ok(20));
        let recent = clipboard.list_recent(space_id, 10).unwrap();
        assert_eq!(
            recent.first().map(|record| record.item.origin_seq),
            Some(22)
        );
        assert_eq!(recent.last().map(|record| record.item.origin_seq), Some(13));

        let second = clipboard
            .apply_retention(space_id, &settings, now_ms)
            .expect("retention should be idempotent");
        assert_eq!(second.total(), 0);
        assert_eq!(clipboard.active_count(space_id), Ok(20));
    }

    #[test]
    fn clipboard_repository_supports_zero_history_and_clear_history() {
        let connection = open_in_memory_database().expect("database should initialize");
        let (space_id, local_device_id, _) =
            seed_space_and_devices(&connection).expect("seed should succeed");
        let clipboard = ClipboardRepository::new(&connection);

        for seq in 1..=2 {
            let item = build_local_clipboard_item(
                LocalClipboardItemInput {
                    item_id: Uuid::now_v7(),
                    space_id,
                    origin_device_id: local_device_id,
                    origin_seq: seq,
                    hlc: HlcTimestamp::new(1_700_000_000_000 + seq, 0),
                    created_at: 1_700_000_000_000 + seq,
                    hmac_key: b"space-key-for-tests",
                },
                format!("item {seq}"),
            )
            .expect("item should build");
            clipboard
                .insert(&ClipboardItemRecord {
                    item,
                    encrypted_content: vec![seq as u8],
                    received_at: 1_700_000_000_000 + seq,
                    expires_at: 1_700_604_800_000,
                    deleted_at: None,
                })
                .expect("insert should succeed");
        }

        let zero_history = AppSettings {
            history_limit: 0,
            ..AppSettings::default()
        };
        let result = clipboard
            .apply_retention(space_id, &zero_history, 1_700_000_001_000)
            .expect("zero-history retention should succeed");
        assert_eq!(result.overflow_items, 2);
        assert_eq!(clipboard.active_count(space_id), Ok(0));

        assert_eq!(
            clipboard
                .clear_history(space_id, 1_700_000_002_000)
                .expect("clear should be idempotent"),
            0
        );
    }

    #[test]
    fn settings_repository_round_trips_app_settings() {
        let connection = open_in_memory_database().expect("database should initialize");
        let settings_repo = SettingsRepository::new(&connection);
        let settings = AppSettings {
            history_limit: 20,
            auto_write_enabled: false,
            ..AppSettings::default()
        };

        assert_eq!(
            settings_repo.load_app_settings().unwrap(),
            None,
            "fresh database should not have app settings"
        );
        settings_repo
            .save_app_settings(&settings, 1_700_000_000_000)
            .expect("settings should save");
        assert_eq!(settings_repo.load_app_settings().unwrap(), Some(settings));
    }
}
