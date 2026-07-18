import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import {
  PairingRdbRepository,
  ClipboardRdbRepository,
  SettingsRdbRepository,
  SpaceRdbRepository,
  SyncHeadRdbRepository,
  TrustedConnectionEndpointRecord
} from '../data/repositories/RdbRepositories';
import { DisplayNameOrigin, SyncHeadRecord } from '../data/repositories/RepositoryCommands';
import { LocalIdentityRdbRepository } from '../data/repositories/LocalIdentityRdbRepository';
import {
  DeviceConnectionState,
  DeviceTrustState,
  InboundClipboardEventKind,
  SpaceState
} from '../models/DomainModels';
import { ManualEndpoint, MdnsServiceCandidate } from '../models/PocModels';
import {
  HelloPayload,
  JsonObject,
  MessageType
} from '../models/ProtocolModels';
import {
  ItemAckPayload,
  ItemBatchPayload,
  ProtocolParser,
  RequestRange,
  RequestRangePayload,
  SyncHeadsPayload
} from '../models/ProtocolModels';
import { LocalDeviceIdentityService } from '../services/crypto/LocalDeviceIdentityService';
import { PairingClientNetworkHandshakeService } from '../services/pairing/PairingClientNetworkHandshakeService';
import {
  ProtocolHandshakeTransportSession,
  ProtocolTransportFrameResult,
  ProtocolTransportSession
} from '../services/transport/ProtocolTransportSession';
import { SpaceKeyDeliveryService } from '../services/pairing/SpaceKeyDeliveryService';
import {
  InboundItemLiveService,
  InboundItemLiveResult,
  InboundItemLiveStatus,
  RdbInboundItemLiveStorageGateway
} from '../services/sync/InboundItemLiveService';
import {
  OutboundItemLiveService,
  OutboundItemLiveStatus
} from '../services/sync/OutboundItemLiveService';
import { WebSocketTransportService } from '../services/transport/WebSocketTransportService';
import {
  PairingGeneratedHandshakeMaterialResult,
  PairingStore
} from './PairingStore';
import {
  PairingHandshakeDraft,
  PairingHandshakeDraftService
} from '../services/pairing/PairingHandshakeDraftService';
import { X25519KeyAgreementService } from '../services/crypto/X25519KeyAgreementService';
import { TrustedDeviceReconnectTarget, TrustedDeviceStore } from './TrustedDeviceStore';
import { OutboundItemBatchService } from '../services/sync/OutboundItemBatchService';
import {
  UiMessageCode,
  UiMessageDescriptor,
  UiMessageParameterName,
  cloneUiMessage,
  uiMessage,
  uiParameter
} from '../services/localization/UiMessageCodes';

enum ConnectionHandshakePurpose {
  PAIRING = 'pairing',
  TRUSTED_RECONNECT = 'trustedReconnect'
}

const TRUSTED_RECONNECT_BASE_DELAY_MS: number = 1_000;
const TRUSTED_RECONNECT_MAX_DELAY_MS: number = 15_000;

export enum PairingConnectionState {
  IDLE = 'idle',
  PREPARING = 'preparing',
  CONNECTING = 'connecting',
  CLIENT_HELLO_SENT = 'clientHelloSent',
  WAITING_AUTH_OK = 'waitingAuthOk',
  AUTHENTICATED = 'authenticated',
  FAILED = 'failed'
}

export interface PairingConnectionSnapshot {
  state: PairingConnectionState;
  authenticated: boolean;
  syncReady: boolean;
  trustedDeviceId: string;
  manualHost: string;
  manualPort: string;
  endpointLabel: string;
  title: UiMessageDescriptor;
  description: UiMessageDescriptor;
  lastError: UiMessageDescriptor | null;
  clientHelloSent: boolean;
  authProofSent: boolean;
  latestReceivedText: string;
  latestReceivedSource: UiMessageDescriptor;
  latestReceivedAtMs: number;
  latestReceivedByteLength: number;
  historyRevision: number;
  pendingOutboundCount: number;
  outboundDeliveryState: OutboundDeliveryState;
  outboundDeliveryDescription: UiMessageDescriptor;
}

export enum OutboundDeliveryState {
  IDLE = 'idle',
  QUEUED = 'queued',
  SENDING = 'sending',
  SENT = 'sent',
  FAILED = 'failed'
}

export interface OutboundDeliverySummary {
  state: OutboundDeliveryState;
  description: UiMessageDescriptor;
}

export function resolveOutboundDelivery(
  pendingCount: number,
  authenticated: boolean,
  readFailed: boolean = false
): OutboundDeliverySummary {
  if (readFailed) {
    return {
      state: OutboundDeliveryState.FAILED,
      description: uiMessage(UiMessageCode.OUTBOUND_READ_FAILED)
    };
  }
  if (!Number.isSafeInteger(pendingCount) || pendingCount <= 0) {
    return {
      state: OutboundDeliveryState.SENT,
      description: uiMessage(UiMessageCode.OUTBOUND_CONFIRMED)
    };
  }
  if (authenticated) {
    return {
      state: OutboundDeliveryState.SENDING,
      description: uiMessage(UiMessageCode.OUTBOUND_PENDING, [
        uiParameter(UiMessageParameterName.COUNT, pendingCount)
      ])
    };
  }
  return {
    state: OutboundDeliveryState.QUEUED,
    description: uiMessage(UiMessageCode.OUTBOUND_QUEUED, [
      uiParameter(UiMessageParameterName.COUNT, pendingCount)
    ])
  };
}

export enum AuthenticatedLocalSendStatus {
  SENT = 'sent',
  QUEUED = 'queued',
  SENDING = 'sending',
  INITIALIZING = 'initializing',
  PAUSED = 'paused',
  NOT_READY = 'notReady',
  FAILED = 'failed'
}

export interface AuthenticatedLocalSendResult {
  status: AuthenticatedLocalSendStatus;
  field?: string;
}

export type PairingConnectionSnapshotListener = (snapshot: PairingConnectionSnapshot) => void;

interface PairingCompletionPersistResult {
  ok: boolean;
  encryptedSpaceKeyRef?: string;
  failureStage?: string;
}

interface InboundBatchResult {
  ok: boolean;
  storedCount: number;
  duplicateCount: number;
  gapCount: number;
}

class PairingConnectionStore {
  private readonly listeners: PairingConnectionSnapshotListener[] = [];
  private readonly transport: WebSocketTransportService;
  private context: common.Context | null = null;
  private identityService: LocalDeviceIdentityService | null = null;
  private networkHandshake: PairingClientNetworkHandshakeService = new PairingClientNetworkHandshakeService();
  private localIdentityPrivateKeyRef: string = '';
  private authenticatedTransportSession: ProtocolTransportSession | null = null;
  // AUTH_OK proves identity but does not make clipboard traffic ready: the
  // space key and initial sync heads still have to finish in wire order.
  private syncReady: boolean = false;
  // The durable record is encrypted before this short-lived live-send queue is
  // populated. The payload itself contains clipboard text, so never log it.
  private pendingInitializationPayloads: JsonObject[] = [];
  private pendingTrustDraft: PairingHandshakeDraft | null = null;
  private pendingTrustServerHello: HelloPayload | null = null;
  private connectionPurpose: ConnectionHandshakePurpose = ConnectionHandshakePurpose.PAIRING;
  private reconnectTarget: TrustedDeviceReconnectTarget | null = null;
  private reconnectTimerId: number = -1;
  private reconnectAttempt: number = 0;
  private foreground: boolean = true;
  private closingByUserOrLifecycle: boolean = false;
  private state: PairingConnectionState = PairingConnectionState.IDLE;
  private manualHost: string = '127.0.0.1';
  private manualPort: string = '0';
  private endpointLabel: string = '';
  private title: UiMessageDescriptor = uiMessage(UiMessageCode.CONNECTION_WAITING_TITLE);
  private description: UiMessageDescriptor = uiMessage(UiMessageCode.CONNECTION_WAITING_DESCRIPTION);
  private lastError: UiMessageDescriptor | null = null;
  private clientHelloSent: boolean = false;
  private authProofSent: boolean = false;
  private latestReceivedText: string = '';
  private latestReceivedSource: UiMessageDescriptor = uiMessage(UiMessageCode.SOURCE_NONE);
  private latestReceivedAtMs: number = 0;
  private latestReceivedByteLength: number = 0;
  private historyRevision: number = 0;
  private pendingOutboundCount: number = 0;
  private outboundDeliveryState: OutboundDeliveryState = OutboundDeliveryState.IDLE;
  private outboundDeliveryDescription: UiMessageDescriptor = uiMessage(UiMessageCode.OUTBOUND_NONE);

