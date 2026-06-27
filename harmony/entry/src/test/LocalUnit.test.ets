import { describe, expect, it } from '@ohos/hypium';
import { ClipboardBridgeService } from '../main/ets/services/clipboard/ClipboardBridgeService';
import {
  ProtocolHandshakeFrameOutcome,
  ProtocolHandshakeTransportSession,
  ProtocolTransportFrameError,
  ProtocolTransportSession
} from '../main/ets/services/transport/ProtocolTransportSession';
import { WebSocketTransportService } from '../main/ets/services/transport/WebSocketTransportService';
import {
  CryptoVectorErrorCode,
  CryptoVectorService,
  SessionDirection,
  decodeBase64Url,
  encodeBase64Url,
  sessionNonce
} from '../main/ets/services/crypto/CryptoVectorService';
import {
  ClipboardValidationError,
  EGGCLIP_MDNS_DISCOVERY_TYPE,
  EGGCLIP_MDNS_SERVICE_TYPE,
  POC_MAX_FRAME_BYTES
} from '../main/ets/models/PocModels';
import {
  ContentType as DomainContentType,
  DomainValidationError,
  HlcTimestamp,
  OriginSeqAllocator,
  buildLocalClipboardItemDraft,
  defaultAppSettings,
  validateAppSettings
} from '../main/ets/models/DomainModels';
import {
  CURRENT_SCHEMA_VERSION,
  INITIAL_SCHEMA_TABLES,
  allSchemaSql,
  pendingMigrations,
  validateSchemaPlan
} from '../main/ets/data/migrations/SchemaMigrations';
import {
  AeadAlgorithm,
  AuthRole,
  ContentType,
  MessageType,
  ProtocolEnvelopeKind,
  ProtocolErrorCode,
  ProtocolInboundSession,
  ProtocolParser,
  ProtocolReplayGuard,
  ProtocolSessionGate,
  ProtocolSessionState,
  PROTOCOL_HANDSHAKE_TIMEOUT_SECONDS,
  PROTOCOL_HEARTBEAT_INTERVAL_SECONDS,
  PROTOCOL_IDLE_DISCONNECT_SECONDS,
  PROTOCOL_MAX_BATCH_ITEMS,
  PROTOCOL_MAX_BATCH_PLAINTEXT_BYTES,
  PROTOCOL_MAX_FRAME_BYTES,
  PROTOCOL_MAX_TEXT_BYTES,
  PROTOCOL_VERSION,
  canonicalAuthTranscript,
  canonicalEncryptedAad
} from '../main/ets/models/ProtocolModels';
import { MAX_TEXT_BYTES } from '../main/ets/utils/TextLimits';

