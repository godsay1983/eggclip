import { common } from '@kit.AbilityKit';
import { defaultAppSettings } from '../models/DomainModels';
import {
  ClipboardRdbRepository,
  SettingsRdbRepository
} from '../data/repositories/RdbRepositories';
import { ClipboardItemRecord } from '../data/repositories/RepositoryCommands';

const HISTORY_PREVIEW_LIMIT: number = 5;

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
  items: HistoryPreviewItem[];
  errorMessage: string;
}

export interface HistoryPreviewItem {
  id: string;
  title: string;
  preview: string;
  source: string;
  receivedAt: string;
}

export class HistoryStore {
  private readonly clipboardRepository: ClipboardRdbRepository;
  private readonly settingsRepository: SettingsRdbRepository;
  private currentState: HistoryStoreState = HistoryStoreState.IDLE;
  private currentUsed: number = 0;
  private currentLimit: number = defaultAppSettings().historyLimit;
  private currentItems: HistoryPreviewItem[] = [];
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
      items: this.currentItems,
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
      const records = await this.clipboardRepository.listRecentAll(HISTORY_PREVIEW_LIMIT);
      this.currentItems = records.map((record: ClipboardItemRecord): HistoryPreviewItem => {
        return toHistoryPreviewItem(record);
      });
      this.currentState = HistoryStoreState.READY;
    } catch (_) {
      this.currentState = HistoryStoreState.ERROR;
      this.currentItems = [];
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
    items: [],
    errorMessage: ''
  };
}

function toHistoryPreviewItem(record: ClipboardItemRecord): HistoryPreviewItem {
  return {
    id: record.item.itemId,
    title: `${record.item.contentLength} 字节文本`,
    preview: '内容已保存；正文预览将在密钥解密链路接入后显示',
    source: `来源设备 ${record.item.originDeviceId.slice(0, 8)}`,
    receivedAt: formatTime(record.receivedAt)
  };
}

function formatTime(milliseconds: number): string {
  const date = new Date(milliseconds);
  const hours = padTime(date.getHours());
  const minutes = padTime(date.getMinutes());
  const seconds = padTime(date.getSeconds());
  return `${hours}:${minutes}:${seconds}`;
}

function padTime(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}