  constructor(
    transport: WebSocketTransportService = new WebSocketTransportService(),
    identityService?: LocalDeviceIdentityService,
    networkHandshake?: PairingClientNetworkHandshakeService
  ) {
    this.transport = transport;
    if (identityService !== undefined) {
      this.identityService = identityService;
    }
    if (networkHandshake !== undefined) {
      this.networkHandshake = networkHandshake;
    }
  }

  initialize(context: common.Context): void {
    this.context = context;
    if (this.identityService === null) {
      this.identityService = new LocalDeviceIdentityService(new LocalIdentityRdbRepository(context));
    }
    this.restoreTrustedReconnect(context);
  }

  subscribe(listener: PairingConnectionSnapshotListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
    listener(this.snapshot());
  }

  unsubscribe(listener: PairingConnectionSnapshotListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  snapshot(): PairingConnectionSnapshot {
    return {
      state: this.state,
      authenticated: this.hasAuthenticatedSession(),
      syncReady: this.syncReady,
      trustedDeviceId: this.reconnectTarget?.deviceId ?? this.pendingTrustServerHello?.deviceId ?? '',
      manualHost: this.manualHost,
      manualPort: this.manualPort,
      endpointLabel: this.endpointLabel,
      title: cloneUiMessage(this.title),
      description: cloneUiMessage(this.description),
      lastError: this.lastError === null ? null : cloneUiMessage(this.lastError),
      clientHelloSent: this.clientHelloSent,
      authProofSent: this.authProofSent,
      latestReceivedText: this.latestReceivedText,
      latestReceivedSource: cloneUiMessage(this.latestReceivedSource),
      latestReceivedAtMs: this.latestReceivedAtMs,
      latestReceivedByteLength: this.latestReceivedByteLength,
      historyRevision: this.historyRevision,
      pendingOutboundCount: this.pendingOutboundCount,
      outboundDeliveryState: this.outboundDeliveryState,
      outboundDeliveryDescription: cloneUiMessage(this.outboundDeliveryDescription)
    };
  }

  updateEndpoint(host: string, portText: string): PairingConnectionSnapshot {
    this.manualHost = host;
    this.manualPort = portText;
    this.endpointLabel = host.length > 0 && portText.length > 0 ? `${host}:${portText}` : '';
    this.emit();
    return this.snapshot();
  }

  async startPairing(pairingStore: PairingStore, nowMs: number = Date.now()): Promise<PairingConnectionSnapshot> {
    if (this.state === PairingConnectionState.AUTHENTICATED &&
      this.authenticatedTransportSession !== null && !this.authenticatedTransportSession.isClosed()) {
      this.title = uiMessage(UiMessageCode.CONNECTION_AUTHENTICATED_TITLE);
      this.description = uiMessage(UiMessageCode.CONNECTION_AUTHENTICATED_DESCRIPTION);
      this.lastError = null;
      this.emit();
      return this.snapshot();
    }
    if (this.identityService === null) {
      this.fail(uiMessage(UiMessageCode.CONNECTION_CONTEXT_FAILED_TITLE),
        uiMessage(UiMessageCode.CONNECTION_CONTEXT_FAILED_DESCRIPTION));
      return this.snapshot();
    }

    const port = Number(this.manualPort);
    if (!Number.isInteger(port) || port < 1 || port > 65535) {
      this.fail(uiMessage(UiMessageCode.CONNECTION_ENDPOINT_INVALID_TITLE),
        uiMessage(UiMessageCode.CONNECTION_ENDPOINT_INVALID_DESCRIPTION));
      return this.snapshot();
    }

    const endpoint: ManualEndpoint = {
      host: this.manualHost,
      port
    };
    this.endpointLabel = `${endpoint.host}:${endpoint.port}`;
    this.state = PairingConnectionState.PREPARING;
    this.title = uiMessage(UiMessageCode.CONNECTION_PREPARING_TITLE);
    this.description = uiMessage(UiMessageCode.CONNECTION_PREPARING_DESCRIPTION);
    this.lastError = null;
    this.clientHelloSent = false;
    this.authProofSent = false;
    this.emit();

    const material = await pairingStore.buildPendingClientHandshakeMaterialWithLocalIdentity(
      this.identityService,
      nowMs,
      'v1'
    );
    return await this.startWithPreparedMaterial(material, endpoint, ConnectionHandshakePurpose.PAIRING);
  }

  async startTrustedReconnect(
    target: TrustedDeviceReconnectTarget,
    nowMs: number = Date.now()
  ): Promise<PairingConnectionSnapshot> {
    this.reconnectTarget = target;
    this.closingByUserOrLifecycle = false;
    if (this.identityService === null) {
      this.fail(uiMessage(UiMessageCode.CONNECTION_CONTEXT_FAILED_TITLE),
        uiMessage(UiMessageCode.CONNECTION_CONTEXT_FAILED_DESCRIPTION));
      return this.snapshot();
    }
    const port = Number(this.manualPort);
    if (!Number.isInteger(port) || port < 1 || port > 65535) {
      this.fail(uiMessage(UiMessageCode.CONNECTION_ENDPOINT_INVALID_TITLE),
        uiMessage(UiMessageCode.CONNECTION_ENDPOINT_INVALID_DESCRIPTION));
      return this.snapshot();
    }
    const identity = await this.identityService.ensureLocalIdentity(nowMs, 'v1');
    if (!identity.ok || identity.identity === undefined) {
      this.fail(uiMessage(UiMessageCode.CONNECTION_MATERIAL_FAILED_TITLE),
        uiMessage(UiMessageCode.CONNECTION_MATERIAL_FAILED_DESCRIPTION));
      return this.snapshot();
    }
    const ephemeral = new X25519KeyAgreementService().generateEphemeralKeyPair();
    if (!ephemeral.ok || ephemeral.privateKey === undefined || ephemeral.publicKey === undefined) {
      this.fail(uiMessage(UiMessageCode.CONNECTION_MATERIAL_FAILED_TITLE),
        uiMessage(UiMessageCode.CONNECTION_MATERIAL_FAILED_DESCRIPTION));
      return this.snapshot();
    }
    const draft = new PairingHandshakeDraftService().buildTrustedDeviceHandshakeDraft({
      spaceId: target.spaceId,
      spaceKeyVersion: target.spaceKeyVersion,
      remoteDeviceId: target.deviceId,
      remoteIdentityPublicKey: target.identityPublicKey,
      localDeviceId: identity.identity.deviceId,
      localIdentityPublicKey: identity.identity.identityPublicKey,
      localEphemeralPublicKey: ephemeral.publicKey
    });
    if (!draft.ok || draft.draft === undefined) {
      this.fail(uiMessage(UiMessageCode.CONNECTION_MATERIAL_FAILED_TITLE),
        uiMessage(UiMessageCode.CONNECTION_MATERIAL_FAILED_DESCRIPTION));
      return this.snapshot();
    }
    return await this.startWithPreparedMaterial({
      ok: true,
      draft: draft.draft,
      localDeviceId: identity.identity.deviceId,
      localIdentityPublicKey: identity.identity.identityPublicKey,
      localIdentityPrivateKeyRef: identity.identity.identityPrivateKeyRef,
      localEphemeralPrivateKey: ephemeral.privateKey,
      localEphemeralPublicKey: ephemeral.publicKey
    }, { host: this.manualHost, port }, ConnectionHandshakePurpose.TRUSTED_RECONNECT);
  }

  async retryTrustedConnection(): Promise<PairingConnectionSnapshot> {
    if (this.isConnectionBusy() || this.state === PairingConnectionState.AUTHENTICATED) {
      return this.snapshot();
    }
    if (this.reconnectTarget === null && this.context !== null) {
      this.reconnectTarget = await new TrustedDeviceStore(this.context).loadFirstReconnectTarget();
    }
    if (this.reconnectTarget === null) {
      this.fail(uiMessage(UiMessageCode.CONNECTION_FAILED_TITLE),
        uiMessage(UiMessageCode.CONNECTION_FAILED_DESCRIPTION));
      return this.snapshot();
    }
    this.clearReconnectTimer();
    this.closingByUserOrLifecycle = false;
    return await this.startTrustedReconnect(this.reconnectTarget);
  }

  setForeground(foreground: boolean): void {
    this.foreground = foreground;
    if (!foreground) {
      this.closingByUserOrLifecycle = true;
      this.clearReconnectTimer();
      this.transport.close();
      const hadAuthenticatedSession = this.hasAuthenticatedSession();
      this.authenticatedTransportSession?.close();
      this.authenticatedTransportSession = null;
      this.syncReady = false;
      if (this.state === PairingConnectionState.AUTHENTICATED || hadAuthenticatedSession) {
        this.state = PairingConnectionState.IDLE;
        this.title = uiMessage(UiMessageCode.CONNECTION_STOPPED_TITLE);
        this.description = uiMessage(UiMessageCode.POC_BACKGROUND);
        this.emit();
      }
      return;
    }
    this.closingByUserOrLifecycle = false;
    if (this.reconnectTarget !== null && this.state !== PairingConnectionState.AUTHENTICATED) {
      this.scheduleTrustedReconnect(0);
    }
  }

  updateTrustedDiscoveryCandidates(candidates: MdnsServiceCandidate[]): void {
    if (this.reconnectTarget === null) {
      return;
    }
    const endpoint = trustedDiscoveryEndpoint(this.reconnectTarget.deviceId, candidates);
    if (endpoint === null || (this.manualHost === endpoint.host && this.manualPort === `${endpoint.port}`)) {
      return;
    }
    this.manualHost = endpoint.host;
    this.manualPort = `${endpoint.port}`;
    this.endpointLabel = `${endpoint.host}:${endpoint.port}`;
    this.emit();
    if (this.foreground && this.state !== PairingConnectionState.AUTHENTICATED) {
      this.clearReconnectTimer();
      this.scheduleTrustedReconnect(0);
    }
  }

  async startWithPreparedMaterial(
    material: PairingGeneratedHandshakeMaterialResult,
    endpoint: ManualEndpoint,
    purpose: ConnectionHandshakePurpose = ConnectionHandshakePurpose.PAIRING
  ): Promise<PairingConnectionSnapshot> {
    if (!material.ok || material.draft === undefined || material.localEphemeralPrivateKey === undefined ||
      material.localIdentityPrivateKeyRef === undefined) {
      this.fail(uiMessage(UiMessageCode.CONNECTION_MATERIAL_FAILED_TITLE),
        uiMessage(UiMessageCode.CONNECTION_MATERIAL_FAILED_DESCRIPTION));
      return this.snapshot();
    }

    this.endpointLabel = `${endpoint.host}:${endpoint.port}`;
    this.localIdentityPrivateKeyRef = material.localIdentityPrivateKeyRef;
    this.connectionPurpose = purpose;
    if (this.pendingTrustDraft !== null && this.pendingTrustDraft.spaceId !== material.draft.spaceId) {
      this.pendingInitializationPayloads = [];
    }
    this.pendingTrustDraft = material.draft;
    this.syncReady = false;
    this.pendingTrustServerHello = null;
    this.networkHandshake.reset();
    const started = this.networkHandshake.start(
      material.draft,
      nextMessageId(),
      0,
      material.localEphemeralPrivateKey
    );
    if (!started.ok || started.outgoingFrame === undefined) {
      this.fail(uiMessage(UiMessageCode.CONNECTION_FAILED_TITLE),
        uiMessage(UiMessageCode.CONNECTION_FAILED_DESCRIPTION));
      return this.snapshot();
    }

    this.state = PairingConnectionState.CONNECTING;
    this.title = uiMessage(UiMessageCode.CONNECTION_CONNECTING_TITLE);
    this.description = uiMessage(UiMessageCode.CONNECTION_CONNECTING_DESCRIPTION, [
      uiParameter(UiMessageParameterName.ENDPOINT, this.endpointLabel)
    ]);
    this.emit();

    const handshakeSession = new ProtocolHandshakeTransportSession();
    const result = await this.transport.connectPairingHandshake(endpoint, handshakeSession, {
      onOpen: () => {
        this.sendClientHello(started.outgoingFrame ?? '');
      },
      onClose: (reason: string) => {
        if (this.closingByUserOrLifecycle || !this.foreground) return;
        if (reason.includes('deviceRevoked')) {
          this.handleDeviceRevoked();
          return;
        }
        if (this.connectionPurpose === ConnectionHandshakePurpose.TRUSTED_RECONNECT &&
          this.reconnectTarget !== null) {
          this.authenticatedTransportSession?.close();
          this.authenticatedTransportSession = null;
          this.syncReady = false;
          this.state = PairingConnectionState.IDLE;
          this.title = uiMessage(UiMessageCode.CONNECTION_CONNECTING_TITLE);
          this.description = uiMessage(UiMessageCode.CONNECTION_FAILED_DESCRIPTION);
          this.queuePendingAfterDisconnect();
          this.emit();
          this.scheduleTrustedReconnect();
          return;
        }
        if (this.state !== PairingConnectionState.AUTHENTICATED && this.state !== PairingConnectionState.FAILED) {
          this.fail(uiMessage(UiMessageCode.CONNECTION_FAILED_TITLE),
            uiMessage(UiMessageCode.CONNECTION_FAILED_DESCRIPTION));
        }
      },
      onError: (reason: string) => {
        if (this.closingByUserOrLifecycle || !this.foreground) return;
        if (this.connectionPurpose === ConnectionHandshakePurpose.TRUSTED_RECONNECT &&
          this.reconnectTarget !== null) {
          this.authenticatedTransportSession?.close();
          this.authenticatedTransportSession = null;
          this.syncReady = false;
          this.state = PairingConnectionState.IDLE;
          this.title = uiMessage(UiMessageCode.CONNECTION_CONNECTING_TITLE);
          this.description = uiMessage(UiMessageCode.CONNECTION_FAILED_DESCRIPTION);
          this.queuePendingAfterDisconnect();
          this.emit();
          this.scheduleTrustedReconnect();
          return;
        }
        this.fail(uiMessage(UiMessageCode.CONNECTION_FAILED_TITLE),
          uiMessage(UiMessageCode.CONNECTION_FAILED_DESCRIPTION));
      },
      onFrame: () => {
      },
      onTextFrame: async (message, frameResult) => {
        await this.handleHandshakeTextFrame(message, frameResult);
      },
      protocolSessionProvider: () => {
        return this.authenticatedTransportSession;
      }
    });
    if (!result.ok) {
      this.fail(uiMessage(UiMessageCode.CONNECTION_ENDPOINT_INVALID_TITLE),
        uiMessage(UiMessageCode.CONNECTION_ENDPOINT_INVALID_DESCRIPTION));
    }
    return this.snapshot();
  }

  async handleHandshakeTextFrame(
    message: string,
    frameResult: ProtocolTransportFrameResult
  ): Promise<PairingConnectionSnapshot> {
    if (!frameResult.ok || frameResult.envelope === undefined) {
      this.fail(uiMessage(UiMessageCode.CONNECTION_FAILED_TITLE),
        uiMessage(UiMessageCode.CONNECTION_FAILED_DESCRIPTION));
      return this.snapshot();
    }

    if (frameResult.envelope.messageType === MessageType.SERVER_HELLO) {
      const proof = await this.networkHandshake.acceptServerHelloAndSignAuthProofWithRef(
        message,
        this.localIdentityPrivateKeyRef,
        nextMessageId(),
        2
      );
      if (!proof.ok || proof.outgoingFrame === undefined) {
        this.fail(uiMessage(UiMessageCode.CONNECTION_FAILED_TITLE),
          uiMessage(UiMessageCode.CONNECTION_FAILED_DESCRIPTION));
        return this.snapshot();
      }
      this.pendingTrustServerHello = proof.serverHello ?? null;
      const sent = await this.transport.sendTextFrame(proof.outgoingFrame);
      if (!sent) {
        this.fail(uiMessage(UiMessageCode.CONNECTION_FAILED_TITLE),
          uiMessage(UiMessageCode.CONNECTION_FAILED_DESCRIPTION));
        return this.snapshot();
      }
      this.authProofSent = true;
      this.state = PairingConnectionState.WAITING_AUTH_OK;
      this.title = uiMessage(UiMessageCode.CONNECTION_HANDSHAKE_SENT_TITLE);
      this.description = uiMessage(UiMessageCode.CONNECTION_HANDSHAKE_SENT_DESCRIPTION);
      this.emit();
      return this.snapshot();
    }

    if (frameResult.envelope.messageType === MessageType.AUTH_PROOF) {
      const serverProof = this.networkHandshake.acceptServerAuthProof(message);
      if (!serverProof.ok) {
        this.fail(uiMessage(UiMessageCode.CONNECTION_FAILED_TITLE),
          uiMessage(UiMessageCode.CONNECTION_FAILED_DESCRIPTION));
        return this.snapshot();
      }
      this.state = PairingConnectionState.WAITING_AUTH_OK;
      this.title = uiMessage(UiMessageCode.CONNECTION_IDENTITY_VERIFIED_TITLE);
      this.description = uiMessage(UiMessageCode.CONNECTION_IDENTITY_VERIFIED_DESCRIPTION);
      this.emit();
      return this.snapshot();
    }

    if (frameResult.envelope.messageType === MessageType.AUTH_OK) {
      const authenticated = this.networkHandshake.acceptAuthOkAndCreateTransportSessionFromRememberedTranscript(message);
      if (!authenticated.ok || authenticated.transportSession === undefined) {
        this.fail(uiMessage(UiMessageCode.CONNECTION_FAILED_TITLE),
          uiMessage(UiMessageCode.CONNECTION_FAILED_DESCRIPTION));
        return this.snapshot();
      }
      this.authenticatedTransportSession = authenticated.transportSession;
      this.syncReady = false;
      this.state = PairingConnectionState.AUTHENTICATED;
      this.lastError = null;
      this.title = uiMessage(UiMessageCode.CONNECTION_AUTHENTICATED_TITLE);
      this.description = uiMessage(UiMessageCode.CONNECTION_AUTHENTICATED_DESCRIPTION);
      this.emit();
      return this.snapshot();
    }

    if (frameResult.envelope.messageType === MessageType.SPACE_KEY_ROTATED) {
      const isInitialPairing = this.connectionPurpose === ConnectionHandshakePurpose.PAIRING;
      const persisted = isInitialPairing
        ? await this.persistPairingCompletion(frameResult.decryptedPayload, Date.now())
        : await this.persistSpaceKeyRotation(frameResult.decryptedPayload, Date.now());
      if (!persisted.ok) {
        this.fail(uiMessage(UiMessageCode.CONNECTION_FAILED_TITLE),
          uiMessage(UiMessageCode.CONNECTION_FAILED_DESCRIPTION));
        return this.snapshot();
      }
      this.state = PairingConnectionState.AUTHENTICATED;
      this.lastError = null;
      this.title = uiMessage(UiMessageCode.CONNECTION_SAVED_TITLE);
      this.description = uiMessage(UiMessageCode.CONNECTION_SAVED_DESCRIPTION);
      this.emit();
      if (this.pendingTrustDraft !== null && this.pendingTrustServerHello !== null) {
        this.reconnectTarget = {
          spaceId: this.pendingTrustDraft.spaceId,
          spaceKeyVersion: this.pendingTrustDraft.spaceKeyVersion,
          deviceId: this.pendingTrustServerHello.deviceId,
          identityPublicKey: this.pendingTrustServerHello.identityPublicKey
        };
        this.rememberTrustedEndpoint();
        await this.completeSyncInitialization(isInitialPairing);
      }
      this.connectionPurpose = ConnectionHandshakePurpose.TRUSTED_RECONNECT;
      return this.snapshot();
    }

    if (frameResult.envelope.messageType === MessageType.SYNC_HEADS) {
      const stored = await this.persistRemoteSyncHeads(frameResult.decryptedPayload, Date.now());
      if (!stored) {
        if (!this.syncReady && this.connectionPurpose === ConnectionHandshakePurpose.TRUSTED_RECONNECT) {
          this.rememberTrustedEndpoint();
          await this.completeSyncInitialization(false);
          if (!this.syncReady) return this.snapshot();
        }
        this.state = PairingConnectionState.AUTHENTICATED;
        this.title = uiMessage(UiMessageCode.CONNECTION_SYNC_INIT_FAILED_TITLE);
        this.description = uiMessage(UiMessageCode.CONNECTION_SYNC_INIT_FAILED_DESCRIPTION);
        this.lastError = uiMessage(UiMessageCode.CONNECTION_SYNC_INIT_FAILED_DESCRIPTION);
        this.syncReady = true;
        this.emit();
        return this.snapshot();
      }
      if (!this.syncReady && this.connectionPurpose === ConnectionHandshakePurpose.TRUSTED_RECONNECT) {
        this.rememberTrustedEndpoint();
        await this.completeSyncInitialization(false);
        if (!this.syncReady) return this.snapshot();
      }
      this.title = uiMessage(UiMessageCode.CONNECTION_SYNC_READY_TITLE);
      this.markAuthenticatedActivity();
      const requested = await this.requestMissingRanges(frameResult.decryptedPayload);
      this.description = uiMessage(UiMessageCode.CONNECTION_SYNC_READY_DESCRIPTION);
      this.emit();
      return this.snapshot();
    }

    if (frameResult.envelope.messageType === MessageType.ITEM_LIVE) {
      const received = await this.persistInboundItemLive(frameResult.decryptedPayload, Date.now());
      const parsedItem = frameResult.decryptedPayload === undefined ? undefined :
        new ProtocolParser().parseClipboardItem(JSON.stringify(frameResult.decryptedPayload)).item;
      if (parsedItem !== undefined && (received.status === InboundItemLiveStatus.STORED ||
        received.status === InboundItemLiveStatus.RELAYED ||
        received.status === InboundItemLiveStatus.DUPLICATE)) {
        const ackPayload = JSON.parse(JSON.stringify({ itemIds: [parsedItem.itemId] })) as JsonObject;
        await this.sendAuthenticatedBusinessFrame(MessageType.ITEM_ACK, ackPayload);
      }
      if (received.status === InboundItemLiveStatus.STORED) {
        if (parsedItem !== undefined) {
          this.latestReceivedText = parsedItem.content;
          this.latestReceivedSource = uiMessage(UiMessageCode.SOURCE_DESKTOP_DEVICE, [
            uiParameter(UiMessageParameterName.DEVICE_SHORT_ID, shortId(parsedItem.originDeviceId))
          ]);
          this.latestReceivedAtMs = Date.now();
          this.latestReceivedByteLength = parsedItem.contentLength;
        }
        this.historyRevision += 1;
        this.markAuthenticatedActivity();
        this.title = uiMessage(UiMessageCode.CONNECTION_RECEIVED_TITLE);
        this.description = uiMessage(UiMessageCode.CONNECTION_RECEIVED_DESCRIPTION);
        this.emit();
        return this.snapshot();
      }
      if (received.status === InboundItemLiveStatus.RELAYED) {
        if (parsedItem !== undefined) {
          this.latestReceivedText = parsedItem.content;
          this.latestReceivedSource = uiMessage(UiMessageCode.SOURCE_SPACE_DEVICE, [
            uiParameter(UiMessageParameterName.DEVICE_SHORT_ID, shortId(parsedItem.originDeviceId))
          ]);
          this.latestReceivedAtMs = Date.now();
          this.latestReceivedByteLength = parsedItem.contentLength;
        }
        this.markAuthenticatedActivity();
        this.title = uiMessage(UiMessageCode.CONNECTION_RECEIVED_TITLE);
        this.description = uiMessage(UiMessageCode.CONNECTION_RECEIVED_DESCRIPTION);
        this.emit();
        return this.snapshot();
      }
      if (received.status === InboundItemLiveStatus.DUPLICATE) {
        this.markAuthenticatedActivity();
        this.title = uiMessage(UiMessageCode.CONNECTION_RECEIVE_DUPLICATE_TITLE);
        this.description = uiMessage(UiMessageCode.CONNECTION_RECEIVE_DUPLICATE_DESCRIPTION);
        this.emit();
        return this.snapshot();
      }
      if (received.status === InboundItemLiveStatus.IGNORED_BY_POLICY) {
        this.markAuthenticatedActivity();
        this.title = uiMessage(UiMessageCode.CONNECTION_RECEIVE_PAUSED_TITLE);
        this.description = uiMessage(UiMessageCode.CONNECTION_RECEIVE_PAUSED_DESCRIPTION);
        this.emit();
        return this.snapshot();
      }
      this.fail(uiMessage(UiMessageCode.CONNECTION_FAILED_TITLE),
        uiMessage(UiMessageCode.CONNECTION_FAILED_DESCRIPTION));
      this.authenticatedTransportSession?.close();
      this.transport.close();
      return this.snapshot();
    }

    if (frameResult.envelope.messageType === MessageType.ITEM_BATCH) {
      const batch = await this.persistInboundItemBatch(frameResult.decryptedPayload, Date.now());
      if (!batch.ok) {
        this.fail(uiMessage(UiMessageCode.CONNECTION_FAILED_TITLE),
          uiMessage(UiMessageCode.CONNECTION_FAILED_DESCRIPTION));
        return this.snapshot();
      }
      this.title = uiMessage(UiMessageCode.CONNECTION_HISTORY_SYNC_TITLE);
      this.markAuthenticatedActivity();
      this.historyRevision += 1;
      this.description = uiMessage(UiMessageCode.CONNECTION_HISTORY_SYNC_DESCRIPTION, [
        uiParameter(UiMessageParameterName.STORED_COUNT, batch.storedCount),
        uiParameter(UiMessageParameterName.DUPLICATE_COUNT, batch.duplicateCount),
        uiParameter(UiMessageParameterName.GAP_COUNT, batch.gapCount)
      ]);
      this.emit();
      return this.snapshot();
    }

    if (frameResult.envelope.messageType === MessageType.REQUEST_RANGE) {
      const parsed = new ProtocolParser().parseRequestRangePayload(frameResult.decryptedPayload);
      if (!parsed.ok || parsed.payload === undefined || this.context === null || this.pendingTrustDraft === null) {
        this.fail(uiMessage(UiMessageCode.CONNECTION_FAILED_TITLE),
          uiMessage(UiMessageCode.CONNECTION_FAILED_DESCRIPTION));
        return this.snapshot();
      }
      const built = await new OutboundItemBatchService(this.context)
        .build(this.pendingTrustDraft.spaceId, parsed.payload, Date.now());
      if (!built.ok || built.payload === undefined) {
        this.fail(uiMessage(UiMessageCode.CONNECTION_FAILED_TITLE),
          uiMessage(UiMessageCode.CONNECTION_FAILED_DESCRIPTION));
        return this.snapshot();
      }
      const batch: ItemBatchPayload = built.payload;
      const batchPayload = JSON.parse(JSON.stringify(batch)) as JsonObject;
      if (!await this.sendAuthenticatedBusinessFrame(MessageType.ITEM_BATCH, batchPayload)) {
        this.fail(uiMessage(UiMessageCode.CONNECTION_FAILED_TITLE),
          uiMessage(UiMessageCode.CONNECTION_FAILED_DESCRIPTION));
      } else {
        this.markAuthenticatedActivity();
      }
      return this.snapshot();
    }

    if (frameResult.envelope.messageType === MessageType.ITEM_ACK) {
      const ack = new ProtocolParser().parseItemAckPayload(frameResult.decryptedPayload);
      if (!ack.ok) {
        this.fail(uiMessage(UiMessageCode.CONNECTION_FAILED_TITLE),
          uiMessage(UiMessageCode.CONNECTION_FAILED_DESCRIPTION));
        return this.snapshot();
      }
      await this.applyOutboundAcknowledgement(ack.payload?.itemIds ?? [], Date.now());
      this.markAuthenticatedActivity();
      return this.snapshot();
    }

    if (frameResult.envelope.messageType === MessageType.AUTH_ERROR ||
      frameResult.envelope.messageType === MessageType.ERROR) {
      const errorCode = pairingAuthErrorCode(frameResult.envelope.payload);
      if (this.connectionPurpose === ConnectionHandshakePurpose.TRUSTED_RECONNECT &&
        (errorCode === 'identityOrSpaceMismatch' || errorCode === 'deviceRevoked')) {
        this.handleDeviceRevoked();
        return this.snapshot();
      }
      this.fail(uiMessage(UiMessageCode.CONNECTION_FAILED_TITLE),
        uiMessage(UiMessageCode.CONNECTION_FAILED_DESCRIPTION));
      return this.snapshot();
    }

    return this.snapshot();
  }

  close(): void {
    this.closingByUserOrLifecycle = true;
    this.clearReconnectTimer();
    this.transport.close();
    this.localIdentityPrivateKeyRef = '';
    this.authenticatedTransportSession = null;
    this.syncReady = false;
    this.pendingInitializationPayloads = [];
    this.pendingTrustDraft = null;
    this.pendingTrustServerHello = null;
    this.connectionPurpose = ConnectionHandshakePurpose.PAIRING;
    this.reconnectTarget = null;
    this.networkHandshake.reset();
    this.state = PairingConnectionState.IDLE;
    this.title = uiMessage(UiMessageCode.CONNECTION_STOPPED_TITLE);
    this.description = uiMessage(UiMessageCode.CONNECTION_STOPPED_DESCRIPTION);
    this.emit();
  }

  /**
   * Sends an already validated ITEM_LIVE payload only through the pairing-owned
   * authenticated transport. Callers retain local persistence responsibility.
   */
  async sendAuthenticatedItemLive(payload: JsonObject): Promise<boolean> {
    return await this.sendAuthenticatedBusinessFrame(MessageType.ITEM_LIVE, payload);
  }

  private async sendAuthenticatedBusinessFrame(messageType: MessageType, payload: JsonObject): Promise<boolean> {
    if (this.state !== PairingConnectionState.AUTHENTICATED ||
      this.authenticatedTransportSession === null ||
      this.authenticatedTransportSession.isClosed()) {
      return false;
    }
    const encoded = this.authenticatedTransportSession.encodeBusinessFrame(
      messageType,
      nextMessageId(),
      payload
    );
    if (!encoded.ok || encoded.frame === undefined) {
      return false;
    }
    const sent = await this.transport.sendTextFrame(encoded.frame);
    if (!sent) {
      this.authenticatedTransportSession.close();
      this.syncReady = false;
    }
    return sent;
  }

  async persistAndSendAuthenticatedLocalText(text: string): Promise<AuthenticatedLocalSendResult> {
    const spaceId = this.pendingTrustDraft?.spaceId ?? this.reconnectTarget?.spaceId ?? '';
    if (this.context === null || spaceId.length === 0) {
      return { status: AuthenticatedLocalSendStatus.NOT_READY };
    }
    const prepared = await new OutboundItemLiveService(this.context).persist(
      spaceId,
      text,
      Date.now()
    );
    if (prepared.status === OutboundItemLiveStatus.PAUSED) {
      return { status: AuthenticatedLocalSendStatus.PAUSED, field: prepared.field };
    }
    if (prepared.status !== OutboundItemLiveStatus.READY || prepared.payload === undefined) {
      return { status: AuthenticatedLocalSendStatus.FAILED, field: prepared.field };
    }
    this.pendingOutboundCount += 1;
    if (!this.syncReady) {
      if (this.pendingInitializationPayloads.length < 20) {
        this.pendingInitializationPayloads.push(prepared.payload);
      }
      this.setOutboundDelivery(OutboundDeliveryState.QUEUED,
        uiMessage(UiMessageCode.OUTBOUND_QUEUED, [
          uiParameter(UiMessageParameterName.COUNT, this.pendingOutboundCount)
        ]));
      return { status: AuthenticatedLocalSendStatus.INITIALIZING };
    }
    if (this.state !== PairingConnectionState.AUTHENTICATED ||
      this.authenticatedTransportSession === null || this.authenticatedTransportSession.isClosed()) {
      this.setOutboundDelivery(OutboundDeliveryState.QUEUED,
        uiMessage(UiMessageCode.OUTBOUND_QUEUED, [
          uiParameter(UiMessageParameterName.COUNT, this.pendingOutboundCount)
        ]));
      return { status: AuthenticatedLocalSendStatus.QUEUED };
    }
    if (await this.sendAuthenticatedItemLive(prepared.payload)) {
      this.setOutboundDelivery(OutboundDeliveryState.SENDING,
        uiMessage(UiMessageCode.OUTBOUND_PENDING, [
          uiParameter(UiMessageParameterName.COUNT, this.pendingOutboundCount)
        ]));
      return { status: AuthenticatedLocalSendStatus.SENDING };
    }
    this.setOutboundDelivery(OutboundDeliveryState.QUEUED,
      uiMessage(UiMessageCode.OUTBOUND_QUEUED, [
        uiParameter(UiMessageParameterName.COUNT, this.pendingOutboundCount)
      ]));
    return { status: AuthenticatedLocalSendStatus.QUEUED, field: 'transport' };
  }

  private sendClientHello(frame: string): void {
    this.transport.sendTextFrame(frame)
      .then((sent: boolean) => {
        if (!sent) {
          this.fail(uiMessage(UiMessageCode.CONNECTION_FAILED_TITLE),
            uiMessage(UiMessageCode.CONNECTION_FAILED_DESCRIPTION));
          return;
        }
        this.clientHelloSent = true;
        this.state = PairingConnectionState.CLIENT_HELLO_SENT;
        this.title = uiMessage(UiMessageCode.CONNECTION_HANDSHAKE_SENT_TITLE);
        this.description = uiMessage(UiMessageCode.CONNECTION_HANDSHAKE_SENT_DESCRIPTION);
        this.emit();
      })
      .catch(() => {
        this.fail(uiMessage(UiMessageCode.CONNECTION_FAILED_TITLE),
          uiMessage(UiMessageCode.CONNECTION_FAILED_DESCRIPTION));
      });
  }

  private scheduleTrustedReconnect(delayMs?: number): void {
    if (!this.foreground || this.reconnectTarget === null || this.reconnectTimerId >= 0 ||
      this.state === PairingConnectionState.AUTHENTICATED || this.isConnectionBusy()) {
      return;
    }
    const delay = delayMs ?? Math.min(
      TRUSTED_RECONNECT_BASE_DELAY_MS * Math.pow(2, this.reconnectAttempt),
      TRUSTED_RECONNECT_MAX_DELAY_MS
    );
    this.reconnectTimerId = setTimeout(() => {
      this.reconnectTimerId = -1;
      const target = this.reconnectTarget;
      if (target === null || !this.foreground) return;
      this.reconnectAttempt += 1;
      this.startTrustedReconnect(target).catch(() => {
        this.scheduleTrustedReconnect();
      });
    }, delay);
  }

  private restoreTrustedReconnect(context: common.Context): void {
    if (this.reconnectTarget !== null || this.manualPort !== '0') return;
    const devices = new TrustedDeviceStore(context);
    const settings = new SettingsRdbRepository(context);
    devices.loadFirstReconnectTarget()
      .then((target: TrustedDeviceReconnectTarget | null) => {
        if (target === null) return;
        settings.loadTrustedConnectionEndpoint().then((endpoint: TrustedConnectionEndpointRecord | null) => {
          if (endpoint === null) return;
          this.reconnectTarget = target;
          this.manualHost = endpoint.host;
          this.manualPort = `${endpoint.port}`;
          this.endpointLabel = `${endpoint.host}:${endpoint.port}`;
          this.emit();
          this.refreshPendingOutboundState().catch(() => {
          });
          if (this.foreground) this.scheduleTrustedReconnect(0);
        }).catch(() => {
        });
      })
      .catch(() => {
      });
  }

  private rememberTrustedEndpoint(): void {
    if (this.context === null) return;
    const port = Number(this.manualPort);
    if (!Number.isInteger(port) || port < 1 || port > 65535) return;
    const record: TrustedConnectionEndpointRecord = {
      host: this.manualHost,
      port,
      connectedAt: Date.now()
    };
    new SettingsRdbRepository(this.context).saveTrustedConnectionEndpoint(record).catch(() => {
    });
  }

  private clearReconnectTimer(): void {
    if (this.reconnectTimerId >= 0) {
      clearTimeout(this.reconnectTimerId);
      this.reconnectTimerId = -1;
    }
    this.reconnectAttempt = 0;
  }

  private handleDeviceRevoked(): void {
    const revokedDeviceId = this.reconnectTarget?.deviceId ?? this.pendingTrustServerHello?.deviceId ?? '';
    this.clearReconnectTimer();
    this.reconnectTarget = null;
    this.authenticatedTransportSession?.close();
    this.authenticatedTransportSession = null;
    this.syncReady = false;
    this.state = PairingConnectionState.FAILED;
    this.title = uiMessage(UiMessageCode.CONNECTION_REVOKED_TITLE);
    this.description = uiMessage(UiMessageCode.CONNECTION_REVOKED_DESCRIPTION);
    this.lastError = uiMessage(UiMessageCode.CONNECTION_REVOKED_DESCRIPTION);
    this.emit();
    if (this.context !== null && revokedDeviceId.length > 0) {
      new TrustedDeviceStore(this.context).markRevoked(revokedDeviceId, Date.now()).catch(() => {
      });
    }
  }

  private isConnectionBusy(): boolean {
    return this.state === PairingConnectionState.PREPARING ||
      this.state === PairingConnectionState.CONNECTING ||
      this.state === PairingConnectionState.CLIENT_HELLO_SENT ||
      this.state === PairingConnectionState.WAITING_AUTH_OK;
  }

  private hasAuthenticatedSession(): boolean {
    return this.authenticatedTransportSession !== null && !this.authenticatedTransportSession.isClosed();
  }

  private markAuthenticatedActivity(): void {
    if (!this.hasAuthenticatedSession()) return;
    this.state = PairingConnectionState.AUTHENTICATED;
    this.lastError = null;
  }

  private async completeSyncInitialization(isInitialPairing: boolean): Promise<void> {
    await this.refreshPendingOutboundState();
    const headsSent = await this.sendLocalSyncHeads();
    if (!headsSent) {
      this.syncReady = false;
      this.title = uiMessage(UiMessageCode.CONNECTION_SYNC_INIT_FAILED_TITLE);
      this.description = uiMessage(UiMessageCode.CONNECTION_SYNC_INIT_FAILED_DESCRIPTION);
      this.emit();
      return;
    }
    this.syncReady = true;
    this.state = PairingConnectionState.AUTHENTICATED;
    this.lastError = null;
    this.title = uiMessage(UiMessageCode.CONNECTION_SYNC_READY_TITLE);
    this.description = uiMessage(UiMessageCode.CONNECTION_SYNC_READY_DESCRIPTION);
    this.emit();

    const queuedPayloads = this.pendingInitializationPayloads.splice(0);
    let submittedCount = 0;
    for (let index = 0; index < queuedPayloads.length; index += 1) {
      if (!await this.sendAuthenticatedItemLive(queuedPayloads[index])) break;
      submittedCount += 1;
    }
    if (submittedCount > 0) {
      this.setOutboundDelivery(OutboundDeliveryState.SENDING,
        uiMessage(UiMessageCode.OUTBOUND_PENDING, [
          uiParameter(UiMessageParameterName.COUNT, this.pendingOutboundCount)
        ]));
    }
  }

  private fail(title: UiMessageDescriptor, description: UiMessageDescriptor): void {
    this.state = PairingConnectionState.FAILED;
    this.title = title;
    this.description = description;
    this.lastError = cloneUiMessage(description);
    this.emit();
  }

  private async persistPairingCompletion(payload: JsonObject | undefined, nowMs: number): Promise<PairingCompletionPersistResult> {
    if (this.context === null ||
      this.pendingTrustDraft === null ||
      this.pendingTrustServerHello === null ||
      payload === undefined) {
      return failedPersist('context');
    }
    const delivery = await new SpaceKeyDeliveryService().acceptInitialDelivery({
      payload,
      expectedSpaceId: this.pendingTrustDraft.spaceId,
      expectedKeyVersion: this.pendingTrustDraft.spaceKeyVersion
    });
    if (!delivery.ok) {
      return failedPersist(`spaceKey:${delivery.error ?? 'unknown'}:${delivery.field ?? 'unknown'}`);
    }
    const spaceId = this.pendingTrustDraft.spaceId;
    const keyVersion = this.pendingTrustDraft.spaceKeyVersion;
    const serverHello = this.pendingTrustServerHello;
    const pairingRepository = new PairingRdbRepository(this.context);
    try {
      await pairingRepository.persistCompletion({
        space: {
          space: {
            spaceId,
            displayName: `space #${shortId(spaceId)}`,
            keyVersion,
            state: SpaceState.ACTIVE,
            createdAt: nowMs
          },
          nameOrigin: DisplayNameOrigin.GENERATED,
          encryptedSpaceKeyRef: delivery.encryptedSpaceKeyRef,
          updatedAt: nowMs
        },
        device: {
          device: {
            deviceId: serverHello.deviceId,
            spaceId,
            displayName: `desktop #${shortId(serverHello.deviceId)}`,
            identityPublicKeyRef: serverHello.identityPublicKey,
            trustState: DeviceTrustState.TRUSTED,
            connectionState: DeviceConnectionState.ONLINE,
            lastSeenAt: nowMs
          },
          nameOrigin: DisplayNameOrigin.GENERATED,
          pairedAt: nowMs
        }
      });
      return {
        ok: true,
        encryptedSpaceKeyRef: delivery.encryptedSpaceKeyRef
      };
    } catch (error) {
      return failedPersist(`rdb:${rdbFailureStage(error)}`);
    }
  }

  private async persistSpaceKeyRotation(
    payload: JsonObject | undefined,
    nowMs: number
  ): Promise<PairingCompletionPersistResult> {
    if (this.context === null || this.pendingTrustDraft === null || payload === undefined) {
      return failedPersist('context');
    }
    const spaces = new SpaceRdbRepository(this.context);
    const current = await spaces.get(this.pendingTrustDraft.spaceId);
    if (current === null) {
      return failedPersist('spaceKey:missingSpace');
    }
    const delivery = await new SpaceKeyDeliveryService().acceptRotation({
      payload,
      expectedSpaceId: this.pendingTrustDraft.spaceId,
      currentKeyVersion: current.space.keyVersion
    });
    if (!delivery.ok) {
      return failedPersist(`spaceKey:${delivery.error ?? 'unknown'}:${delivery.field ?? 'unknown'}`);
    }
    const keyVersionValue = payload.keyVersion;
    if (typeof keyVersionValue !== 'number' || !Number.isSafeInteger(keyVersionValue)) {
      return failedPersist('spaceKey:invalidKeyVersion');
    }
    try {
      await spaces.applyKeyRotation({
        space: {
          spaceId: current.space.spaceId,
          displayName: current.space.displayName,
          keyVersion: keyVersionValue,
          state: SpaceState.ACTIVE,
          createdAt: current.space.createdAt
        },
        nameOrigin: current.nameOrigin,
        encryptedSpaceKeyRef: delivery.encryptedSpaceKeyRef,
        updatedAt: nowMs
      });
      this.pendingTrustDraft.spaceKeyVersion = keyVersionValue;
      if (this.reconnectTarget !== null) {
        this.reconnectTarget.spaceKeyVersion = keyVersionValue;
      }
      return { ok: true, encryptedSpaceKeyRef: delivery.encryptedSpaceKeyRef };
    } catch (_) {
      return failedPersist('rdb:spaceRotation');
    }
  }

  private async persistInboundItemLive(payload: JsonObject | undefined, nowMs: number): Promise<InboundItemLiveResult> {
    if (this.context === null || this.pendingTrustDraft === null ||
      this.pendingTrustServerHello === null || payload === undefined) {
      return { status: InboundItemLiveStatus.REJECTED, field: 'context' };
    }
    const service = new InboundItemLiveService(
      new RdbInboundItemLiveStorageGateway(this.context)
    );
    return await service.accept({
      payload,
      expectedSpaceId: this.pendingTrustDraft.spaceId,
      expectedPeerDeviceId: this.pendingTrustServerHello.deviceId,
      allowTrustedPeerRelay: true,
      nowMs
    });
  }

  private async persistInboundItemBatch(payload: JsonObject | undefined, nowMs: number): Promise<InboundBatchResult> {
    const failed: InboundBatchResult = { ok: false, storedCount: 0, duplicateCount: 0, gapCount: 0 };
    if (this.context === null || this.pendingTrustDraft === null ||
      this.pendingTrustServerHello === null || payload === undefined) return failed;
    const parsed = new ProtocolParser().parseItemBatchPayload(payload);
    if (!parsed.ok || parsed.payload === undefined) return failed;
    const service = new InboundItemLiveService(new RdbInboundItemLiveStorageGateway(this.context));
    const ackedItemIds: string[] = [];
    let storedCount = 0;
    let duplicateCount = 0;
    for (let index = 0; index < parsed.payload.items.length; index += 1) {
      const item = parsed.payload.items[index];
      const itemPayload = JSON.parse(JSON.stringify(item)) as JsonObject;
      const result = await service.accept({
        payload: itemPayload,
        expectedSpaceId: this.pendingTrustDraft.spaceId,
        expectedPeerDeviceId: this.pendingTrustServerHello.deviceId,
        eventKind: InboundClipboardEventKind.ITEM_BATCH,
        nowMs
      });
      if (result.status === InboundItemLiveStatus.STORED) {
        storedCount += 1;
        ackedItemIds.push(item.itemId);
      } else if (result.status === InboundItemLiveStatus.DUPLICATE) {
        duplicateCount += 1;
        ackedItemIds.push(item.itemId);
      } else {
        return failed;
      }
    }
    if (ackedItemIds.length > 0) {
      const ack: ItemAckPayload = { itemIds: ackedItemIds };
      const ackPayload = JSON.parse(JSON.stringify(ack)) as JsonObject;
      if (!await this.sendAuthenticatedBusinessFrame(MessageType.ITEM_ACK, ackPayload)) return failed;
    }
    return {
      ok: true,
      storedCount,
      duplicateCount,
      gapCount: parsed.payload.gaps.length
    };
  }

  private async persistRemoteSyncHeads(payload: JsonObject | undefined, nowMs: number): Promise<boolean> {
    if (this.context === null || this.pendingTrustDraft === null ||
      this.pendingTrustServerHello === null || payload === undefined) {
      return false;
    }
    const parsed = new ProtocolParser().parseSyncHeadsPayload(payload);
    if (!parsed.ok || parsed.payload === undefined) {
      return false;
    }
    const repository = new SyncHeadRdbRepository(this.context);
    const deviceIds = Object.keys(parsed.payload.heads);
    try {
      for (let index = 0; index < deviceIds.length; index += 1) {
        const originDeviceId = deviceIds[index];
        const latestOriginSeq = parsed.payload.heads[originDeviceId];
        const minimumAvailable = parsed.payload.minimumAvailable[originDeviceId];
        if (latestOriginSeq === undefined || minimumAvailable === undefined) return false;
        const record: SyncHeadRecord = {
          head: {
            spaceId: this.pendingTrustDraft.spaceId,
            originDeviceId,
            latestOriginSeq,
            minimumAvailable,
            updatedAt: nowMs
          },
          peerDeviceId: this.pendingTrustServerHello.deviceId
        };
        await repository.upsert(record);
      }
      await this.refreshPendingOutboundState();
      return true;
    } catch (_) {
      return false;
    }
  }

  private async requestMissingRanges(payload: JsonObject | undefined): Promise<boolean> {
    if (this.context === null || this.pendingTrustDraft === null || payload === undefined) return false;
    const parsed = new ProtocolParser().parseSyncHeadsPayload(payload);
    if (!parsed.ok || parsed.payload === undefined) return false;
    const localHeads = await new ClipboardRdbRepository(this.context)
      .summarizeAvailableSequences(this.pendingTrustDraft.spaceId, Date.now());
    const localLatest: Record<string, number> = {};
    for (let index = 0; index < localHeads.length; index += 1) {
      localLatest[localHeads[index].originDeviceId] = localHeads[index].latestOriginSeq;
    }
    const ranges: RequestRange[] = [];
    const remote = parsed.payload as SyncHeadsPayload;
    for (const originDeviceId of Object.keys(remote.heads)) {
      const remoteLatest = remote.heads[originDeviceId];
      const remoteMinimum = remote.minimumAvailable[originDeviceId];
      const localLatestSeq = localLatest[originDeviceId] ?? 0;
      if (remoteLatest === undefined || remoteMinimum === undefined || remoteLatest <= localLatestSeq) continue;
      ranges.push({
        originDeviceId,
        fromSeq: localLatestSeq + 1,
        toSeq: remoteLatest
      });
    }
    if (ranges.length === 0) return false;
    const request: RequestRangePayload = { ranges };
    const requestPayload = JSON.parse(JSON.stringify(request)) as JsonObject;
    return await this.sendAuthenticatedBusinessFrame(MessageType.REQUEST_RANGE, requestPayload);
  }

  private async sendLocalSyncHeads(): Promise<boolean> {
    if (this.context === null || this.pendingTrustDraft === null) return false;
    const heads = await new ClipboardRdbRepository(this.context)
      .summarizeAvailableSequences(this.pendingTrustDraft.spaceId, Date.now());
    const latest: Record<string, number> = {};
    const minimumAvailable: Record<string, number> = {};
    for (let index = 0; index < heads.length; index += 1) {
      latest[heads[index].originDeviceId] = heads[index].latestOriginSeq;
      minimumAvailable[heads[index].originDeviceId] = heads[index].minimumAvailable;
    }
    const syncHeads: SyncHeadsPayload = { heads: latest, minimumAvailable };
    const payload = JSON.parse(JSON.stringify(syncHeads)) as JsonObject;
    return await this.sendAuthenticatedBusinessFrame(MessageType.SYNC_HEADS, payload);
  }

  private async applyOutboundAcknowledgement(itemIds: string[], nowMs: number): Promise<void> {
    if (this.context === null || this.pendingTrustDraft === null || this.pendingTrustServerHello === null) return;
    const clipboard = new ClipboardRdbRepository(this.context);
    const localDeviceId = await new LocalIdentityRdbRepository(this.context).getOrCreateDeviceId(nowMs);
    let acknowledgedSeq = 0;
    for (let index = 0; index < itemIds.length; index += 1) {
      const record = await clipboard.get(itemIds[index]);
      if (record !== null && record.item.spaceId === this.pendingTrustDraft.spaceId &&
        record.item.originDeviceId === localDeviceId) {
        acknowledgedSeq = Math.max(acknowledgedSeq, record.item.originSeq);
      }
    }
    if (acknowledgedSeq === 0) return;
    const repository = new SyncHeadRdbRepository(this.context);
    const existing = await repository.listForPeer(
      this.pendingTrustDraft.spaceId,
      this.pendingTrustServerHello.deviceId
    );
    const current = existing.find((record: SyncHeadRecord) => record.head.originDeviceId === localDeviceId);
    await repository.upsert({
      head: {
        spaceId: this.pendingTrustDraft.spaceId,
        originDeviceId: localDeviceId,
        latestOriginSeq: Math.max(current?.head.latestOriginSeq ?? 0, acknowledgedSeq),
        minimumAvailable: current?.head.minimumAvailable ?? 1,
        updatedAt: nowMs
      },
      peerDeviceId: this.pendingTrustServerHello.deviceId
    });
    await this.refreshPendingOutboundState();
  }

  private async refreshPendingOutboundState(): Promise<void> {
    if (this.context === null) return;
    const spaceId = this.pendingTrustDraft?.spaceId ?? this.reconnectTarget?.spaceId ?? '';
    const peerDeviceId = this.pendingTrustServerHello?.deviceId ?? this.reconnectTarget?.deviceId ?? '';
    if (spaceId.length === 0 || peerDeviceId.length === 0) return;
    try {
      const localDeviceId = await new LocalIdentityRdbRepository(this.context).getOrCreateDeviceId(Date.now());
      const localHeads = await new ClipboardRdbRepository(this.context)
        .summarizeAvailableSequences(spaceId, Date.now());
      const local = localHeads.find((head) => head.originDeviceId === localDeviceId);
      const remoteHeads = await new SyncHeadRdbRepository(this.context).listForPeer(spaceId, peerDeviceId);
      const remote = remoteHeads.find((record: SyncHeadRecord) => record.head.originDeviceId === localDeviceId);
      this.pendingOutboundCount = calculatePendingOutboundCount(
        local?.latestOriginSeq ?? 0,
        remote?.head.latestOriginSeq ?? 0
      );
      const delivery = resolveOutboundDelivery(
        this.pendingOutboundCount,
        this.state === PairingConnectionState.AUTHENTICATED
      );
      this.outboundDeliveryState = delivery.state;
      this.outboundDeliveryDescription = delivery.description;
      this.emit();
    } catch (_) {
      const delivery = resolveOutboundDelivery(this.pendingOutboundCount, false, true);
      this.outboundDeliveryState = delivery.state;
      this.outboundDeliveryDescription = delivery.description;
      this.emit();
    }
  }

  private queuePendingAfterDisconnect(): void {
    if (this.pendingOutboundCount <= 0) return;
    const delivery = resolveOutboundDelivery(this.pendingOutboundCount, false);
    this.outboundDeliveryState = delivery.state;
    this.outboundDeliveryDescription = delivery.description;
  }

  private setOutboundDelivery(state: OutboundDeliveryState, description: UiMessageDescriptor): void {
    this.outboundDeliveryState = state;
    this.outboundDeliveryDescription = description;
    this.emit();
  }

  private emit(): void {
    const current = this.snapshot();
    for (let index = 0; index < this.listeners.length; index += 1) {
      this.listeners[index](current);
    }
  }

}

function nextMessageId(): string {
  return normalizeUuid(util.generateRandomUUID(false), Date.now(), Math.random());
}

function shortId(value: string): string {
  return value.length >= 8 ? value.slice(0, 8) : value;
}

function failedPersist(failureStage: string): PairingCompletionPersistResult {
  return {
    ok: false,
    failureStage
  };
}

function rdbFailureStage(error: Error): string {
  const message = error.message;
  if (message === 'space' || message === 'device') {
    return message;
  }
  return 'persistCompletion';
}

function normalizeUuid(value: string, nowMs: number, randomValue: number): string {
  const lower = value.toLowerCase();
  if (isUuid(lower)) {
    return lower;
  }
  const compact = lower.replace(/[^0-9a-f]/g, '');
  const seed = `${compact}${nowMs.toString(16)}${Math.floor(randomValue * 0xffffffff).toString(16)}`;
  const padded = `${seed}00000000000000000000000000000000`.slice(0, 32);
  const variant = /^[89ab]$/.test(padded.charAt(16)) ? padded.charAt(16) : '8';
  return `${padded.slice(0, 8)}-${padded.slice(8, 12)}-4${padded.slice(13, 16)}-${variant}${padded.slice(17, 20)}-${padded.slice(20)}`;
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

export const pairingConnectionStore: PairingConnectionStore = new PairingConnectionStore();
export { PairingConnectionStore };

export function trustedDiscoveryEndpoint(
  trustedDeviceId: string,
  candidates: MdnsServiceCandidate[]
): ManualEndpoint | null {
  const candidate = candidates.find((item: MdnsServiceCandidate) =>
    item.protocolVersion === 1 && item.instanceId === trustedDeviceId && item.port > 0 && item.port <= 65535);
  if (candidate === undefined) {
    return null;
  }
  return { host: candidate.host, port: candidate.port };
}

export function pairingAuthErrorCode(payload: JsonObject | undefined): string {
  if (payload === undefined) return '';
  const code = payload['code'];
  return typeof code === 'string' ? code : '';
}

export function calculatePendingOutboundCount(localLatest: number, acknowledgedLatest: number): number {
  if (!Number.isSafeInteger(localLatest) || !Number.isSafeInteger(acknowledgedLatest) ||
    localLatest < 0 || acknowledgedLatest < 0) return 0;
  return Math.max(0, localLatest - acknowledgedLatest);
}
