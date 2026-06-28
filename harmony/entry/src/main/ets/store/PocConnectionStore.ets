import { common } from '@kit.AbilityKit';
import {
  AppSettings,
  InboundClipboardEventKind,
  defaultAppSettings,
  inboundClipboardPolicy
} from '../models/DomainModels';
import {
  ManualEndpoint,
  MdnsServiceCandidate,
  PocLifecycleState
} from '../models/PocModels';
import { ConnectionState } from '../models/ShellModels';
import { SettingsRdbRepository } from '../data/repositories/RdbRepositories';
import { MdnsDiscoveryService } from '../services/discovery/MdnsDiscoveryService';
import {
  PocClipboardTextDecodeResult,
  WebSocketTransportService
} from '../services/transport/WebSocketTransportService';

export interface PocConnectionSnapshot {
  manualHost: string;
  manualPort: string;
  discoveryState: PocLifecycleState;
  discoveryStatus: string;
  discoveryCandidates: MdnsServiceCandidate[];
  transportState: PocLifecycleState;
  transportStatus: string;
  transportDiagnostics: string;
  connectionState: ConnectionState;
  connectionTitle: string;
  connectionDescription: string;
  latestReceivedText: string;
  latestReceivedPreview: string;
  latestReceivedSource: string;
  latestReceivedAt: string;
  latestReceivedByteLength: number;
}

export type PocConnectionSnapshotListener = (snapshot: PocConnectionSnapshot) => void;

class PocConnectionStore {
  private readonly transport: WebSocketTransportService = new WebSocketTransportService();
  private readonly listeners: PocConnectionSnapshotListener[] = [];
  private discovery: MdnsDiscoveryService | null = null;
  private settingsRepository: SettingsRdbRepository | null = null;
  private reconnectOnForeground: boolean = false;
  private manualHost: string = '127.0.0.1';
  private manualPort: string = '0';
  private discoveryState: PocLifecycleState = PocLifecycleState.IDLE;
  private discoveryStatus: string = '等待开始局域网发现';
  private discoveryCandidates: MdnsServiceCandidate[] = [];
  private transportState: PocLifecycleState = PocLifecycleState.IDLE;
  private transportStatus: string = '输入桌面端 IP 和端口后手动连接';
  private transportDiagnostics: string = '帧诊断：接收 0 · 接受 0 · 拒绝 0';
  private connectionState: ConnectionState = ConnectionState.OFFLINE;
  private connectionTitle: string = '等待桌面端';
  private connectionDescription: string = '正在等待 mDNS 候选，也可以使用手动 IP';
  private latestReceivedText: string = '';
  private latestReceivedPreview: string = '';
  private latestReceivedSource: string = '暂无内容';
  private latestReceivedAt: string = '';
  private latestReceivedByteLength: number = 0;

  initialize(context: common.UIAbilityContext): void {
    if (this.discovery === null) {
      this.discovery = new MdnsDiscoveryService(context);
    }
    if (this.settingsRepository === null) {
      this.settingsRepository = new SettingsRdbRepository(context);
    }
  }

  subscribe(listener: PocConnectionSnapshotListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
    listener(this.snapshot());
  }

