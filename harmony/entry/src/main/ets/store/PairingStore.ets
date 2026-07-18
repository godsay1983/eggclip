import {
  PairingInvitationError,
  PairingConnectionEndpoint,
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
import {
  LocalDeviceIdentityError,
  LocalDeviceIdentityService
} from '../services/crypto/LocalDeviceIdentityService';
import {
  UiMessageCode,
  UiMessageDescriptor,
  cloneUiMessage,
  uiMessage
} from '../services/localization/UiMessageCodes';

export enum PairingStoreState {
  IDLE = 'idle',
  READY = 'ready',
  PENDING = 'pending',
  COMPLETED = 'completed',
  ERROR = 'error'
}

export interface PairingStoreSnapshot {
  state: PairingStoreState;
  invitationText: string;
  statusMessage: UiMessageDescriptor;
  summary: PairingInvitationSummary | null;
  error: PairingInvitationError | null;
}

export interface PairingGeneratedHandshakeMaterialResult {
  ok: boolean;
  draft?: PairingHandshakeDraft;
  localDeviceId?: string;
  localIdentityPublicKey?: string;
  localIdentityPrivateKeyRef?: string;
  localEphemeralPrivateKey?: string;
  localEphemeralPublicKey?: string;
  handshakeError?: PairingHandshakeDraftError;
  keyAgreementError?: X25519KeyAgreementError;
  identityError?: LocalDeviceIdentityError;
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
      localDeviceId,
      localIdentityPublicKey,
      localEphemeralPrivateKey: keyPair.privateKey,
      localEphemeralPublicKey: keyPair.publicKey
    };
  }

  async buildPendingClientHandshakeMaterialWithLocalIdentity(
    identityProvider: LocalDeviceIdentityService,
    nowMs: number = Date.now(),
    aliasSlot: string = 'v1'
  ): Promise<PairingGeneratedHandshakeMaterialResult> {
    if (!this.hasPendingHandshakeMaterial()) {
      return {
        ok: false,
        handshakeError: PairingHandshakeDraftError.MISSING_PENDING_INVITATION
      };
    }

    const identity = await identityProvider.ensureLocalIdentity(nowMs, aliasSlot);
    if (!identity.ok || identity.identity === undefined) {
      return {
        ok: false,
        identityError: identity.error,
        field: identity.field
      };
    }

    const material = this.buildPendingClientHandshakeMaterial(
      identity.identity.deviceId,
      identity.identity.identityPublicKey,
      nowMs
    );
    if (!material.ok) {
      return material;
    }

    return {
      ok: true,
      draft: material.draft,
      localDeviceId: identity.identity.deviceId,
      localIdentityPublicKey: identity.identity.identityPublicKey,
      localIdentityPrivateKeyRef: identity.identity.identityPrivateKeyRef,
      localEphemeralPrivateKey: material.localEphemeralPrivateKey,
      localEphemeralPublicKey: material.localEphemeralPublicKey
    };
  }

  updateInvitationText(value: string): PairingStoreSnapshot {
    this.pendingPayload = null;
    this.currentSnapshot = {
      state: PairingStoreState.IDLE,
      invitationText: value,
      statusMessage: uiMessage(UiMessageCode.PAIRING_INPUT_UPDATED),
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
      statusMessage: uiMessage(UiMessageCode.PAIRING_PASTE_IMPORTED),
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
        statusMessage: uiMessage(UiMessageCode.PAIRING_VALID_REQUIRED),
        summary: null,
        error: PairingInvitationError.INVALID_PAYLOAD
      };
      return this.snapshot();
    }
    this.currentSnapshot = {
      state: PairingStoreState.PENDING,
      invitationText: '',
      statusMessage: uiMessage(UiMessageCode.PAIRING_CODE_MATCHED),
      summary: cloneSummary(this.currentSnapshot.summary),
      error: null
    };
    return this.snapshot();
  }

  completePairing(): PairingStoreSnapshot {
    const completedSummary = cloneSummary(this.currentSnapshot.summary);
    this.pendingPayload = null;
    this.currentSnapshot = {
      state: PairingStoreState.COMPLETED,
      invitationText: '',
      statusMessage: uiMessage(UiMessageCode.PAIRING_COMPLETED),
      summary: completedSummary,
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
        statusMessage: uiMessage(UiMessageCode.PAIRING_INVITATION_VALID),
        summary: result.summary,
        error: null
      };
    }
    this.pendingPayload = null;
    return {
      state: PairingStoreState.ERROR,
      invitationText: this.currentSnapshot.invitationText,
      statusMessage: uiMessage(UiMessageCode.PAIRING_INVITATION_INVALID),
      summary: null,
      error: result.error ?? PairingInvitationError.INVALID_PAYLOAD
    };
  }
}

export function createInitialPairingSnapshot(): PairingStoreSnapshot {
  return {
    state: PairingStoreState.IDLE,
    invitationText: '',
    statusMessage: uiMessage(UiMessageCode.PAIRING_INITIAL),
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
  if (payload.connectionHints !== undefined) {
    clone.connectionHints = {
      transport: payload.connectionHints.transport,
      endpoints: cloneEndpoints(payload.connectionHints.endpoints)
    };
  }
  return clone;
}

function cloneSnapshot(snapshot: PairingStoreSnapshot): PairingStoreSnapshot {
  return {
    state: snapshot.state,
    invitationText: snapshot.invitationText,
    statusMessage: cloneUiMessage(snapshot.statusMessage),
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
    confirmationCode: summary.confirmationCode,
    endpoints: cloneEndpoints(summary.endpoints)
  };
}

function cloneEndpoints(source: PairingConnectionEndpoint[]): PairingConnectionEndpoint[] {
  const endpoints: PairingConnectionEndpoint[] = [];
  for (let index = 0; index < source.length; index += 1) {
    const endpoint: PairingConnectionEndpoint = { host: source[index].host, port: source[index].port };
    endpoints.push(endpoint);
  }
  return endpoints;
}
