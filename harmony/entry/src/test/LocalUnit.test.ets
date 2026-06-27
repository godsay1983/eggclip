import { describe, expect, it } from '@ohos/hypium';
import { ClipboardBridgeService } from '../main/ets/services/clipboard/ClipboardBridgeService';
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
  AeadAlgorithm,
  AuthRole,
  ContentType,
  MessageType,
  ProtocolEnvelopeKind,
  ProtocolErrorCode,
  ProtocolParser,
  PROTOCOL_HANDSHAKE_TIMEOUT_SECONDS,
  PROTOCOL_HEARTBEAT_INTERVAL_SECONDS,
  PROTOCOL_IDLE_DISCONNECT_SECONDS,
  PROTOCOL_MAX_BATCH_ITEMS,
  PROTOCOL_MAX_BATCH_PLAINTEXT_BYTES,
  PROTOCOL_MAX_FRAME_BYTES,
  PROTOCOL_MAX_TEXT_BYTES,
  PROTOCOL_VERSION,
  canonicalAuthTranscript
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

    it('parsesProtocolEncryptedItemLiveFixture', 0, () => {
      const parser = new ProtocolParser();
      const result = parser.parseEnvelope(ENCRYPTED_ITEM_LIVE_FIXTURE);

      expect(result.ok).assertEqual(true);
      expect(result.envelope?.kind).assertEqual(ProtocolEnvelopeKind.ENCRYPTED);
      expect(result.envelope?.messageType).assertEqual(MessageType.ITEM_LIVE);
      expect(result.envelope?.sessionCounter).assertEqual(12);
      expect(result.envelope?.ciphertext?.algorithm).assertEqual(AeadAlgorithm.AES_256_GCM);
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

const ENCRYPTED_ITEM_LIVE_FIXTURE: string = '{"version":1,"type":"ITEM_LIVE","messageId":"018ff6f3-0d8c-7d1e-a38a-f308c64de79f","sessionCounter":12,"ciphertext":{"algorithm":"AES-256-GCM","keyId":"session-v1-client-to-server","nonce":"DDDDDDDDDDDDDDDD","aad":"EEEEEEEEEEEEEEEE","body":"FFFFFFFFFFFFFFFF","tag":"GGGGGGGGGGGGGGGGGGGGGG"}}';

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
