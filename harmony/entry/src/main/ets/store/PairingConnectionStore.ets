import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { PairingRdbRepository } from '../data/repositories/RdbRepositories';
import { LocalIdentityRdbRepository } from '../data/repositories/LocalIdentityRdbRepository';
import {
  DeviceConnectionState,
  DeviceTrustState,
  SpaceState
} from '../models/DomainModels';
import { ManualEndpoint } from '../models/PocModels';
import {
  HelloPayload,
  JsonObject,
  MessageType
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
import { WebSocketTransportService } from '../services/transport/WebSocketTransportService';
import {
  PairingGeneratedHandshakeMaterialResult,
  PairingStore
} from './PairingStore';
import { PairingHandshakeDraft } from '../services/pairing/PairingHandshakeDraftService';

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
  manualHost: string;
  manualPort: string;
  endpointLabel: string;
  title: string;
  description: string;
  lastError: string;
  clientHelloSent: boolean;
  authProofSent: boolean;
}

export type PairingConnectionSnapshotListener = (snapshot: PairingConnectionSnapshot) => void;

interface PairingCompletionPersistResult {
  ok: boolean;
  encryptedSpaceKeyRef?: string;
  failureStage?: string;
}

class PairingConnectionStore {
  private readonly listeners: PairingConnectionSnapshotListener[] = [];
  private readonly transport: WebSocketTransportService;
  private context: common.Context | null = null;
  private identityService: LocalDeviceIdentityService | null = null;
  private networkHandshake: PairingClientNetworkHandshakeService = new PairingClientNetworkHandshakeService();
  private localIdentityPrivateKeyRef: string = '';
  private authenticatedTransportSession: ProtocolTransportSession | null = null;
  private pendingTrustDraft: PairingHandshakeDraft | null = null;
  private pendingTrustServerHello: HelloPayload | null = null;
  private state: PairingConnectionState = PairingConnectionState.IDLE;
  private manualHost: string = '127.0.0.1';
  private manualPort: string = '0';
  private endpointLabel: string = '未设置';
  private title: string = '等待确认邀请';
  private description: string = '导入邀请并核对确认码后，再连接桌面端完成正式握手。';
  private lastError: string = '';
  private clientHelloSent: boolean = false;
  private authProofSent: boolean = false;

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
      manualHost: this.manualHost,
      manualPort: this.manualPort,
      endpointLabel: this.endpointLabel,
      title: this.title,
      description: this.description,
      lastError: this.lastError,
      clientHelloSent: this.clientHelloSent,
      authProofSent: this.authProofSent
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
    return await this.startWithPreparedMaterial(material, endpoint);
  }

  async startWithPreparedMaterial(
    material: PairingGeneratedHandshakeMaterialResult,
    endpoint: ManualEndpoint
  ): Promise<PairingConnectionSnapshot> {
    if (!material.ok || material.draft === undefined || material.localEphemeralPrivateKey === undefined ||
      material.localIdentityPrivateKeyRef === undefined) {
      this.fail('配对材料生成失败', this.describeMaterialFailure(material.field));
      return this.snapshot();
    }

    this.endpointLabel = `${endpoint.host}:${endpoint.port}`;
    this.localIdentityPrivateKeyRef = material.localIdentityPrivateKeyRef;
    this.pendingTrustDraft = material.draft;
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
    this.title = '正在连接桌面端';
    this.description = `${this.endpointLabel} · 连接成功后会发送 CLIENT_HELLO。`;
    this.emit();

    const handshakeSession = new ProtocolHandshakeTransportSession();
    const result = await this.transport.connectPairingHandshake(endpoint, handshakeSession, {
      onOpen: () => {
        this.sendClientHello(started.outgoingFrame ?? '');
      },
      onClose: (reason: string) => {
        if (this.state !== PairingConnectionState.AUTHENTICATED && this.state !== PairingConnectionState.FAILED) {
          this.fail(this.describeCloseTitle(), this.describeCloseReason(reason));
        }
      },
      onError: (reason: string) => {
        this.fail('配对连接失败', this.describeTransportError(reason));
      },
      onFrame: () => {
      },
      onTextFrame: (message, frameResult) => {
        this.handleHandshakeTextFrame(message, frameResult).catch(() => {
          this.fail('配对握手处理失败', '处理桌面端握手帧时出现异常。');
        });
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
      this.description = '正在等待桌面端确认 AUTH_OK。';
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
      this.state = PairingConnectionState.AUTHENTICATED;
      this.title = '配对握手已认证';
      this.description = '已创建正式协议会话，正在等待桌面端下发加密空间密钥。';
      this.emit();
      return this.snapshot();
    }

    if (frameResult.envelope.messageType === MessageType.SPACE_KEY_ROTATED) {
      const persisted = await this.persistPairingCompletion(frameResult.decryptedPayload, Date.now());
      if (!persisted.ok) {
        this.fail('配对保存失败', this.describePairingPersistFailure(persisted.failureStage));
        return this.snapshot();
      }
      this.state = PairingConnectionState.AUTHENTICATED;
      this.title = '配对已保存';
      this.description = '已保存桌面端可信设备和同步空间密钥引用；后续将接入正式剪贴板同步。';
      this.emit();
      return this.snapshot();
    }

    if (frameResult.envelope.messageType === MessageType.ITEM_LIVE) {
      const received = await this.persistInboundItemLive(frameResult.decryptedPayload, Date.now());
      if (received.status === InboundItemLiveStatus.STORED) {
        this.title = '已安全保存桌面端文本';
        this.description = '内容已使用同步空间密钥加密写入最近记录；请到首页查看并按需复制到本机。';
        this.emit();
        return this.snapshot();
      }
      if (received.status === InboundItemLiveStatus.DUPLICATE) {
        this.title = '已忽略重复桌面端文本';
        this.description = '该实时事件已存在于本机历史，未重复写入。';
        this.emit();
        return this.snapshot();
      }
      if (received.status === InboundItemLiveStatus.IGNORED_BY_POLICY) {
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

    if (frameResult.envelope.messageType === MessageType.AUTH_ERROR ||
      frameResult.envelope.messageType === MessageType.ERROR) {
      this.fail('桌面端拒绝配对', '桌面端返回认证错误，未创建可信设备。');
      return this.snapshot();
    }

    return this.snapshot();
  }

  close(): void {
    this.transport.close();
    this.localIdentityPrivateKeyRef = '';
    this.authenticatedTransportSession = null;
    this.pendingTrustDraft = null;
    this.pendingTrustServerHello = null;
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
    if (this.state !== PairingConnectionState.AUTHENTICATED ||
      this.authenticatedTransportSession === null ||
      this.authenticatedTransportSession.isClosed()) {
      return false;
    }
    const encoded = this.authenticatedTransportSession.encodeBusinessFrame(
      MessageType.ITEM_LIVE,
      nextMessageId(),
      payload
    );
    if (!encoded.ok || encoded.frame === undefined) {
      return false;
    }
    const sent = await this.transport.sendTextFrame(encoded.frame);
    if (!sent) {
      this.authenticatedTransportSession.close();
    }
    return sent;
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
      expectedOriginDeviceId: this.pendingTrustServerHello.deviceId,
      nowMs
    });
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
      return '桌面端关闭认证确认';
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
      return `${closeDetail} 这通常表示桌面端拒绝了 AUTH_PROOF：请重新生成邀请并重新配对。`;
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