export default function localUnitTest() {
  describe('EggClipH1Boundaries', () => {
    it('keepsPublishAndDiscoveryMdnsTypesDistinct', 0, () => {
      expect(EGGCLIP_MDNS_SERVICE_TYPE).assertEqual('_eggclip._tcp.local.');
      expect(EGGCLIP_MDNS_DISCOVERY_TYPE).assertEqual('_eggclip._tcp');
    });

    it('validatesManualWebSocketEndpoint', 0, () => {
      const transport = new WebSocketTransportService();
      const valid = transport.validateEndpoint({ host: ' 192.168.1.20 ', port: 4567 });
      expect(valid.ok).assertEqual(true);
      expect(valid.normalizedUrl).assertEqual('ws://192.168.1.20:4567');
      expect(transport.validateEndpoint({ host: '', port: 4567 }).ok).assertEqual(false);
      expect(transport.validateEndpoint({ host: 'desktop.local', port: 4567 }).ok).assertEqual(false);
      expect(transport.validateEndpoint({ host: '01.2.3.4', port: 4567 }).ok).assertEqual(false);
      expect(transport.validateEndpoint({ host: '224.0.0.1', port: 4567 }).ok).assertEqual(false);
      expect(transport.validateEndpoint({ host: '255.255.255.255', port: 4567 }).ok).assertEqual(false);
      expect(transport.validateEndpoint({ host: '127.0.0.1', port: 0 }).ok).assertEqual(false);
    });

    it('parsesOnlyBoundedClipboardTextFrames', 0, () => {
      const transport = new WebSocketTransportService();
      expect(transport.encodeClipboardTextMessage('from harmony'))
        .assertEqual('{"kind":"clipboardText","text":"from harmony"}');
      expect(transport.parseClipboardTextMessage('{"kind":"clipboardText","text":"蛋定"}'))
        .assertEqual('蛋定');
      expect(transport.parseClipboardTextMessage('{"kind":"other","text":"ignored"}')).assertEqual(null);
      expect(transport.parseClipboardTextMessage('not json')).assertEqual(null);
      expect(transport.parseClipboardTextMessage('{"kind":"clipboardText","text":""}')).assertEqual(null);
      expect(transport.decodeClipboardTextMessage('not json').reason).assertEqual('POC 消息不是有效 JSON');
      expect(transport.decodeClipboardTextMessage('{"kind":"clipboardText","text":""}').reason)
        .assertEqual('POC 文本为空');
      const exactText = 'a'.repeat(MAX_TEXT_BYTES);
      const exactMessage = transport.encodeClipboardTextMessage(exactText);
      expect(exactMessage === null).assertEqual(false);
      expect(transport.parseClipboardTextMessage(exactMessage ?? '')).assertEqual(exactText);
      expect(transport.encodeClipboardTextMessage('')).assertEqual(null);
      expect(transport.encodeClipboardTextMessage('a'.repeat(MAX_TEXT_BYTES + 1))).assertEqual(null);
      const oversizedTextMessage = `{"kind":"clipboardText","text":"${'a'.repeat(MAX_TEXT_BYTES + 1)}"}`;
      expect(transport.decodeClipboardTextMessage(oversizedTextMessage).reason)
        .assertEqual('POC 文本超过 256 KiB 上限');
      expect(transport.parseClipboardTextMessage('a'.repeat(POC_MAX_FRAME_BYTES + 1))).assertEqual(null);
    });

    it('enforcesPlainTextUtf8Boundary', 0, () => {
      const clipboard = new ClipboardBridgeService();
      const empty = clipboard.inspectPlainText('');
      expect(empty.ok).assertEqual(false);
      expect(empty.error).assertEqual(ClipboardValidationError.EMPTY);

      const utf8 = clipboard.inspectPlainText('蛋定🥚');
      expect(utf8.ok).assertEqual(true);
      expect(utf8.byteLength).assertEqual(10);

      expect(clipboard.inspectPlainText('a'.repeat(MAX_TEXT_BYTES)).ok).assertEqual(true);
      const oversized = clipboard.inspectPlainText('a'.repeat(MAX_TEXT_BYTES + 1));
      expect(oversized.ok).assertEqual(false);
      expect(oversized.error).assertEqual(ClipboardValidationError.TOO_LARGE);
    });

    it('tracksSafePocFrameDiagnostics', 0, () => {
      const transport = new WebSocketTransportService();
      transport.decodeClipboardTextMessage('{"kind":"clipboardText","text":"ok"}');
      transport.decodeClipboardTextMessage('not json');
      const diagnostics = transport.currentDiagnostics();
      expect(diagnostics.receivedFrames).assertEqual(2);
      expect(diagnostics.acceptedItems).assertEqual(1);
      expect(diagnostics.rejectedFrames).assertEqual(1);
      expect(diagnostics.lastRejection).assertEqual('POC 消息不是有效 JSON');

      transport.resetDiagnostics();
      expect(transport.currentDiagnostics().receivedFrames).assertEqual(0);
    });

    it('keepsProtocolV1ConstantsAligned', 0, () => {
      expect(PROTOCOL_VERSION).assertEqual(1);
      expect(PROTOCOL_MAX_FRAME_BYTES).assertEqual(1024 * 1024);
      expect(PROTOCOL_MAX_TEXT_BYTES).assertEqual(256 * 1024);
      expect(PROTOCOL_MAX_BATCH_ITEMS).assertEqual(100);
      expect(PROTOCOL_MAX_BATCH_PLAINTEXT_BYTES).assertEqual(512 * 1024);
      expect(PROTOCOL_HANDSHAKE_TIMEOUT_SECONDS).assertEqual(8);
      expect(PROTOCOL_HEARTBEAT_INTERVAL_SECONDS).assertEqual(20);
      expect(PROTOCOL_IDLE_DISCONNECT_SECONDS).assertEqual(60);
    });

    it('buildsDomainHlcAndOriginSequenceModels', 0, () => {
      const local = new HlcTimestamp(1000, 0);
      const tickSameMs = local.tick(1000);
      const tickNewMs = tickSameMs.tick(1005);
      const observed = tickNewMs.observe(new HlcTimestamp(1005, 8), 1004);

      expect(tickSameMs.toWire()).assertEqual('00000000000003e8-0001');
      expect(tickNewMs.toWire()).assertEqual('00000000000003ed-0000');
      expect(observed.toWire()).assertEqual('00000000000003ed-0009');
      expect(local.compare(tickSameMs)).assertEqual(-1);
      expect(observed.compare(tickNewMs)).assertEqual(1);

      const allocator = new OriginSeqAllocator(7);
      expect(allocator.nextSeq()).assertEqual(7);
      expect(allocator.nextSeq()).assertEqual(8);
      expect(allocator.peekNext()).assertEqual(9);
    });

    it('validatesDomainClipboardItemDraftAndSettings', 0, () => {
      const item = buildLocalClipboardItemDraft({
        itemId: '018ff6ef-c394-7d08-8b99-4b7d10f2767a',
        spaceId: '018ff6f0-0a3b-7815-a4db-3eb6e23d9338',
        originDeviceId: '018ff6f0-4adf-7d31-a987-3ef2b25d0212',
        originSeq: 42,
        hlc: new HlcTimestamp(1700000000100, 0),
        createdAt: 1700000000100,
        contentDigest: 'VCKcnWkMQkRIXGbdZ29X9i2PfEJai3L2lV1hCUApXkw'
      }, '蛋定 Clip');

      expect(item.ok).assertEqual(true);
      expect(item.item?.contentType).assertEqual(DomainContentType.TEXT_PLAIN);
      expect(item.item?.contentLength).assertEqual(11);
      expect(item.item?.hlc).assertEqual('0000018bcfe56864-0000');

      const empty = buildLocalClipboardItemDraft({
        itemId: '018ff6ef-c394-7d08-8b99-4b7d10f2767a',
        spaceId: '018ff6f0-0a3b-7815-a4db-3eb6e23d9338',
        originDeviceId: '018ff6f0-4adf-7d31-a987-3ef2b25d0212',
        originSeq: 43,
        hlc: new HlcTimestamp(1700000000101, 0),
        createdAt: 1700000000101,
        contentDigest: 'VCKcnWkMQkRIXGbdZ29X9i2PfEJai3L2lV1hCUApXkw'
      }, '');
      expect(empty.error).assertEqual(DomainValidationError.EMPTY_TEXT);

      const settings = defaultAppSettings();
      expect(settings.historyLimit).assertEqual(50);
      expect(settings.autoWriteEnabled).assertEqual(false);
      expect(validateAppSettings(settings).ok).assertEqual(true);
      expect(validateAppSettings({
        syncEnabled: true,
        autoReceiveEnabled: true,
        autoWriteEnabled: false,
        historyEnabled: true,
        historyLimit: 10,
        retentionDays: 7
      }).error).assertEqual(DomainValidationError.INVALID_HISTORY_LIMIT);
    });

    it('definesRdbSchemaMigrationPlanForLocalSyncTables', 0, () => {
      const pending = pendingMigrations(0);
      const sql = allSchemaSql().join('\n').toLowerCase();

      expect(CURRENT_SCHEMA_VERSION).assertEqual(1);
      expect(pending.length).assertEqual(1);
      expect(pendingMigrations(CURRENT_SCHEMA_VERSION).length).assertEqual(0);
      expect(validateSchemaPlan()).assertEqual(true);
      expect(INITIAL_SCHEMA_TABLES.length).assertEqual(6);
      expect(sql.indexOf('create table if not exists clipboard_items') >= 0).assertEqual(true);
      expect(sql.indexOf('encrypted_content') >= 0).assertEqual(true);
      expect(sql.indexOf('unique(origin_device_id, origin_seq)') >= 0).assertEqual(true);
      expect(sql.indexOf('idx_clipboard_items_retention') >= 0).assertEqual(true);
    });

    it('parsesProtocolClientHelloFixture', 0, () => {
      const parser = new ProtocolParser();
      const result = parser.parseEnvelope(CLIENT_HELLO_FIXTURE);

      expect(result.ok).assertEqual(true);
      expect(result.envelope?.kind).assertEqual(ProtocolEnvelopeKind.PRE_AUTH);
      expect(result.envelope?.messageType).assertEqual(MessageType.CLIENT_HELLO);
      const hello = parser.parseHelloPayload(result.envelope?.payload);
      expect(hello.ok).assertEqual(true);
      expect(hello.payload?.spaceId).assertEqual('018ff6ef-c394-7d08-8b99-4b7d10f2767a');
      expect(hello.payload?.capabilities.length).assertEqual(4);
    });

    it('parsesProtocolAuthProofFixture', 0, () => {
      const parser = new ProtocolParser();
      const result = parser.parseEnvelope(AUTH_PROOF_FIXTURE);

      expect(result.ok).assertEqual(true);
      expect(result.envelope?.kind).assertEqual(ProtocolEnvelopeKind.PRE_AUTH);
      expect(result.envelope?.messageType).assertEqual(MessageType.AUTH_PROOF);
      const proof = parser.parseAuthProofPayload(result.envelope?.payload);
      expect(proof.ok).assertEqual(true);
      expect(proof.payload?.role).assertEqual(AuthRole.CLIENT);
      expect(proof.payload?.transcriptHash).assertEqual('aM5GGwvEfnwOx_BNJSJktCEYEkmCrSH0wgAESnSOYEw');
    });

    it('buildsProtocolAuthTranscriptFixture', 0, () => {
      const transcript = canonicalAuthTranscript({
        role: AuthRole.CLIENT,
        spaceId: '018ff6ef-c394-7d08-8b99-4b7d10f2767a',
        localDeviceId: '018ff6f0-0a3b-7815-a4db-3eb6e23d9338',
        remoteDeviceId: '018ff6f0-4adf-7d31-a987-3ef2b25d0212',
        localIdentityPublicKey: '11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo',
        remoteIdentityPublicKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
        localEphemeralPublicKey: 'hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo',
        remoteEphemeralPublicKey: '3p7bfXt9wbTTW2HC7OQ1Nz-DQ8hbeGdNrfx-FG-IK08',
        pairingContext: 'trusted-device:018ff6ef-c394-7d08-8b99-4b7d10f2767a'
      });

      expect(transcript).assertEqual(AUTH_PROOF_TRANSCRIPT);
    });

    it('movesProtocolSessionGateThroughHandshakeAndEncryptedBusiness', 0, () => {
      const parser = new ProtocolParser();
      const gate = new ProtocolSessionGate();
      const clientHelloResult = parser.parseEnvelope(CLIENT_HELLO_FIXTURE);
      const authProofResult = parser.parseEnvelope(AUTH_PROOF_FIXTURE);
      const authOkResult = parser.parseEnvelope(AUTH_OK_FIXTURE);
      const itemLiveResult = parser.parseEnvelope(ENCRYPTED_ITEM_LIVE_FIXTURE);

      expect(clientHelloResult.ok).assertEqual(true);
      expect(authProofResult.ok).assertEqual(true);
      expect(authOkResult.ok).assertEqual(true);
      expect(itemLiveResult.ok).assertEqual(true);

      expect(gate.connect()).assertEqual(ProtocolSessionState.CONNECTING);
      expect(gate.acceptEnvelope(clientHelloResult.envelope!).state).assertEqual(ProtocolSessionState.HANDSHAKING);
      expect(gate.acceptEnvelope(authProofResult.envelope!).state).assertEqual(ProtocolSessionState.HANDSHAKING);
      expect(gate.acceptEnvelope(authOkResult.envelope!).state).assertEqual(ProtocolSessionState.AUTHENTICATED);
      expect(gate.acceptEnvelope(itemLiveResult.envelope!).state).assertEqual(ProtocolSessionState.READY);
    });

    it('rejectsProtocolSessionGateBusinessBeforeAuthAndPlaintextAfterAuth', 0, () => {
      const parser = new ProtocolParser();
      const itemLiveResult = parser.parseEnvelope(ENCRYPTED_ITEM_LIVE_FIXTURE);
      const clientHelloResult = parser.parseEnvelope(CLIENT_HELLO_FIXTURE);
      const authOkResult = parser.parseEnvelope(AUTH_OK_FIXTURE);
      const gate = new ProtocolSessionGate();

      expect(itemLiveResult.ok).assertEqual(true);
      expect(clientHelloResult.ok).assertEqual(true);
      expect(authOkResult.ok).assertEqual(true);

      gate.startHandshake();
      const earlyBusiness = gate.acceptEnvelope(itemLiveResult.envelope!);
      expect(earlyBusiness.ok).assertEqual(false);
      expect(earlyBusiness.error).assertEqual(ProtocolErrorCode.CIPHERTEXT_BEFORE_AUTH);

      gate.acceptEnvelope(authOkResult.envelope!);
      const latePlaintext = gate.acceptEnvelope(clientHelloResult.envelope!);
      expect(latePlaintext.ok).assertEqual(false);
      expect(latePlaintext.error).assertEqual(ProtocolErrorCode.PLAINTEXT_AFTER_AUTH);
    });

    it('rejectsProtocolReplayMessageIdAndOldCounter', 0, () => {
      const parser = new ProtocolParser();
      const clientHello = parser.parseEnvelope(CLIENT_HELLO_FIXTURE);
      const authProof = parser.parseEnvelope(AUTH_PROOF_FIXTURE);
      const authOkOldCounter = parser.parseEnvelope(AUTH_OK_OLD_COUNTER_FIXTURE);
      const guard = new ProtocolReplayGuard();

      expect(clientHello.ok).assertEqual(true);
      expect(authProof.ok).assertEqual(true);
      expect(authOkOldCounter.ok).assertEqual(true);
      expect(guard.acceptEnvelope(clientHello.envelope!).ok).assertEqual(true);
      expect(guard.acceptEnvelope(clientHello.envelope!).error)
        .assertEqual(ProtocolErrorCode.DUPLICATE_MESSAGE_ID);

      const secondGuard = new ProtocolReplayGuard();
      expect(secondGuard.acceptEnvelope(authProof.envelope!).ok).assertEqual(true);
      expect(secondGuard.acceptEnvelope(authOkOldCounter.envelope!).error)
        .assertEqual(ProtocolErrorCode.REPLAY_COUNTER);
    });

    it('appliesProtocolInboundSessionReplayGuardBeforeStateGate', 0, () => {
      const parser = new ProtocolParser();
      const clientHello = parser.parseEnvelope(CLIENT_HELLO_FIXTURE);
      const session = new ProtocolInboundSession();

      expect(clientHello.ok).assertEqual(true);
      session.connect();
      expect(session.acceptEnvelope(clientHello.envelope!).state).assertEqual(ProtocolSessionState.HANDSHAKING);
      expect(session.acceptEnvelope(clientHello.envelope!).error)
        .assertEqual(ProtocolErrorCode.DUPLICATE_MESSAGE_ID);
    });

    it('movesProtocolHandshakeTransportThroughHelloAndAuthOk', 0, () => {
      const session = new ProtocolHandshakeTransportSession();
      const hello = session.acceptTextFrame(CLIENT_HELLO_FIXTURE);

      expect(hello.ok).assertEqual(true);
      expect(hello.outcome).assertEqual(ProtocolHandshakeFrameOutcome.CONTINUE);
      expect(hello.envelope?.messageType).assertEqual(MessageType.CLIENT_HELLO);

      const authOk = session.acceptTextFrame(AUTH_OK_FIXTURE);
      expect(authOk.ok).assertEqual(true);
      expect(authOk.outcome).assertEqual(ProtocolHandshakeFrameOutcome.AUTHENTICATED);
      expect(session.state()).assertEqual(ProtocolSessionState.AUTHENTICATED);
      expect(session.isClosed()).assertEqual(false);
    });

    it('closesProtocolHandshakeTransportOnAuthErrorAndRejectsEncryptedBusiness', 0, () => {
      const authErrorSession = new ProtocolHandshakeTransportSession();
      const authError = authErrorSession.acceptTextFrame(AUTH_ERROR_FIXTURE);

      expect(authError.ok).assertEqual(true);
      expect(authError.outcome).assertEqual(ProtocolHandshakeFrameOutcome.FAILED);
      expect(authError.envelope?.messageType).assertEqual(MessageType.AUTH_ERROR);
      expect(authErrorSession.isClosed()).assertEqual(true);
      expect(authErrorSession.state()).assertEqual(ProtocolSessionState.FAILED);
      expect(authErrorSession.acceptTextFrame(AUTH_ERROR_FIXTURE).error)
        .assertEqual(ProtocolTransportFrameError.SESSION_CLOSED);

      const encryptedSession = new ProtocolHandshakeTransportSession();
      const encrypted = encryptedSession.acceptTextFrame(ENCRYPTED_ITEM_LIVE_FIXTURE);
      expect(encrypted.ok).assertEqual(false);
      expect(encrypted.protocolError).assertEqual(ProtocolErrorCode.CIPHERTEXT_BEFORE_AUTH);
      expect(encryptedSession.isClosed()).assertEqual(true);
    });

    it('acceptsProtocolTransportEncryptedFrameAfterAuth', 0, () => {
      const session = new ProtocolTransportSession();
      const result = session.acceptTextFrame(ENCRYPTED_ITEM_LIVE_FIXTURE);

      expect(result.ok).assertEqual(true);
      expect(result.envelope?.kind).assertEqual(ProtocolEnvelopeKind.ENCRYPTED);
      expect(result.envelope?.messageType).assertEqual(MessageType.ITEM_LIVE);
      expect(session.state()).assertEqual(ProtocolSessionState.READY);
    });

    it('rejectsProtocolTransportDuplicateAndPocPlaintextFrames', 0, () => {
      const session = new ProtocolTransportSession();

      expect(session.acceptTextFrame(ENCRYPTED_ITEM_LIVE_FIXTURE).ok).assertEqual(true);
      const duplicate = session.acceptTextFrame(ENCRYPTED_ITEM_LIVE_FIXTURE);
      expect(duplicate.ok).assertEqual(false);
      expect(duplicate.error).assertEqual(ProtocolTransportFrameError.PROTOCOL_REJECTED);
      expect(duplicate.protocolError).assertEqual(ProtocolErrorCode.DUPLICATE_MESSAGE_ID);
      expect(session.isClosed()).assertEqual(true);
      expect(session.state()).assertEqual(ProtocolSessionState.FAILED);
      expect(session.acceptTextFrame(ENCRYPTED_ITEM_LIVE_FIXTURE).error)
        .assertEqual(ProtocolTransportFrameError.SESSION_CLOSED);

      const poc = new ProtocolTransportSession().acceptTextFrame('{"kind":"clipboardText","text":"not formal"}');
      expect(poc.ok).assertEqual(false);
      expect(poc.error).assertEqual(ProtocolTransportFrameError.PROTOCOL_REJECTED);
    });

    it('closesProtocolTransportSessionOnEncryptedRemoteError', 0, () => {
      const session = new ProtocolTransportSession();
      const result = session.acceptTextFrame(ENCRYPTED_ERROR_FIXTURE);

      expect(result.ok).assertEqual(false);
      expect(result.error).assertEqual(ProtocolTransportFrameError.REMOTE_ERROR);
      expect(session.isClosed()).assertEqual(true);
      expect(session.state()).assertEqual(ProtocolSessionState.FAILED);
      expect(session.acceptTextFrame(ENCRYPTED_ERROR_FIXTURE).error)
        .assertEqual(ProtocolTransportFrameError.SESSION_CLOSED);
    });

    it('routesProtocolFramesThroughWebSocketTransportDiagnostics', 0, () => {
      const transport = new WebSocketTransportService();
      const session = new ProtocolTransportSession();

      const accepted = transport.decodeProtocolFrameMessage(ENCRYPTED_ITEM_LIVE_FIXTURE, session);
      expect(accepted.ok).assertEqual(true);
      expect(accepted.envelope?.messageType).assertEqual(MessageType.ITEM_LIVE);

      const duplicate = transport.decodeProtocolFrameMessage(ENCRYPTED_ITEM_LIVE_FIXTURE, session);
      expect(duplicate.ok).assertEqual(false);
      expect(duplicate.protocolError).assertEqual(ProtocolErrorCode.DUPLICATE_MESSAGE_ID);
      expect(session.isClosed()).assertEqual(true);

      const afterClosed = transport.decodeProtocolFrameMessage(ENCRYPTED_ITEM_LIVE_FIXTURE, session);
      expect(afterClosed.ok).assertEqual(false);
      expect(afterClosed.error).assertEqual(ProtocolTransportFrameError.SESSION_CLOSED);

      const diagnostics = transport.currentDiagnostics();
      expect(diagnostics.receivedFrames).assertEqual(3);
      expect(diagnostics.acceptedItems).assertEqual(1);
      expect(diagnostics.rejectedFrames).assertEqual(2);
      expect(diagnostics.lastRejection).assertEqual('正式协议拒绝：sessionClosed');
    });

    it('parsesProtocolEncryptedItemLiveFixture', 0, () => {
      const parser = new ProtocolParser();
      const result = parser.parseEnvelope(ENCRYPTED_ITEM_LIVE_FIXTURE);

      expect(result.ok).assertEqual(true);
      expect(result.envelope?.kind).assertEqual(ProtocolEnvelopeKind.ENCRYPTED);
      expect(result.envelope?.messageType).assertEqual(MessageType.ITEM_LIVE);
      expect(result.envelope?.sessionCounter).assertEqual(12);
      expect(result.envelope?.ciphertext?.algorithm).assertEqual(AeadAlgorithm.AES_256_GCM);
    });

    it('buildsCanonicalEncryptedAadForBusinessFrames', 0, () => {
      const aad = canonicalEncryptedAad(
        MessageType.ITEM_LIVE,
        '018ff6f3-0d8c-7d1e-a38a-f308c64de79f',
        12,
        'session-v1-client-to-server'
      );

      expect(aad).assertEqual('EggClip v1 ciphertext aad\n' +
        'version=1\n' +
        'type=ITEM_LIVE\n' +
        'messageId=018ff6f3-0d8c-7d1e-a38a-f308c64de79f\n' +
        'sessionCounter=12\n' +
        'algorithm=AES-256-GCM\n' +
        'keyId=session-v1-client-to-server\n');
      expect(canonicalEncryptedAad(
        MessageType.CLIENT_HELLO,
        '018ff6f3-0d8c-7d1e-a38a-f308c64de79f',
        12,
        'session-v1-client-to-server'
      )).assertEqual(null);
      expect(canonicalEncryptedAad(
        MessageType.ITEM_LIVE,
        'not-a-uuid',
        12,
        'session-v1-client-to-server'
      )).assertEqual(null);
      expect(canonicalEncryptedAad(
        MessageType.ITEM_LIVE,
        '018ff6f3-0d8c-7d1e-a38a-f308c64de79f',
        12,
        'bad\nkey'
      )).assertEqual(null);
    });

    it('parsesProtocolClipboardItemFixture', 0, () => {
      const parser = new ProtocolParser();
      const result = parser.parseClipboardItem(CLIPBOARD_ITEM_FIXTURE);

      expect(result.ok).assertEqual(true);
      expect(result.item?.contentType).assertEqual(ContentType.TEXT_PLAIN);
      expect(result.item?.contentLength).assertEqual(17);
      expect(result.item?.content).assertEqual('EggClip test text');
    });

    it('rejectsProtocolUnknownVersionFixture', 0, () => {
      const parser = new ProtocolParser();
      const result = parser.parseEnvelope(UNKNOWN_VERSION_FIXTURE);

      expect(result.ok).assertEqual(false);
      expect(result.error).assertEqual(ProtocolErrorCode.UNSUPPORTED_VERSION);
    });

    it('rejectsProtocolPostAuthPlaintextFixture', 0, () => {
      const parser = new ProtocolParser();
      const result = parser.parseEnvelope(POST_AUTH_PLAINTEXT_FIXTURE);

      expect(result.ok).assertEqual(false);
      expect(result.error).assertEqual(ProtocolErrorCode.PLAINTEXT_AFTER_AUTH);
    });

    it('rejectsProtocolCiphertextBeforeAuth', 0, () => {
      const parser = new ProtocolParser();
      const result = parser.parseEnvelope(PRE_AUTH_CIPHERTEXT_FIXTURE);

      expect(result.ok).assertEqual(false);
      expect(result.error).assertEqual(ProtocolErrorCode.CIPHERTEXT_BEFORE_AUTH);
    });

    it('decodesBase64UrlCryptoVectorBytes', 0, () => {
      expect(decodeBase64Url('11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo')?.length).assertEqual(32);
      expect(encodeBase64Url(sessionNonce(SessionDirection.CLIENT_TO_SERVER, 12))).assertEqual('YzJzAQAAAAAAAAAM');
      expect(decodeBase64Url('====') === null).assertEqual(true);
    });

    it('validatesCryptoVectorShapesBeforePlatformCryptoIntegration', 0, () => {
      const service = new CryptoVectorService();
      expect(service.validateEd25519SignatureVector(ED25519_SIGNATURE_VECTOR).ok).assertEqual(true);
      expect(service.validateX25519SharedSecretVector(X25519_SHARED_SECRET_VECTOR).ok).assertEqual(true);
      expect(service.validateHkdfSha256Vector(HKDF_SHA256_VECTOR).ok).assertEqual(true);
      expect(service.validateAes256GcmVector(AES_256_GCM_VECTOR).ok).assertEqual(true);
      expect(service.validateSessionKeysVector(SESSION_KEYS_VECTOR).ok).assertEqual(true);
      expect(service.validateReplayCounterVector(REPLAY_COUNTER_VECTOR).ok).assertEqual(true);

      const badEd25519 = service.validateEd25519SignatureVector('{"algorithm":"Ed25519","privateSeed":"AA","publicKey":"AA","message":"","signature":"AA"}');
      expect(badEd25519.ok).assertEqual(false);
      expect(badEd25519.error).assertEqual(CryptoVectorErrorCode.INVALID_LENGTH);
    });
  });
}

