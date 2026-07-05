import webSocket from '@ohos.net.webSocket';
import { EndpointValidationResult, ManualEndpoint, POC_MAX_FRAME_BYTES, PocLifecycleState } from '../../models/PocModels';
import { PROTOCOL_MAX_FRAME_BYTES } from '../../models/ProtocolModels';
import { estimateUtf8Bytes, MAX_TEXT_BYTES } from '../../utils/TextLimits';
import {
  ProtocolHandshakeTransportSession,
  ProtocolTransportFrameError,
  ProtocolTransportFrameResult,
  ProtocolTransportSession
} from './ProtocolTransportSession';

const CONNECT_TIMEOUT_MS: number = 8000;

export interface PocTransportCallbacks {
  onOpen: () => void;
  onClose: (reason: string) => void;
  onError: (reason: string) => void;
  onMessage: (message: string) => void;
}

export interface ProtocolTransportCallbacks {
  onOpen: () => void;
  onClose: (reason: string) => void;
  onError: (reason: string) => void;
  onFrame: (result: ProtocolTransportFrameResult) => void;
}

export interface PairingHandshakeTransportCallbacks {
  onOpen: () => void;
  onClose: (reason: string) => void;
  onError: (reason: string) => void;
  onFrame: (result: ProtocolTransportFrameResult) => void;
  onTextFrame?: (message: string, result: ProtocolTransportFrameResult) => void;
}

export interface PocClipboardTextMessage {
  kind: string;
  text: string;
}

export interface PocClipboardTextDecodeResult {
  ok: boolean;
  text: string;
  byteLength: number;
  reason: string;
}

export interface PocTransportDiagnostics {
  receivedFrames: number;
  acceptedItems: number;
  rejectedFrames: number;
  lastRejection: string;
}

export class WebSocketTransportService {
  private state: PocLifecycleState = PocLifecycleState.IDLE;
  private socket: webSocket.WebSocket | null = null;
  private connected: boolean = false;
  private connectTimeoutId: number = -1;
  private diagnostics: PocTransportDiagnostics = {
    receivedFrames: 0,
    acceptedItems: 0,
    rejectedFrames: 0,
    lastRejection: ''
  };

  currentState(): PocLifecycleState {
    return this.state;
  }

  isConnected(): boolean {
    return this.connected;
  }

  currentDiagnostics(): PocTransportDiagnostics {
    return {
      receivedFrames: this.diagnostics.receivedFrames,
      acceptedItems: this.diagnostics.acceptedItems,
      rejectedFrames: this.diagnostics.rejectedFrames,
      lastRejection: this.diagnostics.lastRejection
    };
  }

  resetDiagnostics(): void {
    this.diagnostics = {
      receivedFrames: 0,
      acceptedItems: 0,
      rejectedFrames: 0,
      lastRejection: ''
    };
  }

  validateEndpoint(endpoint: ManualEndpoint): EndpointValidationResult {
    const host = this.normalizeIpv4Address(endpoint.host);
    if (host === null) {
      return {
        ok: false,
        normalizedUrl: '',
        reason: '请输入有效的 IPv4 地址，例如 192.168.1.10'
      };
    }
    if (endpoint.port < 1 || endpoint.port > 65535) {
      return {
        ok: false,
        normalizedUrl: '',
        reason: '请输入 1 到 65535 之间的端口'
      };
    }
    return {
      ok: true,
      normalizedUrl: `ws://${host}:${endpoint.port}`
    };
  }

  async connect(endpoint: ManualEndpoint, callbacks: PocTransportCallbacks): Promise<EndpointValidationResult> {
    return this.connectInternal(endpoint, {
      timeoutMessage: '连接桌面 POC 超时',
      connectFailureMessage: '连接桌面 POC 失败',
      onOpen: callbacks.onOpen,
      onClose: callbacks.onClose,
      onError: callbacks.onError,
      onTextMessage: callbacks.onMessage,
      onBinaryMessage: () => {
        this.recordBinaryRejection('POC 不支持二进制消息');
        callbacks.onError('POC 不支持二进制消息');
      }
    });
  }

  async connectProtocol(
    endpoint: ManualEndpoint,
    session: ProtocolTransportSession,
    callbacks: ProtocolTransportCallbacks
  ): Promise<EndpointValidationResult> {
    return this.connectInternal(endpoint, {
      timeoutMessage: '连接桌面正式协议超时',
      connectFailureMessage: '连接桌面正式协议失败',
      onOpen: callbacks.onOpen,
      onClose: callbacks.onClose,
      onError: callbacks.onError,
      onTextMessage: (message: string) => {
        callbacks.onFrame(this.decodeProtocolFrameMessage(message, session));
      },
      onBinaryMessage: () => {
        session.close();
        this.recordBinaryRejection('正式协议不支持二进制 WebSocket 消息');
        callbacks.onFrame({
          ok: false,
          error: ProtocolTransportFrameError.BINARY_UNSUPPORTED
        });
        callbacks.onError('正式协议不支持二进制 WebSocket 消息');
      }
    });
  }

