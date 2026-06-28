use std::path::Path;

use tauri::AppHandle;

use crate::{
    settings::{database_path, now_ms},
    storage::{open_database, repositories::ClipboardRepository},
};

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
                 ) VALUES(?1, ?2, ?3, 1, '1700000000000-0000', 'text/plain', 4, 'digest-a', X'74657374', 1700000000000, 1700000000000, 1700604800000, NULL)",
                params![item_id, space_id, device_id],
            )
            .expect("active item should insert");
        connection
            .execute(
                "INSERT INTO clipboard_items(
                    item_id, space_id, origin_device_id, origin_seq, hlc, content_type,
                    content_length, content_digest, encrypted_content, created_at, received_at, expires_at, deleted_at
                 ) VALUES(?1, ?2, ?3, 2, '1700000000001-0000', 'text/plain', 4, 'digest-b', X'74657374', 1700000000001, 1700000000001, 1700604800000, 1700000000100)",
                params![deleted_item_id, space_id, device_id],
            )
            .expect("deleted item should insert");
        drop(connection);

        assert_eq!(
            get_clipboard_history_used_at_path(&path).expect("history count should load"),
            1
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
}
