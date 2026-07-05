import {
  AuthRole,
  HelloPayload,
  MessageType,
  ProtocolParser,
  ProtocolSessionState
} from '../../models/ProtocolModels';
import {
  ProtocolFrameBuildError,
  ProtocolFrameBuilderService
} from '../transport/ProtocolFrameBuilderService';
import {
  ProtocolHandshakeFrameOutcome,
  ProtocolHandshakeTransportSession,
  ProtocolSessionKeys,
  ProtocolTransportFrameError
} from '../transport/ProtocolTransportSession';
import {
  ProtocolTransportSession
} from '../transport/ProtocolTransportSession';
import {
  Ed25519SignatureError,
  Ed25519SignatureService
} from '../crypto/Ed25519SignatureService';
import {
  SessionKeyDerivationError,
  SessionKeyDerivationService
} from '../crypto/SessionKeyDerivationService';
import {
  X25519KeyAgreementError,
  X25519KeyAgreementService
} from '../crypto/X25519KeyAgreementService';
import {
  PairingAuthTranscriptDraft,
  PairingHandshakeDraft,
  PairingHandshakeDraftError,
  PairingHandshakeDraftService
} from './PairingHandshakeDraftService';

export enum PairingClientHandshakeError {
  CLIENT_HELLO_BUILD_FAILED = 'clientHelloBuildFailed',
  SERVER_FRAME_REJECTED = 'serverFrameRejected',
  UNEXPECTED_SERVER_MESSAGE = 'unexpectedServerMessage',
  INVALID_SERVER_HELLO = 'invalidServerHello',
  SERVER_HELLO_MISMATCH = 'serverHelloMismatch',
  AUTH_PROOF_SIGN_FAILED = 'authProofSignFailed',
  AUTH_PROOF_BUILD_FAILED = 'authProofBuildFailed',
  AUTH_PROOF_NOT_SENT = 'authProofNotSent',
  AUTH_OK_REJECTED = 'authOkRejected',
  SHARED_SECRET_DERIVATION_FAILED = 'sharedSecretDerivationFailed',
  SESSION_KEY_DERIVATION_FAILED = 'sessionKeyDerivationFailed'
}

export interface PairingClientHandshakeStartResult {
  ok: boolean;
  session?: PairingClientHandshakeSession;
  clientHelloFrame?: string;
  error?: PairingClientHandshakeError;
  frameError?: ProtocolFrameBuildError;
  field?: string;
}

export interface PairingClientAuthProofResult {
  ok: boolean;
  authProofFrame?: string;
  serverHello?: HelloPayload;
  transcript?: PairingAuthTranscriptDraft;
  error?: PairingClientHandshakeError;
  transportError?: ProtocolTransportFrameError;
  handshakeError?: PairingHandshakeDraftError;
  signatureError?: Ed25519SignatureError;
  frameError?: ProtocolFrameBuildError;
  field?: string;
}

export interface PairingClientAuthenticatedSessionResult {
  ok: boolean;
  transportSession?: ProtocolTransportSession;
  sessionKeys?: ProtocolSessionKeys;
  error?: PairingClientHandshakeError;
  transportError?: ProtocolTransportFrameError;
  keyAgreementError?: X25519KeyAgreementError;
  derivationError?: SessionKeyDerivationError;
  field?: string;
}

export class PairingClientHandshakeSession {
  readonly draft: PairingHandshakeDraft;
  private readonly transportSession: ProtocolHandshakeTransportSession;
  private readonly localEphemeralPrivateKeyValue: string | null;
  private authProofSent: boolean = false;
  private serverHelloPayloadValue: HelloPayload | null = null;

  constructor(draft: PairingHandshakeDraft, localEphemeralPrivateKey?: string) {
    this.draft = draft;
    this.transportSession = new ProtocolHandshakeTransportSession();
    this.localEphemeralPrivateKeyValue = localEphemeralPrivateKey ?? null;
  }

  acceptServerFrame(frame: string) {
    return this.transportSession.acceptTextFrame(frame);
  }

  markAuthProofSent(): void {
    this.authProofSent = true;
  }

  rememberServerHello(serverHello: HelloPayload): void {
    this.serverHelloPayloadValue = cloneHelloPayload(serverHello);
  }

  hasSentAuthProof(): boolean {
    return this.authProofSent;
  }

  localEphemeralPrivateKey(): string | null {
    return this.localEphemeralPrivateKeyValue;
  }

  serverHelloPayload(): HelloPayload | null {
    if (this.serverHelloPayloadValue === null) {
      return null;
    }
    return cloneHelloPayload(this.serverHelloPayloadValue);
  }
}

