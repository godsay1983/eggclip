use rusqlite::{params, types::Type, Connection, OptionalExtension};
use uuid::Uuid;

use crate::sync::{
    broadcast_local_clipboard_after_commit, build_local_clipboard_item, deduplicate_clipboard_item,
    new_uuid_v7, AppSettings, ClipboardDedupDecision, ClipboardItem, ContentType, Device,
    DeviceConnectionState, DeviceTrustState, HlcTimestamp, LocalClipboardBroadcastOutcome,
    LocalClipboardBroadcaster, LocalClipboardItemInput, Space, SpaceState, SyncHead,
    SyncModelError,
};

pub const LOCAL_DEVICE_ID_KEY: &str = "localDeviceId";
pub const NEXT_ORIGIN_SEQ_KEY: &str = "nextOriginSeq";
pub const INITIAL_ORIGIN_SEQ: u64 = 1;
const MILLIS_PER_DAY: u64 = 24 * 60 * 60 * 1_000;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SpaceRecord {
    pub space: Space,
    pub encrypted_space_key_ref: Option<String>,
    pub updated_at: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PairingInvitationState {
    Active,
    Consumed,
    Expired,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PairingInvitationRecord {
    pub invitation_id: Uuid,
    pub space_id: Uuid,
    pub issuer_device_id: Uuid,
    pub secret_verifier: String,
    pub state: PairingInvitationState,
    pub created_at: u64,
    pub expires_at: u64,
    pub consumed_at: Option<u64>,
    pub consumed_by_device_id: Option<Uuid>,
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
pub enum ClipboardInsertOutcome {
    Inserted,
    Duplicate,
    Conflict,
}

#[derive(Debug, Clone)]
pub struct LocalClipboardPersistInput<'a> {
    pub space_id: Uuid,
    pub text: String,
    pub encrypted_content: Vec<u8>,
    pub hmac_key: &'a [u8],
    pub settings: AppSettings,
    pub now_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LocalClipboardPersistResult {
    pub record: ClipboardItemRecord,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LocalClipboardPersistAndBroadcastResult {
    pub record: ClipboardItemRecord,
    pub broadcast_outcome: LocalClipboardBroadcastOutcome,
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

/// Persists a local clipboard write as an immutable item in one database transaction.
///
/// This boundary deliberately does not send network frames. Callers may broadcast
/// `record.item` only after this function returns successfully, so transport
/// failures cannot roll back the local history record or origin sequence.
pub fn persist_local_clipboard_text(
    connection: &mut Connection,
    input: LocalClipboardPersistInput<'_>,
) -> rusqlite::Result<LocalClipboardPersistResult> {
    input
        .settings
        .validate()
        .map_err(|error| rusqlite::Error::ToSqlConversionFailure(Box::new(error)))?;

    let expires_at = retention_expires_at(input.now_ms, input.settings.retention_days)?;
    let transaction = connection.transaction()?;
    let origin_device_id = get_or_create_device_id_in_transaction(&transaction, input.now_ms)?;
    let origin_seq = allocate_origin_seq_in_transaction(&transaction, input.now_ms)?;
    let item = build_local_clipboard_item(
        LocalClipboardItemInput {
            item_id: new_uuid_v7(),
            space_id: input.space_id,
            origin_device_id,
            origin_seq,
            hlc: HlcTimestamp::new(input.now_ms, 0),
            created_at: input.now_ms,
            hmac_key: input.hmac_key,
        },
        input.text,
    )
    .map_err(|error| rusqlite::Error::ToSqlConversionFailure(Box::new(error)))?;
    let record = ClipboardItemRecord {
        item,
        encrypted_content: input.encrypted_content,
        received_at: input.now_ms,
        expires_at,
        deleted_at: None,
    };

    transaction.execute(
        "INSERT INTO clipboard_items(
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
    transaction.commit()?;

    Ok(LocalClipboardPersistResult { record })
}

/// Persists local clipboard content first, then attempts best-effort live broadcast.
///
/// The broadcaster is invoked only after the SQLite transaction has committed.
/// Its failure is reported as status and never rolls back the local immutable item.
pub fn persist_local_clipboard_text_then_broadcast<B>(
    connection: &mut Connection,
    input: LocalClipboardPersistInput<'_>,
    broadcaster: &mut B,
) -> rusqlite::Result<LocalClipboardPersistAndBroadcastResult>
where
    B: LocalClipboardBroadcaster<ClipboardItemRecord>,
{
    let settings = input.settings.clone();
    let result = persist_local_clipboard_text(connection, input)?;
    let broadcast_outcome =
        broadcast_local_clipboard_after_commit(&result.record, &settings, broadcaster);

    Ok(LocalClipboardPersistAndBroadcastResult {
        record: result.record,
        broadcast_outcome,
    })
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

    pub fn list(&self) -> rusqlite::Result<Vec<SpaceRecord>> {
        let mut statement = self.connection.prepare(
            "SELECT space_id, display_name, encrypted_space_key_ref, key_version, state, created_at, updated_at
             FROM spaces ORDER BY created_at DESC, space_id DESC",
        )?;
        let records = statement.query_map([], row_to_space_record)?.collect();
        records
    }
}

pub struct PairingInvitationRepository<'a> {
    connection: &'a Connection,
}

impl<'a> PairingInvitationRepository<'a> {
    pub fn new(connection: &'a Connection) -> Self {
        Self { connection }
    }

    pub fn insert(&self, record: &PairingInvitationRecord) -> rusqlite::Result<()> {
        self.connection.execute(
            "INSERT INTO pairing_invitations(
              invitation_id, space_id, issuer_device_id, secret_verifier, state,
              created_at, expires_at, consumed_at, consumed_by_device_id
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
            params![
                record.invitation_id.to_string(),
                record.space_id.to_string(),
                record.issuer_device_id.to_string(),
                record.secret_verifier,
                pairing_invitation_state_to_db(record.state),
                u64_to_i64(record.created_at)?,
                u64_to_i64(record.expires_at)?,
                option_u64_to_i64(record.consumed_at)?,
                record
                    .consumed_by_device_id
                    .map(|device_id| device_id.to_string()),
            ],
        )?;
        Ok(())
    }

    pub fn get(&self, invitation_id: Uuid) -> rusqlite::Result<Option<PairingInvitationRecord>> {
        self.connection
            .query_row(
                "SELECT invitation_id, space_id, issuer_device_id, secret_verifier, state,
                  created_at, expires_at, consumed_at, consumed_by_device_id
                 FROM pairing_invitations WHERE invitation_id = ?1",
                params![invitation_id.to_string()],
                row_to_pairing_invitation_record,
            )
            .optional()
    }

    pub fn list_active_by_space(
        &self,
        space_id: Uuid,
        now_ms: u64,
    ) -> rusqlite::Result<Vec<PairingInvitationRecord>> {
        let mut statement = self.connection.prepare(
            "SELECT invitation_id, space_id, issuer_device_id, secret_verifier, state,
              created_at, expires_at, consumed_at, consumed_by_device_id
             FROM pairing_invitations
             WHERE space_id = ?1 AND state = 'active' AND expires_at > ?2
             ORDER BY expires_at ASC, invitation_id ASC",
        )?;
        let records = statement
            .query_map(
                params![space_id.to_string(), u64_to_i64(now_ms)?],
                row_to_pairing_invitation_record,
            )?
            .collect();
        records
    }

    pub fn mark_consumed(
        &self,
        invitation_id: Uuid,
        consumed_by_device_id: Uuid,
        consumed_at: u64,
    ) -> rusqlite::Result<bool> {
        let changed = self.connection.execute(
            "UPDATE pairing_invitations
             SET state = 'consumed', consumed_at = ?2, consumed_by_device_id = ?3
             WHERE invitation_id = ?1 AND state = 'active'",
            params![
                invitation_id.to_string(),
                u64_to_i64(consumed_at)?,
                consumed_by_device_id.to_string(),
            ],
        )?;
        Ok(changed > 0)
    }

    pub fn expire_before(&self, now_ms: u64) -> rusqlite::Result<usize> {
        self.connection.execute(
            "UPDATE pairing_invitations
             SET state = 'expired'
             WHERE state = 'active' AND expires_at <= ?1",
            params![u64_to_i64(now_ms)?],
        )
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

    pub fn insert_deduplicated(
        &self,
        record: &ClipboardItemRecord,
    ) -> rusqlite::Result<ClipboardInsertOutcome> {
        if let Some(existing) = self.get(record.item.item_id)? {
            return Ok(dedup_decision_to_insert_outcome(
                deduplicate_clipboard_item(&existing.item, &record.item),
            ));
        }
        if let Some(existing) =
            self.get_by_origin_sequence(record.item.origin_device_id, record.item.origin_seq)?
        {
            return Ok(dedup_decision_to_insert_outcome(
                deduplicate_clipboard_item(&existing.item, &record.item),
            ));
        }

        if self.insert(record)? {
            return Ok(ClipboardInsertOutcome::Inserted);
        }

        if let Some(existing) = self.get(record.item.item_id)? {
            return Ok(dedup_decision_to_insert_outcome(
                deduplicate_clipboard_item(&existing.item, &record.item),
            ));
        }
        if let Some(existing) =
            self.get_by_origin_sequence(record.item.origin_device_id, record.item.origin_seq)?
        {
            return Ok(dedup_decision_to_insert_outcome(
                deduplicate_clipboard_item(&existing.item, &record.item),
            ));
        }
        Ok(ClipboardInsertOutcome::Duplicate)
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

    pub fn get_by_origin_sequence(
        &self,
        origin_device_id: Uuid,
        origin_seq: u64,
    ) -> rusqlite::Result<Option<ClipboardItemRecord>> {
        self.connection
            .query_row(
                "SELECT item_id, space_id, origin_device_id, origin_seq, hlc, content_type,
                  content_length, content_digest, encrypted_content, created_at, received_at, expires_at, deleted_at
                 FROM clipboard_items WHERE origin_device_id = ?1 AND origin_seq = ?2",
                params![origin_device_id.to_string(), u64_to_i64(origin_seq)?],
                row_to_clipboard_record,
            )
            .optional()
    }

    pub fn summarize_available_sequences(
        &self,
        space_id: Uuid,
        updated_at: u64,
    ) -> rusqlite::Result<Vec<SyncHead>> {
        let mut statement = self.connection.prepare(
            "SELECT origin_device_id, MAX(origin_seq), MIN(origin_seq)
             FROM clipboard_items
             WHERE space_id = ?1 AND deleted_at IS NULL
             GROUP BY origin_device_id
             ORDER BY origin_device_id",
        )?;
        let heads = statement
            .query_map(params![space_id.to_string()], |row| {
                let origin_device_id: String = row.get(0)?;
                let latest_origin_seq: i64 = row.get(1)?;
                let minimum_available: i64 = row.get(2)?;
                Ok(SyncHead {
                    space_id,
                    origin_device_id: Uuid::parse_str(&origin_device_id).map_err(|error| {
                        rusqlite::Error::FromSqlConversionFailure(0, Type::Text, Box::new(error))
                    })?,
                    latest_origin_seq: i64_to_u64(latest_origin_seq, 1)?,
                    minimum_available: i64_to_u64(minimum_available, 2)?,
                    updated_at,
                })
            })?
            .collect();
        heads
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

    pub fn list_recent_all(&self, limit: u16) -> rusqlite::Result<Vec<ClipboardItemRecord>> {
        let mut statement = self.connection.prepare(
            "SELECT item_id, space_id, origin_device_id, origin_seq, hlc, content_type,
              content_length, content_digest, encrypted_content, created_at, received_at, expires_at, deleted_at
             FROM clipboard_items
             WHERE deleted_at IS NULL
             ORDER BY hlc DESC, item_id DESC
             LIMIT ?1",
        )?;
        let records = statement
            .query_map(params![i64::from(limit)], row_to_clipboard_record)?
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

    pub fn clear_all_history(&self, deleted_at: u64) -> rusqlite::Result<usize> {
        self.connection.execute(
            "UPDATE clipboard_items SET deleted_at = ?1
             WHERE deleted_at IS NULL",
            params![u64_to_i64(deleted_at)?],
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

    pub fn apply_global_retention(
        &self,
        settings: &AppSettings,
        now_ms: u64,
    ) -> rusqlite::Result<RetentionCleanupResult> {
        settings
            .validate()
            .map_err(|error| rusqlite::Error::ToSqlConversionFailure(Box::new(error)))?;
        if !settings.history_enabled || settings.history_limit == 0 {
            let cleared = self.clear_all_history(now_ms)?;
            return Ok(RetentionCleanupResult {
                expired_items: 0,
                overflow_items: cleared,
            });
        }

        let expired_items = self.connection.execute(
            "UPDATE clipboard_items SET deleted_at = ?1
             WHERE deleted_at IS NULL AND expires_at <= ?1",
            params![u64_to_i64(now_ms)?],
        )?;
        let overflow_items = self.connection.execute(
            "UPDATE clipboard_items SET deleted_at = ?2
             WHERE deleted_at IS NULL AND item_id IN (
               SELECT item_id FROM clipboard_items
               WHERE deleted_at IS NULL
               ORDER BY hlc DESC, item_id DESC
               LIMIT -1 OFFSET ?1
             )",
            params![i64::from(settings.history_limit), u64_to_i64(now_ms)?],
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

    pub fn active_count_all(&self) -> rusqlite::Result<usize> {
        let count: i64 = self.connection.query_row(
            "SELECT COUNT(*) FROM clipboard_items WHERE deleted_at IS NULL",
            [],
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

pub struct LocalIdentityRepository<'a> {
    connection: &'a mut Connection,
}

impl<'a> LocalIdentityRepository<'a> {
    pub fn new(connection: &'a mut Connection) -> Self {
        Self { connection }
    }

    pub fn get_or_create_device_id(&mut self, updated_at: u64) -> rusqlite::Result<Uuid> {
        let transaction = self.connection.transaction()?;
        let existing: Option<String> = transaction
            .query_row(
                "SELECT value FROM app_metadata WHERE key = ?1",
                params![LOCAL_DEVICE_ID_KEY],
                |row| row.get(0),
            )
            .optional()?;
        if let Some(value) = existing {
            transaction.commit()?;
            return parse_uuid(value, 0);
        }

        let device_id = Uuid::new_v4();
        transaction.execute(
            "INSERT INTO app_metadata(key, value, updated_at) VALUES (?1, ?2, ?3)",
            params![
                LOCAL_DEVICE_ID_KEY,
                device_id.to_string(),
                u64_to_i64(updated_at)?,
            ],
        )?;
        transaction.commit()?;
        Ok(device_id)
    }

    pub fn peek_next_origin_seq(&self) -> rusqlite::Result<u64> {
        let value = self
            .connection
            .query_row(
                "SELECT value FROM app_metadata WHERE key = ?1",
                params![NEXT_ORIGIN_SEQ_KEY],
                |row| row.get::<_, String>(0),
            )
            .optional()?;
        match value {
            Some(value) => parse_u64_metadata(&value, 0),
            None => Ok(INITIAL_ORIGIN_SEQ),
        }
    }

    pub fn allocate_origin_seq(&mut self, updated_at: u64) -> rusqlite::Result<u64> {
        let transaction = self.connection.transaction()?;
        transaction.execute(
            "INSERT OR IGNORE INTO app_metadata(key, value, updated_at) VALUES (?1, ?2, ?3)",
            params![
                NEXT_ORIGIN_SEQ_KEY,
                INITIAL_ORIGIN_SEQ.to_string(),
                u64_to_i64(updated_at)?,
            ],
        )?;
        let current_value: String = transaction.query_row(
            "SELECT value FROM app_metadata WHERE key = ?1",
            params![NEXT_ORIGIN_SEQ_KEY],
            |row| row.get(0),
        )?;
        let current = parse_u64_metadata(&current_value, 0)?;
        let next = current.checked_add(1).ok_or_else(|| {
            rusqlite::Error::ToSqlConversionFailure(Box::new(SyncModelError::SequenceOverflow))
        })?;
        transaction.execute(
            "UPDATE app_metadata SET value = ?2, updated_at = ?3 WHERE key = ?1",
            params![
                NEXT_ORIGIN_SEQ_KEY,
                next.to_string(),
                u64_to_i64(updated_at)?
            ],
        )?;
        transaction.commit()?;
        Ok(current)
    }
}

fn get_or_create_device_id_in_transaction(
    transaction: &rusqlite::Transaction<'_>,
    updated_at: u64,
) -> rusqlite::Result<Uuid> {
    let existing: Option<String> = transaction
        .query_row(
            "SELECT value FROM app_metadata WHERE key = ?1",
            params![LOCAL_DEVICE_ID_KEY],
            |row| row.get(0),
        )
        .optional()?;
    if let Some(value) = existing {
        return parse_uuid(value, 0);
    }

    let device_id = Uuid::new_v4();
    transaction.execute(
        "INSERT INTO app_metadata(key, value, updated_at) VALUES (?1, ?2, ?3)",
        params![
            LOCAL_DEVICE_ID_KEY,
            device_id.to_string(),
            u64_to_i64(updated_at)?,
        ],
    )?;
    Ok(device_id)
}

fn allocate_origin_seq_in_transaction(
    transaction: &rusqlite::Transaction<'_>,
    updated_at: u64,
) -> rusqlite::Result<u64> {
    transaction.execute(
        "INSERT OR IGNORE INTO app_metadata(key, value, updated_at) VALUES (?1, ?2, ?3)",
        params![
            NEXT_ORIGIN_SEQ_KEY,
            INITIAL_ORIGIN_SEQ.to_string(),
            u64_to_i64(updated_at)?,
        ],
    )?;
    let current_value: String = transaction.query_row(
        "SELECT value FROM app_metadata WHERE key = ?1",
        params![NEXT_ORIGIN_SEQ_KEY],
        |row| row.get(0),
    )?;
    let current = parse_u64_metadata(&current_value, 0)?;
    let next = current.checked_add(1).ok_or_else(|| {
        rusqlite::Error::ToSqlConversionFailure(Box::new(SyncModelError::SequenceOverflow))
    })?;
    transaction.execute(
        "UPDATE app_metadata SET value = ?2, updated_at = ?3 WHERE key = ?1",
        params![
            NEXT_ORIGIN_SEQ_KEY,
            next.to_string(),
            u64_to_i64(updated_at)?
        ],
    )?;
    Ok(current)
}

fn dedup_decision_to_insert_outcome(decision: ClipboardDedupDecision) -> ClipboardInsertOutcome {
    match decision {
        ClipboardDedupDecision::New => ClipboardInsertOutcome::Inserted,
        ClipboardDedupDecision::Duplicate => ClipboardInsertOutcome::Duplicate,
        ClipboardDedupDecision::Conflict => ClipboardInsertOutcome::Conflict,
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

fn row_to_pairing_invitation_record(
    row: &rusqlite::Row<'_>,
) -> rusqlite::Result<PairingInvitationRecord> {
    Ok(PairingInvitationRecord {
        invitation_id: parse_uuid(row.get::<_, String>(0)?, 0)?,
        space_id: parse_uuid(row.get::<_, String>(1)?, 1)?,
        issuer_device_id: parse_uuid(row.get::<_, String>(2)?, 2)?,
        secret_verifier: row.get(3)?,
        state: db_to_pairing_invitation_state(row.get::<_, String>(4)?, 4)?,
        created_at: i64_to_u64(row.get(5)?, 5)?,
        expires_at: i64_to_u64(row.get(6)?, 6)?,
        consumed_at: option_i64_to_u64(row.get(7)?, 7)?,
        consumed_by_device_id: row
            .get::<_, Option<String>>(8)?
            .map(|value| parse_uuid(value, 8))
            .transpose()?,
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

fn pairing_invitation_state_to_db(value: PairingInvitationState) -> &'static str {
    match value {
        PairingInvitationState::Active => "active",
        PairingInvitationState::Consumed => "consumed",
        PairingInvitationState::Expired => "expired",
    }
}

fn db_to_pairing_invitation_state(
    value: String,
    column: usize,
) -> rusqlite::Result<PairingInvitationState> {
    match value.as_str() {
        "active" => Ok(PairingInvitationState::Active),
        "consumed" => Ok(PairingInvitationState::Consumed),
        "expired" => Ok(PairingInvitationState::Expired),
        _ => Err(text_error(column, "invalid pairing invitation state")),
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

fn parse_u64_metadata(value: &str, column: usize) -> rusqlite::Result<u64> {
    value.parse::<u64>().map_err(|error| {
        rusqlite::Error::FromSqlConversionFailure(column, Type::Text, Box::new(error))
    })
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

pub(crate) fn retention_expires_at(created_at: u64, retention_days: u16) -> rusqlite::Result<u64> {
    let ttl_ms = u64::from(retention_days)
        .checked_mul(MILLIS_PER_DAY)
        .ok_or_else(|| {
            rusqlite::Error::ToSqlConversionFailure(Box::new(SyncModelError::SequenceOverflow))
        })?;
    created_at.checked_add(ttl_ms).ok_or_else(|| {
        rusqlite::Error::ToSqlConversionFailure(Box::new(SyncModelError::SequenceOverflow))
    })
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
        sync::{
            build_local_clipboard_item, HlcTimestamp, LocalClipboardBroadcastError,
            LocalClipboardItemInput, SyncPauseReason,
        },
    };

    struct RecordingBroadcaster {
        attempts: usize,
        fail: bool,
    }

    impl LocalClipboardBroadcaster<ClipboardItemRecord> for RecordingBroadcaster {
        fn broadcast_live_item(
            &mut self,
            _item: &ClipboardItemRecord,
        ) -> Result<(), LocalClipboardBroadcastError> {
            self.attempts += 1;
            if self.fail {
                Err(LocalClipboardBroadcastError)
            } else {
                Ok(())
            }
        }
    }

    fn seed_space_and_devices(connection: &Connection) -> rusqlite::Result<(Uuid, Uuid, Uuid)> {
        let space_id = Uuid::now_v7();
        let local_device_id = Uuid::now_v7();
        let peer_device_id = Uuid::now_v7();
        seed_space_with_devices(connection, space_id, local_device_id, peer_device_id)?;
        Ok((space_id, local_device_id, peer_device_id))
    }

    fn seed_space_with_devices(
        connection: &Connection,
        space_id: Uuid,
        local_device_id: Uuid,
        peer_device_id: Uuid,
    ) -> rusqlite::Result<()> {
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
        Ok(())
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
    fn pairing_invitation_repository_tracks_active_consumed_and_expired_states() {
        let connection = open_in_memory_database().expect("database should initialize");
        let (space_id, local_device_id, peer_device_id) =
            seed_space_and_devices(&connection).expect("seed should succeed");
        let invitations = PairingInvitationRepository::new(&connection);
        let invitation_id = Uuid::now_v7();

        invitations
            .insert(&PairingInvitationRecord {
                invitation_id,
                space_id,
                issuer_device_id: local_device_id,
                secret_verifier: "verifier-ref".to_string(),
                state: PairingInvitationState::Active,
                created_at: 1_700_000_000_000,
                expires_at: 1_700_000_300_000,
                consumed_at: None,
                consumed_by_device_id: None,
            })
            .expect("invitation should insert");

        assert_eq!(
            invitations
                .list_active_by_space(space_id, 1_700_000_100_000)
                .expect("active invitations should list")
                .len(),
            1
        );
        assert!(invitations
            .mark_consumed(invitation_id, peer_device_id, 1_700_000_100_001)
            .expect("invitation should be consumed"));
        assert!(!invitations
            .mark_consumed(invitation_id, peer_device_id, 1_700_000_100_002)
            .expect("consumed invitation should not be consumed twice"));
        let consumed = invitations
            .get(invitation_id)
            .expect("invitation should query")
            .expect("invitation should exist");
        assert_eq!(consumed.state, PairingInvitationState::Consumed);
        assert_eq!(consumed.consumed_by_device_id, Some(peer_device_id));

        let expired_id = Uuid::now_v7();
        invitations
            .insert(&PairingInvitationRecord {
                invitation_id: expired_id,
                space_id,
                issuer_device_id: local_device_id,
                secret_verifier: "expired-verifier-ref".to_string(),
                state: PairingInvitationState::Active,
                created_at: 1_700_000_000_000,
                expires_at: 1_700_000_050_000,
                consumed_at: None,
                consumed_by_device_id: None,
            })
            .expect("expired candidate should insert");
        assert_eq!(
            invitations
                .expire_before(1_700_000_050_000)
                .expect("expired invitation should update"),
            1
        );
        assert_eq!(
            invitations
                .get(expired_id)
                .expect("expired invitation should query")
                .expect("expired invitation should exist")
                .state,
            PairingInvitationState::Expired
        );
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
    fn clipboard_repository_reports_duplicate_and_conflicting_items() {
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
            "dedup".to_string(),
        )
        .expect("item should build");
        let record = ClipboardItemRecord {
            item: item.clone(),
            encrypted_content: vec![1],
            received_at: 1_700_000_000_100,
            expires_at: 1_700_604_800_100,
            deleted_at: None,
        };
        assert_eq!(
            clipboard.insert_deduplicated(&record),
            Ok(ClipboardInsertOutcome::Inserted)
        );
        assert_eq!(
            clipboard.insert_deduplicated(&record),
            Ok(ClipboardInsertOutcome::Duplicate)
        );

        let same_origin_same_digest = ClipboardItemRecord {
            item: ClipboardItem {
                item_id: Uuid::now_v7(),
                ..item.clone()
            },
            encrypted_content: vec![2],
            ..record.clone()
        };
        assert_eq!(
            clipboard.insert_deduplicated(&same_origin_same_digest),
            Ok(ClipboardInsertOutcome::Duplicate)
        );

        let conflicting_item = build_local_clipboard_item(
            LocalClipboardItemInput {
                item_id: Uuid::now_v7(),
                space_id,
                origin_device_id: local_device_id,
                origin_seq: 1,
                hlc: HlcTimestamp::new(1_700_000_000_101, 0),
                created_at: 1_700_000_000_101,
                hmac_key: b"space-key-for-tests",
            },
            "conflict".to_string(),
        )
        .expect("conflicting item should build");
        assert_eq!(
            clipboard.insert_deduplicated(&ClipboardItemRecord {
                item: conflicting_item,
                encrypted_content: vec![3],
                received_at: 1_700_000_000_101,
                expires_at: 1_700_604_800_101,
                deleted_at: None,
            }),
            Ok(ClipboardInsertOutcome::Conflict)
        );
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

    #[test]
    fn local_identity_repository_persists_device_id_and_origin_sequence() {
        let mut connection = open_in_memory_database().expect("database should initialize");
        let first_device_id = {
            let mut identity = LocalIdentityRepository::new(&mut connection);
            let first_device_id = identity
                .get_or_create_device_id(1_700_000_000_000)
                .expect("device id should be created");
            assert_eq!(first_device_id.get_version_num(), 4);
            assert_eq!(identity.peek_next_origin_seq(), Ok(INITIAL_ORIGIN_SEQ));
            assert_eq!(
                identity.allocate_origin_seq(1_700_000_000_001),
                Ok(INITIAL_ORIGIN_SEQ)
            );
            assert_eq!(identity.allocate_origin_seq(1_700_000_000_002), Ok(2));
            assert_eq!(identity.peek_next_origin_seq(), Ok(3));
            first_device_id
        };

        let mut identity = LocalIdentityRepository::new(&mut connection);
        let second_device_id = identity
            .get_or_create_device_id(1_700_000_000_003)
            .expect("device id should be reused");
        assert_eq!(second_device_id, first_device_id);
        assert_eq!(identity.allocate_origin_seq(1_700_000_000_004), Ok(3));
        assert_eq!(identity.peek_next_origin_seq(), Ok(4));
    }

    #[test]
    fn persist_local_clipboard_text_stores_item_and_advances_sequence_after_commit() {
        let mut connection = open_in_memory_database().expect("database should initialize");
        let now_ms = 1_700_000_000_000;
        let local_device_id = {
            let mut identity = LocalIdentityRepository::new(&mut connection);
            identity
                .get_or_create_device_id(now_ms)
                .expect("local device id should be created")
        };
        let space_id = Uuid::now_v7();
        let peer_device_id = Uuid::now_v7();
        seed_space_with_devices(&connection, space_id, local_device_id, peer_device_id)
            .expect("space and devices should seed");

        let result = persist_local_clipboard_text(
            &mut connection,
            LocalClipboardPersistInput {
                space_id,
                text: "本地复制".to_string(),
                encrypted_content: vec![0xAA, 0xBB, 0xCC],
                hmac_key: b"space-key-for-tests",
                settings: AppSettings::default(),
                now_ms,
            },
        )
        .expect("local clipboard item should persist");

        assert_eq!(result.record.item.space_id, space_id);
        assert_eq!(result.record.item.origin_device_id, local_device_id);
        assert_eq!(result.record.item.origin_seq, INITIAL_ORIGIN_SEQ);
        assert_eq!(result.record.item.hlc, HlcTimestamp::new(now_ms, 0));
        assert_eq!(result.record.item.plaintext.as_deref(), Some("本地复制"));
        assert_eq!(result.record.encrypted_content, vec![0xAA, 0xBB, 0xCC]);
        assert_eq!(
            result.record.expires_at,
            now_ms + (u64::from(AppSettings::default().retention_days) * MILLIS_PER_DAY)
        );

        let stored = ClipboardRepository::new(&connection)
            .get(result.record.item.item_id)
            .expect("stored item should be readable")
            .expect("stored item should exist");
        assert_eq!(stored.item.plaintext, None);
        assert_eq!(
            stored.item.content_digest,
            result.record.item.content_digest
        );
        assert_eq!(stored.encrypted_content, vec![0xAA, 0xBB, 0xCC]);

        let identity = LocalIdentityRepository::new(&mut connection);
        assert_eq!(identity.peek_next_origin_seq(), Ok(2));
    }

    #[test]
    fn persist_local_clipboard_text_rolls_back_sequence_when_item_insert_fails() {
        let mut connection = open_in_memory_database().expect("database should initialize");
        let now_ms = 1_700_000_000_000;
        {
            let mut identity = LocalIdentityRepository::new(&mut connection);
            identity
                .get_or_create_device_id(now_ms)
                .expect("local device id should be created");
        }

        let result = persist_local_clipboard_text(
            &mut connection,
            LocalClipboardPersistInput {
                space_id: Uuid::now_v7(),
                text: "没有空间外键".to_string(),
                encrypted_content: vec![1, 2, 3],
                hmac_key: b"space-key-for-tests",
                settings: AppSettings::default(),
                now_ms,
            },
        );

        assert!(result.is_err());
        let item_count: i64 = connection
            .query_row("SELECT COUNT(*) FROM clipboard_items", [], |row| row.get(0))
            .expect("item count should be readable");
        assert_eq!(item_count, 0);
        let identity = LocalIdentityRepository::new(&mut connection);
        assert_eq!(identity.peek_next_origin_seq(), Ok(INITIAL_ORIGIN_SEQ));
    }

    #[test]
    fn persist_local_clipboard_text_then_broadcast_keeps_record_when_broadcast_fails() {
        let mut connection = open_in_memory_database().expect("database should initialize");
        let now_ms = 1_700_000_000_000;
        let local_device_id = {
            let mut identity = LocalIdentityRepository::new(&mut connection);
            identity
                .get_or_create_device_id(now_ms)
                .expect("local device id should be created")
        };
        let space_id = Uuid::now_v7();
        let peer_device_id = Uuid::now_v7();
        seed_space_with_devices(&connection, space_id, local_device_id, peer_device_id)
            .expect("space and devices should seed");
        let mut broadcaster = RecordingBroadcaster {
            attempts: 0,
            fail: true,
        };

        let result = persist_local_clipboard_text_then_broadcast(
            &mut connection,
            LocalClipboardPersistInput {
                space_id,
                text: "广播失败也保留本地历史".to_string(),
                encrypted_content: vec![0x10, 0x20],
                hmac_key: b"space-key-for-tests",
                settings: AppSettings::default(),
                now_ms,
            },
            &mut broadcaster,
        )
        .expect("local transaction should commit before broadcast");

        assert_eq!(broadcaster.attempts, 1);
        assert_eq!(
            result.broadcast_outcome,
            LocalClipboardBroadcastOutcome::Failed
        );

        let stored = ClipboardRepository::new(&connection)
            .get(result.record.item.item_id)
            .expect("stored item should be readable")
            .expect("stored item should remain committed");
        assert_eq!(
            stored.item.content_digest,
            result.record.item.content_digest
        );
        let identity = LocalIdentityRepository::new(&mut connection);
        assert_eq!(identity.peek_next_origin_seq(), Ok(2));
    }

    #[test]
    fn persist_local_clipboard_text_then_broadcast_skips_network_when_sync_is_disabled() {
        let mut connection = open_in_memory_database().expect("database should initialize");
        let now_ms = 1_700_000_000_000;
        let local_device_id = {
            let mut identity = LocalIdentityRepository::new(&mut connection);
            identity
                .get_or_create_device_id(now_ms)
                .expect("local device id should be created")
        };
        let space_id = Uuid::now_v7();
        let peer_device_id = Uuid::now_v7();
        seed_space_with_devices(&connection, space_id, local_device_id, peer_device_id)
            .expect("space and devices should seed");
        let mut broadcaster = RecordingBroadcaster {
            attempts: 0,
            fail: false,
        };

        let result = persist_local_clipboard_text_then_broadcast(
            &mut connection,
            LocalClipboardPersistInput {
                space_id,
                text: "同步关闭只保留本地".to_string(),
                encrypted_content: vec![0x30, 0x40],
                hmac_key: b"space-key-for-tests",
                settings: AppSettings {
                    sync_enabled: false,
                    ..AppSettings::default()
                },
                now_ms,
            },
            &mut broadcaster,
        )
        .expect("local transaction should still commit when sync is disabled");

        assert_eq!(broadcaster.attempts, 0);
        assert_eq!(
            result.broadcast_outcome,
            LocalClipboardBroadcastOutcome::Skipped {
                reason: Some(SyncPauseReason::SyncDisabled),
            }
        );
        assert!(ClipboardRepository::new(&connection)
            .get(result.record.item.item_id)
            .expect("stored item should be readable")
            .is_some());
    }
}
