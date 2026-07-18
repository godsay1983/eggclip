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
import {
  RecentPocEndpointRecord,
  SettingsRdbRepository
} from '../data/repositories/RdbRepositories';
import { MdnsDiscoveryEvent, MdnsDiscoveryService } from '../services/discovery/MdnsDiscoveryService';
import {
  PocClipboardTextDecodeResult,
  WebSocketTransportService
} from '../services/transport/WebSocketTransportService';
import {
  UiMessageCode,
  UiMessageDescriptor,
  UiMessageParameterName,
  cloneUiMessage,
  uiMessage,
  uiParameter
} from '../services/localization/UiMessageCodes';

export interface PocConnectionSnapshot {
  manualHost: string;
  manualPort: string;
  lastSuccessfulHost: string;
  lastSuccessfulPort: string;
  lastSuccessfulEndpointLabel: string;
  lastSuccessfulAtMs: number;
  discoveryState: PocLifecycleState;
  discoveryStatus: UiMessageDescriptor;
  discoveryCandidates: MdnsServiceCandidate[];
  transportState: PocLifecycleState;
  transportStatus: UiMessageDescriptor;
  transportDiagnostics: UiMessageDescriptor;
  connectionState: ConnectionState;
  connectionTitle: UiMessageDescriptor;
  connectionDescription: UiMessageDescriptor;
  latestReceivedText: string;
  latestReceivedPreview: string;
  latestReceivedSource: UiMessageDescriptor;
  latestReceivedAtMs: number;
  latestReceivedByteLength: number;
}

export type PocConnectionSnapshotListener = (snapshot: PocConnectionSnapshot) => void;

class PocConnectionStore {
  private readonly transport: WebSocketTransportService = new WebSocketTransportService();
  private readonly listeners: PocConnectionSnapshotListener[] = [];
  private discovery: MdnsDiscoveryService | null = null;
  private settingsRepository: SettingsRdbRepository | null = null;
  private recentEndpointLoaded: boolean = false;
  private reconnectOnForeground: boolean = false;
  private manualHost: string = '127.0.0.1';
  private manualPort: string = '0';
  private lastSuccessfulHost: string = '';
  private lastSuccessfulPort: string = '';
  private lastSuccessfulEndpointLabel: string = '';
  private lastSuccessfulAtMs: number = 0;
  private discoveryState: PocLifecycleState = PocLifecycleState.IDLE;
  private discoveryStatus: UiMessageDescriptor = uiMessage(UiMessageCode.DISCOVERY_WAITING);
  private discoveryCandidates: MdnsServiceCandidate[] = [];
  private transportState: PocLifecycleState = PocLifecycleState.IDLE;
  private transportStatus: UiMessageDescriptor = uiMessage(UiMessageCode.POC_TRANSPORT_IDLE);
  private transportDiagnostics: UiMessageDescriptor = uiMessage(UiMessageCode.POC_DIAGNOSTICS, [
    uiParameter(UiMessageParameterName.COUNT, 0),
    uiParameter(UiMessageParameterName.COUNT, 0),
    uiParameter(UiMessageParameterName.COUNT, 0)
  ]);
  private connectionState: ConnectionState = ConnectionState.OFFLINE;
  private connectionTitle: UiMessageDescriptor = uiMessage(UiMessageCode.CONNECTION_WAITING_TITLE);
  private connectionDescription: UiMessageDescriptor = uiMessage(UiMessageCode.CONNECTION_WAITING_DESCRIPTION);
  private latestReceivedText: string = '';
  private latestReceivedPreview: string = '';
  private latestReceivedSource: UiMessageDescriptor = uiMessage(UiMessageCode.SOURCE_NONE);
  private latestReceivedAtMs: number = 0;
  private latestReceivedByteLength: number = 0;

