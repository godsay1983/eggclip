import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import {
  LocalClipboardSyncPolicy,
  defaultAppSettings,
  localClipboardSyncPolicy
} from '../models/DomainModels';
import {
  ClipboardRdbRepository,
  SettingsRdbRepository
} from '../data/repositories/RdbRepositories';
import { ClipboardItemRecord } from '../data/repositories/RepositoryCommands';
import { LocalClipboardPersistenceService } from '../services/sync/LocalClipboardPersistenceService';
import { OutboundItemBatchService } from '../services/sync/OutboundItemBatchService';
import { ClipboardBridgeService } from '../services/clipboard/ClipboardBridgeService';
import {
  UiMessageCode,
  UiMessageDescriptor,
  cloneUiMessage,
  uiMessage
} from '../services/localization/UiMessageCodes';

const HISTORY_PREVIEW_LIMIT: number = 5;
const LOCAL_HISTORY_SPACE_ID: string = '018ff6ef-c394-7d08-8b99-4b7d10f2767a';
const LOCAL_HISTORY_ENCRYPTED_PLACEHOLDER: Uint8Array = asciiBytes('eggclip-local-history-metadata-only-v1');

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
  errorMessage: UiMessageDescriptor | null;
}

export interface HistoryPreviewItem {
  id: string;
  title: string;
  preview: string;
  source: string;
  receivedAt: string;
  text: string;
  canCopy: boolean;
  contentLength: number;
}

export interface LocalBroadcastPolicySnapshot {
  allowed: boolean;
  message: UiMessageDescriptor;
}

export class HistoryStore {
  private readonly clipboardRepository: ClipboardRdbRepository;
  private readonly settingsRepository: SettingsRdbRepository;
  private readonly persistenceService: LocalClipboardPersistenceService;
  private readonly historyContentService: OutboundItemBatchService;
  private readonly clipboardBridge: ClipboardBridgeService = new ClipboardBridgeService();
  private currentState: HistoryStoreState = HistoryStoreState.IDLE;
  private currentUsed: number = 0;
  private currentLimit: number = defaultAppSettings().historyLimit;
  private currentItems: HistoryPreviewItem[] = [];
  private currentErrorMessage: UiMessageDescriptor | null = null;

  constructor(context: common.Context) {
    this.clipboardRepository = new ClipboardRdbRepository(context);
    this.settingsRepository = new SettingsRdbRepository(context);
    this.persistenceService = new LocalClipboardPersistenceService(context);
    this.historyContentService = new OutboundItemBatchService(context);
  }

  snapshot(): HistoryStoreSnapshot {
    return {
      state: this.currentState,
      used: this.currentUsed,
      limit: this.currentLimit,
      items: this.currentItems,
      errorMessage: this.currentErrorMessage === null ? null : cloneUiMessage(this.currentErrorMessage)
    };
  }

  async loadSummary(): Promise<HistoryStoreSnapshot> {
    this.currentState = HistoryStoreState.LOADING;
    this.currentErrorMessage = null;
    try {
      const settings = await this.settingsRepository.loadAppSettings();
      this.currentLimit = (settings ?? defaultAppSettings()).historyLimit;
      this.currentUsed = await this.clipboardRepository.countAllActive();
      const records = await this.clipboardRepository.listRecentAll(HISTORY_PREVIEW_LIMIT);
      const items: HistoryPreviewItem[] = [];
      for (let index = 0; index < records.length; index += 1) {
        const restored = await this.historyContentService.restoreHistoryRecord(records[index]);
        items.push(toHistoryPreviewItem(records[index], restored?.content ?? ''));
      }
      this.currentItems = items;
      this.currentState = HistoryStoreState.READY;
    } catch (_) {
      this.currentState = HistoryStoreState.ERROR;
      this.currentItems = [];
      this.currentErrorMessage = uiMessage(UiMessageCode.HISTORY_LOAD_FAILED);
    }
    return this.snapshot();
  }

