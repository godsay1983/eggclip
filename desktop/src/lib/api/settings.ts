import { invoke } from "@tauri-apps/api/core";
import { uiMessage, type UiMessageDescriptor } from "$lib/i18n";
import type { AppSettings } from "$lib/types/settings";

export function defaultAppSettings(): AppSettings {
  return {
    syncEnabled: true,
    autoReceiveEnabled: true,
    autoWriteEnabled: true,
    historyEnabled: true,
    historyLimit: 50,
    retentionDays: 7,
    themeMode: "system",
    languageMode: "system",
  };
}

export async function loadAppSettings(): Promise<AppSettings> {
  return invoke<AppSettings>("load_app_settings");
}

export async function saveAppSettings(settings: AppSettings): Promise<AppSettings> {
  return invoke<AppSettings>("save_app_settings", { settings });
}

export function validateAppSettings(settings: AppSettings): UiMessageDescriptor | null {
  if (![0, 20, 50, 100].includes(settings.historyLimit)) {
    return uiMessage("settings.invalidHistoryLimit");
  }
  if (!Number.isSafeInteger(settings.retentionDays) || settings.retentionDays < 0) {
    return uiMessage("settings.invalidRetentionDays");
  }
  if (!["system", "light", "dark"].includes(settings.themeMode)) {
    return uiMessage("settings.invalidTheme");
  }
  if (!["system", "zh-CN", "en-US"].includes(settings.languageMode)) {
    return uiMessage("settings.invalidLanguage");
  }
  return null;
}
