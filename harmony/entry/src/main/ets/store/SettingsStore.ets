import { common } from '@kit.AbilityKit';
import {
  AppSettings,
  defaultAppSettings,
  validateAppSettings
} from '../models/DomainModels';
import {
  ClipboardRdbRepository,
  SettingsRdbRepository,
  SpaceRdbRepository
} from '../data/repositories/RdbRepositories';
import {
  SpaceKeyCryptoSelfTestResult,
  SpaceKeyCryptoSelfTestService,
  SpaceKeyRefProvider
} from '../services/crypto/SpaceKeyCryptoSelfTestService';
import {
  SpaceKeyRecoveryRepository,
  SpaceKeyRecoveryResult,
  SpaceKeyRecoveryService
} from '../services/crypto/SpaceKeyRecoveryService';
import {
  UiMessageCode,
  UiMessageDescriptor,
  cloneUiMessage,
  uiMessage
} from '../services/localization/UiMessageCodes';

export enum SettingsStoreState {
  IDLE = 'idle',
  LOADING = 'loading',
  READY = 'ready',
  SAVING = 'saving',
  ERROR = 'error'
}

export interface SettingsStoreSnapshot {
  state: SettingsStoreState;
  settings: AppSettings;
  errorMessage: UiMessageDescriptor | null;
}

export class SettingsStore {
  private readonly repository: SettingsRdbRepository;
  private readonly clipboardRepository: ClipboardRdbRepository;
  private readonly spaceRepository: SpaceRdbRepository;
  private readonly spaceKeySelfTest: SpaceKeyCryptoSelfTestService;
  private readonly spaceKeyRecovery: SpaceKeyRecoveryService;
  private currentState: SettingsStoreState = SettingsStoreState.IDLE;
  private currentSettings: AppSettings = defaultAppSettings();
  private currentErrorMessage: UiMessageDescriptor | null = null;

  constructor(context: common.Context) {
    this.repository = new SettingsRdbRepository(context);
    this.clipboardRepository = new ClipboardRdbRepository(context);
    this.spaceRepository = new SpaceRdbRepository(context);
    this.spaceKeySelfTest = new SpaceKeyCryptoSelfTestService(
      new SettingsSpaceKeyRefProvider(this.spaceRepository),
      undefined,
      undefined,
      true
    );
    this.spaceKeyRecovery = new SpaceKeyRecoveryService(
      new SettingsSpaceKeyRecoveryRepository(this.spaceRepository)
    );
  }

  snapshot(): SettingsStoreSnapshot {
    return {
      state: this.currentState,
      settings: cloneSettings(this.currentSettings),
      errorMessage: this.currentErrorMessage === null ? null : cloneUiMessage(this.currentErrorMessage)
    };
  }

  async load(): Promise<SettingsStoreSnapshot> {
    this.currentState = SettingsStoreState.LOADING;
    this.currentErrorMessage = null;
    try {
      const loaded = await this.repository.loadAppSettings();
      const storedSettings = loaded === null ? defaultAppSettings() : loaded;
      this.currentSettings = normalizeHarmonySettings(storedSettings);
      if (loaded !== null && loaded.autoWriteEnabled) {
        await this.repository.saveAppSettings(this.currentSettings, Date.now());
      }
      this.currentState = SettingsStoreState.READY;
    } catch (_) {
      this.currentState = SettingsStoreState.ERROR;
      this.currentErrorMessage = uiMessage(UiMessageCode.SETTINGS_READ_FAILED);
    }
    return this.snapshot();
  }

  async save(settings: AppSettings): Promise<SettingsStoreSnapshot> {
    const normalizedSettings = normalizeHarmonySettings(settings);
    const validation = validateAppSettings(normalizedSettings);
    if (!validation.ok) {
      this.currentState = SettingsStoreState.ERROR;
      this.currentErrorMessage = uiMessage(UiMessageCode.SETTINGS_INVALID);
      return this.snapshot();
    }

    this.currentState = SettingsStoreState.SAVING;
    this.currentSettings = normalizedSettings;
    this.currentErrorMessage = null;
    try {
      const nowMs = Date.now();
      await this.repository.saveAppSettings(this.currentSettings, nowMs);
      await this.clipboardRepository.applyRetentionAll(this.currentSettings, nowMs);
      this.currentState = SettingsStoreState.READY;
    } catch (_) {
      this.currentState = SettingsStoreState.ERROR;
      this.currentErrorMessage = uiMessage(UiMessageCode.SETTINGS_SAVE_FAILED);
    }
    return this.snapshot();
  }

  async setSyncEnabled(syncEnabled: boolean): Promise<SettingsStoreSnapshot> {
    const next = cloneSettings(this.currentSettings);
    next.syncEnabled = syncEnabled;
    return this.save(next);
  }

  async clearLocalHistory(): Promise<SettingsStoreSnapshot> {
    this.currentState = SettingsStoreState.SAVING;
    this.currentErrorMessage = null;
    try {
      await this.clipboardRepository.clearAllHistory(Date.now());
      this.currentState = SettingsStoreState.READY;
    } catch (_) {
      this.currentState = SettingsStoreState.ERROR;
      this.currentErrorMessage = uiMessage(UiMessageCode.SETTINGS_CLEAR_HISTORY_FAILED);
    }
    return this.snapshot();
  }

  async runSpaceKeyCryptoSelfTest(): Promise<SpaceKeyCryptoSelfTestResult> {
    return this.spaceKeySelfTest.run();
  }

  async reinitializePairingSecurityState(): Promise<SpaceKeyRecoveryResult> {
    return this.spaceKeyRecovery.reinitializePairingSecurityState();
  }
}

class SettingsSpaceKeyRefProvider implements SpaceKeyRefProvider {
  private readonly spaceRepository: SpaceRdbRepository;

  constructor(spaceRepository: SpaceRdbRepository) {
    this.spaceRepository = spaceRepository;
  }

  async loadLatestEncryptedSpaceKeyRef(): Promise<string | null> {
    const record = await this.spaceRepository.latestActiveWithKeyRef();
    return record?.encryptedSpaceKeyRef ?? null;
  }
}

class SettingsSpaceKeyRecoveryRepository implements SpaceKeyRecoveryRepository {
  private readonly spaceRepository: SpaceRdbRepository;

  constructor(spaceRepository: SpaceRdbRepository) {
    this.spaceRepository = spaceRepository;
  }

  async listEncryptedSpaceKeyRefs(): Promise<string[]> {
    return this.spaceRepository.listEncryptedSpaceKeyRefs();
  }

  async resetPairingSecurityState(): Promise<void> {
    return this.spaceRepository.resetPairingSecurityState();
  }
}

export function createInitialSettingsSnapshot(): SettingsStoreSnapshot {
  return {
    state: SettingsStoreState.IDLE,
    settings: defaultAppSettings(),
    errorMessage: null
  };
}

export function cloneSettings(settings: AppSettings): AppSettings {
  return {
    syncEnabled: settings.syncEnabled,
    autoReceiveEnabled: settings.autoReceiveEnabled,
    autoWriteEnabled: settings.autoWriteEnabled,
    historyEnabled: settings.historyEnabled,
    historyLimit: settings.historyLimit,
    retentionDays: settings.retentionDays,
    themeMode: settings.themeMode
  };
}

// HarmonyOS v1 only writes received text after an explicit user copy action.
// Persisting auto-write as disabled prevents stale settings from bypassing that boundary.
export function normalizeHarmonySettings(settings: AppSettings): AppSettings {
  const normalized = cloneSettings(settings);
  normalized.autoWriteEnabled = false;
  return normalized;
}
