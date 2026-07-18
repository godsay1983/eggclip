use std::path::Path;

use serde::Serialize;
use tauri::AppHandle;
use uuid::Uuid;

use crate::{
    pairing::load_space_key,
    settings::{database_path, now_ms},
    storage::{
        open_database,
        repositories::{
            persist_local_clipboard_text, ClipboardItemRecord, ClipboardRepository,
            LocalClipboardPersistInput, LocalIdentityRepository, SettingsRepository,
        },
    },
    transport::decrypt_local_clipboard_content,
};

const HISTORY_PREVIEW_LIMIT: u16 = 5;
const LOCAL_HISTORY_SPACE_ID: &str = "018ff6ef-c394-7d08-8b99-4b7d10f2767a";
const LOCAL_HISTORY_ENCRYPTED_PLACEHOLDER: &[u8] = b"eggclip-local-history-metadata-only-v1";

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HistoryItemSummary {
    pub id: String,
    pub preview: String,
    pub origin_device_id: String,
    pub received_at_ms: u64,
    pub content_length: usize,
    pub text: Option<String>,
    pub can_copy: bool,
}

#[tauri::command]
pub fn clear_clipboard_history(app: AppHandle) -> Result<usize, String> {
    let path = database_path(&app)?;
    clear_clipboard_history_at_path(&path, now_ms()?)
}

#[tauri::command]
pub fn get_clipboard_history_used(app: AppHandle) -> Result<usize, String> {
    let path = database_path(&app)?;
    apply_global_history_retention_at_path(&path, now_ms()?)?;
    get_clipboard_history_used_at_path(&path)
}

#[tauri::command]
pub fn list_clipboard_history_preview(app: AppHandle) -> Result<Vec<HistoryItemSummary>, String> {
    let path = database_path(&app)?;
    let connection =
        open_database(&path).map_err(|error| format!("无法打开本地数据库：{error}"))?;
    let records = ClipboardRepository::new(&connection)
        .list_recent_all(HISTORY_PREVIEW_LIMIT)
        .map_err(|error| format!("无法读取历史记录：{error}"))?;
    #[cfg(windows)]
    let secret_store = crate::secret_store::WindowsCredentialSecretStore;
    #[cfg(not(windows))]
    let secret_store = crate::secret_store::UnavailableSecretStore;
    Ok(records
        .iter()
        .map(|record| {
            let text = load_space_key(&connection, &secret_store, record.item.space_id)
                .ok()
                .and_then(|mut key| {
                    let result = decrypt_local_clipboard_content(
                        &key,
                        record.item.space_id,
                        &record.encrypted_content,
                    )
                    .ok()
                    .map(|value| value.as_str().to_owned());
                    key.fill(0);
                    result
                });
            to_history_item_summary_with_text(record, text)
        })
        .collect())
}

#[tauri::command]
pub fn delete_clipboard_history_item(app: AppHandle, item_id: String) -> Result<bool, String> {
    let path = database_path(&app)?;
    delete_clipboard_history_item_at_path(&path, &item_id, now_ms()?)
}

#[tauri::command]
pub fn capture_clipboard_history_text(
    app: AppHandle,
    text: String,
) -> Result<Option<HistoryItemSummary>, String> {
    let path = database_path(&app)?;
    capture_clipboard_history_text_at_path(&path, text, now_ms()?)
}

fn clear_clipboard_history_at_path(path: &Path, deleted_at: u64) -> Result<usize, String> {
    let connection = open_database(path).map_err(|error| format!("无法打开本地数据库：{error}"))?;
    ClipboardRepository::new(&connection)
        .clear_all_history(deleted_at)
        .map_err(|error| format!("无法清空历史：{error}"))
}

fn get_clipboard_history_used_at_path(path: &Path) -> Result<usize, String> {
    let connection = open_database(path).map_err(|error| format!("无法打开本地数据库：{error}"))?;
    ClipboardRepository::new(&connection)
        .active_count_all()
        .map_err(|error| format!("无法读取历史数量：{error}"))
}

