import { estimateUtf8Bytes } from '../../utils/TextLimits';
import {
  canonicalEncryptedAad,
  JsonObject,
  MessageType,
  ParsedEnvelope,
  ProtocolEnvelopeKind,
  ProtocolErrorCode,
  ProtocolInboundSession,
  ProtocolParser,
  ProtocolSessionState,
  PROTOCOL_MAX_FRAME_BYTES
} from '../../models/ProtocolModels';
import { AesGcmCryptoService } from '../crypto/AesGcmCryptoService';
import { decodeBase64Url, encodeBase64Url } from '../crypto/CryptoVectorService';

const SESSION_KEY_ID_CLIENT_TO_SERVER: string = 'session-v1-client-to-server';
const SESSION_KEY_ID_SERVER_TO_CLIENT: string = 'session-v1-server-to-client';

export enum ProtocolTransportFrameError {
  FRAME_TOO_LARGE = 'frameTooLarge',
  BINARY_UNSUPPORTED = 'binaryUnsupported',
  PROTOCOL_REJECTED = 'protocolRejected',
  UNEXPECTED_PLAINTEXT = 'unexpectedPlaintext',
  REMOTE_ERROR = 'remoteError',
  AAD_MISMATCH = 'aadMismatch',
  DECRYPT_FAILED = 'decryptFailed',
  DECRYPTED_PAYLOAD_INVALID = 'decryptedPayloadInvalid',
  SESSION_KEY_MISSING = 'sessionKeyMissing',
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
  decryptedPayload?: JsonObject;
  error?: ProtocolTransportFrameError;
  protocolError?: ProtocolErrorCode;
  outcome?: ProtocolHandshakeFrameOutcome;
}

export interface ProtocolSessionKeys {
  clientToServerKey: string;
  serverToClientKey: string;
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
  private readonly crypto: AesGcmCryptoService = new AesGcmCryptoService();
  private readonly keys?: ProtocolSessionKeys;
  private closed: boolean = false;

  constructor(
    initialState: ProtocolSessionState = ProtocolSessionState.AUTHENTICATED,
    keys?: ProtocolSessionKeys
  ) {
    this.inbound = new ProtocolInboundSession(initialState);
    this.keys = keys;
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

    if (this.keys !== undefined) {
      const decrypted = this.decryptPayload(parsed.envelope);
      if (!decrypted.ok) {
        return this.failWith(decrypted);
      }
      return decrypted;
    }

    return {
      ok: true,
      envelope: parsed.envelope
    };
  }

  private decryptPayload(envelope: ParsedEnvelope): ProtocolTransportFrameResult {
    if (envelope.ciphertext === undefined) {
      return { ok: false, error: ProtocolTransportFrameError.PROTOCOL_REJECTED };
    }
    const expectedAad = canonicalEncryptedAad(
      envelope.messageType,
      envelope.messageId,
      envelope.sessionCounter,
      envelope.ciphertext.keyId
    );
    if (expectedAad === null || encodeBase64Url(utf8Encode(expectedAad)) !== envelope.ciphertext.aad) {
      return { ok: false, envelope, error: ProtocolTransportFrameError.AAD_MISMATCH };
    }

    const key = this.keyForId(envelope.ciphertext.keyId);
    if (key === null) {
      return { ok: false, envelope, error: ProtocolTransportFrameError.SESSION_KEY_MISSING };
    }

    const decrypted = this.crypto.decryptBase64Url(
      key,
      envelope.ciphertext.nonce,
      envelope.ciphertext.aad,
      envelope.ciphertext.body,
      envelope.ciphertext.tag
    );
    if (!decrypted.ok || decrypted.plaintext === undefined) {
      return { ok: false, envelope, error: ProtocolTransportFrameError.DECRYPT_FAILED };
    }
    const payload = parsePayloadBase64Url(decrypted.plaintext);
    if (payload === null) {
      return { ok: false, envelope, error: ProtocolTransportFrameError.DECRYPTED_PAYLOAD_INVALID };
    }
    return {
      ok: true,
      envelope,
      decryptedPayload: payload
    };
  }

  private keyForId(keyId: string): string | null {
    if (this.keys === undefined) {
      return null;
    }
    if (keyId === SESSION_KEY_ID_CLIENT_TO_SERVER) {
      return this.keys.clientToServerKey;
    }
    if (keyId === SESSION_KEY_ID_SERVER_TO_CLIENT) {
      return this.keys.serverToClientKey;
    }
    return null;
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

function parsePayloadBase64Url(value: string): JsonObject | null {
  const decoded = decodeBase64Url(value);
  if (decoded === null) {
    return null;
  }
  let parsed: JsonObject;
  try {
    parsed = JSON.parse(utf8Decode(decoded)) as JsonObject;
  } catch (_) {
    return null;
  }
  if (parsed === null || Array.isArray(parsed) || typeof parsed !== 'object') {
    return null;
  }
  return parsed;
}

function utf8Encode(value: string): Uint8Array {
  const bytes: number[] = [];
  for (let index = 0; index < value.length; index += 1) {
    const code = value.charCodeAt(index);
    if (code <= 0x7f) {
      bytes.push(code);
    } else if (code <= 0x7ff) {
      bytes.push(0xc0 | (code >> 6));
      bytes.push(0x80 | (code & 0x3f));
    } else {
      bytes.push(0xe0 | (code >> 12));
      bytes.push(0x80 | ((code >> 6) & 0x3f));
      bytes.push(0x80 | (code & 0x3f));
    }
  }
  return new Uint8Array(bytes);
}

function utf8Decode(bytes: Uint8Array): string {
  let value = '';
  for (let index = 0; index < bytes.length;) {
    const first = bytes[index];
    if (first <= 0x7f) {
      value += String.fromCharCode(first);
      index += 1;
    } else if ((first & 0xe0) === 0xc0 && index + 1 < bytes.length) {
      const second = bytes[index + 1];
      value += String.fromCharCode(((first & 0x1f) << 6) | (second & 0x3f));
      index += 2;
    } else if ((first & 0xf0) === 0xe0 && index + 2 < bytes.length) {
      const second = bytes[index + 1];
      const third = bytes[index + 2];
      value += String.fromCharCode(((first & 0x0f) << 12) | ((second & 0x3f) << 6) | (third & 0x3f));
      index += 3;
    } else {
      return '';
    }
  }
  return value;
}
