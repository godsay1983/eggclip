import webSocket from '@ohos.net.webSocket';
import { EndpointValidationResult, ManualEndpoint, POC_MAX_FRAME_BYTES, PocLifecycleState } from '../../models/PocModels';
import { PROTOCOL_MAX_FRAME_BYTES, ProtocolSessionState } from '../../models/ProtocolModels';
import { estimateUtf8Bytes, MAX_TEXT_BYTES } from '../../utils/TextLimits';
import {
  ProtocolHandshakeTransportSession,
  ProtocolTransportFrameError,
  ProtocolTransportFrameResult,
  ProtocolTransportSession
} from './ProtocolTransportSession';

const CONNECT_TIMEOUT_MS: number = 8000;

// Transport layers expose stable, non-localized reason codes. Stores decide
// which user-facing message is appropriate without coupling sockets to UI text.
export enum TransportReasonCode {
  INVALID_IPV4 = 'invalidIpv4',
  INVALID_PORT = 'invalidPort',
  POC_TIMEOUT = 'pocTimeout',
  POC_CONNECT_FAILED = 'pocConnectFailed',
  PROTOCOL_TIMEOUT = 'protocolTimeout',
  PROTOCOL_CONNECT_FAILED = 'protocolConnectFailed',
  PAIRING_TIMEOUT = 'pairingTimeout',
  PAIRING_CONNECT_FAILED = 'pairingConnectFailed',
  BINARY_UNSUPPORTED = 'binaryUnsupported',
  FRAME_PROCESSING_FAILED = 'frameProcessingFailed',
  HANDSHAKE_REJECTED = 'handshakeRejected',
  PROTOCOL_REJECTED = 'protocolRejected',
  RECOVERABLE_TRANSPORT_ERROR = 'recoverableTransportError',
  FRAME_TOO_LARGE = 'frameTooLarge',
  MESSAGE_INVALID = 'messageInvalid',
  TEXT_EMPTY = 'textEmpty',
  TEXT_TOO_LARGE = 'textTooLarge',
  JSON_INVALID = 'jsonInvalid'
}

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
  onTextFrame?: (message: string, result: ProtocolTransportFrameResult) => Promise<void> | void;
  protocolSessionProvider?: () => ProtocolTransportSession | null;
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
        reason: TransportReasonCode.INVALID_IPV4
      };
    }
    if (endpoint.port < 1 || endpoint.port > 65535) {
      return {
        ok: false,
        normalizedUrl: '',
        reason: TransportReasonCode.INVALID_PORT
      };
    }
    return {
      ok: true,
      normalizedUrl: `ws://${host}:${endpoint.port}`
    };
  }

  async connect(endpoint: ManualEndpoint, callbacks: PocTransportCallbacks): Promise<EndpointValidationResult> {
    return this.connectInternal(endpoint, {
      timeoutMessage: TransportReasonCode.POC_TIMEOUT,
      connectFailureMessage: TransportReasonCode.POC_CONNECT_FAILED,
      onOpen: callbacks.onOpen,
      onClose: callbacks.onClose,
      onError: callbacks.onError,
      onTextMessage: callbacks.onMessage,
      onBinaryMessage: () => {
        this.recordBinaryRejection(TransportReasonCode.BINARY_UNSUPPORTED);
        callbacks.onError(TransportReasonCode.BINARY_UNSUPPORTED);
      }
    });
  }

  async connectProtocol(
    endpoint: ManualEndpoint,
    session: ProtocolTransportSession,
    callbacks: ProtocolTransportCallbacks
  ): Promise<EndpointValidationResult> {
    return this.connectInternal(endpoint, {
      timeoutMessage: TransportReasonCode.PROTOCOL_TIMEOUT,
      connectFailureMessage: TransportReasonCode.PROTOCOL_CONNECT_FAILED,
      onOpen: callbacks.onOpen,
      onClose: callbacks.onClose,
      onError: callbacks.onError,
      onTextMessage: (message: string) => {
        callbacks.onFrame(this.decodeProtocolFrameMessage(message, session));
      },
      onBinaryMessage: () => {
        session.close();
        this.recordBinaryRejection(TransportReasonCode.BINARY_UNSUPPORTED);
        callbacks.onFrame({
          ok: false,
          error: ProtocolTransportFrameError.BINARY_UNSUPPORTED
        });
        callbacks.onError(TransportReasonCode.BINARY_UNSUPPORTED);
      }
    });
  }

  async connectPairingHandshake(
    endpoint: ManualEndpoint,
    session: ProtocolHandshakeTransportSession,
    callbacks: PairingHandshakeTransportCallbacks
  ): Promise<EndpointValidationResult> {
    let frameProcessing: Promise<void> = Promise.resolve();
    return this.connectInternal(endpoint, {
      timeoutMessage: TransportReasonCode.PAIRING_TIMEOUT,
      connectFailureMessage: TransportReasonCode.PAIRING_CONNECT_FAILED,
      onOpen: callbacks.onOpen,
      onClose: callbacks.onClose,
      onError: callbacks.onError,
      onTextMessage: (message: string) => {
        frameProcessing = frameProcessing
          .then(async () => {
            const protocolSession = session.state() === ProtocolSessionState.AUTHENTICATED &&
              callbacks.protocolSessionProvider !== undefined ? callbacks.protocolSessionProvider() : null;
            const result = protocolSession === null ?
              this.decodeHandshakeFrameMessage(message, session) :
              this.decodeProtocolFrameMessage(message, protocolSession);
            callbacks.onFrame(result);
            if (callbacks.onTextFrame !== undefined) {
              await callbacks.onTextFrame(message, result);
            }
          })
          .catch(() => {
            callbacks.onError(TransportReasonCode.FRAME_PROCESSING_FAILED);
          });
      },
      onBinaryMessage: () => {
        session.close();
        this.recordBinaryRejection(TransportReasonCode.BINARY_UNSUPPORTED);
        callbacks.onFrame({
          ok: false,
          error: ProtocolTransportFrameError.BINARY_UNSUPPORTED
        });
        callbacks.onError(TransportReasonCode.BINARY_UNSUPPORTED);
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
    const reason = result.protocolError ?? result.error ?? ProtocolTransportFrameError.PROTOCOL_REJECTED;
    this.diagnostics.lastRejection = `${TransportReasonCode.HANDSHAKE_REJECTED}:${reason}`;
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
    const reason = result.protocolError ?? result.error ?? ProtocolTransportFrameError.PROTOCOL_REJECTED;
    this.diagnostics.lastRejection = `${TransportReasonCode.PROTOCOL_REJECTED}:${reason}`;
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
      if (this.socket === socket && this.state === PocLifecycleState.STARTING) {
        this.state = PocLifecycleState.FAILED;
        this.connected = false;
        callbacks.onError(callbacks.timeoutMessage);
        this.close();
      }
    }, CONNECT_TIMEOUT_MS);

    socket.on('open', () => {
      if (this.socket !== socket) return;
      this.clearConnectTimeout();
      this.state = PocLifecycleState.RUNNING;
      this.connected = true;
      callbacks.onOpen();
    });
    socket.on('message', (_error, data: string | ArrayBuffer) => {
      if (this.socket !== socket) return;
      if (typeof data === 'string') {
        callbacks.onTextMessage(data);
      } else {
        callbacks.onBinaryMessage(data);
      }
    });
    socket.on('close', (_error, closeResult: webSocket.CloseResult) => {
      if (this.socket !== socket) return;
      this.clearConnectTimeout();
      this.state = PocLifecycleState.IDLE;
      this.connected = false;
      callbacks.onClose(`${closeResult.code}: ${closeResult.reason}`);
    });
    socket.on('error', () => {
      if (this.socket !== socket) return;
      // HarmonyOS may emit a recoverable error without closing the WebSocket.
      // The connect result/timeout handles startup failures, and `close` is the
      // authoritative signal after open. Do not turn a live session into a
      // false UI failure from this advisory event alone.
      this.diagnostics.lastRejection = TransportReasonCode.RECOVERABLE_TRANSPORT_ERROR;
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
      return this.rejectedMessage(TransportReasonCode.FRAME_TOO_LARGE);
    }
    try {
      const parsed = JSON.parse(message) as PocClipboardTextMessage;
      if (parsed.kind !== 'clipboardText' || typeof parsed.text !== 'string') {
        return this.rejectedMessage(TransportReasonCode.MESSAGE_INVALID);
      }
      const byteLength = estimateUtf8Bytes(parsed.text);
      if (byteLength === 0) {
        return this.rejectedMessage(TransportReasonCode.TEXT_EMPTY);
      }
      if (byteLength > MAX_TEXT_BYTES) {
        return this.rejectedMessage(TransportReasonCode.TEXT_TOO_LARGE);
      }
      this.diagnostics.acceptedItems += 1;
      return {
        ok: true,
        text: parsed.text,
        byteLength,
        reason: ''
      };
    } catch (_) {
      return this.rejectedMessage(TransportReasonCode.JSON_INVALID);
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