  unsubscribe(listener: PocConnectionSnapshotListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  snapshot(): PocConnectionSnapshot {
    return {
      manualHost: this.manualHost,
      manualPort: this.manualPort,
      discoveryState: this.discoveryState,
      discoveryStatus: this.discoveryStatus,
      discoveryCandidates: this.discoveryCandidates.slice(),
      transportState: this.transportState,
      transportStatus: this.transportStatus,
      transportDiagnostics: this.transportDiagnostics,
      connectionState: this.connectionState,
      connectionTitle: this.connectionTitle,
      connectionDescription: this.connectionDescription,
      latestReceivedText: this.latestReceivedText,
      latestReceivedPreview: this.latestReceivedPreview,
      latestReceivedSource: this.latestReceivedSource,
      latestReceivedAt: this.latestReceivedAt,
      latestReceivedByteLength: this.latestReceivedByteLength
    };
  }

  startDiscovery(): void {
    if (this.discovery === null) {
      this.discoveryState = PocLifecycleState.FAILED;
      this.discoveryStatus = '无法获取页面上下文，mDNS 搜索不可用';
      this.emit();
      return;
    }
    this.discovery.startSearch({
      onStateChanged: (state: PocLifecycleState, reason: string) => {
        this.discoveryState = state;
        this.discoveryStatus = reason;
        if (this.transportState !== PocLifecycleState.RUNNING) {
          this.connectionState = state === PocLifecycleState.STARTING || state === PocLifecycleState.RUNNING
            ? ConnectionState.CONNECTING
            : ConnectionState.OFFLINE;
          this.connectionTitle = state === PocLifecycleState.FAILED ? '局域网发现不可用' : '正在发现桌面端';
          this.connectionDescription = reason;
        }
        this.emit();
      },
      onCandidatesChanged: (candidates: MdnsServiceCandidate[]) => {
        this.discoveryCandidates = candidates;
        if (candidates.length > 0) {
          this.discoveryStatus = `已发现 ${candidates.length} 个候选地址；mDNS 仅用于发现，不代表设备可信`;
          if (this.transportState !== PocLifecycleState.RUNNING) {
            this.connectionState = ConnectionState.CONNECTING;
            this.connectionTitle = `已发现 ${candidates.length} 个桌面候选`;
            this.connectionDescription = '请选择候选连接；候选地址不代表设备已经认证';
          }
        }
        this.emit();
      }
    });
  }

  stopDiscovery(): void {
    this.discovery?.stopSearch();
    this.discoveryState = PocLifecycleState.IDLE;
    this.discoveryStatus = '已停止局域网发现';
    this.emit();
  }

  connectCandidate(candidate: MdnsServiceCandidate): void {
    this.connectManualEndpoint(candidate.host, candidate.port.toString());
  }

  connectManualEndpoint(host: string, portText: string): void {
    this.manualHost = host;
    this.manualPort = portText;
    const port = Number(portText);
    const endpoint: ManualEndpoint = {
      host,
      port
    };
    this.transportStatus = '正在连接桌面端';
    this.transportState = PocLifecycleState.STARTING;
    this.connectionState = ConnectionState.CONNECTING;
    this.connectionTitle = '正在连接桌面端';
    this.connectionDescription = `${endpoint.host}:${endpoint.port}`;
    this.emit();
    this.transport.connect(endpoint, {
      onOpen: () => {
        this.reconnectOnForeground = true;
        this.transportState = PocLifecycleState.RUNNING;
        this.transportStatus = '已连接桌面端，PasteButton 读取后会发送文本';
        this.connectionState = ConnectionState.ONLINE;
        this.connectionTitle = '已连接桌面端';
        this.connectionDescription = `${endpoint.host}:${endpoint.port} · 当前连接尚未认证`;
        this.refreshTransportDiagnostics();
        this.emit();
      },
      onClose: (reason: string) => {
        this.transportState = PocLifecycleState.IDLE;
        this.transportStatus = `连接已关闭：${reason}`;
        this.connectionState = ConnectionState.OFFLINE;
        this.connectionTitle = '桌面端已断开';
        this.connectionDescription = reason;
        this.emit();
      },
      onError: (reason: string) => {
        this.transportState = PocLifecycleState.FAILED;
        this.transportStatus = `连接失败：${reason}`;
        this.connectionState = ConnectionState.OFFLINE;
        this.connectionTitle = '连接桌面端失败';
        this.connectionDescription = `${reason}；可尝试其他候选或手动 IP`;
        this.refreshTransportDiagnostics();
        this.emit();
      },
      onMessage: (message: string) => {
        const decoded = this.transport.decodeClipboardTextMessage(message);
        this.refreshTransportDiagnostics();
        if (decoded.ok) {
          this.handleInboundClipboardText(decoded);
        } else {
          this.transportStatus = `${decoded.reason}，已忽略`;
          this.emit();
        }
      }
    })
      .then((result) => {
        if (!result.ok) {
          this.transportState = PocLifecycleState.FAILED;
          this.transportStatus = result.reason === undefined ? '连接参数无效' : `连接参数无效：${result.reason}`;
          this.connectionState = ConnectionState.OFFLINE;
          this.connectionTitle = '连接参数无效';
          this.connectionDescription = result.reason ?? '请检查桌面端 IP 和端口';
          this.emit();
        }
      })
      .catch(() => {
        this.transportState = PocLifecycleState.FAILED;
        this.transportStatus = '连接桌面端失败';
        this.connectionState = ConnectionState.OFFLINE;
        this.connectionTitle = '连接桌面端失败';
        this.connectionDescription = '请检查候选地址、Windows 防火墙和当前网络';
        this.emit();
      });
  }

  disconnectManualEndpoint(): void {
    this.reconnectOnForeground = false;
    this.transport.close();
    this.transportState = PocLifecycleState.IDLE;
    this.transportStatus = '已主动断开桌面端';
    this.connectionState = ConnectionState.OFFLINE;
    this.connectionTitle = '已主动断开桌面端';
    this.connectionDescription = 'mDNS 发现仍可继续运行';
    this.emit();
  }

  handleForegroundChanged(appInForeground: boolean): void {
    if (appInForeground) {
      this.startDiscovery();
      if (this.reconnectOnForeground) {
        this.connectManualEndpoint(this.manualHost, this.manualPort);
      }
      return;
    }

    this.reconnectOnForeground = this.transport.isConnected();
    this.discovery?.stopSearch();
    this.transport.close();
    this.transportState = PocLifecycleState.IDLE;
    this.transportStatus = this.reconnectOnForeground
      ? '应用进入后台，已断开；回到前台后将重新连接'
      : '应用进入后台，已停止发现和连接';
    this.connectionState = ConnectionState.OFFLINE;
    this.connectionTitle = '应用已进入后台';
    this.connectionDescription = '前台同步已停止，回到前台后会重新发现';
    this.emit();
  }

  async sendClipboardText(text: string): Promise<boolean> {
    return this.transport.sendClipboardText(text);
  }

  isConnected(): boolean {
    return this.transport.isConnected();
  }

  private emit(): void {
    const current = this.snapshot();
    for (let index = 0; index < this.listeners.length; index += 1) {
      this.listeners[index](current);
    }
  }

  private handleInboundClipboardText(decoded: PocClipboardTextDecodeResult): void {
    this.loadSettings()
      .then((settings: AppSettings) => {
        const policy = inboundClipboardPolicy(InboundClipboardEventKind.ITEM_LIVE, settings);
        if (!policy.updateHistory) {
          this.transportStatus = '收到桌面端文本，但当前策略已暂停自动接收，已忽略';
          this.connectionState = ConnectionState.PAUSED;
          this.connectionTitle = '自动接收已暂停';
          this.connectionDescription = '设置开启后，桌面端文本才会进入预览；不会写入本机剪贴板';
          this.emit();
          return;
        }

        this.latestReceivedText = decoded.text;
        this.latestReceivedPreview = this.trimPreview(decoded.text);
        this.latestReceivedSource = '桌面端';
        this.latestReceivedAt = this.formatTime(Date.now());
        this.latestReceivedByteLength = decoded.byteLength;
        this.transportStatus = `收到桌面端文本：${decoded.byteLength} 字节`;
        this.connectionState = ConnectionState.ONLINE;
        this.connectionTitle = '已收到桌面端文本';
        this.connectionDescription = '内容只进入预览，点击后才会复制到本机';
        this.emit();
      })
      .catch(() => {
        this.transportStatus = '收到桌面端文本，但读取接收策略失败，已忽略';
        this.connectionState = ConnectionState.PAUSED;
        this.connectionTitle = '接收策略不可用';
        this.connectionDescription = '未确认本机设置前，不展示远端文本';
        this.emit();
      });
  }

  private async loadSettings(): Promise<AppSettings> {
    if (this.settingsRepository === null) {
      return defaultAppSettings();
    }
    return await this.settingsRepository.loadAppSettings() ?? defaultAppSettings();
  }

  private trimPreview(text: string): string {
    if (text.length <= 180) {
      return text;
    }
    return `${text.slice(0, 90)}\n……\n${text.slice(-60)}`;
  }

  private formatTime(milliseconds: number): string {
    const date = new Date(milliseconds);
    return `${this.padTime(date.getHours())}:${this.padTime(date.getMinutes())}:${this.padTime(date.getSeconds())}`;
  }

  private padTime(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }

  private refreshTransportDiagnostics(): void {
    const diagnostics = this.transport.currentDiagnostics();
    const rejection = diagnostics.lastRejection.length > 0
      ? ` · 上次拒绝：${diagnostics.lastRejection}`
      : '';
    this.transportDiagnostics = `帧诊断：接收 ${diagnostics.receivedFrames} · 接受 ${diagnostics.acceptedItems} · 拒绝 ${diagnostics.rejectedFrames}${rejection}`;
  }
}

export const pocConnectionStore: PocConnectionStore = new PocConnectionStore();
