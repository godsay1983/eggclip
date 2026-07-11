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
  errorMessage: string;
}

export class SettingsStore {
  private readonly repository: SettingsRdbRepository;
  private readonly clipboardRepository: ClipboardRdbRepository;
  private readonly spaceRepository: SpaceRdbRepository;
  private readonly spaceKeySelfTest: SpaceKeyCryptoSelfTestService;
  private readonly spaceKeyRecovery: SpaceKeyRecoveryService;
  private currentState: SettingsStoreState = SettingsStoreState.IDLE;
  private currentSettings: AppSettings = defaultAppSettings();
  private currentErrorMessage: string = '';

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
      errorMessage: this.currentErrorMessage
    };
  }

  async load(): Promise<SettingsStoreSnapshot> {
    this.currentState = SettingsStoreState.LOADING;
    this.currentErrorMessage = '';
    try {
      const loaded = await this.repository.loadAppSettings();
      this.currentSettings = loaded === null ? defaultAppSettings() : cloneSettings(loaded);
      this.currentState = SettingsStoreState.READY;
    } catch (_) {
      this.currentState = SettingsStoreState.ERROR;
      this.currentErrorMessage = '读取设置失败';
    }
    return this.snapshot();
  }

  async save(settings: AppSettings): Promise<SettingsStoreSnapshot> {
    const validation = validateAppSettings(settings);
    if (!validation.ok) {
      this.currentState = SettingsStoreState.ERROR;
      this.currentErrorMessage = '设置参数无效';
      return this.snapshot();
    }

    this.currentState = SettingsStoreState.SAVING;
    this.currentSettings = cloneSettings(settings);
    this.currentErrorMessage = '';
    try {
      const nowMs = Date.now();
      await this.repository.saveAppSettings(this.currentSettings, nowMs);
      await this.clipboardRepository.applyRetentionAll(this.currentSettings, nowMs);
      this.currentState = SettingsStoreState.READY;
    } catch (_) {
      this.currentState = SettingsStoreState.ERROR;
      this.currentErrorMessage = '保存设置失败';
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
    this.currentErrorMessage = '';
    try {
      await this.clipboardRepository.clearAllHistory(Date.now());
      this.currentState = SettingsStoreState.READY;
    } catch (_) {
      this.currentState = SettingsStoreState.ERROR;
      this.currentErrorMessage = '清空历史失败';
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
    errorMessage: ''
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
