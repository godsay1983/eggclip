use std::{cmp::Ordering, fmt};

use hmac::{Hmac, Mac};
use serde::{de::Error as _, Deserialize, Deserializer, Serialize, Serializer};
use sha2::Sha256;
use tauri::AppHandle;
use uuid::Uuid;

use crate::clipboard::{self, ClipboardText};
use crate::crypto::encode_base64url;
use crate::protocol::MAX_TEXT_BYTES;

type HmacSha256 = Hmac<Sha256>;

pub const DEFAULT_HISTORY_LIMIT: u16 = 50;
pub const DEFAULT_RETENTION_DAYS: u16 = 7;
pub const MIN_HISTORY_LIMIT: u16 = 0;
pub const MAX_HISTORY_LIMIT: u16 = 100;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ContentType {
    TextPlain,
}

impl ContentType {
    pub fn wire_value(self) -> &'static str {
        match self {
            ContentType::TextPlain => "text/plain",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum DeviceTrustState {
    Trusted,
    Revoked,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum DeviceConnectionState {
    Offline,
    Connecting,
    Online,
    AuthFailed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum SpaceState {
    Active,
    RotatingKey,
    Archived,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SyncModelError {
    EmptyText,
    TextTooLarge {
        actual_bytes: usize,
        max_bytes: usize,
    },
    InvalidHistoryLimit(u16),
    SequenceOverflow,
    InvalidHmacKey,
}

impl fmt::Display for SyncModelError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            SyncModelError::EmptyText => formatter.write_str("text/plain content is empty"),
            SyncModelError::TextTooLarge {
                actual_bytes,
                max_bytes,
            } => write!(
                formatter,
                "text/plain content is too large: {actual_bytes} bytes, max {max_bytes}"
            ),
            SyncModelError::InvalidHistoryLimit(limit) => {
                write!(formatter, "invalid history limit {limit}")
            }
            SyncModelError::SequenceOverflow => formatter.write_str("origin sequence overflow"),
            SyncModelError::InvalidHmacKey => formatter.write_str("invalid HMAC key"),
        }
    }
}

impl std::error::Error for SyncModelError {}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ClipboardItem {
    pub item_id: Uuid,
    pub space_id: Uuid,
    pub origin_device_id: Uuid,
    pub origin_seq: u64,
    pub hlc: HlcTimestamp,
    pub content_type: ContentType,
    pub content_length: usize,
    pub content_digest: String,
    pub created_at: u64,
    pub encrypted_content_ref: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub plaintext: Option<String>,
}

impl ClipboardItem {
    pub fn stable_order_key(&self) -> ClipboardOrderKey<'_> {
        ClipboardOrderKey {
            hlc: self.hlc,
            origin_device_id: &self.origin_device_id,
            origin_seq: self.origin_seq,
            item_id: &self.item_id,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Device {
    pub device_id: Uuid,
    pub space_id: Uuid,
    pub display_name: String,
    pub identity_public_key_ref: String,
    pub trust_state: DeviceTrustState,
    pub connection_state: DeviceConnectionState,
    pub last_seen_at: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Space {
    pub space_id: Uuid,
    pub display_name: String,
    pub key_version: u32,
    pub state: SpaceState,
    pub created_at: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncHead {
    pub space_id: Uuid,
    pub origin_device_id: Uuid,
    pub latest_origin_seq: u64,
    pub minimum_available: u64,
    pub updated_at: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AppSettings {
    pub sync_enabled: bool,
    pub auto_receive_enabled: bool,
    pub auto_write_enabled: bool,
    pub history_enabled: bool,
    pub history_limit: u16,
    pub retention_days: u16,
}

impl Default for AppSettings {
    fn default() -> Self {
        Self {
            sync_enabled: true,
            auto_receive_enabled: true,
            auto_write_enabled: true,
            history_enabled: true,
            history_limit: DEFAULT_HISTORY_LIMIT,
            retention_days: DEFAULT_RETENTION_DAYS,
        }
    }
}

impl AppSettings {
    pub fn validate(&self) -> Result<(), SyncModelError> {
        if !matches!(self.history_limit, 0 | 20 | 50 | 100) {
            return Err(SyncModelError::InvalidHistoryLimit(self.history_limit));
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct HlcTimestamp {
    pub wall_time_ms: u64,
    pub logical: u16,
}

impl HlcTimestamp {
    pub fn new(wall_time_ms: u64, logical: u16) -> Self {
        Self {
            wall_time_ms,
            logical,
        }
    }

    pub fn tick(self, now_ms: u64) -> Self {
        if now_ms > self.wall_time_ms {
            return Self::new(now_ms, 0);
        }
        Self::new(self.wall_time_ms, self.logical.saturating_add(1))
    }

    pub fn observe(self, remote: Self, now_ms: u64) -> Self {
        let wall_time_ms = now_ms.max(self.wall_time_ms).max(remote.wall_time_ms);
        let logical = if wall_time_ms == self.wall_time_ms && wall_time_ms == remote.wall_time_ms {
            self.logical.max(remote.logical).saturating_add(1)
        } else if wall_time_ms == self.wall_time_ms {
            self.logical.saturating_add(1)
        } else if wall_time_ms == remote.wall_time_ms {
            remote.logical.saturating_add(1)
        } else {
            0
        };
        Self::new(wall_time_ms, logical)
    }

    pub fn to_wire(self) -> String {
        format!("{:016x}-{:04x}", self.wall_time_ms, self.logical)
    }

    pub fn from_wire(value: &str) -> Option<Self> {
        let (wall_time_ms, logical) = value.split_once('-')?;
        if wall_time_ms.len() != 16 || logical.len() != 4 {
            return None;
        }
        let wall_time_ms = u64::from_str_radix(wall_time_ms, 16).ok()?;
        let logical = u16::from_str_radix(logical, 16).ok()?;
        Some(Self::new(wall_time_ms, logical))
    }
}

impl Serialize for HlcTimestamp {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        serializer.serialize_str(&self.to_wire())
    }
}

impl<'de> Deserialize<'de> for HlcTimestamp {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let value = String::deserialize(deserializer)?;
        Self::from_wire(&value).ok_or_else(|| D::Error::custom("invalid HLC timestamp"))
    }
}

impl Ord for HlcTimestamp {
    fn cmp(&self, other: &Self) -> Ordering {
        (self.wall_time_ms, self.logical).cmp(&(other.wall_time_ms, other.logical))
    }
}

impl PartialOrd for HlcTimestamp {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

#[derive(Debug, Clone, Copy)]
pub struct ClipboardOrderKey<'a> {
    hlc: HlcTimestamp,
    origin_device_id: &'a Uuid,
    origin_seq: u64,
    item_id: &'a Uuid,
}

impl Ord for ClipboardOrderKey<'_> {
    fn cmp(&self, other: &Self) -> Ordering {
        (
            self.hlc,
            self.origin_device_id.as_bytes(),
            self.origin_seq,
            self.item_id.as_bytes(),
        )
            .cmp(&(
                other.hlc,
                other.origin_device_id.as_bytes(),
                other.origin_seq,
                other.item_id.as_bytes(),
            ))
    }
}

impl PartialOrd for ClipboardOrderKey<'_> {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl PartialEq for ClipboardOrderKey<'_> {
    fn eq(&self, other: &Self) -> bool {
        self.cmp(other) == Ordering::Equal
    }
}

impl Eq for ClipboardOrderKey<'_> {}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct OriginSeqAllocator {
    next_value: u64,
}

impl OriginSeqAllocator {
    pub fn new(next_value: u64) -> Self {
        Self { next_value }
    }

    pub fn next_seq(&mut self) -> Result<u64, SyncModelError> {
        let current = self.next_value;
        self.next_value = self
            .next_value
            .checked_add(1)
            .ok_or(SyncModelError::SequenceOverflow)?;
        Ok(current)
    }

    pub fn peek_next(&self) -> u64 {
        self.next_value
    }
}

pub fn new_uuid_v7() -> Uuid {
    Uuid::now_v7()
}

pub fn content_hmac_digest(hmac_key: &[u8], text: &str) -> Result<String, SyncModelError> {
    let mut hmac =
        HmacSha256::new_from_slice(hmac_key).map_err(|_| SyncModelError::InvalidHmacKey)?;
    hmac.update(ContentType::TextPlain.wire_value().as_bytes());
    hmac.update(b"\n");
    hmac.update(text.as_bytes());
    Ok(encode_base64url(&hmac.finalize().into_bytes()))
}

#[derive(Debug, Clone, Copy)]
pub struct LocalClipboardItemInput<'a> {
    pub item_id: Uuid,
    pub space_id: Uuid,
    pub origin_device_id: Uuid,
    pub origin_seq: u64,
    pub hlc: HlcTimestamp,
    pub created_at: u64,
    pub hmac_key: &'a [u8],
}

pub fn build_local_clipboard_item(
    input: LocalClipboardItemInput<'_>,
    text: String,
) -> Result<ClipboardItem, SyncModelError> {
    let content_length = text.len();
    if content_length == 0 {
        return Err(SyncModelError::EmptyText);
    }
    if content_length > MAX_TEXT_BYTES {
        return Err(SyncModelError::TextTooLarge {
            actual_bytes: content_length,
            max_bytes: MAX_TEXT_BYTES,
        });
    }
    let content_digest = content_hmac_digest(input.hmac_key, &text)?;
    Ok(ClipboardItem {
        item_id: input.item_id,
        space_id: input.space_id,
        origin_device_id: input.origin_device_id,
        origin_seq: input.origin_seq,
        hlc: input.hlc,
        content_type: ContentType::TextPlain,
        content_length,
        content_digest,
        created_at: input.created_at,
        encrypted_content_ref: None,
        plaintext: Some(text),
    })
}

/// Only authenticated online ITEM_LIVE events may enter this policy boundary.
/// The unauthenticated POC transport and historical/batch events must never call it.
pub fn apply_authenticated_live_item(app: &AppHandle, item: &ClipboardText) -> Result<(), String> {
    clipboard::write_remote_clipboard_text(app, item)
}

#[cfg(test)]
mod tests {
    use super::*;
    use uuid::Timestamp;

    fn uuid_from_ms(ms: u64) -> Uuid {
        Uuid::new_v7(Timestamp::from_unix_time(
            ms / 1000,
            ((ms % 1000) * 1_000_000) as u32,
            0,
            0,
        ))
    }

    #[test]
    fn hlc_tick_and_observe_keep_monotonic_order() {
        let local = HlcTimestamp::new(1_000, 0);
        let tick_same_ms = local.tick(1_000);
        let tick_new_ms = tick_same_ms.tick(1_005);
        let observed = tick_new_ms.observe(HlcTimestamp::new(1_005, 8), 1_004);

        assert_eq!(tick_same_ms, HlcTimestamp::new(1_000, 1));
        assert_eq!(tick_new_ms, HlcTimestamp::new(1_005, 0));
        assert_eq!(observed, HlcTimestamp::new(1_005, 9));
        assert!(local < tick_same_ms);
        assert!(tick_same_ms < tick_new_ms);
        assert!(tick_new_ms < observed);
        assert_eq!(observed.to_wire(), "00000000000003ed-0009");
        assert_eq!(
            HlcTimestamp::from_wire("00000000000003ed-0009"),
            Some(observed)
        );
    }

    #[test]
    fn uuid_v7_and_stable_order_key_are_sortable() {
        let space_id = uuid_from_ms(1_700_000_000_000);
        let device_id = uuid_from_ms(1_700_000_000_001);
        let first = ClipboardItem {
            item_id: uuid_from_ms(1_700_000_000_010),
            space_id,
            origin_device_id: device_id,
            origin_seq: 1,
            hlc: HlcTimestamp::new(1_000, 0),
            content_type: ContentType::TextPlain,
            content_length: 1,
            content_digest: "a".to_string(),
            created_at: 1_000,
            encrypted_content_ref: None,
            plaintext: Some("a".to_string()),
        };
        let second = ClipboardItem {
            item_id: uuid_from_ms(1_700_000_000_011),
            origin_seq: 2,
            hlc: HlcTimestamp::new(1_000, 1),
            plaintext: Some("b".to_string()),
            ..first.clone()
        };

        assert_eq!(new_uuid_v7().get_version_num(), 7);
        assert!(first.item_id < second.item_id);
        assert!(first.stable_order_key() < second.stable_order_key());
    }

    #[test]
    fn builds_local_clipboard_item_with_hmac_digest_and_text_limits() {
        let item = build_local_clipboard_item(
            LocalClipboardItemInput {
                item_id: uuid_from_ms(1_700_000_000_010),
                space_id: uuid_from_ms(1_700_000_000_000),
                origin_device_id: uuid_from_ms(1_700_000_000_001),
                origin_seq: 42,
                hlc: HlcTimestamp::new(1_700_000_000_100, 0),
                created_at: 1_700_000_000_100,
                hmac_key: b"space-key-for-tests",
            },
            "蛋定 Clip".to_string(),
        )
        .expect("valid local item should be built");

        assert_eq!(item.origin_seq, 42);
        assert_eq!(item.content_type, ContentType::TextPlain);
        assert_eq!(item.content_length, "蛋定 Clip".len());
        let serialized = serde_json::to_value(&item).expect("item should serialize");
        assert_eq!(serialized["hlc"], "0000018bcfe56864-0000");
        assert_eq!(
            item.content_digest,
            content_hmac_digest(b"space-key-for-tests", "蛋定 Clip").unwrap()
        );
        assert_ne!(
            item.content_digest,
            content_hmac_digest(b"other-space-key", "蛋定 Clip").unwrap()
        );

        let empty = build_local_clipboard_item(
            LocalClipboardItemInput {
                item_id: item.item_id,
                space_id: item.space_id,
                origin_device_id: item.origin_device_id,
                origin_seq: 43,
                hlc: item.hlc.tick(item.created_at),
                created_at: item.created_at,
                hmac_key: b"space-key-for-tests",
            },
            String::new(),
        );
        assert_eq!(empty, Err(SyncModelError::EmptyText));
    }

    #[test]
    fn origin_sequence_allocator_advances_without_skipping() {
        let mut allocator = OriginSeqAllocator::new(7);
        assert_eq!(allocator.next_seq(), Ok(7));
        assert_eq!(allocator.next_seq(), Ok(8));
        assert_eq!(allocator.peek_next(), 9);
    }

    #[test]
    fn app_settings_allow_only_supported_history_limits() {
        let defaults = AppSettings::default();
        assert_eq!(defaults.history_limit, DEFAULT_HISTORY_LIMIT);
        assert_eq!(defaults.validate(), Ok(()));

        for limit in [
            MIN_HISTORY_LIMIT,
            20,
            DEFAULT_HISTORY_LIMIT,
            MAX_HISTORY_LIMIT,
        ] {
            let settings = AppSettings {
                history_limit: limit,
                ..AppSettings::default()
            };
            assert_eq!(settings.validate(), Ok(()));
        }

        let invalid = AppSettings {
            history_limit: 10,
            ..AppSettings::default()
        };
        assert_eq!(
            invalid.validate(),
            Err(SyncModelError::InvalidHistoryLimit(10))
        );
    }
}
