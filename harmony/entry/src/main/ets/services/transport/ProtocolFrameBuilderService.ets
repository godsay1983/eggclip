import {
  AuthProofPayload,
  AuthRole,
  HelloPayload,
  MessageType,
  ProtocolErrorCode,
  ProtocolParser,
  PROTOCOL_MAX_FRAME_BYTES,
  SignatureAlgorithm,
  PROTOCOL_VERSION
} from '../../models/ProtocolModels';
import { decodeBase64Url } from '../crypto/CryptoVectorService';
import { sha256Utf8Base64Url } from '../crypto/Sha256Service';
import { estimateUtf8Bytes } from '../../utils/TextLimits';

export enum ProtocolFrameBuildError {
  INVALID_MESSAGE_ID = 'invalidMessageId',
  INVALID_COUNTER = 'invalidCounter',
  INVALID_PAYLOAD = 'invalidPayload',
  INVALID_SIGNATURE = 'invalidSignature',
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

interface AuthProofEnvelope {
  version: number;
  type: MessageType;
  messageId: string;
  sessionCounter: number;
  payload: AuthProofPayload;
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

  buildAuthProofFrame(
    role: AuthRole,
    canonicalTranscript: string,
    signature: string,
    messageId: string,
    sessionCounter: number
  ): ProtocolFrameBuildResult {
    if (!isUuid(messageId)) {
      return failed(ProtocolFrameBuildError.INVALID_MESSAGE_ID, 'messageId');
    }
    if (!Number.isSafeInteger(sessionCounter) || sessionCounter < 0) {
      return failed(ProtocolFrameBuildError.INVALID_COUNTER, 'sessionCounter');
    }
    if (role !== AuthRole.CLIENT && role !== AuthRole.SERVER) {
      return failed(ProtocolFrameBuildError.INVALID_PAYLOAD, 'role');
    }
    if (canonicalTranscript.length === 0) {
      return failed(ProtocolFrameBuildError.INVALID_PAYLOAD, 'canonicalTranscript');
    }
    if (!hasBase64UrlLength(signature, 64)) {
      return failed(ProtocolFrameBuildError.INVALID_SIGNATURE, 'signature');
    }

    const payload: AuthProofPayload = {
      role,
      signatureAlgorithm: SignatureAlgorithm.ED25519,
      transcriptHash: sha256Utf8Base64Url(canonicalTranscript),
      signature
    };
    const envelope: AuthProofEnvelope = {
      version: PROTOCOL_VERSION,
      type: MessageType.AUTH_PROOF,
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
    const authProof = this.parser.parseAuthProofPayload(parsed.envelope.payload);
    if (!authProof.ok) {
      return {
        ok: false,
        frame: '',
        error: ProtocolFrameBuildError.INVALID_PAYLOAD,
        protocolError: authProof.error,
        field: authProof.field
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

function hasBase64UrlLength(value: string, expectedBytes: number): boolean {
  const decoded = decodeBase64Url(value);
  return decoded !== null && decoded.length === expectedBytes;
}