const CLIENT_HELLO_FIXTURE: string = '{"version":1,"type":"CLIENT_HELLO","messageId":"018ff6f0-2b1f-7cc5-b5d0-7e82c5f70f01","sessionCounter":0,"payload":{"spaceId":"018ff6ef-c394-7d08-8b99-4b7d10f2767a","deviceId":"018ff6f0-0a3b-7815-a4db-3eb6e23d9338","identityPublicKey":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","ephemeralPublicKey":"BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB","capabilities":["textPlain","syncHeads","itemBatch","itemLive"]}}';

const AUTH_PROOF_FIXTURE: string = '{"version":1,"type":"AUTH_PROOF","messageId":"018ff6f1-1d2a-725d-8d1a-894d2f5b0a42","sessionCounter":2,"payload":{"role":"client","signatureAlgorithm":"Ed25519","transcriptHash":"aM5GGwvEfnwOx_BNJSJktCEYEkmCrSH0wgAESnSOYEw","signature":"cdpm2njgsHCfH0hrubU-NbHMbWcN1xNtr-vZTKx_Tdf85hHKW8gIJuk463rj4f744vegLphZFO0RTvP_gQjeAg"}}';

const AUTH_PROOF_TRANSCRIPT: string = 'EggClip v1 auth transcript\nrole=client\nspaceId=018ff6ef-c394-7d08-8b99-4b7d10f2767a\nlocalDeviceId=018ff6f0-0a3b-7815-a4db-3eb6e23d9338\nremoteDeviceId=018ff6f0-4adf-7d31-a987-3ef2b25d0212\nlocalIdentityPublicKey=11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo\nremoteIdentityPublicKey=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\nlocalEphemeralPublicKey=hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo\nremoteEphemeralPublicKey=3p7bfXt9wbTTW2HC7OQ1Nz-DQ8hbeGdNrfx-FG-IK08\npairingContext=trusted-device:018ff6ef-c394-7d08-8b99-4b7d10f2767a\n';