export class PairingClientHandshakeSessionService {
  private readonly parser: ProtocolParser = new ProtocolParser();
  private readonly frameBuilder: ProtocolFrameBuilderService = new ProtocolFrameBuilderService();
  private readonly draftService: PairingHandshakeDraftService = new PairingHandshakeDraftService();
  private readonly signatureService: Ed25519SignatureService = new Ed25519SignatureService();
  private readonly keyDerivation: SessionKeyDerivationService = new SessionKeyDerivationService();
  private readonly keyAgreement: X25519KeyAgreementService = new X25519KeyAgreementService();

  start(
    draft: PairingHandshakeDraft,
    clientHelloMessageId: string,
    clientHelloCounter: number = 0,
    localEphemeralPrivateKey?: string
  ): PairingClientHandshakeStartResult {
    const clientHello = this.frameBuilder.buildClientHelloFrame(
      draft.clientHelloPayload,
      clientHelloMessageId,
      clientHelloCounter
    );
    if (!clientHello.ok) {
      return {
        ok: false,
        error: PairingClientHandshakeError.CLIENT_HELLO_BUILD_FAILED,
        frameError: clientHello.error,
        field: clientHello.field
      };
    }
    return {
      ok: true,
      session: new PairingClientHandshakeSession(draft, localEphemeralPrivateKey),
      clientHelloFrame: clientHello.frame
    };
  }

  acceptServerHelloAndSignAuthProof(
    session: PairingClientHandshakeSession,
    serverHelloFrame: string,
    localIdentityPrivateSeed: string,
    authProofMessageId: string,
    authProofCounter: number = 2
  ): PairingClientAuthProofResult {
    const accepted = session.acceptServerFrame(serverHelloFrame);
    if (!accepted.ok || accepted.envelope === undefined) {
      return {
        ok: false,
        error: PairingClientHandshakeError.SERVER_FRAME_REJECTED,
        transportError: accepted.error
      };
    }
    if (accepted.outcome !== ProtocolHandshakeFrameOutcome.CONTINUE ||
      accepted.envelope.messageType !== MessageType.SERVER_HELLO) {
      return {
        ok: false,
        error: PairingClientHandshakeError.UNEXPECTED_SERVER_MESSAGE
      };
    }

    const serverHello = this.parser.parseHelloPayload(accepted.envelope.payload);
    if (!serverHello.ok || serverHello.payload === undefined) {
      return {
        ok: false,
        error: PairingClientHandshakeError.INVALID_SERVER_HELLO,
        field: serverHello.field
      };
    }

    const transcript = this.draftService.buildClientAuthTranscriptDraft(session.draft, serverHello.payload);
    if (!transcript.ok || transcript.transcript === undefined) {
      return {
        ok: false,
        error: PairingClientHandshakeError.SERVER_HELLO_MISMATCH,
        handshakeError: transcript.error,
        field: transcript.field
      };
    }

    const signature = this.signatureService.signMessage(
      localIdentityPrivateSeed,
      transcript.transcript.canonicalTranscript
    );
    if (!signature.ok || signature.signature === undefined) {
      return {
        ok: false,
        error: PairingClientHandshakeError.AUTH_PROOF_SIGN_FAILED,
        signatureError: signature.error,
        field: signature.field
      };
    }

    const authProof = this.frameBuilder.buildAuthProofFrame(
      AuthRole.CLIENT,
      transcript.transcript.canonicalTranscript,
      signature.signature,
      authProofMessageId,
      authProofCounter
    );
    if (!authProof.ok) {
      return {
        ok: false,
        error: PairingClientHandshakeError.AUTH_PROOF_BUILD_FAILED,
        frameError: authProof.error,
        field: authProof.field
      };
    }
    session.rememberServerHello(serverHello.payload);
    session.markAuthProofSent();

    return {
      ok: true,
      authProofFrame: authProof.frame,
      serverHello: serverHello.payload,
      transcript: transcript.transcript
    };
  }