  async deleteItem(itemId: string): Promise<HistoryStoreSnapshot> {
    this.currentState = HistoryStoreState.LOADING;
    this.currentErrorMessage = null;
    try {
      await this.clipboardRepository.markDeleted(itemId, Date.now());
    } catch (_) {
      this.currentState = HistoryStoreState.ERROR;
      this.currentErrorMessage = uiMessage(UiMessageCode.HISTORY_DELETE_FAILED);
      return this.snapshot();
    }
    return this.loadSummary();
  }

  async clearAll(): Promise<HistoryStoreSnapshot> {
    this.currentState = HistoryStoreState.LOADING;
    this.currentErrorMessage = null;
    try {
      await this.clipboardRepository.clearAllHistory(Date.now());
    } catch (_) {
      this.currentState = HistoryStoreState.ERROR;
      this.currentErrorMessage = uiMessage(UiMessageCode.HISTORY_CLEAR_FAILED);
      return this.snapshot();
    }
    return this.loadSummary();
  }

  async captureLocalText(text: string): Promise<HistoryStoreSnapshot> {
    this.currentState = HistoryStoreState.LOADING;
    this.currentErrorMessage = null;
    try {
      const settings = await this.settingsRepository.loadAppSettings() ?? defaultAppSettings();
      if (!settings.historyEnabled || settings.historyLimit === 0) {
        return this.loadSummary();
      }
      await this.persistenceService.persist({
        spaceId: LOCAL_HISTORY_SPACE_ID,
        text,
        contentDigest: localHistoryDigest(),
        encryptedContent: LOCAL_HISTORY_ENCRYPTED_PLACEHOLDER,
        settings,
        nowMs: Date.now()
      });
    } catch (_) {
      this.currentState = HistoryStoreState.ERROR;
      this.currentErrorMessage = uiMessage(UiMessageCode.HISTORY_SAVE_FAILED);
      return this.snapshot();
    }
    return this.loadSummary();
  }

  async loadLocalBroadcastPolicy(): Promise<LocalBroadcastPolicySnapshot> {
    const settings = await this.settingsRepository.loadAppSettings() ?? defaultAppSettings();
    const policy: LocalClipboardSyncPolicy = localClipboardSyncPolicy(settings);
    return {
      allowed: policy.broadcastAfterCommit,
      message: policy.broadcastAfterCommit ?
        uiMessage(UiMessageCode.HISTORY_BROADCAST_ALLOWED) :
        uiMessage(UiMessageCode.HISTORY_BROADCAST_PAUSED)
    };
  }

  async copyItem(itemId: string): Promise<boolean> {
    const item = this.currentItems.find((candidate: HistoryPreviewItem): boolean => candidate.id === itemId);
    if (item === undefined || !item.canCopy) return false;
    const result = await this.clipboardBridge.writePlainTextByUserAction(item.text);
    return result.ok;
  }
}

export function createInitialHistorySnapshot(): HistoryStoreSnapshot {
  return {
    state: HistoryStoreState.IDLE,
    used: 0,
    limit: defaultAppSettings().historyLimit,
    items: [],
    errorMessage: null
  };
}

function toHistoryPreviewItem(record: ClipboardItemRecord, text: string): HistoryPreviewItem {
  return {
    id: record.item.itemId,
    title: `${record.item.contentLength} 字节文本`,
    preview: text.length > 0 ? trimPreview(text) : '内容暂不可用',
    source: `来源设备 ${record.item.originDeviceId.slice(0, 8)}`,
    receivedAt: formatTime(record.receivedAt),
    text,
    canCopy: text.length > 0,
    contentLength: record.item.contentLength
  };
}

function trimPreview(text: string): string {
  return text.length > 180 ? `${text.slice(0, 180)}…` : text;
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

function localHistoryDigest(): string {
  return util.generateRandomUUID(false).toLowerCase().split('-').join('');
}

function asciiBytes(value: string): Uint8Array {
  const bytes = new Uint8Array(value.length);
  for (let index = 0; index < value.length; index += 1) {
    bytes[index] = value.charCodeAt(index) & 0xff;
  }
  return bytes;
}
