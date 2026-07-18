import type { LanguageMode, SupportedLocale } from "$lib/i18n/types";

export const DEFAULT_LANGUAGE_MODE: LanguageMode = "system";
export const DEFAULT_LOCALE: SupportedLocale = "en-US";

export function isLanguageMode(value: unknown): value is LanguageMode {
  return value === "system" || value === "zh-CN" || value === "en-US";
}

export function resolveSystemLocale(languages: readonly string[]): SupportedLocale {
  for (const language of languages) {
    const normalized = language.trim().toLowerCase();
    if (normalized.startsWith("zh")) {
      return "zh-CN";
    }
    if (normalized.startsWith("en")) {
      return "en-US";
    }
  }
  return DEFAULT_LOCALE;
}

export function resolveEffectiveLocale(
  languageMode: LanguageMode,
  systemLanguages: readonly string[] = readSystemLanguages(),
): SupportedLocale {
  return languageMode === "system"
    ? resolveSystemLocale(systemLanguages)
    : languageMode;
}

export function readSystemLanguages(): readonly string[] {
  if (typeof navigator === "undefined") {
    return [];
  }
  if (navigator.languages.length > 0) {
    return navigator.languages;
  }
  return navigator.language.length > 0 ? [navigator.language] : [];
}