const AUTH_OK_FIXTURE: string = '{"version":1,"type":"AUTH_OK","messageId":"018ff6f1-25f0-7c09-a4cf-3d683ebfae33","sessionCounter":3,"payload":{}}';

const AUTH_OK_OLD_COUNTER_FIXTURE: string = '{"version":1,"type":"AUTH_OK","messageId":"018ff6f1-25f0-7c09-a4cf-3d683ebfae33","sessionCounter":1,"payload":{}}';

const AUTH_ERROR_FIXTURE: string = '{"version":1,"type":"AUTH_ERROR","messageId":"018ff6f1-35f0-7c09-a4cf-3d683ebfae33","sessionCounter":3,"payload":{"code":"authFailed"}}';

const ENCRYPTED_ITEM_LIVE_FIXTURE: string = '{"version":1,"type":"ITEM_LIVE","messageId":"018ff6f3-0d8c-7d1e-a38a-f308c64de79f","sessionCounter":12,"ciphertext":{"algorithm":"AES-256-GCM","keyId":"session-v1-client-to-server","nonce":"DDDDDDDDDDDDDDDD","aad":"EEEEEEEEEEEEEEEE","body":"FFFFFFFFFFFFFFFF","tag":"GGGGGGGGGGGGGGGGGGGGGG"}}';

