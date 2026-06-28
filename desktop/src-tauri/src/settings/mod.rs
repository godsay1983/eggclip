use std::{
    fs,
    path::{Path, PathBuf},
    time::{SystemTime, UNIX_EPOCH},
};

use tauri::{AppHandle, Manager};

use crate::{
    storage::{open_database, repositories::SettingsRepository},
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

fn database_path(app: &AppHandle) -> Result<PathBuf, String> {
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
    Ok(settings)
}

fn now_ms() -> Result<u64, String> {
    let duration = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|error| format!("系统时间不可用：{error}"))?;
    Ok(duration.as_millis().min(u128::from(u64::MAX)) as u64)
}

#[cfg(test)]
mod tests {
    use super::*;
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
}
