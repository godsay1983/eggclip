import webSocket from '@ohos.net.webSocket';
import { EndpointValidationResult, ManualEndpoint, PocLifecycleState } from '../../models/PocModels';

export interface PocTransportCallbacks {
  onOpen: () => void;
  onClose: (reason: string) => void;
  onError: (reason: string) => void;
  onMessage: (message: string) => void;
}

interface PocClipboardTextMessage {
  kind: string;
  text: string;
}

export class WebSocketTransportService {
  private state: PocLifecycleState = PocLifecycleState.IDLE;
  private socket: webSocket.WebSocket | null = null;
  private connected: boolean = false;

  currentState(): PocLifecycleState {
    return this.state;
  }

  isConnected(): boolean {
    return this.connected;
  }

  validateEndpoint(endpoint: ManualEndpoint): EndpointValidationResult {
    const host = endpoint.host.trim();
    if (host.length === 0) {
      return {
        ok: false,
        normalizedUrl: '',
        reason: 'host is required'
      };
    }
    if (endpoint.port < 1 || endpoint.port > 65535) {
      return {
        ok: false,
        normalizedUrl: '',
        reason: 'port is out of range'
      };
    }
    return {
      ok: true,
      normalizedUrl: `ws://${host}:${endpoint.port}`
    };
  }

  async connect(endpoint: ManualEndpoint, callbacks: PocTransportCallbacks): Promise<EndpointValidationResult> {
    const result = this.validateEndpoint(endpoint);
    if (!result.ok) {
      this.state = PocLifecycleState.FAILED;
      return result;
    }

    this.close();
    this.state = PocLifecycleState.STARTING;
    this.connected = false;
    const socket = webSocket.createWebSocket();
    this.socket = socket;

    socket.on('open', () => {
      this.state = PocLifecycleState.RUNNING;
      this.connected = true;
      callbacks.onOpen();
    });
    socket.on('message', (_error, data: string | ArrayBuffer) => {
      if (typeof data === 'string') {
        callbacks.onMessage(data);
      }
    });
    socket.on('close', (_error, closeResult: webSocket.CloseResult) => {
      this.state = PocLifecycleState.IDLE;
      this.connected = false;
      callbacks.onClose(`${closeResult.code}: ${closeResult.reason}`);
    });
    socket.on('error', (error) => {
      this.state = PocLifecycleState.FAILED;
      this.connected = false;
      callbacks.onError(error.message);
    });

    try {
      await socket.connect(result.normalizedUrl, {
        proxy: 'no-proxy',
        pingInterval: 30,
        pongTimeout: 10
      });
    } catch (_) {
      this.state = PocLifecycleState.FAILED;
      this.connected = false;
      return {
        ok: false,
        normalizedUrl: result.normalizedUrl,
        reason: 'connect failed'
      };
    }
    return result;
  }

  async sendClipboardText(text: string): Promise<boolean> {
    if (this.socket === null || !this.connected) {
      return false;
    }
    const message: PocClipboardTextMessage = {
      kind: 'clipboardText',
      text
    };
    try {
      return await this.socket.send(JSON.stringify(message));
    } catch (_) {
      this.state = PocLifecycleState.FAILED;
      this.connected = false;
      return false;
    }
  }

  close(): void {
    if (this.socket !== null) {
      this.socket.off('open');
      this.socket.off('message');
      this.socket.off('close');
      this.socket.off('error');
      this.socket.close().catch(() => {
      });
      this.socket = null;
    }
    this.connected = false;
    this.state = PocLifecycleState.IDLE;
  }
}