  async connectPairingHandshake(
    endpoint: ManualEndpoint,
    session: ProtocolHandshakeTransportSession,
    callbacks: PairingHandshakeTransportCallbacks
  ): Promise<EndpointValidationResult> {
    return this.connectInternal(endpoint, {
      timeoutMessage: '连接桌面配对握手超时',
      connectFailureMessage: '连接桌面配对握手失败',
      onOpen: callbacks.onOpen,
      onClose: callbacks.onClose,
      onError: callbacks.onError,
      onTextMessage: (message: string) => {
        const result = this.decodeHandshakeFrameMessage(message, session);
        callbacks.onFrame(result);
        if (callbacks.onTextFrame !== undefined) {
          callbacks.onTextFrame(message, result);
        }
      },
      onBinaryMessage: () => {
        session.close();
        this.recordBinaryRejection('配对握手不支持二进制 WebSocket 消息');
        callbacks.onFrame({
          ok: false,
          error: ProtocolTransportFrameError.BINARY_UNSUPPORTED
        });
        callbacks.onError('配对握手不支持二进制 WebSocket 消息');
      }
    });
  }

  decodeHandshakeFrameMessage(
    message: string,
    session: ProtocolHandshakeTransportSession
  ): ProtocolTransportFrameResult {
    this.diagnostics.receivedFrames += 1;
    const result = session.acceptTextFrame(message);
    if (result.ok) {
      this.diagnostics.acceptedItems += 1;
      return result;
    }

    this.diagnostics.rejectedFrames += 1;
    this.diagnostics.lastRejection = result.protocolError !== undefined ?
      `配对握手拒绝：${result.protocolError}` :
      `配对握手拒绝：${result.error ?? ProtocolTransportFrameError.PROTOCOL_REJECTED}`;
    return result;
  }

  decodeProtocolFrameMessage(
    message: string,
    session: ProtocolTransportSession
  ): ProtocolTransportFrameResult {
    this.diagnostics.receivedFrames += 1;
    const result = session.acceptTextFrame(message);
    if (result.ok) {
      this.diagnostics.acceptedItems += 1;
      return result;
    }

    this.diagnostics.rejectedFrames += 1;
    this.diagnostics.lastRejection = result.protocolError !== undefined ?
      `正式协议拒绝：${result.protocolError}` :
      `正式协议拒绝：${result.error ?? ProtocolTransportFrameError.PROTOCOL_REJECTED}`;
    return result;
  }

  private async connectInternal(endpoint: ManualEndpoint, callbacks: InternalTransportCallbacks): Promise<EndpointValidationResult> {
    const result = this.validateEndpoint(endpoint);
    if (!result.ok) {
      this.state = PocLifecycleState.FAILED;
      return result;
    }

    this.close();
    this.resetDiagnostics();
    this.state = PocLifecycleState.STARTING;
    this.connected = false;
    const socket = webSocket.createWebSocket();
    this.socket = socket;
    this.connectTimeoutId = setTimeout(() => {
      if (this.state === PocLifecycleState.STARTING) {
        this.state = PocLifecycleState.FAILED;
        this.connected = false;
        callbacks.onError(callbacks.timeoutMessage);
        this.close();
      }
    }, CONNECT_TIMEOUT_MS);

    socket.on('open', () => {
      this.clearConnectTimeout();
      this.state = PocLifecycleState.RUNNING;
      this.connected = true;
      callbacks.onOpen();
    });
    socket.on('message', (_error, data: string | ArrayBuffer) => {
      if (typeof data === 'string') {
        callbacks.onTextMessage(data);
      } else {
        callbacks.onBinaryMessage(data);
      }
    });
    socket.on('close', (_error, closeResult: webSocket.CloseResult) => {
      this.clearConnectTimeout();
      this.state = PocLifecycleState.IDLE;
      this.connected = false;
      callbacks.onClose(`${closeResult.code}: ${closeResult.reason}`);
    });
    socket.on('error', (error) => {
      this.clearConnectTimeout();
      this.state = PocLifecycleState.FAILED;
      this.connected = false;
      callbacks.onError(`WebSocket 错误：${error.message}`);
    });

    try {
      await socket.connect(result.normalizedUrl, {
        proxy: 'no-proxy',
        pingInterval: 30,
        pongTimeout: 10
      });
    } catch (_) {
      this.clearConnectTimeout();
      this.state = PocLifecycleState.FAILED;
      this.connected = false;
      return {
        ok: false,
        normalizedUrl: result.normalizedUrl,
        reason: callbacks.connectFailureMessage
      };
    }
    return result;
  }

