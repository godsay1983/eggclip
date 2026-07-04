import {
  HelloPayload,
  MessageType,
  ProtocolErrorCode,
  ProtocolParser,
  PROTOCOL_MAX_FRAME_BYTES,
  PROTOCOL_VERSION
} from '../../models/ProtocolModels';
import { estimateUtf8Bytes } from '../../utils/TextLimits';

export enum ProtocolFrameBuildError {
  INVALID_MESSAGE_ID = 'invalidMessageId',
  INVALID_COUNTER = 'invalidCounter',
  INVALID_PAYLOAD = 'invalidPayload',
  FRAME_TOO_LARGE = 'frameTooLarge',
  SERIALIZE_FAILED = 'serializeFailed'
}

export interface ProtocolFrameBuildResult {
  ok: boolean;
  frame: string;
  error?: ProtocolFrameBuildError;
  protocolError?: ProtocolErrorCode;
  field?: string;
}

interface ClientHelloEnvelope {
  version: number;
  type: MessageType;
  messageId: string;
  sessionCounter: number;
  payload: HelloPayload;
}

export class ProtocolFrameBuilderService {
  private readonly parser: ProtocolParser = new ProtocolParser();

  buildClientHelloFrame(
    payload: HelloPayload,
    messageId: string,
    sessionCounter: number = 0
  ): ProtocolFrameBuildResult {
    if (!isUuid(messageId)) {
      return failed(ProtocolFrameBuildError.INVALID_MESSAGE_ID, 'messageId');
    }
    if (!Number.isSafeInteger(sessionCounter) || sessionCounter < 0) {
      return failed(ProtocolFrameBuildError.INVALID_COUNTER, 'sessionCounter');
    }

    const envelope: ClientHelloEnvelope = {
      version: PROTOCOL_VERSION,
      type: MessageType.CLIENT_HELLO,
      messageId,
      sessionCounter,
      payload
    };

    let frame = '';
    try {
      frame = JSON.stringify(envelope);
    } catch (_) {
      return failed(ProtocolFrameBuildError.SERIALIZE_FAILED, 'envelope');
    }
    if (estimateUtf8Bytes(frame) > PROTOCOL_MAX_FRAME_BYTES) {
      return failed(ProtocolFrameBuildError.FRAME_TOO_LARGE, 'frame');
    }

    const parsed = this.parser.parseEnvelope(frame);
    if (!parsed.ok || parsed.envelope === undefined) {
      return {
        ok: false,
        frame: '',
        error: ProtocolFrameBuildError.INVALID_PAYLOAD,
        protocolError: parsed.error,
        field: parsed.field
      };
    }
    const hello = this.parser.parseHelloPayload(parsed.envelope.payload);
    if (!hello.ok) {
      return {
        ok: false,
        frame: '',
        error: ProtocolFrameBuildError.INVALID_PAYLOAD,
        protocolError: hello.error,
        field: hello.field
      };
    }

    return {
      ok: true,
      frame
    };
  }
}

function failed(error: ProtocolFrameBuildError, field: string): ProtocolFrameBuildResult {
  return {
    ok: false,
    frame: '',
    error,
    field
  };
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}
