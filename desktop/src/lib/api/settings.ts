import { invoke } from "@tauri-apps/api/core";
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
  };
}

export async function loadAppSettings(): Promise<AppSettings> {
  return invoke<AppSettings>("load_app_settings");
}

export async function saveAppSettings(settings: AppSettings): Promise<AppSettings> {
  return invoke<AppSettings>("save_app_settings", { settings });
}

export function validateAppSettings(settings: AppSettings): string | null {
  if (![0, 20, 50, 100].includes(settings.historyLimit)) {
    return "历史数量只能选择 0、20、50 或 100。";
  }
  if (!Number.isSafeInteger(settings.retentionDays) || settings.retentionDays < 0) {
    return "历史保留天数必须是非负整数。";
  }
  if (!["system", "light", "dark"].includes(settings.themeMode)) {
    return "主题只能选择跟随系统、浅色或深色。";
  }
  return null;
}
