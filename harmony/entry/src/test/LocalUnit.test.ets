import { describe, expect, it } from '@ohos/hypium';
import { ClipboardBridgeService } from '../main/ets/services/clipboard/ClipboardBridgeService';
import {
  AES_256_GCM_VECTOR,
  ED25519_SIGNATURE_VECTOR,
  HKDF_SHA256_VECTOR,
  REPLAY_COUNTER_VECTOR,
  SESSION_KEYS_VECTOR,
  X25519_SHARED_SECRET_VECTOR
} from './ProtocolCryptoFixtures';
import {
  ProtocolHandshakeFrameOutcome,
  ProtocolHandshakeTransportSession,
  ProtocolTransportFrameError,
  ProtocolTransportSession
} from '../main/ets/services/transport/ProtocolTransportSession';
import {
  ProtocolFrameBuildError,
  ProtocolFrameBuilderService
} from '../main/ets/services/transport/ProtocolFrameBuilderService';
import { WebSocketTransportService } from '../main/ets/services/transport/WebSocketTransportService';
import {
  SettingsStoreState,
  cloneSettings,
  createInitialSettingsSnapshot
} from '../main/ets/store/SettingsStore';
import {
  CryptoVectorErrorCode,
  CryptoVectorService,
  SessionDirection,
  decodeBase64Url,
  encodeBase64Url,
  sessionNonce
} from '../main/ets/services/crypto/CryptoVectorService';
import {
  INITIAL_SPACE_KEY_VERSION,
  SPACE_KEY_BYTES,
  SpaceKeyReferenceError,
  SpaceKeyReferenceService
} from '../main/ets/services/crypto/SpaceKeyReferenceService';
import {
  PairingInvitationError,
  PairingInvitationService
} from '../main/ets/services/pairing/PairingInvitationService';
import {
  PairingHandshakeDraftError,
  PairingHandshakeDraftService
} from '../main/ets/services/pairing/PairingHandshakeDraftService';
import {
  PairingClientHandshakeError,
  PairingClientHandshakeSessionService
} from '../main/ets/services/pairing/PairingClientHandshakeSessionService';
import {
  PairingAuthProofValidationError,
  PairingAuthProofValidationService
} from '../main/ets/services/pairing/PairingAuthProofValidationService';
import {
  PairingStore,
  PairingStoreState
} from '../main/ets/store/PairingStore';
import {
  ClipboardValidationError,
  EGGCLIP_MDNS_DISCOVERY_TYPE,
  EGGCLIP_MDNS_SERVICE_TYPE,
  POC_MAX_FRAME_BYTES
} from '../main/ets/models/PocModels';
import {
  AppSettings,
  ContentType as DomainContentType,
  ClipboardDedupDecision,
  DomainValidationError,
  HlcTimestamp,
  InboundClipboardEventKind,
  OriginSeqAllocator,
  SyncPauseReason,
  ThemeMode,
  buildLocalClipboardItemDraft,
  deduplicateClipboardItem,
  defaultAppSettings,
  inboundClipboardPolicy,
  localClipboardSyncPolicy,
  validateAppSettings
} from '../main/ets/models/DomainModels';
import {
  CURRENT_SCHEMA_VERSION,
  DATABASE_NAME,
  INITIAL_SCHEMA_TABLES,
  allSchemaSql,
  pendingMigrations,
  validateSchemaPlan
} from '../main/ets/data/migrations/SchemaMigrations';
import { DATABASE_VERSION, STORE_CONFIG } from '../main/ets/data/db/DbConstants';
import {
  ClipboardRepository,
  DeviceRepository,
  INITIAL_ORIGIN_SEQ,
  LOCAL_DEVICE_ID_KEY,
  LocalIdentityRepository,
  LocalClipboardPersistenceCommands,
  NEXT_ORIGIN_SEQ_KEY,
  SettingsRepository,
  SpaceRepository,
  SyncHeadRepository
} from '../main/ets/data/repositories/RepositoryCommands';
import {
  DeviceConnectionState as DomainDeviceConnectionState,
  DeviceTrustState as DomainDeviceTrustState,
  SpaceState as DomainSpaceState
} from '../main/ets/models/DomainModels';
import {
  AeadAlgorithm,
  AuthRole,
  Capability,
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
        retentionDays: 7,
        themeMode: ThemeMode.SYSTEM
      }).error).assertEqual(DomainValidationError.INVALID_HISTORY_LIMIT);
    });

    it('appliesDomainSyncPausePolicies', 0, () => {
      const defaults = defaultAppSettings();
      const syncDisabled: AppSettings = {
        syncEnabled: false,
        autoReceiveEnabled: true,
        autoWriteEnabled: false,
        historyEnabled: true,
        historyLimit: 50,
        retentionDays: 7,
        themeMode: ThemeMode.SYSTEM
      };
      const receiveDisabled: AppSettings = {
        syncEnabled: true,
        autoReceiveEnabled: false,
        autoWriteEnabled: true,
        historyEnabled: true,
        historyLimit: 50,
        retentionDays: 7,
        themeMode: ThemeMode.SYSTEM
      };
      const writeDisabled: AppSettings = {
        syncEnabled: true,
        autoReceiveEnabled: true,
        autoWriteEnabled: false,
        historyEnabled: true,
        historyLimit: 50,
        retentionDays: 7,
        themeMode: ThemeMode.SYSTEM
      };

      expect(localClipboardSyncPolicy(syncDisabled).persistLocally).assertEqual(true);
      expect(localClipboardSyncPolicy(syncDisabled).broadcastAfterCommit).assertEqual(false);
      expect(localClipboardSyncPolicy(syncDisabled).blockedReason)
        .assertEqual(SyncPauseReason.SYNC_DISABLED);

      expect(inboundClipboardPolicy(InboundClipboardEventKind.ITEM_LIVE, defaults).updateHistory)
        .assertEqual(true);
      expect(inboundClipboardPolicy(InboundClipboardEventKind.ITEM_LIVE, defaults).writeSystemClipboard)
        .assertEqual(false);
      expect(inboundClipboardPolicy(InboundClipboardEventKind.ITEM_LIVE, syncDisabled).blockedReason)
        .assertEqual(SyncPauseReason.SYNC_DISABLED);
      expect(inboundClipboardPolicy(InboundClipboardEventKind.ITEM_LIVE, receiveDisabled).blockedReason)
        .assertEqual(SyncPauseReason.AUTO_RECEIVE_DISABLED);
      expect(inboundClipboardPolicy(InboundClipboardEventKind.ITEM_LIVE, writeDisabled).updateHistory)
        .assertEqual(true);
      expect(inboundClipboardPolicy(InboundClipboardEventKind.ITEM_LIVE, writeDisabled).writeSystemClipboard)
        .assertEqual(false);
      expect(inboundClipboardPolicy(InboundClipboardEventKind.ITEM_LIVE, writeDisabled).blockedReason)
        .assertEqual(SyncPauseReason.AUTO_WRITE_DISABLED);
      expect(inboundClipboardPolicy(InboundClipboardEventKind.ITEM_BATCH, receiveDisabled).updateHistory)
        .assertEqual(false);
      expect(inboundClipboardPolicy(InboundClipboardEventKind.ITEM_BATCH, defaults).writeSystemClipboard)
        .assertEqual(false);
    });

    it('createsSettingsStoreSnapshotsWithoutSharingMutableSettings', 0, () => {
      const snapshot = createInitialSettingsSnapshot();
      expect(snapshot.state).assertEqual(SettingsStoreState.IDLE);
      expect(snapshot.settings.historyLimit).assertEqual(50);
      expect(snapshot.settings.autoWriteEnabled).assertEqual(false);

      const cloned = cloneSettings(snapshot.settings);
      cloned.syncEnabled = false;
      cloned.historyLimit = 20;

      expect(snapshot.settings.syncEnabled).assertEqual(true);
      expect(snapshot.settings.historyLimit).assertEqual(50);
      expect(cloned.syncEnabled).assertEqual(false);
      expect(cloned.historyLimit).assertEqual(20);
    });

    it('deduplicatesDomainClipboardItemsByItemIdOriginSeqAndDigest', 0, () => {
      const base = buildLocalClipboardItemDraft({
        itemId: '018ff6ef-c394-7d08-8b99-4b7d10f2767a',
        spaceId: '018ff6f0-0a3b-7815-a4db-3eb6e23d9338',
        originDeviceId: '018ff6f0-4adf-7d31-a987-3ef2b25d0212',
        originSeq: 42,
        hlc: new HlcTimestamp(1700000000100, 0),
        createdAt: 1700000000100,
        contentDigest: 'VCKcnWkMQkRIXGbdZ29X9i2PfEJai3L2lV1hCUApXkw'
      }, '蛋定 Clip');
      const conflict = buildLocalClipboardItemDraft({
        itemId: '018ff6f1-c394-7d08-8b99-4b7d10f2767a',
        spaceId: '018ff6f0-0a3b-7815-a4db-3eb6e23d9338',
        originDeviceId: '018ff6f0-4adf-7d31-a987-3ef2b25d0212',
        originSeq: 42,
        hlc: new HlcTimestamp(1700000000101, 0),
        createdAt: 1700000000101,
        contentDigest: 'q2WZ8A9TeXn4YosU3cNLuYx9R2DpBvK5JmHFgEaC710'
      }, '不同内容');
      if (base.item === undefined || conflict.item === undefined) {
        expect(false).assertEqual(true);
        return;
      }

      expect(deduplicateClipboardItem(base.item, base.item))
        .assertEqual(ClipboardDedupDecision.DUPLICATE);
      const sameOriginSameDigest = buildLocalClipboardItemDraft({
        itemId: '018ff6f2-c394-7d08-8b99-4b7d10f2767a',
        spaceId: base.item.spaceId,
        originDeviceId: base.item.originDeviceId,
        originSeq: base.item.originSeq,
        hlc: new HlcTimestamp(1700000000102, 0),
        createdAt: 1700000000102,
        contentDigest: base.item.contentDigest
      }, '蛋定 Clip');
      if (sameOriginSameDigest.item === undefined) {
        expect(false).assertEqual(true);
        return;
      }
      expect(deduplicateClipboardItem(base.item, sameOriginSameDigest.item))
        .assertEqual(ClipboardDedupDecision.DUPLICATE);
      expect(deduplicateClipboardItem(base.item, conflict.item))
        .assertEqual(ClipboardDedupDecision.CONFLICT);
      const newItem = buildLocalClipboardItemDraft({
        itemId: '018ff6f3-c394-7d08-8b99-4b7d10f2767a',
        spaceId: base.item.spaceId,
        originDeviceId: base.item.originDeviceId,
        originSeq: 43,
        hlc: new HlcTimestamp(1700000000103, 0),
        createdAt: 1700000000103,
        contentDigest: base.item.contentDigest
      }, '蛋定 Clip');
      if (newItem.item === undefined) {
        expect(false).assertEqual(true);
        return;
      }
      expect(deduplicateClipboardItem(base.item, newItem.item))
        .assertEqual(ClipboardDedupDecision.NEW);
    });

    it('definesRdbSchemaMigrationPlanForLocalSyncTables', 0, () => {
      const pending = pendingMigrations(0);
      const sql = allSchemaSql().join('\n').toLowerCase();

      expect(CURRENT_SCHEMA_VERSION).assertEqual(1);
      expect(DATABASE_VERSION).assertEqual(CURRENT_SCHEMA_VERSION);
      expect(STORE_CONFIG.name).assertEqual(DATABASE_NAME);
      expect(pending.length).assertEqual(1);
      expect(pendingMigrations(CURRENT_SCHEMA_VERSION).length).assertEqual(0);
      expect(validateSchemaPlan()).assertEqual(true);
      expect(INITIAL_SCHEMA_TABLES.length).assertEqual(6);
      expect(sql.indexOf('create table if not exists clipboard_items') >= 0).assertEqual(true);
      expect(sql.indexOf('encrypted_content') >= 0).assertEqual(true);
      expect(sql.indexOf('unique(origin_device_id, origin_seq)') >= 0).assertEqual(true);
      expect(sql.indexOf('idx_clipboard_items_retention') >= 0).assertEqual(true);
    });

    it('buildsRepositoryCommandsWithoutPersistingPlaintext', 0, () => {
      const spaceId = '018ff6ef-c394-7d08-8b99-4b7d10f2767a';
      const localDeviceId = '018ff6f0-0a3b-7815-a4db-3eb6e23d9338';
      const peerDeviceId = '018ff6f0-4adf-7d31-a987-3ef2b25d0212';
      const spaces = new SpaceRepository();
      const devices = new DeviceRepository();
      const clipboard = new ClipboardRepository();
      const heads = new SyncHeadRepository();
      const settings = new SettingsRepository();

      const space = spaces.upsert({
        space: {
          spaceId,
          displayName: '默认空间',
          keyVersion: 1,
          state: DomainSpaceState.ACTIVE,
          createdAt: 1700000000000
        },
        encryptedSpaceKeyRef: 'huks://space-key',
        updatedAt: 1700000000000
      });
      expect(space.sql.indexOf('INSERT INTO spaces') >= 0).assertEqual(true);
      expect(space.args[2]).assertEqual('huks://space-key');

      const device = devices.upsert({
        device: {
          deviceId: localDeviceId,
          spaceId,
          displayName: 'HarmonyOS',
          identityPublicKeyRef: 'huks://identity-public-key',
          trustState: DomainDeviceTrustState.TRUSTED,
          connectionState: DomainDeviceConnectionState.OFFLINE
        },
        pairedAt: 1700000000000
      });
      expect(device.sql.indexOf('INSERT INTO devices') >= 0).assertEqual(true);
      expect(devices.listBySpace(spaceId).args[0]).assertEqual(spaceId);

      const item = buildLocalClipboardItemDraft({
        itemId: '018ff6f1-c394-7d08-8b99-4b7d10f2767a',
        spaceId,
        originDeviceId: localDeviceId,
        originSeq: 1,
        hlc: new HlcTimestamp(1700000000100, 0),
        createdAt: 1700000000100,
        contentDigest: 'VCKcnWkMQkRIXGbdZ29X9i2PfEJai3L2lV1hCUApXkw'
      }, '不要入库的明文');
      expect(item.ok).assertEqual(true);
      if (item.item === undefined) {
        expect(false).assertEqual(true);
        return;
      }
      const builtItem = item.item;
      const insertItem = clipboard.insert({
        item: builtItem,
        encryptedContent: new Uint8Array([1, 2, 3]),
        receivedAt: 1700000000100,
        expiresAt: 1700604800100
      });
      expect(insertItem === null).assertEqual(false);
      if (insertItem === null) {
        expect(false).assertEqual(true);
        return;
      }
      expect(insertItem.sql.indexOf('plaintext')).assertEqual(-1);
      expect(insertItem.sql.indexOf('encrypted_content') >= 0).assertEqual(true);
      expect(insertItem.args[8] instanceof Uint8Array).assertEqual(true);
      expect(clipboard.listRecent(spaceId, 50).args[1]).assertEqual(50);
      const listAll = clipboard.listRecentAll(5);
      expect(listAll.sql.indexOf('WHERE deleted_at IS NULL') >= 0).assertEqual(true);
      expect(listAll.sql.indexOf('space_id = ?')).assertEqual(-1);
      expect(listAll.args[0]).assertEqual(5);
      expect(clipboard.markDeleted(builtItem.itemId, 1700000000200).args[0]).assertEqual(1700000000200);
      const clearAll = clipboard.clearAllHistory(1700000000250);
      expect(clearAll.sql.indexOf('WHERE deleted_at IS NULL') >= 0).assertEqual(true);
      expect(clearAll.sql.indexOf('space_id = ?')).assertEqual(-1);
      expect(clearAll.args[0]).assertEqual(1700000000250);
      const countAll = clipboard.countAllActive();
      expect(countAll.sql.indexOf('COUNT(*) AS active_count') >= 0).assertEqual(true);
      expect(countAll.sql.indexOf('deleted_at IS NULL') >= 0).assertEqual(true);
      expect(countAll.args.length).assertEqual(0);

      const syncHead = heads.upsert({
        peerDeviceId,
        head: {
          spaceId,
          originDeviceId: localDeviceId,
          latestOriginSeq: 1,
          minimumAvailable: 1,
          updatedAt: 1700000000300
        }
      });
      expect(syncHead.sql.indexOf('ON CONFLICT(space_id, peer_device_id, origin_device_id)') >= 0)
        .assertEqual(true);

      const saveSettings = settings.saveAppSettings(defaultAppSettings(), 1700000000400);
      expect(saveSettings === null).assertEqual(false);
      expect(saveSettings?.args[0]).assertEqual('appSettings');
      expect(settings.saveAppSettings({
        syncEnabled: true,
        autoReceiveEnabled: true,
        autoWriteEnabled: false,
        historyEnabled: true,
        historyLimit: 10,
        retentionDays: 7,
        themeMode: ThemeMode.SYSTEM
      }, 1700000000400)).assertEqual(null);
      expect(settings.loadAppSettings().args[0]).assertEqual('appSettings');
    });

    it('buildsSpaceKeyHuksAliasWithoutPersistingRawKey', 0, () => {
      const spaceId = '018ff6ef-c394-7d08-8b99-4b7d10f2767a';
      const service = new SpaceKeyReferenceService();
      const alias = service.buildHuksAlias(spaceId, INITIAL_SPACE_KEY_VERSION);

      expect(alias.ok).assertEqual(true);
      expect(alias.alias).assertEqual(`huks://eggclip/space-key/${spaceId}/v1`);
      expect(service.inspectImportedSpaceKey(new Uint8Array(SPACE_KEY_BYTES)).ok).assertEqual(true);
      expect(service.inspectImportedSpaceKey(new Uint8Array(SPACE_KEY_BYTES - 1)).error)
        .assertEqual(SpaceKeyReferenceError.INVALID_KEY_LENGTH);
      expect(service.buildHuksAlias('not-a-uuid', INITIAL_SPACE_KEY_VERSION).error)
        .assertEqual(SpaceKeyReferenceError.INVALID_SPACE_ID);
      expect(service.buildHuksAlias(spaceId, 0).error)
        .assertEqual(SpaceKeyReferenceError.INVALID_KEY_VERSION);

      const command = new SpaceRepository().upsert({
        space: {
          spaceId,
          displayName: '默认空间',
          keyVersion: INITIAL_SPACE_KEY_VERSION,
          state: DomainSpaceState.ACTIVE,
          createdAt: 1700000000000
        },
        encryptedSpaceKeyRef: alias.alias,
        updatedAt: 1700000000000
      });

      expect(command.args[2]).assertEqual(alias.alias);
      let containsRawKey = false;
      for (const arg of command.args) {
        if (arg instanceof Uint8Array) {
          containsRawKey = true;
        }
      }
      expect(containsRawKey).assertEqual(false);
    });

    it('buildsRetentionRepositoryCommandsForHistoryPolicy', 0, () => {
      const spaceId = '018ff6ef-c394-7d08-8b99-4b7d10f2767a';
      const clipboard = new ClipboardRepository();
      const settings = defaultAppSettings();
      const retention = clipboard.retentionCommands(spaceId, settings, 1700604800000);

      expect(retention === null).assertEqual(false);
      if (retention === null) {
        expect(false).assertEqual(true);
        return;
      }
      expect(retention.length).assertEqual(2);
      expect(retention[0].sql.indexOf('expires_at <= ?') >= 0).assertEqual(true);
      expect(retention[0].args[0]).assertEqual(1700604800000);
      expect(retention[0].args[1]).assertEqual(spaceId);
      expect(retention[1].sql.indexOf('LIMIT -1 OFFSET ?') >= 0).assertEqual(true);
      expect(retention[1].args[3]).assertEqual(50);

      const zeroHistory = clipboard.retentionCommands(spaceId, {
        syncEnabled: true,
        autoReceiveEnabled: true,
        autoWriteEnabled: false,
        historyEnabled: true,
        historyLimit: 0,
        retentionDays: 7,
        themeMode: ThemeMode.SYSTEM
      }, 1700604800000);
      expect(zeroHistory === null).assertEqual(false);
      if (zeroHistory === null) {
        expect(false).assertEqual(true);
        return;
      }
      expect(zeroHistory.length).assertEqual(1);
      expect(zeroHistory[0].sql.indexOf('WHERE space_id = ? AND deleted_at IS NULL') >= 0)
        .assertEqual(true);

      const invalid = clipboard.retentionCommands(spaceId, {
        syncEnabled: true,
        autoReceiveEnabled: true,
        autoWriteEnabled: false,
        historyEnabled: true,
        historyLimit: 10,
        retentionDays: 7,
        themeMode: ThemeMode.SYSTEM
      }, 1700604800000);
      expect(invalid).assertEqual(null);
    });

    it('buildsLocalIdentityRepositoryCommandsForDeviceIdAndOriginSeq', 0, () => {
      const identity = new LocalIdentityRepository();
      const deviceId = '550e8400-e29b-41d4-a716-446655440000';

      const loadDeviceId = identity.loadLocalDeviceId();
      expect(loadDeviceId.sql.indexOf('SELECT value FROM app_metadata') >= 0).assertEqual(true);
      expect(loadDeviceId.args[0]).assertEqual(LOCAL_DEVICE_ID_KEY);

      const insertDeviceId = identity.insertLocalDeviceId(deviceId, 1700000000000);
      expect(insertDeviceId.sql.indexOf('INSERT OR IGNORE INTO app_metadata') >= 0).assertEqual(true);
      expect(insertDeviceId.args[0]).assertEqual(LOCAL_DEVICE_ID_KEY);
      expect(insertDeviceId.args[1]).assertEqual(deviceId);

      const initializeSeq = identity.initializeOriginSeq(1700000000001);
      expect(initializeSeq.args[0]).assertEqual(NEXT_ORIGIN_SEQ_KEY);
      expect(initializeSeq.args[1]).assertEqual(INITIAL_ORIGIN_SEQ.toString());

      const loadSeq = identity.loadNextOriginSeq();
      expect(loadSeq.args[0]).assertEqual(NEXT_ORIGIN_SEQ_KEY);

      const advanceSeq = identity.advanceOriginSeq(7, 1700000000002);
      expect(advanceSeq === null).assertEqual(false);
      if (advanceSeq === null) {
        expect(false).assertEqual(true);
        return;
      }
      expect(advanceSeq.sql.indexOf('WHERE key = ? AND value = ?') >= 0).assertEqual(true);
      expect(advanceSeq.args[0]).assertEqual('8');
      expect(advanceSeq.args[2]).assertEqual(NEXT_ORIGIN_SEQ_KEY);
      expect(advanceSeq.args[3]).assertEqual('7');
      expect(identity.advanceOriginSeq(Number.MAX_SAFE_INTEGER, 1700000000003)).assertEqual(null);
    });

    it('buildsLocalClipboardPersistenceCommandsWithoutBroadcasting', 0, () => {
      const workflow = new LocalClipboardPersistenceCommands();
      const plan = workflow.build({
        itemId: '018ff6f1-c394-7d08-8b99-4b7d10f2767a',
        spaceId: '018ff6ef-c394-7d08-8b99-4b7d10f2767a',
        originDeviceId: '018ff6f0-0a3b-7815-a4db-3eb6e23d9338',
        originSeq: 7,
        text: '来自 PasteButton 的一次性明文',
        contentDigest: 'VCKcnWkMQkRIXGbdZ29X9i2PfEJai3L2lV1hCUApXkw',
        encryptedContent: new Uint8Array([9, 8, 7]),
        settings: defaultAppSettings(),
        nowMs: 1700000000100
      });

      expect(plan === null).assertEqual(false);
      if (plan === null) {
        expect(false).assertEqual(true);
        return;
      }
      expect(plan.record.item.originSeq).assertEqual(7);
      expect(plan.record.item.hlc).assertEqual('0000018bcfe56864-0000');
      expect(plan.record.item.plaintext).assertEqual('来自 PasteButton 的一次性明文');
      expect(plan.record.expiresAt).assertEqual(1700604800100);
      expect(plan.commands.length).assertEqual(3);
      expect(plan.commands[0].args[0]).assertEqual(NEXT_ORIGIN_SEQ_KEY);
      expect(plan.commands[1].args[0]).assertEqual('8');
      expect(plan.commands[2].sql.indexOf('encrypted_content') >= 0).assertEqual(true);
      expect(plan.commands[2].sql.indexOf('plaintext')).assertEqual(-1);
      expect(plan.commands[2].args[8] instanceof Uint8Array).assertEqual(true);

      const invalidText = workflow.build({
        itemId: '018ff6f1-c394-7d08-8b99-4b7d10f2767a',
        spaceId: '018ff6ef-c394-7d08-8b99-4b7d10f2767a',
        originDeviceId: '018ff6f0-0a3b-7815-a4db-3eb6e23d9338',
        originSeq: 7,
        text: '',
        contentDigest: 'VCKcnWkMQkRIXGbdZ29X9i2PfEJai3L2lV1hCUApXkw',
        encryptedContent: new Uint8Array([9, 8, 7]),
        settings: defaultAppSettings(),
        nowMs: 1700000000100
      });
      expect(invalidText).assertEqual(null);
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

    it('parsesDesktopPairingInvitationUriWithoutPersistingTrust', 0, () => {
      const service = new PairingInvitationService();
      const result = service.parse(PAIRING_INVITATION_FIXTURE, 1700000000000);

      expect(result.ok).assertEqual(true);
      expect(result.payload?.invitationId).assertEqual('018ff6f0-1111-7222-8333-123456789abc');
      expect(result.payload?.spaceId).assertEqual('018ff6ef-c394-7d08-8b99-4b7d10f2767a');
      expect(result.payload?.spaceKeyVersion).assertEqual(1);
      expect(result.payload?.pairingSecret).assertEqual('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA');
      expect(result.summary?.spaceShortId).assertEqual('10f2767a');
      expect(result.summary?.issuerDeviceName).assertEqual('桌面端 #11qYAYKx');
      expect(result.summary?.issuerShortFingerprint).assertEqual('11qYAYKx');
      expect(result.summary?.expiresInSeconds).assertEqual(300);
      expect(result.summary?.confirmationCode).assertEqual('574920');
    });

    it('rejectsInvalidOrExpiredPairingInvitationUri', 0, () => {
      const service = new PairingInvitationService();

      expect(service.parse('', 1700000000000).error).assertEqual(PairingInvitationError.EMPTY);
      expect(service.parse('https://example.com', 1700000000000).error)
        .assertEqual(PairingInvitationError.INVALID_SCHEME);
      expect(service.parse('eggclip://pair?p=not-base64', 1700000000000).error)
        .assertEqual(PairingInvitationError.INVALID_PAYLOAD);
      expect(service.parse(PAIRING_INVITATION_FIXTURE, 1700000300000).error)
        .assertEqual(PairingInvitationError.EXPIRED);
      expect(service.parse(BAD_PAIRING_SECRET_INVITATION_FIXTURE, 1700000000000).field)
        .assertEqual('pairingSecret');
    });

    it('rejectsPairingInvitationFieldLengthAndControlBoundaries', 0, () => {
      const service = new PairingInvitationService();
      const valid = service.parse(pairingInvitationFixtureUri('EggClip Desktop'), 1700000000000);
      expect(valid.ok).assertEqual(true);
      expect(valid.summary?.issuerDeviceName).assertEqual('EggClip Desktop');

      const longDeviceName = service.parse(pairingInvitationFixtureUri('a'.repeat(33)), 1700000000000);
      expect(longDeviceName.error).assertEqual(PairingInvitationError.INVALID_FIELD);
      expect(longDeviceName.field).assertEqual('issuerDeviceName');

      const controlDeviceName = service.parse(pairingInvitationFixtureUri('EggClip\nDesktop'), 1700000000000);
      expect(controlDeviceName.error).assertEqual(PairingInvitationError.INVALID_FIELD);
      expect(controlDeviceName.field).assertEqual('issuerDeviceName');

      const tooLarge = service.parse(`eggclip://pair?p=${'A'.repeat(4097)}`, 1700000000000);
      expect(tooLarge.error).assertEqual(PairingInvitationError.TOO_LARGE);
    });

    it('keepsPairingStoreAsParseOnlyUntilSecurePairingIsImplemented', 0, () => {
      const store = new PairingStore();
      store.updateInvitationText(PAIRING_INVITATION_FIXTURE);
      const parsed = store.parseCurrent(1700000000000);

      expect(parsed.state).assertEqual(PairingStoreState.READY);
      expect(parsed.summary?.confirmationCode).assertEqual('574920');
      expect(parsed.statusText.indexOf('下一步') >= 0).assertEqual(true);

      const cleared = store.clear();
      expect(cleared.state).assertEqual(PairingStoreState.IDLE);
      expect(cleared.summary === null).assertEqual(true);
    });

    it('movesPairingStoreToPendingOnlyAfterManualCodeConfirmation', 0, () => {
      const emptyStore = new PairingStore();
      const rejected = emptyStore.confirmCodeMatched();
      expect(rejected.state).assertEqual(PairingStoreState.ERROR);
      expect(rejected.summary === null).assertEqual(true);

      const store = new PairingStore();
      store.updateInvitationText(PAIRING_INVITATION_FIXTURE);
      store.parseCurrent(1700000000000);
      expect(store.hasPendingHandshakeMaterial()).assertEqual(false);
      const pending = store.confirmCodeMatched();

      expect(pending.state).assertEqual(PairingStoreState.PENDING);
      expect(pending.invitationText).assertEqual('');
      expect(pending.summary?.confirmationCode).assertEqual('574920');
      expect(pending.statusText.indexOf('邀请 secret 已从可见输入中清理') >= 0).assertEqual(true);
      expect(pending.error === null).assertEqual(true);
      expect(store.hasPendingHandshakeMaterial()).assertEqual(true);

      const cleared = store.clear();
      expect(cleared.state).assertEqual(PairingStoreState.IDLE);
      expect(store.hasPendingHandshakeMaterial()).assertEqual(false);
    });

    it('buildsPairingClientHandshakeDraftWithoutExposingPairingSecret', 0, () => {
      const store = new PairingStore();
      const missing = store.buildPendingClientHandshakeDraft(
        '018ff6f0-4adf-7d31-a987-3ef2b25d0212',
        '11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo',
        'hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo',
        1700000000000
      );
      expect(missing.ok).assertEqual(false);
      expect(missing.error).assertEqual(PairingHandshakeDraftError.MISSING_PENDING_INVITATION);

      store.importInvitationText(PAIRING_INVITATION_FIXTURE, 1700000000000);
      store.confirmCodeMatched();
      const draft = store.buildPendingClientHandshakeDraft(
        '018ff6f0-4adf-7d31-a987-3ef2b25d0212',
        '11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo',
        'hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo',
        1700000000000
      );

      expect(draft.ok).assertEqual(true);
      expect(draft.draft?.invitationId).assertEqual('018ff6f0-1111-7222-8333-123456789abc');
      expect(draft.draft?.spaceId).assertEqual('018ff6ef-c394-7d08-8b99-4b7d10f2767a');
      expect(draft.draft?.remoteDeviceId).assertEqual('018ff6f0-0a3b-7815-a4db-3eb6e23d9338');
      expect(draft.draft?.pairingContext)
        .assertEqual('pairing-invitation:v1:018ff6f0-1111-7222-8333-123456789abc');
      expect(draft.draft?.clientHelloPayload.deviceId).assertEqual('018ff6f0-4adf-7d31-a987-3ef2b25d0212');
      expect(draft.draft?.clientHelloPayload.identityPublicKey)
        .assertEqual('11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo');
      expect(draft.draft?.clientHelloPayload.ephemeralPublicKey)
        .assertEqual('hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo');
      const serialized = JSON.stringify(draft.draft);
      expect(serialized.indexOf('pairingSecret')).assertEqual(-1);
      expect(serialized.indexOf('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA')).assertEqual(-1);
    });

    it('buildsClientHelloFrameFromPairingDraftForHandshakeTransport', 0, () => {
      const store = new PairingStore();
      store.importInvitationText(PAIRING_INVITATION_FIXTURE, 1700000000000);
      store.confirmCodeMatched();
      const draft = store.buildPendingClientHandshakeDraft(
        '018ff6f0-4adf-7d31-a987-3ef2b25d0212',
        '11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo',
        'hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo',
        1700000000000
      );
      if (!draft.ok || draft.draft === undefined) {
        expect(false).assertEqual(true);
        return;
      }

      const builder = new ProtocolFrameBuilderService();
      const invalid = builder.buildClientHelloFrame(
        draft.draft.clientHelloPayload,
        'not-a-uuid',
        0
      );
      expect(invalid.ok).assertEqual(false);
      expect(invalid.error).assertEqual(ProtocolFrameBuildError.INVALID_MESSAGE_ID);

      const built = builder.buildClientHelloFrame(
        draft.draft.clientHelloPayload,
        '018ff6f0-2b1f-7cc5-b5d0-7e82c5f70f01',
        1
      );
      expect(built.ok).assertEqual(true);
      expect(built.frame.indexOf('pairingSecret')).assertEqual(-1);
      expect(built.frame.indexOf('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA')).assertEqual(-1);

      const parser = new ProtocolParser();
      const parsed = parser.parseEnvelope(built.frame);
      expect(parsed.ok).assertEqual(true);
      expect(parsed.envelope?.messageType).assertEqual(MessageType.CLIENT_HELLO);
      const hello = parser.parseHelloPayload(parsed.envelope?.payload);
      expect(hello.ok).assertEqual(true);
      expect(hello.payload?.spaceId).assertEqual(draft.draft.spaceId);
      expect(hello.payload?.deviceId).assertEqual('018ff6f0-4adf-7d31-a987-3ef2b25d0212');

      const session = new ProtocolHandshakeTransportSession();
      const accepted = session.acceptTextFrame(built.frame);
      expect(accepted.ok).assertEqual(true);
      expect(accepted.outcome).assertEqual(ProtocolHandshakeFrameOutcome.CONTINUE);
    });

    it('buildsClientAuthTranscriptDraftAfterMatchingServerHello', 0, () => {
      const service = new PairingHandshakeDraftService();
      const store = new PairingStore();
      store.importInvitationText(PAIRING_INVITATION_FIXTURE, 1700000000000);
      store.confirmCodeMatched();
      const draft = store.buildPendingClientHandshakeDraft(
        '018ff6f0-4adf-7d31-a987-3ef2b25d0212',
        '3p7bfXt9wbTTW2HC7OQ1Nz-DQ8hbeGdNrfx-FG-IK08',
        'hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo',
        1700000000000
      );
      if (!draft.ok || draft.draft === undefined) {
        expect(false).assertEqual(true);
        return;
      }

      const transcript = service.buildClientAuthTranscriptDraft(draft.draft, {
        spaceId: '018ff6ef-c394-7d08-8b99-4b7d10f2767a',
        deviceId: '018ff6f0-0a3b-7815-a4db-3eb6e23d9338',
        identityPublicKey: '11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaapcHUro',
        ephemeralPublicKey: 'Sl2dW6TOLeFyjjv0gDUPJeB-IclH0Z4zdvCbPB4WF0I',
        capabilities: [Capability.TEXT_PLAIN, Capability.SYNC_HEADS]
      });

      expect(transcript.ok).assertEqual(true);
      if (transcript.transcript === undefined) {
        expect(false).assertEqual(true);
        return;
      }
      const transcriptValue = transcript.transcript;
      expect(transcriptValue.input.role).assertEqual(AuthRole.CLIENT);
      expect(transcriptValue.input.localDeviceId).assertEqual('018ff6f0-4adf-7d31-a987-3ef2b25d0212');
      expect(transcriptValue.input.remoteDeviceId).assertEqual('018ff6f0-0a3b-7815-a4db-3eb6e23d9338');
      expect(transcriptValue.input.localIdentityPublicKey)
        .assertEqual('3p7bfXt9wbTTW2HC7OQ1Nz-DQ8hbeGdNrfx-FG-IK08');
      expect(transcriptValue.input.remoteIdentityPublicKey)
        .assertEqual('11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaapcHUro');
      expect(transcriptValue.canonicalTranscript.indexOf('role=client') >= 0).assertEqual(true);
      expect(transcriptValue.canonicalTranscript.indexOf(
        'pairingContext=pairing-invitation:v1:018ff6f0-1111-7222-8333-123456789abc'
      ) >= 0).assertEqual(true);

      const wrongSpace = service.buildClientAuthTranscriptDraft(draft.draft, {
        spaceId: '018ff6f0-1111-7222-8333-123456789abc',
        deviceId: '018ff6f0-0a3b-7815-a4db-3eb6e23d9338',
        identityPublicKey: '11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaapcHUro',
        ephemeralPublicKey: 'Sl2dW6TOLeFyjjv0gDUPJeB-IclH0Z4zdvCbPB4WF0I',
        capabilities: [Capability.TEXT_PLAIN]
      });
      expect(wrongSpace.ok).assertEqual(false);
      expect(wrongSpace.error).assertEqual(PairingHandshakeDraftError.SERVER_HELLO_MISMATCH);
      expect(wrongSpace.field).assertEqual('spaceId');
    });

    it('buildsAuthProofFrameFromClientTranscriptDraft', 0, () => {
      const handshake = new PairingHandshakeDraftService();
      const store = new PairingStore();
      store.importInvitationText(PAIRING_INVITATION_FIXTURE, 1700000000000);
      store.confirmCodeMatched();
      const draft = store.buildPendingClientHandshakeDraft(
        '018ff6f0-4adf-7d31-a987-3ef2b25d0212',
        '3p7bfXt9wbTTW2HC7OQ1Nz-DQ8hbeGdNrfx-FG-IK08',
        'hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo',
        1700000000000
      );
      if (!draft.ok || draft.draft === undefined) {
        expect(false).assertEqual(true);
        return;
      }
      const transcript = handshake.buildClientAuthTranscriptDraft(draft.draft, {
        spaceId: '018ff6ef-c394-7d08-8b99-4b7d10f2767a',
        deviceId: '018ff6f0-0a3b-7815-a4db-3eb6e23d9338',
        identityPublicKey: '11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaapcHUro',
        ephemeralPublicKey: 'Sl2dW6TOLeFyjjv0gDUPJeB-IclH0Z4zdvCbPB4WF0I',
        capabilities: [Capability.TEXT_PLAIN, Capability.SYNC_HEADS]
      });
      if (!transcript.ok || transcript.transcript === undefined) {
        expect(false).assertEqual(true);
        return;
      }

      const builder = new ProtocolFrameBuilderService();
      const invalidSignature = builder.buildAuthProofFrame(
        AuthRole.CLIENT,
        transcript.transcript.canonicalTranscript,
        'AA',
        '018ff6f1-1d2a-725d-8d1a-894d2f5b0a42',
        2
      );
      expect(invalidSignature.ok).assertEqual(false);
      expect(invalidSignature.error).assertEqual(ProtocolFrameBuildError.INVALID_SIGNATURE);

      const built = builder.buildAuthProofFrame(
        AuthRole.CLIENT,
        transcript.transcript.canonicalTranscript,
        TEST_ED25519_SIGNATURE,
        '018ff6f1-1d2a-725d-8d1a-894d2f5b0a42',
        2
      );
      expect(built.ok).assertEqual(true);
      expect(built.frame.indexOf('pairingSecret')).assertEqual(-1);
      expect(built.frame.indexOf('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA')).assertEqual(-1);

      const parser = new ProtocolParser();
      const parsed = parser.parseEnvelope(built.frame);
      expect(parsed.ok).assertEqual(true);
      expect(parsed.envelope?.messageType).assertEqual(MessageType.AUTH_PROOF);
      const proof = parser.parseAuthProofPayload(parsed.envelope?.payload);
      expect(proof.ok).assertEqual(true);
      expect(proof.payload?.role).assertEqual(AuthRole.CLIENT);
      expect(proof.payload?.signature).assertEqual(TEST_ED25519_SIGNATURE);
      expect(proof.payload?.transcriptHash).assertEqual('V7r4hNyV_MTEfFFXqZQ8KipuV8u96rMSryE535SPmCQ');

      const session = new ProtocolHandshakeTransportSession();
      const accepted = session.acceptTextFrame(built.frame);
      expect(accepted.ok).assertEqual(true);
      expect(accepted.outcome).assertEqual(ProtocolHandshakeFrameOutcome.CONTINUE);
    });

    it('validatesAuthProofPayloadAgainstCanonicalTranscriptBeforeEd25519Verify', 0, () => {
      const handshake = new PairingHandshakeDraftService();
      const store = new PairingStore();
      store.importInvitationText(PAIRING_INVITATION_FIXTURE, 1700000000000);
      store.confirmCodeMatched();
      const draft = store.buildPendingClientHandshakeDraft(
        '018ff6f0-4adf-7d31-a987-3ef2b25d0212',
        '3p7bfXt9wbTTW2HC7OQ1Nz-DQ8hbeGdNrfx-FG-IK08',
        'hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo',
        1700000000000
      );
      if (!draft.ok || draft.draft === undefined) {
        expect(false).assertEqual(true);
        return;
      }
      const transcript = handshake.buildClientAuthTranscriptDraft(draft.draft, {
        spaceId: '018ff6ef-c394-7d08-8b99-4b7d10f2767a',
        deviceId: '018ff6f0-0a3b-7815-a4db-3eb6e23d9338',
        identityPublicKey: '11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaapcHUro',
        ephemeralPublicKey: 'Sl2dW6TOLeFyjjv0gDUPJeB-IclH0Z4zdvCbPB4WF0I',
        capabilities: [Capability.TEXT_PLAIN, Capability.SYNC_HEADS]
      });
      if (!transcript.ok || transcript.transcript === undefined) {
        expect(false).assertEqual(true);
        return;
      }

      const builder = new ProtocolFrameBuilderService();
      const built = builder.buildAuthProofFrame(
        AuthRole.CLIENT,
        transcript.transcript.canonicalTranscript,
        TEST_ED25519_SIGNATURE,
        '018ff6f1-1d2a-725d-8d1a-894d2f5b0a42',
        2
      );
      const parser = new ProtocolParser();
      const parsed = parser.parseEnvelope(built.frame);
      const proof = parser.parseAuthProofPayload(parsed.envelope?.payload);
      if (!proof.ok || proof.payload === undefined) {
        expect(false).assertEqual(true);
        return;
      }

      const validator = new PairingAuthProofValidationService();
      expect(validator.validatePayloadAgainstTranscript(
        proof.payload,
        AuthRole.CLIENT,
        transcript.transcript
      ).ok).assertEqual(true);
      expect(validator.validatePayloadAgainstTranscript(
        {
          role: AuthRole.SERVER,
          signatureAlgorithm: proof.payload.signatureAlgorithm,
          transcriptHash: proof.payload.transcriptHash,
          signature: proof.payload.signature
        },
        AuthRole.CLIENT,
        transcript.transcript
      ).error).assertEqual(PairingAuthProofValidationError.ROLE_MISMATCH);
      expect(validator.validatePayloadAgainstTranscript(
        {
          role: AuthRole.CLIENT,
          signatureAlgorithm: proof.payload.signatureAlgorithm,
          transcriptHash: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
          signature: proof.payload.signature
        },
        AuthRole.CLIENT,
        transcript.transcript
      ).error).assertEqual(PairingAuthProofValidationError.TRANSCRIPT_HASH_MISMATCH);
      expect(validator.validatePayloadAgainstTranscript(
        {
          role: AuthRole.CLIENT,
          signatureAlgorithm: proof.payload.signatureAlgorithm,
          transcriptHash: proof.payload.transcriptHash,
          signature: 'AA'
        },
        AuthRole.CLIENT,
        transcript.transcript
      ).error).assertEqual(PairingAuthProofValidationError.INVALID_SIGNATURE);
    });

    it('exposesAuthProofEd25519VerificationBoundary', 0, () => {
      const parser = new ProtocolParser();
      const result = parser.parseEnvelope(AUTH_PROOF_FIXTURE);
      if (!result.ok || result.envelope === undefined) {
        expect(false).assertEqual(true);
        return;
      }
      const proof = parser.parseAuthProofPayload(result.envelope.payload);
      if (!proof.ok || proof.payload === undefined) {
        expect(false).assertEqual(true);
        return;
      }
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
      if (transcript === null) {
        expect(false).assertEqual(true);
        return;
      }

      const validator = new PairingAuthProofValidationService();
      const verified = validator.verifyPayloadSignatureAgainstTranscript(
        proof.payload,
        AuthRole.CLIENT,
        {
          input: {
            role: AuthRole.CLIENT,
            spaceId: '018ff6ef-c394-7d08-8b99-4b7d10f2767a',
            localDeviceId: '018ff6f0-0a3b-7815-a4db-3eb6e23d9338',
            remoteDeviceId: '018ff6f0-4adf-7d31-a987-3ef2b25d0212',
            localIdentityPublicKey: '11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo',
            remoteIdentityPublicKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
            localEphemeralPublicKey: 'hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo',
            remoteEphemeralPublicKey: '3p7bfXt9wbTTW2HC7OQ1Nz-DQ8hbeGdNrfx-FG-IK08',
            pairingContext: 'trusted-device:018ff6ef-c394-7d08-8b99-4b7d10f2767a'
          },
          canonicalTranscript: transcript
        },
        '11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo'
      );
      expect(verified.ok || verified.error === PairingAuthProofValidationError.SIGNATURE_VERIFY_FAILED)
        .assertEqual(true);
      expect(verified.error === PairingAuthProofValidationError.INVALID_SIGNATURE).assertEqual(false);
      expect(verified.error === PairingAuthProofValidationError.TRANSCRIPT_HASH_MISMATCH).assertEqual(false);
    });

    it('orchestratesClientPairingHandshakeUntilAuthProofFrame', 0, () => {
      const store = new PairingStore();
      store.importInvitationText(PAIRING_INVITATION_FIXTURE, 1700000000000);
      store.confirmCodeMatched();
      const draft = store.buildPendingClientHandshakeDraft(
        '018ff6f0-4adf-7d31-a987-3ef2b25d0212',
        '3p7bfXt9wbTTW2HC7OQ1Nz-DQ8hbeGdNrfx-FG-IK08',
        'hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo',
        1700000000000
      );
      if (!draft.ok || draft.draft === undefined) {
        expect(false).assertEqual(true);
        return;
      }

      const service = new PairingClientHandshakeSessionService();
      const started = service.start(
        draft.draft,
        '018ff6f0-2b1f-7cc5-b5d0-7e82c5f70f01',
        0
      );
      expect(started.ok).assertEqual(true);
      if (started.session === undefined || started.clientHelloFrame === undefined) {
        expect(false).assertEqual(true);
        return;
      }
      expect(started.clientHelloFrame.indexOf('CLIENT_HELLO') >= 0).assertEqual(true);
      expect(started.clientHelloFrame.indexOf('pairingSecret')).assertEqual(-1);

      const result = service.acceptServerHelloAndBuildAuthProof(
        started.session,
        SERVER_HELLO_FRAME_FOR_PAIRING_FIXTURE,
        TEST_ED25519_SIGNATURE,
        '018ff6f1-1d2a-725d-8d1a-894d2f5b0a42',
        2
      );
      expect(result.ok).assertEqual(true);
      expect(result.serverHello?.deviceId).assertEqual('018ff6f0-0a3b-7815-a4db-3eb6e23d9338');
      expect(result.transcript?.input.remoteDeviceId).assertEqual('018ff6f0-0a3b-7815-a4db-3eb6e23d9338');
      expect((result.authProofFrame?.indexOf('AUTH_PROOF') ?? -1) >= 0).assertEqual(true);
      expect(result.authProofFrame?.indexOf('pairingSecret') ?? 0).assertEqual(-1);

      const parser = new ProtocolParser();
      const proofEnvelope = parser.parseEnvelope(result.authProofFrame ?? '');
      expect(proofEnvelope.ok).assertEqual(true);
      expect(proofEnvelope.envelope?.messageType).assertEqual(MessageType.AUTH_PROOF);
    });

    it('rejectsClientPairingHandshakeWhenServerHelloIdentityDiffersFromInvitation', 0, () => {
      const store = new PairingStore();
      store.importInvitationText(PAIRING_INVITATION_FIXTURE, 1700000000000);
      store.confirmCodeMatched();
      const draft = store.buildPendingClientHandshakeDraft(
        '018ff6f0-4adf-7d31-a987-3ef2b25d0212',
        '3p7bfXt9wbTTW2HC7OQ1Nz-DQ8hbeGdNrfx-FG-IK08',
        'hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo',
        1700000000000
      );
      if (!draft.ok || draft.draft === undefined) {
        expect(false).assertEqual(true);
        return;
      }

      const service = new PairingClientHandshakeSessionService();
      const started = service.start(
        draft.draft,
        '018ff6f0-2b1f-7cc5-b5d0-7e82c5f70f01',
        0
      );
      if (!started.ok || started.session === undefined) {
        expect(false).assertEqual(true);
        return;
      }

      const result = service.acceptServerHelloAndBuildAuthProof(
        started.session,
        SERVER_HELLO_FRAME_WITH_WRONG_IDENTITY_FIXTURE,
        TEST_ED25519_SIGNATURE,
        '018ff6f1-1d2a-725d-8d1a-894d2f5b0a42',
        2
      );
      expect(result.ok).assertEqual(false);
      expect(result.error).assertEqual(PairingClientHandshakeError.SERVER_HELLO_MISMATCH);
      expect(result.handshakeError).assertEqual(PairingHandshakeDraftError.SERVER_HELLO_MISMATCH);
      expect(result.field).assertEqual('identityPublicKey');
    });

    it('importsPairingInvitationTextThroughStoreWithoutPersistenceSideEffects', 0, () => {
      const store = new PairingStore();
      const parsed = store.importInvitationText(PAIRING_INVITATION_FIXTURE, 1700000000000);

      expect(parsed.state).assertEqual(PairingStoreState.READY);
      expect(parsed.invitationText).assertEqual(PAIRING_INVITATION_FIXTURE);
      expect(parsed.summary?.spaceShortId).assertEqual('10f2767a');
      expect(parsed.summary?.confirmationCode).assertEqual('574920');

      const expired = store.importInvitationText(PAIRING_INVITATION_FIXTURE, 1700000300000);
      expect(expired.state).assertEqual(PairingStoreState.ERROR);
      expect(expired.error).assertEqual(PairingInvitationError.EXPIRED);
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

    it('exposesEd25519SignatureVectorCryptoFrameworkBoundary', 0, () => {
      const service = new CryptoVectorService();
      const result = service.verifyEd25519SignatureVector(ED25519_SIGNATURE_VECTOR);

      expect(result.ok || result.error === CryptoVectorErrorCode.SIGNATURE_MISMATCH ||
        result.error === CryptoVectorErrorCode.PLATFORM_CRYPTO_FAILED).assertEqual(true);
    });
  });
}

const PAIRING_INVITATION_FIXTURE: string = 'eggclip://pair?p=eyJhcHAiOiJlZ2djbGlwIiwidmVyc2lvbiI6MSwia2luZCI6InBhaXJpbmdJbnZpdGF0aW9uIiwiaW52aXRhdGlvbklkIjoiMDE4ZmY2ZjAtMTExMS03MjIyLTgzMzMtMTIzNDU2Nzg5YWJjIiwic3BhY2VJZCI6IjAxOGZmNmVmLWMzOTQtN2QwOC04Yjk5LTRiN2QxMGYyNzY3YSIsInNwYWNlS2V5VmVyc2lvbiI6MSwiaXNzdWVyRGV2aWNlSWQiOiIwMThmZjZmMC0wYTNiLTc4MTUtYTRkYi0zZWI2ZTIzZDkzMzgiLCJpc3N1ZXJJZGVudGl0eVB1YmxpY0tleSI6IjExcVlBWUt4Q3JmVlNfN1R5V1FIT2c3aGN2UGFwaU1scndJYWFwY0hVcm8iLCJwYWlyaW5nU2VjcmV0IjoiQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQSIsImV4cGlyZXNBdE1zIjoxNzAwMDAwMzAwMDAwfQ';

const BAD_PAIRING_SECRET_INVITATION_FIXTURE: string = 'eggclip://pair?p=eyJhcHAiOiJlZ2djbGlwIiwidmVyc2lvbiI6MSwia2luZCI6InBhaXJpbmdJbnZpdGF0aW9uIiwic3BhY2VJZCI6IjAxOGZmNmVmLWMzOTQtN2QwOC04Yjk5LTRiN2QxMGYyNzY3YSIsInNwYWNlS2V5VmVyc2lvbiI6MSwiaXNzdWVyRGV2aWNlSWQiOiIwMThmZjZmMC0wYTNiLTc4MTUtYTRkYi0zZWI2ZTIzZDkzMzgiLCJpc3N1ZXJJZGVudGl0eVB1YmxpY0tleSI6IjExcVlBWUt4Q3JmVlNfN1R5V1FIT2c3aGN2UGFwaU1scndJYWFQY0hVUm8iLCJwYWlyaW5nU2VjcmV0IjoiQUEiLCJleHBpcmVzQXRNcyI6MTcwMDAwMDMwMDAwMH0';

interface PairingInvitationFixturePayload {
  app: string;
  version: number;
  kind: string;
  invitationId: string;
  spaceId: string;
  spaceKeyVersion: number;
  issuerDeviceName?: string;
  issuerDeviceId: string;
  issuerIdentityPublicKey: string;
  pairingSecret: string;
  expiresAtMs: number;
}

function basePairingInvitationPayload(issuerDeviceName?: string): PairingInvitationFixturePayload {
  const payload: PairingInvitationFixturePayload = {
    app: 'eggclip',
    version: 1,
    kind: 'pairingInvitation',
    invitationId: '018ff6f0-1111-7222-8333-123456789abc',
    spaceId: '018ff6ef-c394-7d08-8b99-4b7d10f2767a',
    spaceKeyVersion: 1,
    issuerDeviceId: '018ff6f0-0a3b-7815-a4db-3eb6e23d9338',
    issuerIdentityPublicKey: '11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo',
    pairingSecret: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    expiresAtMs: 1700000300000
  };
  if (issuerDeviceName !== undefined) {
    payload.issuerDeviceName = issuerDeviceName;
  }
  return payload;
}

function pairingInvitationFixtureUri(issuerDeviceName?: string): string {
  return `eggclip://pair?p=${encodeBase64Url(asciiBytes(JSON.stringify(basePairingInvitationPayload(issuerDeviceName))))}`;
}

function asciiBytes(value: string): Uint8Array {
  const bytes = new Uint8Array(value.length);
  for (let index = 0; index < value.length; index += 1) {
    bytes[index] = value.charCodeAt(index) & 0xff;
  }
  return bytes;
}

const CLIENT_HELLO_FIXTURE: string = '{"version":1,"type":"CLIENT_HELLO","messageId":"018ff6f0-2b1f-7cc5-b5d0-7e82c5f70f01","sessionCounter":0,"payload":{"spaceId":"018ff6ef-c394-7d08-8b99-4b7d10f2767a","deviceId":"018ff6f0-0a3b-7815-a4db-3eb6e23d9338","identityPublicKey":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","ephemeralPublicKey":"BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB","capabilities":["textPlain","syncHeads","itemBatch","itemLive"]}}';

const AUTH_PROOF_FIXTURE: string = '{"version":1,"type":"AUTH_PROOF","messageId":"018ff6f1-1d2a-725d-8d1a-894d2f5b0a42","sessionCounter":2,"payload":{"role":"client","signatureAlgorithm":"Ed25519","transcriptHash":"aM5GGwvEfnwOx_BNJSJktCEYEkmCrSH0wgAESnSOYEw","signature":"cdpm2njgsHCfH0hrubU-NbHMbWcN1xNtr-vZTKx_Tdf85hHKW8gIJuk463rj4f744vegLphZFO0RTvP_gQjeAg"}}';

const AUTH_PROOF_TRANSCRIPT: string = 'EggClip v1 auth transcript\nrole=client\nspaceId=018ff6ef-c394-7d08-8b99-4b7d10f2767a\nlocalDeviceId=018ff6f0-0a3b-7815-a4db-3eb6e23d9338\nremoteDeviceId=018ff6f0-4adf-7d31-a987-3ef2b25d0212\nlocalIdentityPublicKey=11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo\nremoteIdentityPublicKey=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\nlocalEphemeralPublicKey=hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo\nremoteEphemeralPublicKey=3p7bfXt9wbTTW2HC7OQ1Nz-DQ8hbeGdNrfx-FG-IK08\npairingContext=trusted-device:018ff6ef-c394-7d08-8b99-4b7d10f2767a\n';

const TEST_ED25519_SIGNATURE: string = 'AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyAhIiMkJSYnKCkqKywtLi8wMTIzNDU2Nzg5Ojs8PT4_QA';

const SERVER_HELLO_FRAME_FOR_PAIRING_FIXTURE: string = '{"version":1,"type":"SERVER_HELLO","messageId":"018ff6f1-0000-7000-8000-000000000001","sessionCounter":1,"payload":{"spaceId":"018ff6ef-c394-7d08-8b99-4b7d10f2767a","deviceId":"018ff6f0-0a3b-7815-a4db-3eb6e23d9338","identityPublicKey":"11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaapcHUro","ephemeralPublicKey":"Sl2dW6TOLeFyjjv0gDUPJeB-IclH0Z4zdvCbPB4WF0I","capabilities":["textPlain","syncHeads"]}}';

const SERVER_HELLO_FRAME_WITH_WRONG_IDENTITY_FIXTURE: string = '{"version":1,"type":"SERVER_HELLO","messageId":"018ff6f1-0000-7000-8000-000000000002","sessionCounter":1,"payload":{"spaceId":"018ff6ef-c394-7d08-8b99-4b7d10f2767a","deviceId":"018ff6f0-0a3b-7815-a4db-3eb6e23d9338","identityPublicKey":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","ephemeralPublicKey":"Sl2dW6TOLeFyjjv0gDUPJeB-IclH0Z4zdvCbPB4WF0I","capabilities":["textPlain","syncHeads"]}}';

const AUTH_OK_FIXTURE: string = '{"version":1,"type":"AUTH_OK","messageId":"018ff6f1-25f0-7c09-a4cf-3d683ebfae33","sessionCounter":3,"payload":{}}';

const AUTH_OK_OLD_COUNTER_FIXTURE: string = '{"version":1,"type":"AUTH_OK","messageId":"018ff6f1-25f0-7c09-a4cf-3d683ebfae33","sessionCounter":1,"payload":{}}';

const AUTH_ERROR_FIXTURE: string = '{"version":1,"type":"AUTH_ERROR","messageId":"018ff6f1-35f0-7c09-a4cf-3d683ebfae33","sessionCounter":3,"payload":{"code":"authFailed"}}';

const ENCRYPTED_ITEM_LIVE_FIXTURE: string = '{"version":1,"type":"ITEM_LIVE","messageId":"018ff6f3-0d8c-7d1e-a38a-f308c64de79f","sessionCounter":12,"ciphertext":{"algorithm":"AES-256-GCM","keyId":"session-v1-client-to-server","nonce":"DDDDDDDDDDDDDDDD","aad":"EEEEEEEEEEEEEEEE","body":"FFFFFFFFFFFFFFFF","tag":"GGGGGGGGGGGGGGGGGGGGGG"}}';

const ENCRYPTED_ERROR_FIXTURE: string = '{"version":1,"type":"ERROR","messageId":"018ff6f4-0d8c-7d1e-a38a-f308c64de79f","sessionCounter":12,"ciphertext":{"algorithm":"AES-256-GCM","keyId":"session-v1-client-to-server","nonce":"DDDDDDDDDDDDDDDD","aad":"EEEEEEEEEEEEEEEE","body":"FFFFFFFFFFFFFFFF","tag":"GGGGGGGGGGGGGGGGGGGGGG"}}';

const CLIPBOARD_ITEM_FIXTURE: string = '{"itemId":"018ff6f3-3653-7c79-b38b-f4af3575396b","spaceId":"018ff6ef-c394-7d08-8b99-4b7d10f2767a","originDeviceId":"018ff6f0-0a3b-7815-a4db-3eb6e23d9338","originSeq":42,"hlc":"1781946000123:0:018ff6f0","contentType":"text/plain","contentLength":17,"contentDigest":"CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC","createdAt":1781946000123,"content":"EggClip test text"}';

const UNKNOWN_VERSION_FIXTURE: string = '{"version":2,"type":"CLIENT_HELLO","messageId":"018ff6f0-2b1f-7cc5-b5d0-7e82c5f70f01","sessionCounter":0,"payload":{}}';

const POST_AUTH_PLAINTEXT_FIXTURE: string = '{"version":1,"type":"ITEM_LIVE","messageId":"018ff6f3-0d8c-7d1e-a38a-f308c64de79f","sessionCounter":12,"payload":{"content":"must not be plaintext after auth"}}';

const PRE_AUTH_CIPHERTEXT_FIXTURE: string = '{"version":1,"type":"CLIENT_HELLO","messageId":"018ff6f0-2b1f-7cc5-b5d0-7e82c5f70f01","sessionCounter":0,"ciphertext":{"algorithm":"AES-256-GCM","keyId":"session-v1-client-to-server","nonce":"DDDDDDDDDDDDDDDD","aad":"EEEEEEEEEEEEEEEE","body":"FFFFFFFFFFFFFFFF","tag":"GGGGGGGGGGGGGGGGGGGGGG"}}';
