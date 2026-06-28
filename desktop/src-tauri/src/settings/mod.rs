use std::{
    fs,
    path::{Path, PathBuf},
    time::{SystemTime, UNIX_EPOCH},
};

use tauri::{AppHandle, Manager};

use crate::{
    storage::{
        open_database,
        repositories::{ClipboardRepository, SettingsRepository},
    },
    sync::AppSettings,
};

const DATABASE_FILE_NAME: &str = "eggclip.db";

#[tauri::command]
pub fn load_app_settings(app: AppHandle) -> Result<AppSettings, String> {
    let path = database_path(&app)?;
    load_app_settings_from_path(&path)
}

#[tauri::command]
pub fn save_app_settings(app: AppHandle, settings: AppSettings) -> Result<AppSettings, String> {
    let path = database_path(&app)?;
    save_app_settings_to_path(&path, settings, now_ms()?)
}

pub(crate) fn database_path(app: &AppHandle) -> Result<PathBuf, String> {
    let directory = app
        .path()
        .app_data_dir()
        .map_err(|error| format!("无法定位应用数据目录：{error}"))?;
    fs::create_dir_all(&directory).map_err(|error| format!("无法创建应用数据目录：{error}"))?;
    Ok(directory.join(DATABASE_FILE_NAME))
}

fn load_app_settings_from_path(path: &Path) -> Result<AppSettings, String> {
    let connection = open_database(path).map_err(|error| format!("无法打开本地数据库：{error}"))?;
    SettingsRepository::new(&connection)
        .load_app_settings()
        .map_err(|error| format!("无法读取设置：{error}"))
        .map(|settings| settings.unwrap_or_default())
}

fn save_app_settings_to_path(
    path: &Path,
    settings: AppSettings,
    updated_at: u64,
) -> Result<AppSettings, String> {
    settings
        .validate()
        .map_err(|error| format!("设置参数无效：{error}"))?;
    let connection = open_database(path).map_err(|error| format!("无法打开本地数据库：{error}"))?;
    SettingsRepository::new(&connection)
        .save_app_settings(&settings, updated_at)
        .map_err(|error| format!("无法保存设置：{error}"))?;
    ClipboardRepository::new(&connection)
        .apply_global_retention(&settings, updated_at)
        .map_err(|error| format!("无法应用历史策略：{error}"))?;
    Ok(settings)
}

pub(crate) fn now_ms() -> Result<u64, String> {
    let duration = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|error| format!("系统时间不可用：{error}"))?;
    Ok(duration.as_millis().min(u128::from(u64::MAX)) as u64)
}

#[cfg(test)]
mod tests {
    use super::*;
    use rusqlite::params;
    use uuid::Uuid;

    fn temp_database_path() -> PathBuf {
        std::env::temp_dir().join(format!("eggclip-settings-{}.db", Uuid::now_v7()))
    }

    #[test]
    fn settings_commands_return_defaults_for_fresh_database() {
        let path = temp_database_path();
        let settings = load_app_settings_from_path(&path).expect("settings should load");
        let _ = fs::remove_file(&path);
        let _ = fs::remove_file(path.with_extension("db-shm"));
        let _ = fs::remove_file(path.with_extension("db-wal"));

        assert_eq!(settings, AppSettings::default());
    }

    #[test]
    fn settings_commands_persist_valid_settings() {
        let path = temp_database_path();
        let settings = AppSettings {
            sync_enabled: false,
            auto_receive_enabled: false,
            auto_write_enabled: false,
            history_enabled: true,
            history_limit: 20,
            retention_days: 14,
            ..AppSettings::default()
        };

        let saved = save_app_settings_to_path(&path, settings.clone(), 1_700_000_000_000)
            .expect("settings should save");
        let loaded = load_app_settings_from_path(&path).expect("settings should load");
        let _ = fs::remove_file(&path);
        let _ = fs::remove_file(path.with_extension("db-shm"));
        let _ = fs::remove_file(path.with_extension("db-wal"));

        assert_eq!(saved, settings);
        assert_eq!(loaded, settings);
    }

    #[test]
    fn settings_commands_reject_invalid_history_limit() {
        let path = temp_database_path();
        let result = save_app_settings_to_path(
            &path,
            AppSettings {
                history_limit: 10,
                ..AppSettings::default()
            },
            1_700_000_000_000,
        );
        let _ = fs::remove_file(&path);
        let _ = fs::remove_file(path.with_extension("db-shm"));
        let _ = fs::remove_file(path.with_extension("db-wal"));

        assert!(result.is_err());
    }

    #[test]
    fn saving_history_policy_applies_retention_to_existing_items() {
        let path = temp_database_path();
        let connection = open_database(&path).expect("database should open");
        let space_id = Uuid::now_v7().to_string();
        let device_id = Uuid::now_v7().to_string();
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
        for seq in 1..=3 {
            let item_id = Uuid::now_v7().to_string();
            let timestamp = 1_700_000_000_000_i64 + seq;
            connection
                .execute(
                    "INSERT INTO clipboard_items(
                        item_id, space_id, origin_device_id, origin_seq, hlc, content_type,
                        content_length, content_digest, encrypted_content, created_at, received_at, expires_at, deleted_at
                     ) VALUES(?1, ?2, ?3, ?4, ?5, 'text/plain', 4, ?6, X'74657374', ?7, ?7, 1700604800000, NULL)",
                    params![
                        item_id,
                        space_id,
                        device_id,
                        seq,
                        format!("0000018bcfe5680{seq}-0000"),
                        format!("digest-{seq}"),
                        timestamp,
                    ],
                )
                .expect("item should insert");
        }
        drop(connection);

        save_app_settings_to_path(
            &path,
            AppSettings {
                history_limit: 0,
                ..AppSettings::default()
            },
            1_700_000_010_000,
        )
        .expect("settings should save and apply retention");
        let connection = open_database(&path).expect("database should reopen");
        let active_count: i64 = connection
            .query_row(
                "SELECT COUNT(*) FROM clipboard_items WHERE deleted_at IS NULL",
                [],
                |row| row.get(0),
            )
            .expect("count should load");
        let _ = fs::remove_file(&path);
        let _ = fs::remove_file(path.with_extension("db-shm"));
        let _ = fs::remove_file(path.with_extension("db-wal"));

        assert_eq!(active_count, 0);
    }
}