  acceptServerHelloAndBuildAuthProof(
    session: PairingClientHandshakeSession,
    serverHelloFrame: string,
    signature: string,
    authProofMessageId: string,
    authProofCounter: number = 2
  ): PairingClientAuthProofResult {
    const accepted = session.acceptServerFrame(serverHelloFrame);
    if (!accepted.ok || accepted.envelope === undefined) {
      return {
        ok: false,
        error: PairingClientHandshakeError.SERVER_FRAME_REJECTED,
        transportError: accepted.error
      };
    }
    if (accepted.outcome !== ProtocolHandshakeFrameOutcome.CONTINUE ||
      accepted.envelope.messageType !== MessageType.SERVER_HELLO) {
      return {
        ok: false,
        error: PairingClientHandshakeError.UNEXPECTED_SERVER_MESSAGE
      };
    }

    const serverHello = this.parser.parseHelloPayload(accepted.envelope.payload);
    if (!serverHello.ok || serverHello.payload === undefined) {
      return {
        ok: false,
        error: PairingClientHandshakeError.INVALID_SERVER_HELLO,
        field: serverHello.field
      };
    }

    const transcript = this.draftService.buildClientAuthTranscriptDraft(session.draft, serverHello.payload);
    if (!transcript.ok || transcript.transcript === undefined) {
      return {
        ok: false,
        error: PairingClientHandshakeError.SERVER_HELLO_MISMATCH,
        handshakeError: transcript.error,
        field: transcript.field
      };
    }

    const authProof = this.frameBuilder.buildAuthProofFrame(
      AuthRole.CLIENT,
      transcript.transcript.canonicalTranscript,
      signature,
      authProofMessageId,
      authProofCounter
    );
    if (!authProof.ok) {
      return {
        ok: false,
        error: PairingClientHandshakeError.AUTH_PROOF_BUILD_FAILED,
        frameError: authProof.error,
        field: authProof.field
      };
    }
    session.rememberServerHello(serverHello.payload);
    session.markAuthProofSent();

    return {
      ok: true,
      authProofFrame: authProof.frame,
      serverHello: serverHello.payload,
      transcript: transcript.transcript
    };
  }

  acceptAuthOkAndCreateTransportSession(
    session: PairingClientHandshakeSession,
    authOkFrame: string,
    sharedSecretBase64Url: string,
    transcriptSaltBase64Url: string
  ): PairingClientAuthenticatedSessionResult {
    if (!session.hasSentAuthProof()) {
      return {
        ok: false,
        error: PairingClientHandshakeError.AUTH_PROOF_NOT_SENT
      };
    }

    const accepted = session.acceptServerFrame(authOkFrame);
    if (!accepted.ok || accepted.envelope === undefined ||
      accepted.outcome !== ProtocolHandshakeFrameOutcome.AUTHENTICATED ||
      accepted.envelope.messageType !== MessageType.AUTH_OK) {
      return {
        ok: false,
        error: PairingClientHandshakeError.AUTH_OK_REJECTED,
        transportError: accepted.error
      };
    }

    const derived = this.keyDerivation.deriveSessionKeys(sharedSecretBase64Url, transcriptSaltBase64Url);
    if (!derived.ok || derived.keys === undefined) {
      return {
        ok: false,
        error: PairingClientHandshakeError.SESSION_KEY_DERIVATION_FAILED,
        derivationError: derived.error,
        field: derived.field
      };
    }

    const sessionKeys: ProtocolSessionKeys = {
      clientToServerKey: derived.keys.clientToServerKey,
      serverToClientKey: derived.keys.serverToClientKey
    };
    return {
      ok: true,
      sessionKeys,
      transportSession: new ProtocolTransportSession(ProtocolSessionState.AUTHENTICATED, sessionKeys)
    };
  }

  acceptAuthOkAndCreateTransportSessionFromEphemeral(
    session: PairingClientHandshakeSession,
    authOkFrame: string,
    transcriptSaltBase64Url: string
  ): PairingClientAuthenticatedSessionResult {
    if (!session.hasSentAuthProof()) {
      return {
        ok: false,
        error: PairingClientHandshakeError.AUTH_PROOF_NOT_SENT
      };
    }

    const localEphemeralPrivateKey = session.localEphemeralPrivateKey();
    if (localEphemeralPrivateKey === null) {
      return {
        ok: false,
        error: PairingClientHandshakeError.SHARED_SECRET_DERIVATION_FAILED,
        field: 'localEphemeralPrivateKey'
      };
    }

    const serverHello = session.serverHelloPayload();
    if (serverHello === null) {
      return {
        ok: false,
        error: PairingClientHandshakeError.SHARED_SECRET_DERIVATION_FAILED,
        field: 'serverHello'
      };
    }

    const sharedSecret = this.keyAgreement.deriveSharedSecret(
      localEphemeralPrivateKey,
      serverHello.ephemeralPublicKey
    );
    if (!sharedSecret.ok || sharedSecret.sharedSecret === undefined) {
      return {
        ok: false,
        error: PairingClientHandshakeError.SHARED_SECRET_DERIVATION_FAILED,
        keyAgreementError: sharedSecret.error,
        field: sharedSecret.field
      };
    }

    return this.acceptAuthOkAndCreateTransportSession(
      session,
      authOkFrame,
      sharedSecret.sharedSecret,
      transcriptSaltBase64Url
    );
  }
}

function cloneHelloPayload(payload: HelloPayload): HelloPayload {
  const clone: HelloPayload = {
    spaceId: payload.spaceId,
    deviceId: payload.deviceId,
    identityPublicKey: payload.identityPublicKey,
    ephemeralPublicKey: payload.ephemeralPublicKey,
    capabilities: payload.capabilities.slice()
  };
  if (payload.pairingContext !== undefined) {
    clone.pairingContext = payload.pairingContext;
  }
  return clone;
}