fn apply_global_history_retention_at_path(path: &Path, current_time: u64) -> Result<(), String> {
    let connection = open_database(path).map_err(|error| format!("无法打开本地数据库：{error}"))?;
    let settings = SettingsRepository::new(&connection)
        .load_app_settings()
        .map_err(|error| format!("无法读取设置：{error}"))?
        .unwrap_or_default();
    ClipboardRepository::new(&connection)
        .apply_global_retention(&settings, current_time)
        .map(|_| ())
        .map_err(|error| format!("无法清理过期历史：{error}"))
}

#[cfg(test)]
fn list_clipboard_history_preview_at_path(
    path: &Path,
    limit: u16,
) -> Result<Vec<HistoryItemSummary>, String> {
    let connection = open_database(path).map_err(|error| format!("无法打开本地数据库：{error}"))?;
    ClipboardRepository::new(&connection)
        .list_recent_all(limit)
        .map(|records| records.iter().map(to_history_item_summary).collect())
        .map_err(|error| format!("无法读取历史记录：{error}"))
}

fn delete_clipboard_history_item_at_path(
    path: &Path,
    item_id: &str,
    deleted_at: u64,
) -> Result<bool, String> {
    let item_id = Uuid::parse_str(item_id).map_err(|_| "历史记录 ID 无效".to_string())?;
    let connection = open_database(path).map_err(|error| format!("无法打开本地数据库：{error}"))?;
    ClipboardRepository::new(&connection)
        .mark_deleted(item_id, deleted_at)
        .map_err(|error| format!("无法删除历史记录：{error}"))
}

pub(crate) fn capture_clipboard_history_text_at_path(
    path: &Path,
    text: String,
    captured_at: u64,
) -> Result<Option<HistoryItemSummary>, String> {
    let mut connection =
        open_database(path).map_err(|error| format!("无法打开本地数据库：{error}"))?;
    let settings = SettingsRepository::new(&connection)
        .load_app_settings()
        .map_err(|error| format!("无法读取设置：{error}"))?
        .unwrap_or_default();
    if !settings.history_enabled || settings.history_limit == 0 {
        return Ok(None);
    }

    let local_device_id = LocalIdentityRepository::new(&mut connection)
        .get_or_create_device_id(captured_at)
        .map_err(|error| format!("无法读取本机身份：{error}"))?;
    let hmac_key = format!("eggclip-local-history-v1:{local_device_id}");
    let space_id = Uuid::parse_str(LOCAL_HISTORY_SPACE_ID)
        .map_err(|error| format!("本机历史空间无效：{error}"))?;
    ensure_local_history_space_and_device(&connection, space_id, local_device_id, captured_at)?;
    let result = persist_local_clipboard_text(
        &mut connection,
        LocalClipboardPersistInput {
            space_id,
            text,
            encrypted_content: LOCAL_HISTORY_ENCRYPTED_PLACEHOLDER.to_vec(),
            hmac_key: hmac_key.as_bytes(),
            settings: settings.clone(),
            now_ms: captured_at,
        },
    )
    .map_err(|error| format!("无法保存本机历史：{error}"))?;
    ClipboardRepository::new(&connection)
        .apply_global_retention(&settings, captured_at)
        .map_err(|error| format!("无法清理过期历史：{error}"))?;
    Ok(Some(to_history_item_summary(&result.record)))
}

fn ensure_local_history_space_and_device(
    connection: &rusqlite::Connection,
    space_id: Uuid,
    local_device_id: Uuid,
    now_ms: u64,
) -> Result<(), String> {
    let now_ms = i64::try_from(now_ms).map_err(|_| "本机历史时间超出范围".to_string())?;
    connection
        .execute(
            "INSERT OR IGNORE INTO spaces(
              space_id, display_name, encrypted_space_key_ref, key_version, state,
              created_at, updated_at, local_role
            ) VALUES (?1, '本机历史', NULL, 1, 'active', ?2, ?2, 'owner')",
            rusqlite::params![space_id.to_string(), now_ms],
        )
        .map_err(|error| format!("无法初始化本机历史空间：{error}"))?;
    connection
        .execute(
            "INSERT OR IGNORE INTO device_identities(device_id, identity_public_key)
             VALUES (?1, 'local-history://identity')",
            rusqlite::params![local_device_id.to_string()],
        )
        .map_err(|error| format!("无法初始化本机历史设备身份：{error}"))?;
    connection
        .execute(
            "INSERT OR IGNORE INTO space_members(
              space_id, device_id, display_name, trust_state, connection_state,
              route_role, paired_at, last_seen_at, revoked_at
            ) VALUES (?2, ?1, '本机', 'trusted', 'offline', 'acceptOnly', ?3, NULL, NULL)",
            rusqlite::params![local_device_id.to_string(), space_id.to_string(), now_ms],
        )
        .map_err(|error| format!("无法初始化本机历史设备：{error}"))?;
    Ok(())
}

