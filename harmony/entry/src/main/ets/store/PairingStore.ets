import {
  PairingInvitationError,
  PairingInvitationParseResult,
  PairingInvitationService,
  PairingInvitationSummary
} from '../services/pairing/PairingInvitationService';

export enum PairingStoreState {
  IDLE = 'idle',
  READY = 'ready',
  PENDING = 'pending',
  ERROR = 'error'
}

export interface PairingStoreSnapshot {
  state: PairingStoreState;
  invitationText: string;
  statusText: string;
  summary: PairingInvitationSummary | null;
  error: PairingInvitationError | null;
}

export class PairingStore {
  private readonly service: PairingInvitationService = new PairingInvitationService();
  private currentSnapshot: PairingStoreSnapshot = createInitialPairingSnapshot();

  snapshot(): PairingStoreSnapshot {
    return cloneSnapshot(this.currentSnapshot);
  }

  updateInvitationText(value: string): PairingStoreSnapshot {
    this.currentSnapshot = {
      state: PairingStoreState.IDLE,
      invitationText: value,
      statusText: '已更新输入，点击“校验邀请”后解析',
      summary: null,
      error: null
    };
    return this.snapshot();
  }

  parseCurrent(nowMs: number = Date.now()): PairingStoreSnapshot {
    const result = this.service.parse(this.currentSnapshot.invitationText, nowMs);
    this.currentSnapshot = this.snapshotFromResult(result);
    return this.snapshot();
  }

  importInvitationText(value: string, nowMs: number = Date.now()): PairingStoreSnapshot {
    this.currentSnapshot = {
      state: PairingStoreState.IDLE,
      invitationText: value,
      statusText: '已从系统 PasteButton 读取邀请，正在校验',
      summary: null,
      error: null
    };
    return this.parseCurrent(nowMs);
  }

  confirmCodeMatched(): PairingStoreSnapshot {
    if (this.currentSnapshot.summary === null) {
      this.currentSnapshot = {
        state: PairingStoreState.ERROR,
        invitationText: this.currentSnapshot.invitationText,
        statusText: '请先导入并校验有效邀请，再继续配对。',
        summary: null,
        error: PairingInvitationError.INVALID_PAYLOAD
      };
      return this.snapshot();
    }
    this.currentSnapshot = {
      state: PairingStoreState.PENDING,
      invitationText: this.currentSnapshot.invitationText,
      statusText: '已确认六位码一致。等待接入身份交换、握手和 spaceKey 安全接收。',
      summary: cloneSummary(this.currentSnapshot.summary),
      error: null
    };
    return this.snapshot();
  }

  clear(): PairingStoreSnapshot {
    this.currentSnapshot = createInitialPairingSnapshot();
    return this.snapshot();
  }

  private snapshotFromResult(result: PairingInvitationParseResult): PairingStoreSnapshot {
    if (result.ok && result.summary !== undefined) {
      return {
        state: PairingStoreState.READY,
        invitationText: this.currentSnapshot.invitationText,
        statusText: '邀请格式有效。下一步将接入身份交换、确认码核对和 spaceKey 安全接收。',
        summary: result.summary,
        error: null
      };
    }
    return {
      state: PairingStoreState.ERROR,
      invitationText: this.currentSnapshot.invitationText,
      statusText: this.service.describeError(result),
      summary: null,
      error: result.error ?? PairingInvitationError.INVALID_PAYLOAD
    };
  }
}

export function createInitialPairingSnapshot(): PairingStoreSnapshot {
  return {
    state: PairingStoreState.IDLE,
    invitationText: '',
    statusText: '从桌面端复制配对邀请后，粘贴到这里进行校验。',
    summary: null,
    error: null
  };
}

function cloneSnapshot(snapshot: PairingStoreSnapshot): PairingStoreSnapshot {
  return {
    state: snapshot.state,
    invitationText: snapshot.invitationText,
    statusText: snapshot.statusText,
    summary: cloneSummary(snapshot.summary),
    error: snapshot.error
  };
}

function cloneSummary(summary: PairingInvitationSummary | null): PairingInvitationSummary | null {
  if (summary === null) {
    return null;
  }
  return {
    invitationId: summary.invitationId,
    spaceId: summary.spaceId,
    spaceShortId: summary.spaceShortId,
    spaceKeyVersion: summary.spaceKeyVersion,
    issuerDeviceName: summary.issuerDeviceName,
    issuerDeviceId: summary.issuerDeviceId,
    issuerShortFingerprint: summary.issuerShortFingerprint,
    expiresAtMs: summary.expiresAtMs,
    expiresInSeconds: summary.expiresInSeconds,
    confirmationCode: summary.confirmationCode
  };
}