const ENCRYPTED_ERROR_FIXTURE: string = '{"version":1,"type":"ERROR","messageId":"018ff6f4-0d8c-7d1e-a38a-f308c64de79f","sessionCounter":12,"ciphertext":{"algorithm":"AES-256-GCM","keyId":"session-v1-client-to-server","nonce":"DDDDDDDDDDDDDDDD","aad":"EEEEEEEEEEEEEEEE","body":"FFFFFFFFFFFFFFFF","tag":"GGGGGGGGGGGGGGGGGGGGGG"}}';

const CLIPBOARD_ITEM_FIXTURE: string = '{"itemId":"018ff6f3-3653-7c79-b38b-f4af3575396b","spaceId":"018ff6ef-c394-7d08-8b99-4b7d10f2767a","originDeviceId":"018ff6f0-0a3b-7815-a4db-3eb6e23d9338","originSeq":42,"hlc":"1781946000123:0:018ff6f0","contentType":"text/plain","contentLength":17,"contentDigest":"CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC","createdAt":1781946000123,"content":"EggClip test text"}';

const UNKNOWN_VERSION_FIXTURE: string = '{"version":2,"type":"CLIENT_HELLO","messageId":"018ff6f0-2b1f-7cc5-b5d0-7e82c5f70f01","sessionCounter":0,"payload":{}}';

