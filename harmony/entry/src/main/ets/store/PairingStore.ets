import {
  PairingInvitationError,
  PairingInvitationPayload,
  PairingInvitationParseResult,
  PairingInvitationService,
  PairingInvitationSummary
} from '../services/pairing/PairingInvitationService';
import {
  PairingHandshakeDraft,
  PairingHandshakeDraftError,
  PairingHandshakeDraftResult,
  PairingHandshakeDraftService
} from '../services/pairing/PairingHandshakeDraftService';
import {
  X25519KeyAgreementError,
  X25519KeyAgreementService
} from '../services/crypto/X25519KeyAgreementService';

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

export interface PairingGeneratedHandshakeMaterialResult {
  ok: boolean;
  draft?: PairingHandshakeDraft;
  localEphemeralPrivateKey?: string;
  localEphemeralPublicKey?: string;
  handshakeError?: PairingHandshakeDraftError;
  keyAgreementError?: X25519KeyAgreementError;
  field?: string;
}

export class PairingStore {
  private readonly service: PairingInvitationService = new PairingInvitationService();
  private readonly handshakeDraftService: PairingHandshakeDraftService = new PairingHandshakeDraftService();
  private readonly keyAgreement: X25519KeyAgreementService = new X25519KeyAgreementService();
  private currentSnapshot: PairingStoreSnapshot = createInitialPairingSnapshot();
  private pendingPayload: PairingInvitationPayload | null = null;

  snapshot(): PairingStoreSnapshot {
    return cloneSnapshot(this.currentSnapshot);
  }

  hasPendingHandshakeMaterial(): boolean {
    return this.currentSnapshot.state === PairingStoreState.PENDING && this.pendingPayload !== null;
  }

  buildPendingClientHandshakeDraft(
    localDeviceId: string,
    localIdentityPublicKey: string,
    localEphemeralPublicKey: string,
    nowMs: number = Date.now()
  ): PairingHandshakeDraftResult {
    if (!this.hasPendingHandshakeMaterial()) {
      return this.handshakeDraftService.buildClientHandshakeDraft({
        invitation: null,
        localDeviceId,
        localIdentityPublicKey,
        localEphemeralPublicKey,
        nowMs
      });
    }
    return this.handshakeDraftService.buildClientHandshakeDraft({
      invitation: clonePayload(this.pendingPayload as PairingInvitationPayload),
      localDeviceId,
      localIdentityPublicKey,
      localEphemeralPublicKey,
      nowMs
    });
  }

  buildPendingClientHandshakeMaterial(
    localDeviceId: string,
    localIdentityPublicKey: string,
    nowMs: number = Date.now()
  ): PairingGeneratedHandshakeMaterialResult {
    if (!this.hasPendingHandshakeMaterial()) {
      return {
        ok: false,
        handshakeError: PairingHandshakeDraftError.MISSING_PENDING_INVITATION
      };
    }

    const keyPair = this.keyAgreement.generateEphemeralKeyPair();
    if (!keyPair.ok || keyPair.privateKey === undefined || keyPair.publicKey === undefined) {
      return {
        ok: false,
        keyAgreementError: keyPair.error,
        field: keyPair.field
      };
    }

    const draft = this.handshakeDraftService.buildClientHandshakeDraft({
      invitation: clonePayload(this.pendingPayload as PairingInvitationPayload),
      localDeviceId,
      localIdentityPublicKey,
      localEphemeralPublicKey: keyPair.publicKey,
      nowMs
    });
    if (!draft.ok || draft.draft === undefined) {
      return {
        ok: false,
        handshakeError: draft.error,
        field: draft.field
      };
    }

    return {
      ok: true,
      draft: draft.draft,
      localEphemeralPrivateKey: keyPair.privateKey,
      localEphemeralPublicKey: keyPair.publicKey
    };
  }

  updateInvitationText(value: string): PairingStoreSnapshot {
    this.pendingPayload = null;
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
    if (this.currentSnapshot.summary === null || this.pendingPayload === null) {
      this.pendingPayload = null;
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
      invitationText: '',
      statusText: '已确认六位码一致。邀请 secret 已从可见输入中清理，等待接入身份交换、握手和 spaceKey 安全接收。',
      summary: cloneSummary(this.currentSnapshot.summary),
      error: null
    };
    return this.snapshot();
  }

  clear(): PairingStoreSnapshot {
    this.pendingPayload = null;
    this.currentSnapshot = createInitialPairingSnapshot();
    return this.snapshot();
  }

  private snapshotFromResult(result: PairingInvitationParseResult): PairingStoreSnapshot {
    if (result.ok && result.summary !== undefined && result.payload !== undefined) {
      this.pendingPayload = clonePayload(result.payload);
      return {
        state: PairingStoreState.READY,
        invitationText: this.currentSnapshot.invitationText,
        statusText: '邀请格式有效。下一步将接入身份交换、确认码核对和 spaceKey 安全接收。',
        summary: result.summary,
        error: null
      };
    }
    this.pendingPayload = null;
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

function clonePayload(payload: PairingInvitationPayload): PairingInvitationPayload {
  const clone: PairingInvitationPayload = {
    app: payload.app,
    version: payload.version,
    kind: payload.kind,
    spaceId: payload.spaceId,
    spaceKeyVersion: payload.spaceKeyVersion,
    issuerDeviceId: payload.issuerDeviceId,
    issuerIdentityPublicKey: payload.issuerIdentityPublicKey,
    pairingSecret: payload.pairingSecret,
    expiresAtMs: payload.expiresAtMs
  };
  if (payload.invitationId !== undefined) {
    clone.invitationId = payload.invitationId;
  }
  if (payload.issuerDeviceName !== undefined) {
    clone.issuerDeviceName = payload.issuerDeviceName;
  }
  return clone;
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
