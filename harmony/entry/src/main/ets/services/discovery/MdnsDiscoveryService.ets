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
  onStateChanged: (state: PocLifecycleState, event: MdnsDiscoveryEvent) => void;
  onCandidatesChanged: (candidates: MdnsServiceCandidate[]) => void;
}

export enum MdnsDiscoveryEvent {
  ALREADY_RUNNING = 'alreadyRunning',
  SEARCHING = 'searching',
  STOPPED = 'stopped',
  START_FAILED = 'startFailed',
  STOP_FAILED = 'stopFailed',
  RESOLVE_FAILED = 'resolveFailed'
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
      callbacks.onStateChanged(this.state, MdnsDiscoveryEvent.ALREADY_RUNNING);
      callbacks.onCandidatesChanged(this.currentCandidates());
      return;
    }

    this.callbacks = callbacks;
    this.state = PocLifecycleState.STARTING;
    this.generation += 1;
    callbacks.onStateChanged(this.state, MdnsDiscoveryEvent.SEARCHING);

    try {
      const discovery = mdns.createDiscoveryService(this.context, EGGCLIP_MDNS_DISCOVERY_TYPE);
      this.discovery = discovery;
      discovery.on('discoveryStart', this.onDiscoveryStart);
      discovery.on('discoveryStop', this.onDiscoveryStop);
      discovery.on('serviceFound', this.onServiceFound);
      discovery.on('serviceLost', this.onServiceLost);
      discovery.startSearchingMDNS();
    } catch (_) {
      this.failSearch(MdnsDiscoveryEvent.START_FAILED);
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
      this.callbacks.onStateChanged(this.state, MdnsDiscoveryEvent.STOPPED);
      this.callbacks.onCandidatesChanged([]);
    }
  }

  private readonly onDiscoveryStart = (event: mdns.DiscoveryEventInfo): void => {
    if (event.errorCode !== undefined) {
      this.failSearch(MdnsDiscoveryEvent.START_FAILED);
      return;
    }
    this.state = PocLifecycleState.RUNNING;
    this.notifyState(MdnsDiscoveryEvent.SEARCHING);
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
      this.notifyState(MdnsDiscoveryEvent.STOP_FAILED);
      return;
    }
    this.state = PocLifecycleState.IDLE;
    this.notifyState(MdnsDiscoveryEvent.STOPPED);
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
          this.notifyState(MdnsDiscoveryEvent.RESOLVE_FAILED);
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

  private failSearch(event: MdnsDiscoveryEvent): void {
    this.generation += 1;
    this.state = PocLifecycleState.FAILED;
    this.candidates = [];
    this.notifyState(event);
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

  private notifyState(event: MdnsDiscoveryEvent): void {
    if (this.callbacks !== null) {
      this.callbacks.onStateChanged(this.state, event);
    }
  }

  private notifyCandidates(): void {
    if (this.callbacks !== null) {
      this.callbacks.onCandidatesChanged(this.currentCandidates());
    }
  }
}
