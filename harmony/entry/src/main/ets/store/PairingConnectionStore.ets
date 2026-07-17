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
import { SyncHeadRecord } from '../data/repositories/RepositoryCommands';
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
import {
  PairingClientNetworkHandshakeError,
  PairingClientNetworkHandshakeService
} from '../services/pairing/PairingClientNetworkHandshakeService';
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
  title: string;
  description: string;
  lastError: string;
  clientHelloSent: boolean;
  authProofSent: boolean;
  latestReceivedText: string;
  latestReceivedSource: string;
  latestReceivedAt: string;
  latestReceivedByteLength: number;
  historyRevision: number;
  pendingOutboundCount: number;
  outboundDeliveryState: OutboundDeliveryState;
  outboundDeliveryDescription: string;
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
  description: string;
}

export function resolveOutboundDelivery(
  pendingCount: number,
  authenticated: boolean,
  readFailed: boolean = false
): OutboundDeliverySummary {
  if (readFailed) {
    return {
      state: OutboundDeliveryState.FAILED,
      description: '无法读取待同步记录状态，本机历史仍保留'
    };
  }
  if (!Number.isSafeInteger(pendingCount) || pendingCount <= 0) {
    return {
      state: OutboundDeliveryState.SENT,
      description: '本机同步记录均已收到桌面端确认'
    };
  }
  if (authenticated) {
    return {
      state: OutboundDeliveryState.SENDING,
      description: `${pendingCount} 条本机记录正在等待桌面端确认`
    };
  }
  return {
    state: OutboundDeliveryState.QUEUED,
    description: `${pendingCount} 条本机记录等待连接恢复后自动补发`
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
  private endpointLabel: string = '未设置';
  private title: string = '等待确认邀请';
  private description: string = '导入邀请并核对确认码后，再连接桌面端完成正式握手。';
  private lastError: string = '';
  private clientHelloSent: boolean = false;
  private authProofSent: boolean = false;
  private latestReceivedText: string = '';
  private latestReceivedSource: string = '';
  private latestReceivedAt: string = '';
  private latestReceivedByteLength: number = 0;
  private historyRevision: number = 0;
  private pendingOutboundCount: number = 0;
  private outboundDeliveryState: OutboundDeliveryState = OutboundDeliveryState.IDLE;
  private outboundDeliveryDescription: string = '没有等待发送的本机记录';

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
      title: this.title,
      description: this.description,
      lastError: this.lastError,
      clientHelloSent: this.clientHelloSent,
      authProofSent: this.authProofSent,
      latestReceivedText: this.latestReceivedText,
      latestReceivedSource: this.latestReceivedSource,
      latestReceivedAt: this.latestReceivedAt,
      latestReceivedByteLength: this.latestReceivedByteLength,
      historyRevision: this.historyRevision,
      pendingOutboundCount: this.pendingOutboundCount,
      outboundDeliveryState: this.outboundDeliveryState,
      outboundDeliveryDescription: this.outboundDeliveryDescription
    };
  }

  updateEndpoint(host: string, portText: string): PairingConnectionSnapshot {
    this.manualHost = host;
    this.manualPort = portText;
    const port = portText.length > 0 ? portText : '未设置';
    this.endpointLabel = `${host}:${port}`;
    this.emit();
    return this.snapshot();
  }

  async startPairing(pairingStore: PairingStore, nowMs: number = Date.now()): Promise<PairingConnectionSnapshot> {
    if (this.state === PairingConnectionState.AUTHENTICATED &&
      this.authenticatedTransportSession !== null && !this.authenticatedTransportSession.isClosed()) {
      this.title = '已认证连接';
      this.description = '当前正式会话仍在线，无需重复配对；邀请已消费一次。';
      this.lastError = '';
      this.emit();
      return this.snapshot();
    }
    if (this.identityService === null) {
      this.fail('本机身份未初始化', '缺少页面上下文，无法访问 HUKS/RDB 本机身份。');
      return this.snapshot();
    }

    const port = Number(this.manualPort);
    if (!Number.isInteger(port) || port < 1 || port > 65535) {
      this.fail('配对端口无效', '请输入桌面端显示的 1 到 65535 之间的 WebSocket 端口。');
      return this.snapshot();
    }

    const endpoint: ManualEndpoint = {
      host: this.manualHost,
      port
    };
    this.endpointLabel = `${endpoint.host}:${endpoint.port}`;
    this.state = PairingConnectionState.PREPARING;
    this.title = '正在准备配对握手';
    this.description = '正在初始化本机身份并生成 CLIENT_HELLO。';
    this.lastError = '';
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
      this.fail('本机身份未初始化', '缺少页面上下文，无法访问 HUKS/RDB 本机身份。');
      return this.snapshot();
    }
    const port = Number(this.manualPort);
    if (!Number.isInteger(port) || port < 1 || port > 65535) {
      this.fail('重连端口无效', '请输入桌面端显示的 1 到 65535 之间的 WebSocket 端口。');
      return this.snapshot();
    }
    const identity = await this.identityService.ensureLocalIdentity(nowMs, 'v1');
    if (!identity.ok || identity.identity === undefined) {
      this.fail('重连材料生成失败', this.describeMaterialFailure(identity.field));
      return this.snapshot();
    }
    const ephemeral = new X25519KeyAgreementService().generateEphemeralKeyPair();
    if (!ephemeral.ok || ephemeral.privateKey === undefined || ephemeral.publicKey === undefined) {
      this.fail('重连材料生成失败', '无法生成本次连接所需的临时密钥。');
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
      this.fail('重连材料生成失败', '已保存的同步空间或可信设备身份记录无效。');
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
      this.fail('没有可恢复的可信设备', '请先到设备页扫码或粘贴桌面端邀请完成配对。');
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
        this.title = '已暂停可信连接';
        this.description = '应用位于后台；返回前台后会恢复已配对设备连接。';
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
      this.fail('配对材料生成失败', this.describeMaterialFailure(material.field));
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
      this.fail('CLIENT_HELLO 构建失败', this.describeNetworkFailure(started.error));
      return this.snapshot();
    }

    this.state = PairingConnectionState.CONNECTING;
    this.title = purpose === ConnectionHandshakePurpose.TRUSTED_RECONNECT ? '正在恢复可信连接' : '正在连接桌面端';
    this.description = purpose === ConnectionHandshakePurpose.TRUSTED_RECONNECT
      ? `${this.endpointLabel} · 将使用已保存的设备身份恢复认证连接。`
      : `${this.endpointLabel} · 连接成功后会发送 CLIENT_HELLO。`;
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
          this.title = '可信连接已断开';
          this.description = `${this.describeCloseReason(reason)}；正在尝试恢复已配对设备连接。`;
          this.queuePendingAfterDisconnect();
          this.emit();
          this.scheduleTrustedReconnect();
          return;
        }
        if (this.state !== PairingConnectionState.AUTHENTICATED && this.state !== PairingConnectionState.FAILED) {
          this.fail(this.describeCloseTitle(), this.describeCloseReason(reason));
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
          this.title = '可信连接失败';
          this.description = `${this.describeTransportError(reason)}；正在尝试恢复已配对设备连接。`;
          this.queuePendingAfterDisconnect();
          this.emit();
          this.scheduleTrustedReconnect();
          return;
        }
        this.fail('配对连接失败', this.describeTransportError(reason));
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
      this.fail('配对连接参数无效', result.reason ?? '请检查桌面端 IP 和端口。');
    }
    return this.snapshot();
  }

  async handleHandshakeTextFrame(
    message: string,
    frameResult: ProtocolTransportFrameResult
  ): Promise<PairingConnectionSnapshot> {
    if (!frameResult.ok || frameResult.envelope === undefined) {
      this.fail('桌面端握手帧被拒绝', '收到的握手帧不符合协议或顺序。');
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
        this.fail('AUTH_PROOF 生成失败', this.describeNetworkFailure(proof.error));
        return this.snapshot();
      }
      this.pendingTrustServerHello = proof.serverHello ?? null;
      const sent = await this.transport.sendTextFrame(proof.outgoingFrame);
      if (!sent) {
        this.fail('AUTH_PROOF 发送失败', 'WebSocket 当前不可用或协议帧超过大小限制。');
        return this.snapshot();
      }
      this.authProofSent = true;
      this.state = PairingConnectionState.WAITING_AUTH_OK;
      this.title = '已发送身份证明';
      this.description = '正在验证桌面端身份证明。';
      this.emit();
      return this.snapshot();
    }

    if (frameResult.envelope.messageType === MessageType.AUTH_PROOF) {
      const serverProof = this.networkHandshake.acceptServerAuthProof(message);
      if (!serverProof.ok) {
        this.fail('桌面端身份验证失败', this.describeNetworkFailure(serverProof.error));
        return this.snapshot();
      }
      this.state = PairingConnectionState.WAITING_AUTH_OK;
      this.title = '桌面端身份已确认';
      this.description = '正在等待桌面端完成认证。';
      this.emit();
      return this.snapshot();
    }

    if (frameResult.envelope.messageType === MessageType.AUTH_OK) {
      const authenticated = this.networkHandshake.acceptAuthOkAndCreateTransportSessionFromRememberedTranscript(message);
      if (!authenticated.ok || authenticated.transportSession === undefined) {
        this.fail('AUTH_OK 处理失败', this.describeNetworkFailure(authenticated.error));
        return this.snapshot();
      }
      this.authenticatedTransportSession = authenticated.transportSession;
      this.syncReady = false;
      this.state = PairingConnectionState.AUTHENTICATED;
      this.lastError = '';
      this.title = this.connectionPurpose === ConnectionHandshakePurpose.TRUSTED_RECONNECT
        ? '可信连接已认证'
        : '配对握手已认证';
      this.description = this.connectionPurpose === ConnectionHandshakePurpose.TRUSTED_RECONNECT
        ? '身份认证已完成，正在初始化空间密钥和同步状态。'
        : '身份认证已完成，正在等待桌面端下发加密空间密钥。';
      this.emit();
      return this.snapshot();
    }

    if (frameResult.envelope.messageType === MessageType.SPACE_KEY_ROTATED) {
      const isInitialPairing = this.connectionPurpose === ConnectionHandshakePurpose.PAIRING;
      const persisted = isInitialPairing
        ? await this.persistPairingCompletion(frameResult.decryptedPayload, Date.now())
        : await this.persistSpaceKeyRotation(frameResult.decryptedPayload, Date.now());
      if (!persisted.ok) {
        this.fail(isInitialPairing ? '配对保存失败' : '空间密钥轮换失败',
          this.describePairingPersistFailure(persisted.failureStage));
        return this.snapshot();
      }
      this.state = PairingConnectionState.AUTHENTICATED;
      this.lastError = '';
      this.title = isInitialPairing ? '配对已保存' : '空间密钥已更新';
      this.description = isInitialPairing
        ? '已保存桌面端可信设备和同步空间密钥引用。'
        : '已安全导入桌面端轮换后的空间密钥；旧密钥绑定的本机同步历史已清空，正式同步可以继续。';
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
        this.title = '实时同步在线，历史初始化异常';
        this.description = '可信连接仍可收发实时文本；稍后重连会重新尝试历史补同步。';
        this.lastError = '收到的 SYNC_HEADS 不符合协议，或本机可信设备上下文已失效。';
        this.syncReady = true;
        this.emit();
        return this.snapshot();
      }
      if (!this.syncReady && this.connectionPurpose === ConnectionHandshakePurpose.TRUSTED_RECONNECT) {
        this.rememberTrustedEndpoint();
        await this.completeSyncInitialization(false);
        if (!this.syncReady) return this.snapshot();
      }
      this.title = '同步状态已更新';
      this.markAuthenticatedActivity();
      const requested = await this.requestMissingRanges(frameResult.decryptedPayload);
      this.description = requested
        ? '正在补齐本机缺失的最近记录。'
        : '最近记录已是最新。';
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
          this.latestReceivedSource = `桌面端 #${shortId(parsedItem.originDeviceId)}`;
          this.latestReceivedAt = formatClockTime(Date.now());
          this.latestReceivedByteLength = parsedItem.contentLength;
        }
        this.historyRevision += 1;
        this.markAuthenticatedActivity();
        this.title = '已安全保存桌面端文本';
        this.description = '内容已使用同步空间密钥加密写入最近记录；请到首页查看并按需复制到本机。';
        this.emit();
        return this.snapshot();
      }
      if (received.status === InboundItemLiveStatus.RELAYED) {
        if (parsedItem !== undefined) {
          this.latestReceivedText = parsedItem.content;
          this.latestReceivedSource = `同空间设备 #${shortId(parsedItem.originDeviceId)}`;
          this.latestReceivedAt = formatClockTime(Date.now());
          this.latestReceivedByteLength = parsedItem.contentLength;
        }
        this.markAuthenticatedActivity();
        this.title = '已接收同空间设备文本';
        this.description = '内容由可信桌面端实时转发；可在首页查看并按需复制到本机。';
        this.emit();
        return this.snapshot();
      }
      if (received.status === InboundItemLiveStatus.DUPLICATE) {
        this.markAuthenticatedActivity();
        this.title = '已忽略重复桌面端文本';
        this.description = '该实时事件已存在于本机历史，未重复写入。';
        this.emit();
        return this.snapshot();
      }
      if (received.status === InboundItemLiveStatus.IGNORED_BY_POLICY) {
        this.markAuthenticatedActivity();
        this.title = '自动接收已暂停';
        this.description = '收到的桌面端实时文本已按当前同步策略忽略。';
        this.emit();
        return this.snapshot();
      }
      this.fail('桌面端实时文本被拒绝', '该 ITEM_LIVE 未通过可信设备、空间或本地加密存储校验。');
      this.authenticatedTransportSession?.close();
      this.transport.close();
      return this.snapshot();
    }

    if (frameResult.envelope.messageType === MessageType.ITEM_BATCH) {
      const batch = await this.persistInboundItemBatch(frameResult.decryptedPayload, Date.now());
      if (!batch.ok) {
        this.fail('桌面端历史批次被拒绝', 'ITEM_BATCH 未通过协议、可信设备或本地加密存储校验。');
        return this.snapshot();
      }
      this.title = '历史补同步完成';
      this.markAuthenticatedActivity();
      this.historyRevision += 1;
      this.description = `新增 ${batch.storedCount} 条 · 重复 ${batch.duplicateCount} 条 · retention gap ${batch.gapCount} 个`;
      this.emit();
      return this.snapshot();
    }

    if (frameResult.envelope.messageType === MessageType.REQUEST_RANGE) {
      const parsed = new ProtocolParser().parseRequestRangePayload(frameResult.decryptedPayload);
      if (!parsed.ok || parsed.payload === undefined || this.context === null || this.pendingTrustDraft === null) {
        this.fail('历史范围请求被拒绝', 'REQUEST_RANGE 格式无效或同步空间上下文已失效。');
        return this.snapshot();
      }
      const built = await new OutboundItemBatchService(this.context)
        .build(this.pendingTrustDraft.spaceId, parsed.payload, Date.now());
      if (!built.ok || built.payload === undefined) {
        this.fail('历史批次构造失败', '无法从本机 retention 窗口恢复请求的历史记录。');
        return this.snapshot();
      }
      const batch: ItemBatchPayload = built.payload;
      const batchPayload = JSON.parse(JSON.stringify(batch)) as JsonObject;
      if (!await this.sendAuthenticatedBusinessFrame(MessageType.ITEM_BATCH, batchPayload)) {
        this.fail('历史批次发送失败', '认证连接已失效，稍后重连会重新比较同步头。');
      } else {
        this.markAuthenticatedActivity();
      }
      return this.snapshot();
    }

    if (frameResult.envelope.messageType === MessageType.ITEM_ACK) {
      const ack = new ProtocolParser().parseItemAckPayload(frameResult.decryptedPayload);
      if (!ack.ok) {
        this.fail('历史确认帧被拒绝', 'ITEM_ACK 格式无效。');
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
      this.fail('桌面端拒绝配对', describePairingAuthError(frameResult.envelope.payload));
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
    this.title = '已停止配对';
    this.description = '可以重新导入邀请或再次连接桌面端。';
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
        `${this.pendingOutboundCount} 条本机记录等待同步初始化完成后自动发送`);
      return { status: AuthenticatedLocalSendStatus.INITIALIZING };
    }
    if (this.state !== PairingConnectionState.AUTHENTICATED ||
      this.authenticatedTransportSession === null || this.authenticatedTransportSession.isClosed()) {
      this.setOutboundDelivery(OutboundDeliveryState.QUEUED,
        `${this.pendingOutboundCount} 条本机记录等待可信连接恢复后发送`);
      return { status: AuthenticatedLocalSendStatus.QUEUED };
    }
    if (await this.sendAuthenticatedItemLive(prepared.payload)) {
      this.setOutboundDelivery(OutboundDeliveryState.SENDING,
        `${this.pendingOutboundCount} 条本机记录已提交，正在等待桌面端确认`);
      return { status: AuthenticatedLocalSendStatus.SENDING };
    }
    this.setOutboundDelivery(OutboundDeliveryState.QUEUED,
      `${this.pendingOutboundCount} 条本机记录发送失败，连接恢复后将自动补发`);
    return { status: AuthenticatedLocalSendStatus.QUEUED, field: 'transport' };
  }

  private sendClientHello(frame: string): void {
    this.transport.sendTextFrame(frame)
      .then((sent: boolean) => {
        if (!sent) {
          this.fail('CLIENT_HELLO 发送失败', 'WebSocket 当前不可用或协议帧超过大小限制。');
          return;
        }
        this.clientHelloSent = true;
        this.state = PairingConnectionState.CLIENT_HELLO_SENT;
        this.title = '已发送 CLIENT_HELLO';
        this.description = '正在等待桌面端返回 SERVER_HELLO。';
        this.emit();
      })
      .catch(() => {
        this.fail('CLIENT_HELLO 发送失败', '发送握手帧时出现异常。');
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
    this.title = '此设备已被桌面端移除';
    this.description = '可信关系已撤销，自动重连已停止；如需继续同步，请在桌面端生成新邀请后重新配对。';
    this.lastError = this.description;
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
    this.lastError = '';
  }

  private async completeSyncInitialization(isInitialPairing: boolean): Promise<void> {
    await this.refreshPendingOutboundState();
    const headsSent = await this.sendLocalSyncHeads();
    if (!headsSent) {
      this.syncReady = false;
      this.title = '同步初始化尚未完成';
      this.description = '认证连接已建立，但同步状态发送失败；连接恢复后会自动重试。';
      this.emit();
      return;
    }
    this.syncReady = true;
    this.state = PairingConnectionState.AUTHENTICATED;
    this.lastError = '';
    this.title = isInitialPairing ? '配对完成，同步已就绪' : '可信连接已就绪';
    this.description = '安全连接和同步状态均已初始化，可以双向同步纯文本。';
    this.emit();

    const queuedPayloads = this.pendingInitializationPayloads.splice(0);
    let submittedCount = 0;
    for (let index = 0; index < queuedPayloads.length; index += 1) {
      if (!await this.sendAuthenticatedItemLive(queuedPayloads[index])) break;
      submittedCount += 1;
    }
    if (submittedCount > 0) {
      this.setOutboundDelivery(OutboundDeliveryState.SENDING,
        `${this.pendingOutboundCount} 条本机记录已在初始化完成后自动提交`);
    }
  }

  private fail(title: string, description: string): void {
    this.state = PairingConnectionState.FAILED;
    this.title = title;
    this.description = description;
    this.lastError = description;
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
            displayName: `同步空间 #${shortId(spaceId)}`,
            keyVersion,
            state: SpaceState.ACTIVE,
            createdAt: nowMs
          },
          encryptedSpaceKeyRef: delivery.encryptedSpaceKeyRef,
          updatedAt: nowMs
        },
        device: {
          device: {
            deviceId: serverHello.deviceId,
            spaceId,
            displayName: `桌面端 #${shortId(serverHello.deviceId)}`,
            identityPublicKeyRef: serverHello.identityPublicKey,
            trustState: DeviceTrustState.TRUSTED,
            connectionState: DeviceConnectionState.ONLINE,
            lastSeenAt: nowMs
          },
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

  private setOutboundDelivery(state: OutboundDeliveryState, description: string): void {
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

  private describeMaterialFailure(field?: string): string {
    if (field !== undefined && field.length > 0) {
      if (field === 'deviceIdMetadata') {
        return '无法读取或写入本机设备 ID，请重启应用；如果仍失败，请清除应用数据后重试。';
      }
      if (field === 'identityPublicKeyMetadata') {
        return '无法读取本机身份公钥 metadata，请重启应用后重试。';
      }
      if (field === 'identityPrivateKeyRefMetadata') {
        return '无法读取本机 HUKS 私钥引用 metadata，请重启应用后重试。';
      }
      if (field === 'saveIdentityPublicKeyMetadata') {
        return '无法保存本机身份公钥 metadata，请检查应用数据库状态。';
      }
      if (field === 'saveIdentityPrivateKeyRefMetadata') {
        return '无法保存本机 HUKS 私钥引用 metadata，请检查应用数据库状态。';
      }
      if (field === 'localDeviceId') {
        return '本机设备 ID 格式无效，已修复生成逻辑；请重启应用或清除应用数据后重试。';
      }
      return `无法生成安全握手材料：${field}`;
    }
    return '请确认邀请仍在有效期内，并检查本机 HUKS 身份是否可用。';
  }

  private describeNetworkFailure(error?: PairingClientNetworkHandshakeError): string {
    if (error === PairingClientNetworkHandshakeError.INVALID_PHASE) {
      return '握手消息顺序不正确，已停止本次配对。';
    }
    if (error === PairingClientNetworkHandshakeError.AUTH_PROOF_FAILED) {
      return '无法生成或发送 AUTH_PROOF，未创建可信设备。';
    }
    if (error === PairingClientNetworkHandshakeError.SERVER_AUTH_PROOF_FAILED) {
      return '桌面端身份签名无效或与邀请不一致，已拒绝建立连接。';
    }
    if (error === PairingClientNetworkHandshakeError.AUTH_OK_FAILED) {
      return '桌面端确认失败或会话密钥派生失败。';
    }
    return '正式配对握手失败，未创建可信设备。';
  }

  private describePairingPersistFailure(stage: string | undefined): string {
    if (stage === undefined || stage === 'context') {
      return '已收到桌面端加密空间密钥包，但本机页面上下文或握手状态已失效，请重新配对。';
    }
    if (stage.indexOf('spaceKey:importFailed') === 0) {
      return `已收到桌面端加密空间密钥包，但 HUKS 空间密钥导入失败（阶段：${safeStageSuffix(stage)}）。请重启应用后重试；如果仍失败，请尝试清除应用数据后重新配对。`;
    }
    if (stage.indexOf('spaceKey:') === 0) {
      return `已收到桌面端加密空间密钥包，但空间密钥 payload 校验失败（阶段：${safeStageSuffix(stage)}）。请重新生成邀请并重新配对。`;
    }
    if (stage === 'rdb:space') {
      return '已收到桌面端加密空间密钥包，HUKS 空间密钥处理已通过，但写入本机同步空间记录失败。请重启应用后重试；如果仍失败，请清除应用数据后重新配对。';
    }
    if (stage === 'rdb:device') {
      return '已收到桌面端加密空间密钥包，HUKS 空间密钥处理已通过，但写入桌面端可信设备记录失败。请重启应用后重试；如果仍失败，请清除应用数据后重新配对。';
    }
    if (stage.indexOf('rdb:') === 0) {
      return '已收到桌面端加密空间密钥包，HUKS 空间密钥处理已通过，但写入本机数据库失败。请重启应用后重试。';
    }
    return '已收到桌面端加密空间密钥包，但无法完整写入本机同步空间和可信设备记录。';
  }

  private describeCloseTitle(): string {
    if (this.state === PairingConnectionState.CLIENT_HELLO_SENT) {
      return '桌面端关闭配对握手';
    }
    if (this.state === PairingConnectionState.WAITING_AUTH_OK) {
      return '桌面端关闭身份认证';
    }
    if (this.state === PairingConnectionState.CONNECTING) {
      return '配对连接已关闭';
    }
    return '配对连接中断';
  }

  private describeCloseReason(reason: string): string {
    const normalized = reason.trim().toLowerCase();
    const closeDetail = reason.trim().length > 0 ? `底层连接信息：${reason.trim()}` : '底层连接没有返回详细原因。';
    if (this.state === PairingConnectionState.CLIENT_HELLO_SENT) {
      return `${closeDetail} 这通常表示桌面端拒绝了 CLIENT_HELLO：请在桌面端重新生成邀请，确认邀请未过期、未被使用，并查看桌面端“帧诊断”的上次拒绝原因。`;
    }
    if (this.state === PairingConnectionState.WAITING_AUTH_OK) {
      return `${closeDetail} 这通常表示双向身份证明未完成：请重新生成邀请并重新配对。`;
    }
    if (normalized.indexOf('link is down') >= 0 || normalized === '0:' || normalized === '0') {
      return `${closeDetail} 请确认手机和桌面端在同一局域网，桌面端 WebSocket 服务仍在运行，并优先填写桌面端显示的普通 Wi-Fi IPv4 地址。`;
    }
    return closeDetail;
  }

  private describeTransportError(reason: string): string {
    const trimmed = reason.trim();
    if (trimmed.length <= 0) {
      return 'WebSocket 连接失败，请检查桌面端 IP、端口和局域网连通性。';
    }
    if (trimmed.toLowerCase().indexOf('link is down') >= 0) {
      return `${trimmed}。请确认手机和桌面端在同一局域网，桌面端服务仍在运行，并优先使用普通 Wi-Fi IPv4 地址。`;
    }
    return trimmed;
  }
}

function nextMessageId(): string {
  return normalizeUuid(util.generateRandomUUID(false), Date.now(), Math.random());
}

function shortId(value: string): string {
  return value.length >= 8 ? value.slice(0, 8) : value;
}

function formatClockTime(milliseconds: number): string {
  const date = new Date(milliseconds);
  const hours = date.getHours().toString().padStart(2, '0');
  const minutes = date.getMinutes().toString().padStart(2, '0');
  const seconds = date.getSeconds().toString().padStart(2, '0');
  return `${hours}:${minutes}:${seconds}`;
}

function failedPersist(failureStage: string): PairingCompletionPersistResult {
  return {
    ok: false,
    failureStage
  };
}

function safeStageSuffix(stage: string): string {
  const parts = stage.split(':');
  const suffix = parts.length > 0 ? parts[parts.length - 1] : 'unknown';
  return /^[A-Za-z0-9_.-]{1,48}$/.test(suffix) ? suffix : 'unknown';
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

export function describePairingAuthError(payload: JsonObject | undefined): string {
  const code = payload === undefined || typeof payload.code !== 'string' ? '' : payload.code;
  if (code === 'invitationExpired') {
    return '邀请已过期，请在桌面端重新生成。';
  }
  if (code === 'invitationConsumed') {
    return '邀请已经使用过；邀请只能成功消费一次，请重新生成。';
  }
  if (code === 'invitationMissing') {
    return '桌面端找不到该邀请，可能已经清理或来自其他桌面端。';
  }
  if (code === 'identityOrSpaceMismatch') {
    return '邀请中的设备身份或同步空间与桌面端不匹配，已拒绝建立连接。';
  }
  if (code === 'authProofFailed') {
    return '设备身份签名校验失败，未创建可信设备。';
  }
  return '桌面端返回认证错误，未创建可信设备。';
}

function pairingAuthErrorCode(payload: JsonObject | undefined): string {
  if (payload === undefined) return '';
  const code = payload['code'];
  return typeof code === 'string' ? code : '';
}

export function calculatePendingOutboundCount(localLatest: number, acknowledgedLatest: number): number {
  if (!Number.isSafeInteger(localLatest) || !Number.isSafeInteger(acknowledgedLatest) ||
    localLatest < 0 || acknowledgedLatest < 0) return 0;
  return Math.max(0, localLatest - acknowledgedLatest);
}