const POST_AUTH_PLAINTEXT_FIXTURE: string = '{"version":1,"type":"ITEM_LIVE","messageId":"018ff6f3-0d8c-7d1e-a38a-f308c64de79f","sessionCounter":12,"payload":{"content":"must not be plaintext after auth"}}';

const PRE_AUTH_CIPHERTEXT_FIXTURE: string = '{"version":1,"type":"CLIENT_HELLO","messageId":"018ff6f0-2b1f-7cc5-b5d0-7e82c5f70f01","sessionCounter":0,"ciphertext":{"algorithm":"AES-256-GCM","keyId":"session-v1-client-to-server","nonce":"DDDDDDDDDDDDDDDD","aad":"EEEEEEEEEEEEEEEE","body":"FFFFFFFFFFFFFFFF","tag":"GGGGGGGGGGGGGGGGGGGGGG"}}';

const ED25519_SIGNATURE_VECTOR: string = '{"algorithm":"Ed25519","source":"RFC 8032 test 1","privateSeed":"nWGxne_9WmC6hEr0kuwsxERJxWl7MmkZcDusAxyuf2A","publicKey":"11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo","message":"","signature":"5VZDAMNgrHKQhuLMgG6CioSHfx645dl02HPgZSJJAVVfuIIVkKM7rMYeOXAc-bRr0lv18FlbviRlUUFDjnoQCw"}';

