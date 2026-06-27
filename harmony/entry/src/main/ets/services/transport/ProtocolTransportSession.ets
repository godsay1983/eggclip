import { estimateUtf8Bytes } from '../../utils/TextLimits';
import {
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
  PROTOCOL_REJECTED = 'protocolRejected',
  UNEXPECTED_PLAINTEXT = 'unexpectedPlaintext'
}

export interface ProtocolTransportFrameResult {
  ok: boolean;
  envelope?: ParsedEnvelope;
  error?: ProtocolTransportFrameError;
  protocolError?: ProtocolErrorCode;
}

export class ProtocolTransportSession {
  private readonly parser: ProtocolParser = new ProtocolParser();
  private readonly inbound: ProtocolInboundSession;

  constructor(initialState: ProtocolSessionState = ProtocolSessionState.AUTHENTICATED) {
    this.inbound = new ProtocolInboundSession(initialState);
  }

  state(): ProtocolSessionState {
    return this.inbound.state();
  }

  acceptTextFrame(frame: string): ProtocolTransportFrameResult {
    if (estimateUtf8Bytes(frame) > PROTOCOL_MAX_FRAME_BYTES) {
      return { ok: false, error: ProtocolTransportFrameError.FRAME_TOO_LARGE };
    }

    const parsed = this.parser.parseEnvelope(frame);
    if (!parsed.ok || parsed.envelope === undefined) {
      return {
        ok: false,
        error: ProtocolTransportFrameError.PROTOCOL_REJECTED,
        protocolError: parsed.error
      };
    }

    const gate = this.inbound.acceptEnvelope(parsed.envelope);
    if (!gate.ok) {
      return {
        ok: false,
        error: ProtocolTransportFrameError.PROTOCOL_REJECTED,
        protocolError: gate.error
      };
    }

    if (parsed.envelope.kind !== ProtocolEnvelopeKind.ENCRYPTED) {
      return { ok: false, error: ProtocolTransportFrameError.UNEXPECTED_PLAINTEXT };
    }

    return {
      ok: true,
      envelope: parsed.envelope
    };
  }
}
