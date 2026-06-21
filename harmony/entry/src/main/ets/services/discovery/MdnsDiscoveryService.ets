import { common } from '@kit.AbilityKit';
import { mdns } from '@kit.NetworkKit';
import {
  EGGCLIP_MDNS_DISCOVERY_TYPE,
  EGGCLIP_MDNS_SERVICE_TYPE,
  MdnsServiceCandidate,
  PocLifecycleState
} from '../../models/PocModels';

const TXT_PROTOCOL_VERSION: string = 'protocolVersion';
const TXT_INSTANCE_ID: string = 'instanceId';
const MAX_CANDIDATES: number = 32;
const MAX_INSTANCE_ID_LENGTH: number = 96;

export interface MdnsDiscoveryCallbacks {
  onStateChanged: (state: PocLifecycleState, reason: string) => void;
  onCandidatesChanged: (candidates: MdnsServiceCandidate[]) => void;
}

export class MdnsDiscoveryService {
  private readonly context: common.UIAbilityContext;
  private state: PocLifecycleState = PocLifecycleState.IDLE;
  private candidates: MdnsServiceCandidate[] = [];
  private discovery: mdns.DiscoveryService | null = null;
  private callbacks: MdnsDiscoveryCallbacks | null = null;
  private generation: number = 0;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  serviceType(): string {
    return EGGCLIP_MDNS_SERVICE_TYPE;
  }

  currentState(): PocLifecycleState {
    return this.state;
  }

  currentCandidates(): MdnsServiceCandidate[] {
    return this.candidates.slice();
  }

  startSearch(callbacks: MdnsDiscoveryCallbacks): void {
    if (this.discovery !== null) {
      callbacks.onStateChanged(this.state, 'mDNS 搜索已在运行');
      callbacks.onCandidatesChanged(this.currentCandidates());
      return;
    }

    this.callbacks = callbacks;
    this.state = PocLifecycleState.STARTING;
    this.generation += 1;
    callbacks.onStateChanged(this.state, '正在搜索局域网 EggClip 服务');

    try {
      const discovery = mdns.createDiscoveryService(this.context, EGGCLIP_MDNS_DISCOVERY_TYPE);
      this.discovery = discovery;
      discovery.on('discoveryStart', this.onDiscoveryStart);
      discovery.on('discoveryStop', this.onDiscoveryStop);
      discovery.on('serviceFound', this.onServiceFound);
      discovery.on('serviceLost', this.onServiceLost);
      discovery.startSearchingMDNS();
    } catch (_) {
      this.failSearch('无法启动 mDNS 搜索，请检查 Wi-Fi 和网络权限');
    }
  }

  stopSearch(): void {
    this.generation += 1;
    const discovery = this.discovery;
    this.discovery = null;
    if (discovery !== null) {
      try {
        discovery.stopSearchingMDNS();
      } catch (_) {
      }
      this.detachDiscovery(discovery);
    }
    this.state = PocLifecycleState.IDLE;
    this.candidates = [];
    if (this.callbacks !== null) {
      this.callbacks.onStateChanged(this.state, 'mDNS 搜索已停止，仍可使用手动 IP');
      this.callbacks.onCandidatesChanged([]);
    }
  }

  private readonly onDiscoveryStart = (event: mdns.DiscoveryEventInfo): void => {
    if (event.errorCode !== undefined) {
      this.failSearch(this.discoveryErrorMessage(event.errorCode));
      return;
    }
    this.state = PocLifecycleState.RUNNING;
    this.notifyState('正在搜索局域网 EggClip 服务');
  };

  private readonly onDiscoveryStop = (event: mdns.DiscoveryEventInfo): void => {
    this.generation += 1;
    const discovery = this.discovery;
    this.discovery = null;
    if (discovery !== null) {
      this.detachDiscovery(discovery);
    }
    this.candidates = [];
    this.notifyCandidates();
    if (event.errorCode !== undefined) {
      this.state = PocLifecycleState.FAILED;
      this.notifyState(`mDNS 搜索停止异常，错误码 ${event.errorCode}`);
      return;
    }
    this.state = PocLifecycleState.IDLE;
    this.notifyState('mDNS 搜索已停止，仍可使用手动 IP');
  };

