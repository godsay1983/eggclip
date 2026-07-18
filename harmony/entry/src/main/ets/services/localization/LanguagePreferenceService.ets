import { i18n } from '@kit.LocalizationKit';

export enum LanguageMode {
  SYSTEM = 'system',
  ZH_CN = 'zh-CN',
  EN_US = 'en-US'
}

export enum SupportedLocale {
  ZH_CN = 'zh-CN',
  EN_US = 'en-US'
}

export const DEFAULT_LANGUAGE_MODE: LanguageMode = LanguageMode.SYSTEM;
export const DEFAULT_LOCALE: SupportedLocale = SupportedLocale.EN_US;

export interface AppLanguageGateway {
  getAppPreferredLanguage(): string;
  getFirstSystemPreferredLanguage(): string;
  setAppPreferredLanguage(language: string): void;
}

class SystemAppLanguageGateway implements AppLanguageGateway {
  getAppPreferredLanguage(): string {
    return i18n.System.getAppPreferredLanguage();
  }

  getFirstSystemPreferredLanguage(): string {
    return i18n.System.getFirstPreferredLanguage();
  }

  setAppPreferredLanguage(language: string): void {
    i18n.System.setAppPreferredLanguage(language);
  }
}

export class LanguagePreferenceService {
  private readonly gateway: AppLanguageGateway;

  constructor(gateway?: AppLanguageGateway) {
    this.gateway = gateway ?? new SystemAppLanguageGateway();
  }

  loadMode(): LanguageMode {
    return languageModeFromPreferredLanguage(this.gateway.getAppPreferredLanguage());
  }

  saveMode(mode: LanguageMode): void {
    this.gateway.setAppPreferredLanguage(preferredLanguageFromMode(mode));
  }

  currentLocale(): SupportedLocale {
    return resolveEffectiveLocale(this.loadMode(), [this.gateway.getFirstSystemPreferredLanguage()]);
  }
}

export function languageModeFromPreferredLanguage(value: string): LanguageMode {
  const normalized = normalizeLanguageTag(value);
  if (normalized === 'zh-cn') {
    return LanguageMode.ZH_CN;
  }
  if (normalized === 'en-us') {
    return LanguageMode.EN_US;
  }
  return LanguageMode.SYSTEM;
}

export function preferredLanguageFromMode(mode: LanguageMode): string {
  return mode === LanguageMode.SYSTEM ? 'default' : mode;
}

export function resolveEffectiveLocale(
  mode: LanguageMode,
  systemLanguages: string[]
): SupportedLocale {
  if (mode === LanguageMode.ZH_CN) {
    return SupportedLocale.ZH_CN;
  }
  if (mode === LanguageMode.EN_US) {
    return SupportedLocale.EN_US;
  }
  for (let index = 0; index < systemLanguages.length; index += 1) {
    const normalized = normalizeLanguageTag(systemLanguages[index]);
    if (normalized.startsWith('zh')) {
      return SupportedLocale.ZH_CN;
    }
    if (normalized.startsWith('en')) {
      return SupportedLocale.EN_US;
    }
  }
  return DEFAULT_LOCALE;
}

function normalizeLanguageTag(value: string): string {
  return value.trim().replace('_', '-').toLowerCase();
}
