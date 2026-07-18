import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { i18n } from '@kit.LocalizationKit';

const LANGUAGE_PREFERENCES_NAME: string = 'eggclip_language_preferences';
const LANGUAGE_MODE_KEY: string = 'language_mode';

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

export interface LanguageModeStore {
  loadMode(): LanguageMode | null;
  saveMode(mode: LanguageMode): Promise<void>;
}

class LanguagePreferencesOptions implements preferences.Options {
  name: string = LANGUAGE_PREFERENCES_NAME;
}

class PreferencesLanguageModeStore implements LanguageModeStore {
  private readonly context: common.Context;

  constructor(context: common.Context) {
    this.context = context;
  }

  loadMode(): LanguageMode | null {
    try {
      const store = preferences.getPreferencesSync(this.context, new LanguagePreferencesOptions());
      return storedLanguageMode(store.getSync(LANGUAGE_MODE_KEY, ''));
    } catch (_) {
      return null;
    }
  }

  async saveMode(mode: LanguageMode): Promise<void> {
    const store = await preferences.getPreferences(this.context, LANGUAGE_PREFERENCES_NAME);
    await store.put(LANGUAGE_MODE_KEY, mode);
    await store.flush();
  }
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
  private readonly modeStore: LanguageModeStore | null;

  constructor(gateway?: AppLanguageGateway, modeStore?: LanguageModeStore) {
    this.gateway = gateway ?? new SystemAppLanguageGateway();
    this.modeStore = modeStore ?? null;
  }

  loadMode(): LanguageMode {
    const storedMode = this.modeStore?.loadMode() ?? null;
    if (storedMode !== null) {
      return storedMode;
    }
    return languageModeFromPreferredLanguage(this.gateway.getAppPreferredLanguage());
  }

  async saveMode(mode: LanguageMode): Promise<void> {
    this.gateway.setAppPreferredLanguage(preferredLanguageFromMode(mode));
    if (this.modeStore !== null) {
      await this.modeStore.saveMode(mode);
    }
  }

  currentLocale(): SupportedLocale {
    return resolveEffectiveLocale(this.loadMode(), [this.gateway.getFirstSystemPreferredLanguage()]);
  }
}

export function createPersistentLanguagePreferenceService(
  context: common.Context
): LanguagePreferenceService {
  return new LanguagePreferenceService(
    undefined,
    new PreferencesLanguageModeStore(context)
  );
}

export function languageModeFromPreferredLanguage(value: string): LanguageMode {
  const normalized = normalizeLanguageTag(value);
  if (normalized.startsWith('zh')) {
    return LanguageMode.ZH_CN;
  }
  if (normalized.startsWith('en')) {
    return LanguageMode.EN_US;
  }
  return LanguageMode.SYSTEM;
}

export function preferredLanguageFromMode(mode: LanguageMode): string {
  if (mode === LanguageMode.SYSTEM) {
    return 'default';
  }
  return mode === LanguageMode.ZH_CN ? 'zh-Hans-CN' : 'en-US';
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

function storedLanguageMode(value: preferences.ValueType): LanguageMode | null {
  if (value === LanguageMode.SYSTEM) {
    return LanguageMode.SYSTEM;
  }
  if (value === LanguageMode.ZH_CN) {
    return LanguageMode.ZH_CN;
  }
  if (value === LanguageMode.EN_US) {
    return LanguageMode.EN_US;
  }
  return null;
}