  private readonly onServiceFound = (serviceInfo: mdns.LocalServiceInfo): void => {
    const generation = this.generation;
    mdns.resolveLocalService(this.context, serviceInfo)
      .then((resolved: mdns.LocalServiceInfo) => {
        if (generation !== this.generation || this.discovery === null) {
          return;
        }
        const candidate = this.toCandidate(resolved);
        if (candidate !== null) {
          this.mergeCandidate(candidate);
        }
      })
      .catch(() => {
        if (generation === this.generation && this.discovery !== null) {
          this.notifyState('发现服务但地址解析失败，继续搜索');
        }
      });
  };

  private readonly onServiceLost = (serviceInfo: mdns.LocalServiceInfo): void => {
    const next = this.candidates.filter((candidate: MdnsServiceCandidate) =>
      candidate.serviceName !== serviceInfo.serviceName);
    if (next.length !== this.candidates.length) {
      this.candidates = next;
      this.notifyCandidates();
    }
  };

  private toCandidate(serviceInfo: mdns.LocalServiceInfo): MdnsServiceCandidate | null {
    const host = serviceInfo.host?.address.trim() ?? '';
    const family = serviceInfo.host?.family ?? 1;
    const port = serviceInfo.port ?? 0;
    if (host.length === 0 || family !== 1 || port < 1 || port > 65535) {
      return null;
    }

    const protocolVersionText = this.readAllowedTxt(serviceInfo, TXT_PROTOCOL_VERSION);
    const protocolVersion = Number(protocolVersionText);
    const instanceIdText = this.readAllowedTxt(serviceInfo, TXT_INSTANCE_ID);
    const instanceId = instanceIdText.length > 0 ? instanceIdText : serviceInfo.serviceName;
    if (instanceId.length === 0 || instanceId.length > MAX_INSTANCE_ID_LENGTH) {
      return null;
    }
    return {
      instanceId,
      serviceName: serviceInfo.serviceName,
      host,
      port,
      protocolVersion: Number.isInteger(protocolVersion) && protocolVersion > 0 ? protocolVersion : 0
    };
  }

  private readAllowedTxt(serviceInfo: mdns.LocalServiceInfo, key: string): string {
    const attribute = serviceInfo.serviceAttribute?.find((item: mdns.ServiceAttribute) => item.key === key);
    if (attribute === undefined) {
      return '';
    }
    let value = '';
    attribute.value.forEach((byte: number) => {
      if (byte >= 0x20 && byte <= 0x7e) {
        value += String.fromCharCode(byte);
      }
    });
    return value;
  }

  private mergeCandidate(candidate: MdnsServiceCandidate): void {
    const existingIndex = this.candidates.findIndex((item: MdnsServiceCandidate) =>
      item.instanceId === candidate.instanceId);
    if (existingIndex >= 0) {
      this.candidates[existingIndex] = candidate;
    } else if (this.candidates.length < MAX_CANDIDATES) {
      this.candidates.push(candidate);
    }
    this.notifyCandidates();
  }

  private failSearch(reason: string): void {
    this.generation += 1;
    this.state = PocLifecycleState.FAILED;
    this.candidates = [];
    this.notifyState(reason);
    this.notifyCandidates();
    const discovery = this.discovery;
    this.discovery = null;
    if (discovery !== null) {
      try {
        discovery.stopSearchingMDNS();
      } catch (_) {
      }
      this.detachDiscovery(discovery);
    }
  }

  private detachDiscovery(discovery: mdns.DiscoveryService): void {
    discovery.off('discoveryStart', this.onDiscoveryStart);
    discovery.off('discoveryStop', this.onDiscoveryStop);
    discovery.off('serviceFound', this.onServiceFound);
    discovery.off('serviceLost', this.onServiceLost);
  }

  private discoveryErrorMessage(errorCode: mdns.MdnsError): string {
    if (errorCode === mdns.MdnsError.INTERNAL_ERROR) {
      return 'mDNS 子系统启动失败；模拟器可能不支持局域网组播，请使用真机验证或改用手动 IP';
    }
    if (errorCode === mdns.MdnsError.ALREADY_ACTIVE) {
      return 'mDNS 搜索已在运行';
    }
    if (errorCode === mdns.MdnsError.MAX_LIMIT) {
      return 'mDNS 搜索数量已达系统上限，请停止其他搜索后重试';
    }
    return `mDNS 搜索启动失败，错误码 ${errorCode}`;
  }

  private notifyState(reason: string): void {
    if (this.callbacks !== null) {
      this.callbacks.onStateChanged(this.state, reason);
    }
  }

  private notifyCandidates(): void {
    if (this.callbacks !== null) {
      this.callbacks.onCandidatesChanged(this.currentCandidates());
    }
  }
}
