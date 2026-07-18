import type { LanguageMode } from "$lib/i18n/types";
import type { UiMessageDescriptor } from "$lib/i18n";

export type { LanguageMode } from "$lib/i18n/types";

export type ThemeMode = "system" | "light" | "dark";

export interface AppSettings {
  syncEnabled: boolean;
  autoReceiveEnabled: boolean;
  autoWriteEnabled: boolean;
  historyEnabled: boolean;
  historyLimit: 0 | 20 | 50 | 100;
  retentionDays: number;
  themeMode: ThemeMode;
  languageMode: LanguageMode;
}

export type SettingsLoadState = "idle" | "loading" | "ready" | "saving" | "error";

export interface SettingsSnapshot {
  state: SettingsLoadState;
  settings: AppSettings;
  errorMessage: UiMessageDescriptor | null;
}
