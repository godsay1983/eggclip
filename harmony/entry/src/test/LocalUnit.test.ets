import { describe, expect, it } from '@ohos/hypium';
import { ClipboardBridgeService } from '../main/ets/services/clipboard/ClipboardBridgeService';
import { WebSocketTransportService } from '../main/ets/services/transport/WebSocketTransportService';
import {
  ClipboardValidationError,
  EGGCLIP_MDNS_DISCOVERY_TYPE,
  EGGCLIP_MDNS_SERVICE_TYPE,
  POC_MAX_FRAME_BYTES
} from '../main/ets/models/PocModels';
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
  });
}
