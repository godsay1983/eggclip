import {
  AuthRole,
  HelloPayload,
  MessageType,
  ProtocolParser
} from '../../models/ProtocolModels';
import {
  ProtocolFrameBuildError,
  ProtocolFrameBuilderService
} from '../transport/ProtocolFrameBuilderService';
import {
  ProtocolHandshakeFrameOutcome,
  ProtocolHandshakeTransportSession,
  ProtocolTransportFrameError
} from '../transport/ProtocolTransportSession';
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
  AUTH_PROOF_BUILD_FAILED = 'authProofBuildFailed'
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
  frameError?: ProtocolFrameBuildError;
  field?: string;
}

export class PairingClientHandshakeSession {
  readonly draft: PairingHandshakeDraft;
  private readonly transportSession: ProtocolHandshakeTransportSession;

  constructor(draft: PairingHandshakeDraft) {
    this.draft = draft;
    this.transportSession = new ProtocolHandshakeTransportSession();
  }

  acceptServerFrame(frame: string) {
    return this.transportSession.acceptTextFrame(frame);
  }
}

export class PairingClientHandshakeSessionService {
  private readonly parser: ProtocolParser = new ProtocolParser();
  private readonly frameBuilder: ProtocolFrameBuilderService = new ProtocolFrameBuilderService();
  private readonly draftService: PairingHandshakeDraftService = new PairingHandshakeDraftService();

  start(
    draft: PairingHandshakeDraft,
    clientHelloMessageId: string,
    clientHelloCounter: number = 0
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
      session: new PairingClientHandshakeSession(draft),
      clientHelloFrame: clientHello.frame
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

    return {
      ok: true,
      authProofFrame: authProof.frame,
      serverHello: serverHello.payload,
      transcript: transcript.transcript
    };
  }
}