fn to_history_item_summary(record: &ClipboardItemRecord) -> HistoryItemSummary {
    to_history_item_summary_with_text(record, None)
}

fn to_history_item_summary_with_text(
    record: &ClipboardItemRecord,
    text: Option<String>,
) -> HistoryItemSummary {
    HistoryItemSummary {
        id: record.item.item_id.to_string(),
        preview: text.as_deref().map(history_preview).unwrap_or_default(),
        origin_device_id: record.item.origin_device_id.to_string(),
        received_at_ms: record.received_at,
        content_length: record.item.content_length,
        can_copy: text.is_some(),
        text,
    }
}

fn history_preview(text: &str) -> String {
    const MAX_CHARS: usize = 180;
    let mut chars = text.chars();
    let preview: String = chars.by_ref().take(MAX_CHARS).collect();
    if chars.next().is_some() {
        format!("{preview}…")
    } else {
        preview
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use rusqlite::params;
    use std::fs;
    use uuid::Uuid;

    fn temp_database_path() -> std::path::PathBuf {
        std::env::temp_dir().join(format!("eggclip-history-{}.db", Uuid::now_v7()))
    }

    fn cleanup_database(path: &Path) {
        let _ = fs::remove_file(path);
        let _ = fs::remove_file(path.with_extension("db-shm"));
        let _ = fs::remove_file(path.with_extension("db-wal"));
    }

    #[test]
    fn clear_clipboard_history_marks_all_active_items_deleted() {
        let path = temp_database_path();
        let connection = open_database(&path).expect("database should open");
        let space_id = Uuid::now_v7().to_string();
        let device_id = Uuid::now_v7().to_string();
        let item_id = Uuid::now_v7().to_string();
        let second_item_id = Uuid::now_v7().to_string();
        let deleted_item_id = Uuid::now_v7().to_string();
        connection
            .execute(
                "INSERT INTO spaces(space_id, display_name, encrypted_space_key_ref, key_version, state, created_at, updated_at)
                 VALUES(?1, '测试空间', NULL, 1, 'active', 1700000000000, 1700000000000)",
                params![space_id],
            )
            .expect("space should insert");
        connection
            .execute(
                "INSERT INTO device_identities(device_id, identity_public_key)
                 VALUES(?1, 'test-public-key')",
                params![device_id],
            )
            .expect("device identity should insert");
        connection
            .execute(
                "INSERT INTO space_members(
                    space_id, device_id, display_name, trust_state, connection_state,
                    route_role, last_successful_host, last_successful_port,
                    paired_at, last_seen_at, revoked_at
                 ) VALUES(?2, ?1, '本机', 'trusted', 'offline', 'acceptOnly', NULL, NULL,
                    1700000000000, NULL, NULL)",
                params![device_id, space_id],
            )
            .expect("space member should insert");
        connection
            .execute(
                "INSERT INTO clipboard_items(
                    item_id, space_id, origin_device_id, origin_seq, hlc, content_type,
                    content_length, content_digest, encrypted_content, created_at, received_at, expires_at, deleted_at
                 ) VALUES(?1, ?2, ?3, 1, '0000018bcfe56800-0000', 'text/plain', 4, 'digest-a', X'74657374', 1700000000000, 1700000000000, 1700604800000, NULL)",
                params![item_id, space_id, device_id],
            )
            .expect("active item should insert");
        connection
            .execute(
                "INSERT INTO clipboard_items(
                    item_id, space_id, origin_device_id, origin_seq, hlc, content_type,
                    content_length, content_digest, encrypted_content, created_at, received_at, expires_at, deleted_at
                 ) VALUES(?1, ?2, ?3, 2, '0000018bcfe56802-0000', 'text/plain', 8, 'digest-c', X'7465737432', 1700000000002, 1700000000002, 1700604800000, NULL)",
                params![second_item_id, space_id, device_id],
            )
            .expect("second active item should insert");
        connection
            .execute(
                "INSERT INTO clipboard_items(
                    item_id, space_id, origin_device_id, origin_seq, hlc, content_type,
                    content_length, content_digest, encrypted_content, created_at, received_at, expires_at, deleted_at
                 ) VALUES(?1, ?2, ?3, 3, '0000018bcfe56801-0000', 'text/plain', 4, 'digest-b', X'74657374', 1700000000001, 1700000000001, 1700604800000, 1700000000100)",
                params![deleted_item_id, space_id, device_id],
            )
            .expect("deleted item should insert");
        drop(connection);

        assert_eq!(
            get_clipboard_history_used_at_path(&path).expect("history count should load"),
            2
        );
        let items =
            list_clipboard_history_preview_at_path(&path, 5).expect("history preview should load");
        assert_eq!(items.len(), 2);
        assert_eq!(items[0].id, second_item_id);
        assert_eq!(items[0].content_length, 8);
        assert!(items[0].preview.is_empty());
        assert!(
            delete_clipboard_history_item_at_path(&path, &second_item_id, 1_700_000_001_500)
                .expect("item should delete")
        );
        assert_eq!(
            get_clipboard_history_used_at_path(&path).expect("history count should reload"),
            1
        );
        assert!(
            !delete_clipboard_history_item_at_path(&path, &second_item_id, 1_700_000_001_600)
                .expect("deleted item should be idempotent")
        );
        let cleared = clear_clipboard_history_at_path(&path, 1_700_000_002_000)
            .expect("history should clear");
        assert_eq!(
            get_clipboard_history_used_at_path(&path).expect("history count should reload"),
            0
        );
        let connection = open_database(&path).expect("database should reopen");
        let active_count: i64 = connection
            .query_row(
                "SELECT COUNT(*) FROM clipboard_items WHERE deleted_at IS NULL",
                [],
                |row| row.get(0),
            )
            .expect("count should load");
        let old_deleted_count: i64 = connection
            .query_row(
                "SELECT COUNT(*) FROM clipboard_items WHERE deleted_at = 1700000000100",
                [],
                |row| row.get(0),
            )
            .expect("old deleted count should load");
        cleanup_database(&path);

        assert_eq!(cleared, 1);
        assert_eq!(active_count, 0);
        assert_eq!(old_deleted_count, 1);
    }

    #[test]
    fn capture_clipboard_history_text_persists_visible_local_history() {
        let path = temp_database_path();
        let text = "蛋定 Clip visible history".to_string();

        let captured =
            capture_clipboard_history_text_at_path(&path, text.clone(), 1_700_000_010_000)
                .expect("clipboard text should persist")
                .expect("history should be enabled by default");

        assert_eq!(captured.content_length, text.len());
        assert!(!captured.origin_device_id.is_empty());
        assert!(captured.preview.is_empty());
        assert_eq!(
            get_clipboard_history_used_at_path(&path).expect("history count should reload"),
            1
        );
        let items =
            list_clipboard_history_preview_at_path(&path, 5).expect("history preview should load");
        assert_eq!(items.len(), 1);
        assert_eq!(items[0].id, captured.id);

        let connection = open_database(&path).expect("database should reopen");
        let encrypted_content: Vec<u8> = connection
            .query_row(
                "SELECT encrypted_content FROM clipboard_items WHERE item_id = ?1",
                params![captured.id],
                |row| row.get(0),
            )
            .expect("encrypted content should load");
        let stored_space_count: i64 = connection
            .query_row(
                "SELECT COUNT(*) FROM spaces WHERE space_id = ?1",
                params![LOCAL_HISTORY_SPACE_ID],
                |row| row.get(0),
            )
            .expect("local space count should load");
        cleanup_database(&path);

        assert_eq!(encrypted_content, LOCAL_HISTORY_ENCRYPTED_PLACEHOLDER);
        assert_ne!(encrypted_content, text.as_bytes());
        assert_eq!(stored_space_count, 1);
    }
}
