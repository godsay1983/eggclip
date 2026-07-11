use std::path::Path;

use serde::Serialize;
use tauri::AppHandle;
use uuid::Uuid;

use crate::{
    settings::{database_path, now_ms},
    storage::{
        open_database,
        repositories::{
            persist_local_clipboard_text, ClipboardItemRecord, ClipboardRepository,
            LocalClipboardPersistInput, LocalIdentityRepository, SettingsRepository,
        },
    },
};

const HISTORY_PREVIEW_LIMIT: u16 = 5;
const LOCAL_HISTORY_SPACE_ID: &str = "018ff6ef-c394-7d08-8b99-4b7d10f2767a";
const LOCAL_HISTORY_ENCRYPTED_PLACEHOLDER: &[u8] = b"eggclip-local-history-metadata-only-v1";

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HistoryItemSummary {
    pub id: String,
    pub title: String,
    pub preview: String,
    pub source: String,
    pub received_at_ms: u64,
    pub content_length: usize,
}

#[tauri::command]
pub fn clear_clipboard_history(app: AppHandle) -> Result<usize, String> {
    let path = database_path(&app)?;
    clear_clipboard_history_at_path(&path, now_ms()?)
}

#[tauri::command]
pub fn get_clipboard_history_used(app: AppHandle) -> Result<usize, String> {
    let path = database_path(&app)?;
    get_clipboard_history_used_at_path(&path)
}

#[tauri::command]
pub fn list_clipboard_history_preview(app: AppHandle) -> Result<Vec<HistoryItemSummary>, String> {
    let path = database_path(&app)?;
    list_clipboard_history_preview_at_path(&path, HISTORY_PREVIEW_LIMIT)
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
        .apply_retention(space_id, &settings, captured_at)
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
              space_id, display_name, encrypted_space_key_ref, key_version, state, created_at, updated_at
            ) VALUES (?1, '本机历史', NULL, 1, 'active', ?2, ?2)",
            rusqlite::params![space_id.to_string(), now_ms],
        )
        .map_err(|error| format!("无法初始化本机历史空间：{error}"))?;
    connection
        .execute(
            "INSERT OR IGNORE INTO devices(
              device_id, space_id, display_name, identity_public_key, trust_state,
              connection_state, paired_at, last_seen_at, revoked_at
            ) VALUES (?1, ?2, '本机', 'local-history://identity', 'trusted', 'offline', ?3, NULL, NULL)",
            rusqlite::params![local_device_id.to_string(), space_id.to_string(), now_ms],
        )
        .map_err(|error| format!("无法初始化本机历史设备：{error}"))?;
    Ok(())
}

fn to_history_item_summary(record: &ClipboardItemRecord) -> HistoryItemSummary {
    let device = record.item.origin_device_id.to_string();
    let short_device = device.get(0..8).unwrap_or("unknown");
    HistoryItemSummary {
        id: record.item.item_id.to_string(),
        title: format!("{} 字节文本", record.item.content_length),
        preview: "内容已保存；正文预览将在密钥解密链路接入后显示".to_string(),
        source: format!("来源设备 {short_device}"),
        received_at_ms: record.received_at,
        content_length: record.item.content_length,
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
                "INSERT INTO devices(
                    device_id, space_id, display_name, identity_public_key, trust_state,
                    connection_state, paired_at, last_seen_at, revoked_at
                 ) VALUES(?1, ?2, '本机', 'test-public-key', 'trusted', 'offline', 1700000000000, NULL, NULL)",
                params![device_id, space_id],
            )
            .expect("device should insert");
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
        assert!(items[0].preview.contains("密钥解密链路"));
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
        assert!(captured.title.contains(&text.len().to_string()));
        assert!(captured.preview.contains("密钥解密链路"));
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