const X25519_SHARED_SECRET_VECTOR: string = '{"algorithm":"X25519","source":"RFC 7748 section 6.1","alicePrivateKey":"dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo","alicePublicKey":"hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo","bobPrivateKey":"XasIfmJKikt54X-Lg4AO5m87sSkmGLb9HC-LJ_-I4Os","bobPublicKey":"3p7bfXt9wbTTW2HC7OQ1Nz-DQ8hbeGdNrfx-FG-IK08","sharedSecret":"Sl2dW6TOLeFyjjv0gDUPJeB-IclH0Z4zdvCbPB4WF0I"}';

const HKDF_SHA256_VECTOR: string = '{"algorithm":"HKDF-SHA-256","source":"RFC 5869 test case 1","ikm":"CwsLCwsLCwsLCwsLCwsLCwsLCwsLCw","salt":"AAECAwQFBgcICQoLDA","info":"8PHy8_T19vf4-Q","length":42,"prk":"B3cJNiwuMt8N3D8NxHu6Y5C2xzu1D5wxIuyEStfCs-U","okm":"PLJfJfqs1XqQQ09k0DYvKi0tCpDPGlpMXbAtVuzExb80AHII1biHGFhl"}';

const AES_256_GCM_VECTOR: string = '{"algorithm":"AES-256-GCM","source":"Synthetic AES-256-GCM zero key/nonce/plaintext test-only vector","key":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","nonce":"AAAAAAAAAAAAAAAA","aad":"","plaintext":"AAAAAAAAAAAAAAAAAAAAAA","ciphertext":"zqdAPU1ga24HTsXTuvOdGA","tag":"0NHIp5mZa_AmW5i11Iq5GQ","tamperedTag":"0NHIp5mZa_AmW5i11Iq5GA"}';

const SESSION_KEYS_VECTOR: string = '{"algorithm":"EggClip-Session-Keys-v1","source":"Synthetic test-only session key derivation vector","sharedSecret":"Sl2dW6TOLeFyjjv0gDUPJeB-IclH0Z4zdvCbPB4WF0I","transcriptSalt":"RWdnQ2xpcCB2MSB0ZXN0IGhhbmRzaGFrZSBzYWx0","clientToServerInfo":"EggClip v1 session key client-to-server","serverToClientInfo":"EggClip v1 session key server-to-client","clientToServerKey":"_CuE_7SfzdShnxyzHQy4IJ0zQjMAUVq-tynBZ2lBPYQ","serverToClientKey":"TSo91xPhGNnQb2KPW6xyjJJFeHsimcUss0Rm2Tnbo2M","counter":12,"clientToServerNonce":"YzJzAQAAAAAAAAAM","serverToClientNonce":"czJjAQAAAAAAAAAM"}';

const REPLAY_COUNTER_VECTOR: string = '{"algorithm":"EggClip-Session-Counter-v1","accepted":[1,2,5],"rejected":[{"counter":2,"reason":"duplicate"},{"counter":4,"reason":"old"}]}';
