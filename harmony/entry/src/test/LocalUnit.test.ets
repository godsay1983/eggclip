import { describe, expect, it } from '@ohos/hypium';
import { ClipboardBridgeService } from '../main/ets/services/clipboard/ClipboardBridgeService';
import { WebSocketTransportService } from '../main/ets/services/transport/WebSocketTransportService';
import {
  ClipboardValidationError,
  EGGCLIP_MDNS_DISCOVERY_TYPE,
  EGGCLIP_MDNS_SERVICE_TYPE,
  POC_MAX_FRAME_BYTES
} from '../main/ets/models/PocModels';
import {
  AeadAlgorithm,
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
  PROTOCOL_VERSION
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
  });
}

const CLIENT_HELLO_FIXTURE: string = '{"version":1,"type":"CLIENT_HELLO","messageId":"018ff6f0-2b1f-7cc5-b5d0-7e82c5f70f01","sessionCounter":0,"payload":{"spaceId":"018ff6ef-c394-7d08-8b99-4b7d10f2767a","deviceId":"018ff6f0-0a3b-7815-a4db-3eb6e23d9338","identityPublicKey":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","ephemeralPublicKey":"BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB","capabilities":["textPlain","syncHeads","itemBatch","itemLive"]}}';

const ENCRYPTED_ITEM_LIVE_FIXTURE: string = '{"version":1,"type":"ITEM_LIVE","messageId":"018ff6f3-0d8c-7d1e-a38a-f308c64de79f","sessionCounter":12,"ciphertext":{"algorithm":"AES-256-GCM","keyId":"session-v1-client-to-server","nonce":"DDDDDDDDDDDDDDDD","aad":"EEEEEEEEEEEEEEEE","body":"FFFFFFFFFFFFFFFF","tag":"GGGGGGGGGGGGGGGGGGGGGG"}}';

const CLIPBOARD_ITEM_FIXTURE: string = '{"itemId":"018ff6f3-3653-7c79-b38b-f4af3575396b","spaceId":"018ff6ef-c394-7d08-8b99-4b7d10f2767a","originDeviceId":"018ff6f0-0a3b-7815-a4db-3eb6e23d9338","originSeq":42,"hlc":"1781946000123:0:018ff6f0","contentType":"text/plain","contentLength":17,"contentDigest":"CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC","createdAt":1781946000123,"content":"EggClip test text"}';

const UNKNOWN_VERSION_FIXTURE: string = '{"version":2,"type":"CLIENT_HELLO","messageId":"018ff6f0-2b1f-7cc5-b5d0-7e82c5f70f01","sessionCounter":0,"payload":{}}';

const POST_AUTH_PLAINTEXT_FIXTURE: string = '{"version":1,"type":"ITEM_LIVE","messageId":"018ff6f3-0d8c-7d1e-a38a-f308c64de79f","sessionCounter":12,"payload":{"content":"must not be plaintext after auth"}}';

const PRE_AUTH_CIPHERTEXT_FIXTURE: string = '{"version":1,"type":"CLIENT_HELLO","messageId":"018ff6f0-2b1f-7cc5-b5d0-7e82c5f70f01","sessionCounter":0,"ciphertext":{"algorithm":"AES-256-GCM","keyId":"session-v1-client-to-server","nonce":"DDDDDDDDDDDDDDDD","aad":"EEEEEEEEEEEEEEEE","body":"FFFFFFFFFFFFFFFF","tag":"GGGGGGGGGGGGGGGGGGGGGG"}}';
