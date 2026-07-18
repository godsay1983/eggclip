import { derived, writable } from "svelte/store";
import { resolveEffectiveLocale } from "$lib/i18n/locale";
import { enUSMessages } from "$lib/i18n/messages/en-US";
import { zhCNMessages } from "$lib/i18n/messages/zh-CN";
import type {
  LanguageMode,
  MessageArguments,
  MessageCatalog,
  MessageKey,
  SupportedLocale,
} from "$lib/i18n/types";

const catalogs: Record<SupportedLocale, MessageCatalog> = {
  "zh-CN": zhCNMessages,
  "en-US": enUSMessages,
};

const languageModeState = writable<LanguageMode>("system");

export const languageMode = {
  subscribe: languageModeState.subscribe,
  set: languageModeState.set,
};

export const effectiveLocale = derived(languageModeState, ($languageMode) =>
  resolveEffectiveLocale($languageMode),
);

export function setLanguageMode(value: LanguageMode): void {
  languageModeState.set(value);
}

export function translate<Key extends MessageKey>(
  locale: SupportedLocale,
  key: Key,
  ...args: MessageArguments[Key]
): string {
  const message: (...values: MessageArguments[Key]) => string = catalogs[locale][key];
  return message(...args);
}

export type { LanguageMode, MessageKey, SupportedLocale } from "$lib/i18n/types";
export { formatDateTime, formatTime } from "$lib/i18n/format";
export {
  DEFAULT_LANGUAGE_MODE,
  DEFAULT_LOCALE,
  isLanguageMode,
  readSystemLanguages,
  resolveEffectiveLocale,
  resolveSystemLocale,
} from "$lib/i18n/locale";