  async sendClipboardText(text: string): Promise<boolean> {
    if (this.socket === null || !this.connected) {
      return false;
    }
    const message = this.encodeClipboardTextMessage(text);
    if (message === null) {
      return false;
    }
    try {
      return await this.socket.send(message);
    } catch (_) {
      this.state = PocLifecycleState.FAILED;
      this.connected = false;
      return false;
    }
  }

  async sendTextFrame(frame: string): Promise<boolean> {
    if (this.socket === null || !this.connected || estimateUtf8Bytes(frame) > PROTOCOL_MAX_FRAME_BYTES) {
      return false;
    }
    try {
      return await this.socket.send(frame);
    } catch (_) {
      this.state = PocLifecycleState.FAILED;
      this.connected = false;
      return false;
    }
  }

  parseClipboardTextMessage(message: string): string | null {
    const result = this.decodeClipboardTextMessage(message);
    return result.ok ? result.text : null;
  }

  decodeClipboardTextMessage(message: string): PocClipboardTextDecodeResult {
    this.diagnostics.receivedFrames += 1;
    if (estimateUtf8Bytes(message) > POC_MAX_FRAME_BYTES) {
      return this.rejectedMessage('POC 消息超过 1 MiB 帧上限');
    }
    try {
      const parsed = JSON.parse(message) as PocClipboardTextMessage;
      if (parsed.kind !== 'clipboardText' || typeof parsed.text !== 'string') {
        return this.rejectedMessage('POC 消息类型或字段无效');
      }
      const byteLength = estimateUtf8Bytes(parsed.text);
      if (byteLength === 0) {
        return this.rejectedMessage('POC 文本为空');
      }
      if (byteLength > MAX_TEXT_BYTES) {
        return this.rejectedMessage('POC 文本超过 256 KiB 上限');
      }
      this.diagnostics.acceptedItems += 1;
      return {
        ok: true,
        text: parsed.text,
        byteLength,
        reason: ''
      };
    } catch (_) {
      return this.rejectedMessage('POC 消息不是有效 JSON');
    }
  }

  encodeClipboardTextMessage(text: string): string | null {
    const byteLength = estimateUtf8Bytes(text);
    if (byteLength === 0 || byteLength > MAX_TEXT_BYTES) {
      return null;
    }
    const message: PocClipboardTextMessage = {
      kind: 'clipboardText',
      text
    };
    const serialized = JSON.stringify(message);
    return estimateUtf8Bytes(serialized) <= POC_MAX_FRAME_BYTES ? serialized : null;
  }

  close(): void {
    this.clearConnectTimeout();
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

  private clearConnectTimeout(): void {
    if (this.connectTimeoutId >= 0) {
      clearTimeout(this.connectTimeoutId);
      this.connectTimeoutId = -1;
    }
  }

  private normalizeIpv4Address(value: string): string | null {
    const host = value.trim();
    const parts = host.split('.');
    if (parts.length !== 4) {
      return null;
    }
    const octets: number[] = [];
    for (let index = 0; index < parts.length; index += 1) {
      const part = parts[index];
      if (!/^\d{1,3}$/.test(part) || (part.length > 1 && part.startsWith('0'))) {
        return null;
      }
      const octet = Number(part);
      if (octet < 0 || octet > 255) {
        return null;
      }
      octets.push(octet);
    }
    if (octets[0] === 0 || octets[0] >= 224 || octets.every((octet: number) => octet === 255)) {
      return null;
    }
    return octets.join('.');
  }

  private rejectedMessage(reason: string): PocClipboardTextDecodeResult {
    this.diagnostics.rejectedFrames += 1;
    this.diagnostics.lastRejection = reason;
    return {
      ok: false,
      text: '',
      byteLength: 0,
      reason
    };
  }

  private recordBinaryRejection(reason: string): void {
    this.diagnostics.receivedFrames += 1;
    this.diagnostics.rejectedFrames += 1;
    this.diagnostics.lastRejection = reason;
  }
}

interface InternalTransportCallbacks {
  timeoutMessage: string;
  connectFailureMessage: string;
  onOpen: () => void;
  onClose: (reason: string) => void;
  onError: (reason: string) => void;
  onTextMessage: (message: string) => void;
  onBinaryMessage: (data: ArrayBuffer) => void;
}
