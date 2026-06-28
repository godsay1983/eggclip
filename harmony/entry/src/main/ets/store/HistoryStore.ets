import { common } from '@kit.AbilityKit';
import { defaultAppSettings } from '../models/DomainModels';
import {
  ClipboardRdbRepository,
  SettingsRdbRepository
} from '../data/repositories/RdbRepositories';

export enum HistoryStoreState {
  IDLE = 'idle',
  LOADING = 'loading',
  READY = 'ready',
  ERROR = 'error'
}

export interface HistoryStoreSnapshot {
  state: HistoryStoreState;
  used: number;
  limit: number;
  errorMessage: string;
}

export class HistoryStore {
  private readonly clipboardRepository: ClipboardRdbRepository;
  private readonly settingsRepository: SettingsRdbRepository;
  private currentState: HistoryStoreState = HistoryStoreState.IDLE;
  private currentUsed: number = 0;
  private currentLimit: number = defaultAppSettings().historyLimit;
  private currentErrorMessage: string = '';

  constructor(context: common.Context) {
    this.clipboardRepository = new ClipboardRdbRepository(context);
    this.settingsRepository = new SettingsRdbRepository(context);
  }

  snapshot(): HistoryStoreSnapshot {
    return {
      state: this.currentState,
      used: this.currentUsed,
      limit: this.currentLimit,
      errorMessage: this.currentErrorMessage
    };
  }

  async loadSummary(): Promise<HistoryStoreSnapshot> {
    this.currentState = HistoryStoreState.LOADING;
    this.currentErrorMessage = '';
    try {
      const settings = await this.settingsRepository.loadAppSettings();
      this.currentLimit = (settings ?? defaultAppSettings()).historyLimit;
      this.currentUsed = await this.clipboardRepository.countAllActive();
      this.currentState = HistoryStoreState.READY;
    } catch (_) {
      this.currentState = HistoryStoreState.ERROR;
      this.currentErrorMessage = '读取历史摘要失败';
    }
    return this.snapshot();
  }
}

export function createInitialHistorySnapshot(): HistoryStoreSnapshot {
  return {
    state: HistoryStoreState.IDLE,
    used: 0,
    limit: defaultAppSettings().historyLimit,
    errorMessage: ''
  };
}
