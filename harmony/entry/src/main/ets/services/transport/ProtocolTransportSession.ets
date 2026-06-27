import { estimateUtf8Bytes } from '../../utils/TextLimits';
import {
  MessageType,
  ParsedEnvelope,
  ProtocolEnvelopeKind,
  ProtocolErrorCode,
  ProtocolInboundSession,
  ProtocolParser,
  ProtocolSessionState,
  PROTOCOL_MAX_FRAME_BYTES
} from '../../models/ProtocolModels';

export enum ProtocolTransportFrameError {
  FRAME_TOO_LARGE = 'frameTooLarge',
  BINARY_UNSUPPORTED = 'binaryUnsupported',
  PROTOCOL_REJECTED = 'protocolRejected',
  UNEXPECTED_PLAINTEXT = 'unexpectedPlaintext',
  REMOTE_ERROR = 'remoteError',
  SESSION_CLOSED = 'sessionClosed'
}

export enum ProtocolHandshakeFrameOutcome {
  CONTINUE = 'continue',
  AUTHENTICATED = 'authenticated',
  FAILED = 'failed'
}

export interface ProtocolTransportFrameResult {
  ok: boolean;
  envelope?: ParsedEnvelope;
  error?: ProtocolTransportFrameError;
  protocolError?: ProtocolErrorCode;
  outcome?: ProtocolHandshakeFrameOutcome;
}

export class ProtocolHandshakeTransportSession {
  private readonly parser: ProtocolParser = new ProtocolParser();
  private readonly inbound: ProtocolInboundSession;
  private closed: boolean = false;

  constructor() {
    this.inbound = new ProtocolInboundSession();
    this.inbound.connect();
    this.inbound.startHandshake();
  }

  state(): ProtocolSessionState {
    return this.inbound.state();
  }

  isClosed(): boolean {
    return this.closed;
  }

  close(): void {
    this.fail();
  }

  acceptTextFrame(frame: string): ProtocolTransportFrameResult {
    if (this.closed) {
      return { ok: false, error: ProtocolTransportFrameError.SESSION_CLOSED };
    }
    if (estimateUtf8Bytes(frame) > PROTOCOL_MAX_FRAME_BYTES) {
      return this.failWith({ ok: false, error: ProtocolTransportFrameError.FRAME_TOO_LARGE });
    }

    const parsed = this.parser.parseEnvelope(frame);
    if (!parsed.ok || parsed.envelope === undefined) {
      return this.failWith({
        ok: false,
        error: ProtocolTransportFrameError.PROTOCOL_REJECTED,
        protocolError: parsed.error
      });
    }

    const gate = this.inbound.acceptEnvelope(parsed.envelope);
    if (!gate.ok) {
      return this.failWith({
        ok: false,
        error: ProtocolTransportFrameError.PROTOCOL_REJECTED,
        protocolError: gate.error
      });
    }

    if (parsed.envelope.kind !== ProtocolEnvelopeKind.PRE_AUTH) {
      return this.failWith({ ok: false, error: ProtocolTransportFrameError.UNEXPECTED_PLAINTEXT });
    }

    if (parsed.envelope.messageType === MessageType.AUTH_OK) {
      return { ok: true, envelope: parsed.envelope, outcome: ProtocolHandshakeFrameOutcome.AUTHENTICATED };
    }
    if (parsed.envelope.messageType === MessageType.AUTH_ERROR ||
      parsed.envelope.messageType === MessageType.ERROR) {
      this.fail();
      return { ok: true, envelope: parsed.envelope, outcome: ProtocolHandshakeFrameOutcome.FAILED };
    }
    return { ok: true, envelope: parsed.envelope, outcome: ProtocolHandshakeFrameOutcome.CONTINUE };
  }

  private failWith(result: ProtocolTransportFrameResult): ProtocolTransportFrameResult {
    this.fail();
    return result;
  }

  private fail(): void {
    this.closed = true;
    this.inbound.fail();
  }
}

export class ProtocolTransportSession {
  private readonly parser: ProtocolParser = new ProtocolParser();
  private readonly inbound: ProtocolInboundSession;
  private closed: boolean = false;

  constructor(initialState: ProtocolSessionState = ProtocolSessionState.AUTHENTICATED) {
    this.inbound = new ProtocolInboundSession(initialState);
  }

  state(): ProtocolSessionState {
    return this.inbound.state();
  }

  isClosed(): boolean {
    return this.closed;
  }

  close(): void {
    this.fail();
  }

  acceptTextFrame(frame: string): ProtocolTransportFrameResult {
    if (this.closed) {
      return { ok: false, error: ProtocolTransportFrameError.SESSION_CLOSED };
    }
    if (estimateUtf8Bytes(frame) > PROTOCOL_MAX_FRAME_BYTES) {
      return this.failWith({ ok: false, error: ProtocolTransportFrameError.FRAME_TOO_LARGE });
    }

    const parsed = this.parser.parseEnvelope(frame);
    if (!parsed.ok || parsed.envelope === undefined) {
      return this.failWith({
        ok: false,
        error: ProtocolTransportFrameError.PROTOCOL_REJECTED,
        protocolError: parsed.error
      });
    }

    const gate = this.inbound.acceptEnvelope(parsed.envelope);
    if (!gate.ok) {
      return this.failWith({
        ok: false,
        error: ProtocolTransportFrameError.PROTOCOL_REJECTED,
        protocolError: gate.error
      });
    }

    if (parsed.envelope.kind !== ProtocolEnvelopeKind.ENCRYPTED) {
      return this.failWith({ ok: false, error: ProtocolTransportFrameError.UNEXPECTED_PLAINTEXT });
    }
    if (parsed.envelope.messageType === MessageType.ERROR) {
      return this.failWith({ ok: false, error: ProtocolTransportFrameError.REMOTE_ERROR });
    }

    return {
      ok: true,
      envelope: parsed.envelope
    };
  }

  private failWith(result: ProtocolTransportFrameResult): ProtocolTransportFrameResult {
    this.fail();
    return result;
  }

  private fail(): void {
    this.closed = true;
    this.inbound.fail();
  }
}