  initialize(context: common.UIAbilityContext): void {
    if (this.discovery === null) {
      this.discovery = new MdnsDiscoveryService(context);
    }
    if (this.settingsRepository === null) {
      this.settingsRepository = new SettingsRdbRepository(context);
    }
    this.loadRecentEndpoint();
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
      lastSuccessfulHost: this.lastSuccessfulHost,
      lastSuccessfulPort: this.lastSuccessfulPort,
      lastSuccessfulEndpointLabel: this.lastSuccessfulEndpointLabel,
      lastSuccessfulAtMs: this.lastSuccessfulAtMs,
      discoveryState: this.discoveryState,
      discoveryStatus: cloneUiMessage(this.discoveryStatus),
      discoveryCandidates: this.discoveryCandidates.slice(),
      transportState: this.transportState,
      transportStatus: cloneUiMessage(this.transportStatus),
      transportDiagnostics: cloneUiMessage(this.transportDiagnostics),
      connectionState: this.connectionState,
      connectionTitle: cloneUiMessage(this.connectionTitle),
      connectionDescription: cloneUiMessage(this.connectionDescription),
      latestReceivedText: this.latestReceivedText,
      latestReceivedPreview: this.latestReceivedPreview,
      latestReceivedSource: cloneUiMessage(this.latestReceivedSource),
      latestReceivedAtMs: this.latestReceivedAtMs,
      latestReceivedByteLength: this.latestReceivedByteLength
    };
  }

  startDiscovery(): void {
    if (this.discovery === null) {
      this.discoveryState = PocLifecycleState.FAILED;
      this.discoveryStatus = uiMessage(UiMessageCode.DISCOVERY_UNAVAILABLE);
      this.emit();
      return;
    }
    this.discovery.startSearch({
      onStateChanged: (state: PocLifecycleState, _event: MdnsDiscoveryEvent) => {
        this.discoveryState = state;
        this.discoveryStatus = state === PocLifecycleState.FAILED
          ? uiMessage(UiMessageCode.DISCOVERY_UNAVAILABLE)
          : uiMessage(UiMessageCode.DISCOVERY_SEARCHING);
        if (this.transportState !== PocLifecycleState.RUNNING) {
          this.connectionState = state === PocLifecycleState.STARTING || state === PocLifecycleState.RUNNING
            ? ConnectionState.CONNECTING
            : ConnectionState.OFFLINE;
          this.connectionTitle = state === PocLifecycleState.FAILED
            ? uiMessage(UiMessageCode.CONNECTION_FAILED_TITLE)
            : uiMessage(UiMessageCode.CONNECTION_CONNECTING_TITLE);
          this.connectionDescription = state === PocLifecycleState.FAILED
            ? uiMessage(UiMessageCode.DISCOVERY_UNAVAILABLE)
            : uiMessage(UiMessageCode.DISCOVERY_SEARCHING);
        }
        this.emit();
      },
      onCandidatesChanged: (candidates: MdnsServiceCandidate[]) => {
        this.discoveryCandidates = candidates;
        if (candidates.length > 0) {
          this.discoveryStatus = uiMessage(UiMessageCode.DISCOVERY_FOUND, [
            uiParameter(UiMessageParameterName.COUNT, candidates.length)
          ]);
          if (this.transportState !== PocLifecycleState.RUNNING) {
            this.connectionState = ConnectionState.CONNECTING;
            this.connectionTitle = uiMessage(UiMessageCode.CONNECTION_CONNECTING_TITLE);
            this.connectionDescription = uiMessage(UiMessageCode.DISCOVERY_FOUND, [
              uiParameter(UiMessageParameterName.COUNT, candidates.length)
            ]);
          }
        }
        this.emit();
      }
    });
  }

  stopDiscovery(): void {
    this.discovery?.stopSearch();
    this.discoveryState = PocLifecycleState.IDLE;
    this.discoveryStatus = uiMessage(UiMessageCode.DISCOVERY_STOPPED);
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
    this.transportStatus = uiMessage(UiMessageCode.POC_CONNECTING, [
      uiParameter(UiMessageParameterName.ENDPOINT, `${endpoint.host}:${endpoint.port}`)
    ]);
    this.transportState = PocLifecycleState.STARTING;
    this.connectionState = ConnectionState.CONNECTING;
    this.connectionTitle = uiMessage(UiMessageCode.CONNECTION_CONNECTING_TITLE);
    this.connectionDescription = uiMessage(UiMessageCode.CONNECTION_CONNECTING_DESCRIPTION, [
      uiParameter(UiMessageParameterName.ENDPOINT, `${endpoint.host}:${endpoint.port}`)
    ]);
    this.emit();
    this.transport.connect(endpoint, {
      onOpen: () => {
        this.reconnectOnForeground = true;
        this.rememberSuccessfulEndpoint(endpoint.host, endpoint.port);
        this.transportState = PocLifecycleState.RUNNING;
        this.transportStatus = uiMessage(UiMessageCode.POC_CONNECTED, [
          uiParameter(UiMessageParameterName.ENDPOINT, `${endpoint.host}:${endpoint.port}`)
        ]);
        this.connectionState = ConnectionState.ONLINE;
        this.connectionTitle = uiMessage(UiMessageCode.CONNECTION_AUTHENTICATED_TITLE);
        this.connectionDescription = uiMessage(UiMessageCode.POC_CONNECTED, [
          uiParameter(UiMessageParameterName.ENDPOINT, `${endpoint.host}:${endpoint.port}`)
        ]);
        this.refreshTransportDiagnostics();
        this.emit();
      },
      onClose: (reason: string) => {
        this.transportState = PocLifecycleState.IDLE;
        this.transportStatus = uiMessage(UiMessageCode.POC_CLOSED);
        this.connectionState = ConnectionState.OFFLINE;
        this.connectionTitle = uiMessage(UiMessageCode.CONNECTION_STOPPED_TITLE);
        this.connectionDescription = uiMessage(UiMessageCode.POC_CLOSED);
        this.emit();
      },
      onError: (reason: string) => {
        this.transportState = PocLifecycleState.FAILED;
        this.transportStatus = uiMessage(UiMessageCode.POC_FAILED);
        this.connectionState = ConnectionState.OFFLINE;
        this.connectionTitle = uiMessage(UiMessageCode.CONNECTION_FAILED_TITLE);
        this.connectionDescription = uiMessage(UiMessageCode.POC_FAILED);
        this.refreshTransportDiagnostics();
        this.emit();
      },
      onMessage: (message: string) => {
        const decoded = this.transport.decodeClipboardTextMessage(message);
        this.refreshTransportDiagnostics();
        if (decoded.ok) {
          this.handleInboundClipboardText(decoded);
        } else {
          this.transportStatus = uiMessage(UiMessageCode.POC_FAILED);
          this.emit();
        }
      }
    })
      .then((result) => {
        if (!result.ok) {
          this.transportState = PocLifecycleState.FAILED;
          this.transportStatus = uiMessage(UiMessageCode.POC_INVALID);
          this.connectionState = ConnectionState.OFFLINE;
          this.connectionTitle = uiMessage(UiMessageCode.CONNECTION_ENDPOINT_INVALID_TITLE);
          this.connectionDescription = uiMessage(UiMessageCode.CONNECTION_ENDPOINT_INVALID_DESCRIPTION);
          this.emit();
        }
      })
      .catch(() => {
        this.transportState = PocLifecycleState.FAILED;
        this.transportStatus = uiMessage(UiMessageCode.POC_FAILED);
        this.connectionState = ConnectionState.OFFLINE;
        this.connectionTitle = uiMessage(UiMessageCode.CONNECTION_FAILED_TITLE);
        this.connectionDescription = uiMessage(UiMessageCode.POC_FAILED);
        this.emit();
      });
  }

  disconnectManualEndpoint(): void {
    this.reconnectOnForeground = false;
    this.transport.close();
    this.transportState = PocLifecycleState.IDLE;
    this.transportStatus = uiMessage(UiMessageCode.POC_DISCONNECTED);
    this.connectionState = ConnectionState.OFFLINE;
    this.connectionTitle = uiMessage(UiMessageCode.CONNECTION_STOPPED_TITLE);
    this.connectionDescription = uiMessage(UiMessageCode.POC_DISCONNECTED);
    this.emit();
  }

  connectLastSuccessfulEndpoint(): void {
    if (this.lastSuccessfulHost.length === 0 || this.lastSuccessfulPort.length === 0) {
      this.transportStatus = uiMessage(UiMessageCode.POC_RECENT_MISSING);
      this.emit();
      return;
    }
    this.connectManualEndpoint(this.lastSuccessfulHost, this.lastSuccessfulPort);
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
    this.transportStatus = uiMessage(UiMessageCode.POC_BACKGROUND);
    this.connectionState = ConnectionState.OFFLINE;
    this.connectionTitle = uiMessage(UiMessageCode.CONNECTION_STOPPED_TITLE);
    this.connectionDescription = uiMessage(UiMessageCode.POC_BACKGROUND);
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

  private rememberSuccessfulEndpoint(host: string, port: number): void {
    const connectedAt = Date.now();
    this.lastSuccessfulHost = host;
    this.lastSuccessfulPort = port.toString();
    this.lastSuccessfulEndpointLabel = `${host}:${port}`;
    this.lastSuccessfulAtMs = connectedAt;
    this.saveRecentEndpoint({
      host,
      port,
      connectedAt
    });
  }

  private loadRecentEndpoint(): void {
    if (this.recentEndpointLoaded || this.settingsRepository === null) {
      return;
    }
    this.recentEndpointLoaded = true;
    this.settingsRepository.loadRecentPocEndpoint()
      .then((record: RecentPocEndpointRecord | null) => {
        if (record === null) {
          return;
        }
        this.lastSuccessfulHost = record.host;
        this.lastSuccessfulPort = record.port.toString();
        this.lastSuccessfulEndpointLabel = `${record.host}:${record.port}`;
        this.lastSuccessfulAtMs = record.connectedAt;
        if (this.manualPort === '0') {
          this.manualHost = record.host;
          this.manualPort = record.port.toString();
        }
        this.emit();
      })
      .catch(() => {
        this.lastSuccessfulHost = '';
        this.lastSuccessfulPort = '';
        this.lastSuccessfulEndpointLabel = '';
        this.lastSuccessfulAtMs = 0;
        this.emit();
      });
  }

  private saveRecentEndpoint(record: RecentPocEndpointRecord): void {
    this.settingsRepository?.saveRecentPocEndpoint(record).catch(() => {
      this.transportStatus = uiMessage(UiMessageCode.POC_CONNECTED, [
        uiParameter(UiMessageParameterName.ENDPOINT, this.lastSuccessfulEndpointLabel)
      ]);
      this.emit();
    });
  }

  private handleInboundClipboardText(decoded: PocClipboardTextDecodeResult): void {
    this.loadSettings()
      .then((settings: AppSettings) => {
        const policy = inboundClipboardPolicy(InboundClipboardEventKind.ITEM_LIVE, settings);
        if (!policy.updateHistory) {
          this.transportStatus = uiMessage(UiMessageCode.CONNECTION_RECEIVE_PAUSED_DESCRIPTION);
          this.connectionState = ConnectionState.PAUSED;
          this.connectionTitle = uiMessage(UiMessageCode.CONNECTION_RECEIVE_PAUSED_TITLE);
          this.connectionDescription = uiMessage(UiMessageCode.CONNECTION_RECEIVE_PAUSED_DESCRIPTION);
          this.emit();
          return;
        }

        this.latestReceivedText = decoded.text;
        this.latestReceivedPreview = this.trimPreview(decoded.text);
        this.latestReceivedSource = uiMessage(UiMessageCode.SOURCE_DESKTOP);
        this.latestReceivedAtMs = Date.now();
        this.latestReceivedByteLength = decoded.byteLength;
        this.transportStatus = uiMessage(UiMessageCode.CONNECTION_RECEIVED_DESCRIPTION);
        this.connectionState = ConnectionState.ONLINE;
        this.connectionTitle = uiMessage(UiMessageCode.CONNECTION_RECEIVED_TITLE);
        this.connectionDescription = uiMessage(UiMessageCode.CONNECTION_RECEIVED_DESCRIPTION);
        this.emit();
      })
      .catch(() => {
        this.transportStatus = uiMessage(UiMessageCode.CONNECTION_RECEIVE_PAUSED_DESCRIPTION);
        this.connectionState = ConnectionState.PAUSED;
        this.connectionTitle = uiMessage(UiMessageCode.CONNECTION_FAILED_TITLE);
        this.connectionDescription = uiMessage(UiMessageCode.CONNECTION_FAILED_DESCRIPTION);
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

  private refreshTransportDiagnostics(): void {
    const diagnostics = this.transport.currentDiagnostics();
    this.transportDiagnostics = uiMessage(UiMessageCode.POC_DIAGNOSTICS, [
      uiParameter(UiMessageParameterName.COUNT, diagnostics.receivedFrames),
      uiParameter(UiMessageParameterName.COUNT, diagnostics.acceptedItems),
      uiParameter(UiMessageParameterName.COUNT, diagnostics.rejectedFrames)
    ]);
  }
}

export const pocConnectionStore: PocConnectionStore = new PocConnectionStore();
