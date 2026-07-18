import { describe, expect, it } from '@ohos/hypium';
import { ClipboardBridgeService } from '../main/ets/services/clipboard/ClipboardBridgeService';
import {
  AES_256_GCM_VECTOR,
  AUTH_ERROR_INVITATION_CONSUMED_VECTOR,
  ED25519_SIGNATURE_VECTOR,
  HMAC_SHA256_VECTOR,
  HKDF_SHA256_VECTOR,
  REPLAY_COUNTER_VECTOR,
  PAIRING_SECRET_PROOF_VECTOR,
  SESSION_KEYS_VECTOR,
  X25519_SHARED_SECRET_VECTOR
} from './ProtocolCryptoFixtures';
import {
  ProtocolHandshakeFrameOutcome,
  ProtocolHandshakeTransportSession,
  ProtocolAesGcmGateway,
  ProtocolTransportFrameError,
  ProtocolTransportFrameResult,
  ProtocolTransportSession
} from '../main/ets/services/transport/ProtocolTransportSession';
import {
  ProtocolFrameBuildError,
  ProtocolFrameBuilderService
} from '../main/ets/services/transport/ProtocolFrameBuilderService';
import {
  PairingHandshakeTransportCallbacks,
  TransportReasonCode,
  WebSocketTransportService
} from '../main/ets/services/transport/WebSocketTransportService';
import {
  SettingsStoreState,
  cloneSettings,
  createInitialSettingsSnapshot,
  normalizeHarmonySettings
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
  AesGcmCryptoError,
  AesGcmCryptoService,
  AesGcmDecryptResult,
  AesGcmEncryptResult
} from '../main/ets/services/crypto/AesGcmCryptoService';
import {
  SessionKeyDerivationError,
  SessionKeyDerivationService
} from '../main/ets/services/crypto/SessionKeyDerivationService';
import {
  X25519KeyAgreementError,
  X25519KeyAgreementService
} from '../main/ets/services/crypto/X25519KeyAgreementService';
import {
  Ed25519SignatureError,
  Ed25519SignatureService
} from '../main/ets/services/crypto/Ed25519SignatureService';
import {
  Ed25519IdentityError,
  Ed25519IdentityService
} from '../main/ets/services/crypto/Ed25519IdentityService';
import {
  Ed25519HuksIdentityError,
  Ed25519HuksIdentityMaterialResult,
  Ed25519HuksKeyRefResult,
  Ed25519HuksIdentityService,
  Ed25519HuksSignatureResult
} from '../main/ets/services/crypto/Ed25519HuksIdentityService';
import {
  LocalDeviceIdentityError,
  LocalDeviceIdentityMetadataGateway,
  LocalDeviceIdentityService,
  LocalDeviceSecureIdentityGateway
} from '../main/ets/services/crypto/LocalDeviceIdentityService';
import {
  INITIAL_SPACE_KEY_VERSION,
  SPACE_KEY_BYTES,
  SpaceKeyReferenceError,
  SpaceKeyReferenceService
} from '../main/ets/services/crypto/SpaceKeyReferenceService';
import {
  SpaceKeyHuksError,
  SpaceKeyHuksDecryptResult,
  SpaceKeyHuksDeleteResult,
  SpaceKeyHuksEncryptResult,
  SpaceKeyHuksImportResult,
  SpaceKeyHuksService,
  SpaceKeySecureImporter
} from '../main/ets/services/crypto/SpaceKeyHuksService';
import {
  SpaceKeyDestroyer,
  SpaceKeyRecoveryError,
  SpaceKeyRecoveryRepository,
  SpaceKeyRecoveryService
} from '../main/ets/services/crypto/SpaceKeyRecoveryService';
import {
  SpaceKeyAesGcmGateway,
  SpaceKeyCryptoSelfTestError,
  SpaceKeyCryptoSelfTestService,
  SpaceKeyRefProvider,
  hmacConfirmationCode
} from '../main/ets/services/crypto/SpaceKeyCryptoSelfTestService';
import {
  PairingInvitationError,
  PairingInvitationPayload,
  PairingInvitationService
} from '../main/ets/services/pairing/PairingInvitationService';
import { PairingSecretProofService } from '../main/ets/services/pairing/PairingSecretProofService';
import {
  PairingHandshakeDraft,
  PairingHandshakeDraftError,
  PairingAuthTranscriptDraft,
  PairingHandshakeDraftService
} from '../main/ets/services/pairing/PairingHandshakeDraftService';
import {
  PairingClientAuthProofSigner,
  PairingClientHandshakeError,
  PairingClientHandshakeSessionService
} from '../main/ets/services/pairing/PairingClientHandshakeSessionService';
import {
  PairingAuthProofValidationError,
  PairingAuthProofValidationResult,
  PairingAuthProofValidator,
  PairingAuthProofValidationService
} from '../main/ets/services/pairing/PairingAuthProofValidationService';
import {
  SpaceKeyDeliveryError,
  SpaceKeyDeliveryInput,
  SpaceKeyDeliveryService
} from '../main/ets/services/pairing/SpaceKeyDeliveryService';
import {
  PairingClientNetworkHandshakeError,
  PairingClientNetworkHandshakePhase,
  PairingClientNetworkHandshakeService
} from '../main/ets/services/pairing/PairingClientNetworkHandshakeService';
import {
  PairingGeneratedHandshakeMaterialResult,
  PairingStore,
  PairingStoreState
} from '../main/ets/store/PairingStore';
import {
  PairingConnectionState,
  PairingConnectionStore,
  OutboundDeliveryState,
  calculatePendingOutboundCount,
  pairingAuthErrorCode,
  resolveOutboundDelivery,
  trustedDiscoveryEndpoint
} from '../main/ets/store/PairingConnectionStore';
import { normalizeTrustedDeviceName } from '../main/ets/store/TrustedDeviceStore';
import { connectionExperiencePolicy } from '../main/ets/services/ui/ConnectionExperiencePolicy';
import {
  InboundItemLiveService,
  InboundItemLiveStatus,
  InboundItemLiveStorageGateway,
  SecureRandomGateway
} from '../main/ets/services/sync/InboundItemLiveService';
import {
  ClipboardValidationError,
  EGGCLIP_MDNS_DISCOVERY_TYPE,
  EGGCLIP_MDNS_SERVICE_TYPE,
  EndpointValidationResult,
  ManualEndpoint,
  POC_MAX_FRAME_BYTES
} from '../main/ets/models/PocModels';
import {
  AppSettings,
  ContentType as DomainContentType,
  ClipboardDedupDecision,
  Device as DomainDevice,
  DomainValidationError,
  HlcTimestamp,
  InboundClipboardEventKind,
  OriginSeqAllocator,
  SyncPauseReason,
  ThemeMode,
  Space as DomainSpace,
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
  isLegacyGeneratedDeviceName,
  isLegacyGeneratedSpaceName,
  pendingMigrations,
  validateSchemaPlan
} from '../main/ets/data/migrations/SchemaMigrations';
import { DATABASE_VERSION, STORE_CONFIG } from '../main/ets/data/db/DbConstants';
import {
  ClipboardItemRecord,
  ClipboardRepository,
  DisplayNameOrigin,
  DeviceRecord,
  DeviceRepository,
  INITIAL_ORIGIN_SEQ,
  LOCAL_IDENTITY_PRIVATE_KEY_REF_KEY,
  LOCAL_IDENTITY_PUBLIC_KEY_KEY,
  LOCAL_DEVICE_ID_KEY,
  LocalIdentityRepository,
  LocalClipboardPersistenceCommands,
  NEXT_ORIGIN_SEQ_KEY,
  SettingsRepository,
  SpaceRecord,
  SpaceRepository,
  SyncHeadRepository
} from '../main/ets/data/repositories/RepositoryCommands';
import {
  DeviceConnectionState as DomainDeviceConnectionState,
  DeviceTrustState as DomainDeviceTrustState,
  SpaceState as DomainSpaceState
} from '../main/ets/models/DomainModels';
import {
  AppLanguageGateway,
  LanguageModeStore,
  DEFAULT_LANGUAGE_MODE,
  DEFAULT_LOCALE,
  LanguageMode,
  LanguagePreferenceService,
  SupportedLocale,
  languageModeFromPreferredLanguage,
  preferredLanguageFromMode,
  resolveEffectiveLocale
} from '../main/ets/services/localization/LanguagePreferenceService';
import {
  UiMessageCode,
  UiMessageDescriptor,
  uiMessage
} from '../main/ets/services/localization/UiMessageCodes';
import {
  UiStringResolver,
  formatUiMessage
} from '../main/ets/services/localization/UiMessageFormatter';
import {
  formatLocalizedDateTime,
  formatLocalizedTime
} from '../main/ets/services/localization/LocalizedFormatter';
import { ConnectionState } from '../main/ets/models/ShellModels';
import {
  AeadAlgorithm,
  AuthProofPayload,
  AuthRole,
  Capability,
  HelloPayload,
  ContentType,
  JsonObject,
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

interface PairingSecretProofVectorFixture {
  invitationId: string;
  spaceId: string;
  issuerDeviceId: string;
  issuerIdentityPublicKey: string;
  clientDeviceId: string;
  clientIdentityPublicKey: string;
  clientEphemeralPublicKey: string;
  pairingSecret: string;
  verifier: string;
  claim: string;
  proof: string;
}

class TestAppLanguageGateway implements AppLanguageGateway {
  appPreferredLanguage: string = 'default';
  systemPreferredLanguage: string = 'en-US';
  savedLanguage: string = '';

  getAppPreferredLanguage(): string {
    return this.appPreferredLanguage;
  }

  getFirstSystemPreferredLanguage(): string {
    return this.systemPreferredLanguage;
  }

  setAppPreferredLanguage(language: string): void {
    this.savedLanguage = language;
    this.appPreferredLanguage = language;
  }
}

class TestLanguageModeStore implements LanguageModeStore {
  savedMode: LanguageMode | null = null;

  loadMode(): LanguageMode | null {
    return this.savedMode;
  }

  async saveMode(mode: LanguageMode): Promise<void> {
    this.savedMode = mode;
  }
}

class TestUiStringResolver implements UiStringResolver {
  private readonly locale: string;

  constructor(locale: string) {
    this.locale = locale;
  }

  getStringByNameSync(resourceName: string, ...args: Array<string | number>): string {
    if (resourceName === 'missing_code') {
      throw new Error('missing resource');
    }
    return `${this.locale}:${resourceName}:${args.join(',')}`;
  }
}

export default function localUnitTest() {
  describe('EggClipH1Boundaries', () => {
    it('countsOnlyUnacknowledgedLocalSequencesAsPending', 0, () => {
      expect(calculatePendingOutboundCount(8, 5)).assertEqual(3);
      expect(calculatePendingOutboundCount(5, 8)).assertEqual(0);
      expect(calculatePendingOutboundCount(-1, 0)).assertEqual(0);
    });

    it('mapsReliableOutboundQueueToVisibleDeliveryStates', 0, () => {
      expect(resolveOutboundDelivery(0, true).state).assertEqual(OutboundDeliveryState.SENT);
      expect(resolveOutboundDelivery(3, false).state).assertEqual(OutboundDeliveryState.QUEUED);
      expect(resolveOutboundDelivery(3, true).state).assertEqual(OutboundDeliveryState.SENDING);
      expect(resolveOutboundDelivery(3, true, true).state).assertEqual(OutboundDeliveryState.FAILED);
      expect(resolveOutboundDelivery(-1, false).state).assertEqual(OutboundDeliveryState.SENT);
    });

    it('keepsFirstUseAndTrustedRetryUiStatesActionable', 0, () => {
      const firstUse = connectionExperiencePolicy(0, ConnectionState.OFFLINE, true, false);
      expect(firstUse.showFirstUse).assertTrue();
      expect(firstUse.showRetry).assertFalse();

      const offline = connectionExperiencePolicy(1, ConnectionState.OFFLINE, false, false);
      expect(offline.showFirstUse).assertFalse();
      expect(offline.showRetry).assertTrue();
      expect(offline.retryEnabled).assertFalse();

      const foreground = connectionExperiencePolicy(1, ConnectionState.AUTH_FAILED, true, false);
      expect(foreground.retryEnabled).assertTrue();
      expect(connectionExperiencePolicy(1, ConnectionState.AUTH_FAILED, true, true).retryEnabled).assertFalse();
    });

    it('formatsExistingUiStateWithTheCurrentLanguageResolver', 0, () => {
      const message = uiMessage(UiMessageCode.OUTBOUND_PENDING);
      const zh = formatUiMessage(new TestUiStringResolver('zh-CN'), message);
      const en = formatUiMessage(new TestUiStringResolver('en-US'), message);
      expect(zh).assertEqual('zh-CN:ui_outbound_pending:');
      expect(en).assertEqual('en-US:ui_outbound_pending:');
    });

    it('fallsBackForUnknownUiMessageCodes', 0, () => {
      const unknown: UiMessageDescriptor = { code: 'missing_code', parameters: [] };
      expect(formatUiMessage(new TestUiStringResolver('en-US'), unknown))
        .assertEqual('en-US:ui_message_unknown:');
    });

    it('rejectsSensitiveUiMessageParameterNames', 0, () => {
      let rejected = false;
      try {
        uiMessage(UiMessageCode.OUTBOUND_PENDING, [{ name: 'clipboardText', value: 'secret' }]);
      } catch (_) {
        rejected = true;
      }
      expect(rejected).assertTrue();
    });

    it('keepsDynamicSourcesAsCodesWithSafeParameters', 0, () => {
      const source = uiMessage(UiMessageCode.SOURCE_DESKTOP_DEVICE, [
        { name: 'deviceShortId', value: '15a91e5a' }
      ]);
      expect(source.code).assertEqual(UiMessageCode.SOURCE_DESKTOP_DEVICE);
      expect(source.parameters.length).assertEqual(1);
      expect(source.parameters[0].value).assertEqual('15a91e5a');
    });

    it('formatsTimeAndDateWithTheSelectedLocale', 0, () => {
      const value = Date.UTC(2026, 6, 18, 9, 5, 4);
      expect(formatLocalizedTime(value, SupportedLocale.EN_US).length > 0).assertTrue();
      expect(formatLocalizedTime(value, SupportedLocale.ZH_CN).length > 0).assertTrue();
      const english = formatLocalizedDateTime(value, SupportedLocale.EN_US);
      const chinese = formatLocalizedDateTime(value, SupportedLocale.ZH_CN);
      expect(english.length > 0).assertTrue();
      expect(chinese.length > 0).assertTrue();
      expect(english === chinese).assertFalse();
    });

    it('normalizesTrustedDeviceNamesForSafeDisplay', 0, () => {
      expect(normalizeTrustedDeviceName('  我的   桌面端  ')).assertEqual('我的 桌面端');
      expect(normalizeTrustedDeviceName('   ')).assertEqual('');
      expect(normalizeTrustedDeviceName('123456789012345678901234567890123456789012345'))
        .assertEqual('1234567890123456789012345678901234567890');
    });

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
      expect(transport.decodeClipboardTextMessage('not json').reason).assertEqual(TransportReasonCode.JSON_INVALID);
      expect(transport.decodeClipboardTextMessage('{"kind":"clipboardText","text":""}').reason)
        .assertEqual(TransportReasonCode.TEXT_EMPTY);
      const exactText = 'a'.repeat(MAX_TEXT_BYTES);
      const exactMessage = transport.encodeClipboardTextMessage(exactText);
      expect(exactMessage === null).assertEqual(false);
      expect(transport.parseClipboardTextMessage(exactMessage ?? '')).assertEqual(exactText);
      expect(transport.encodeClipboardTextMessage('')).assertEqual(null);
      expect(transport.encodeClipboardTextMessage('a'.repeat(MAX_TEXT_BYTES + 1))).assertEqual(null);
      const oversizedTextMessage = `{"kind":"clipboardText","text":"${'a'.repeat(MAX_TEXT_BYTES + 1)}"}`;
      expect(transport.decodeClipboardTextMessage(oversizedTextMessage).reason)
        .assertEqual(TransportReasonCode.TEXT_TOO_LARGE);
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
      expect(diagnostics.lastRejection).assertEqual(TransportReasonCode.JSON_INVALID);

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

    it('keepsHarmonyLanguageModesOnTheSystemPreferenceBoundary', 0, () => {
      expect(DEFAULT_LANGUAGE_MODE).assertEqual(LanguageMode.SYSTEM);
      expect(DEFAULT_LOCALE).assertEqual(SupportedLocale.EN_US);
      expect(languageModeFromPreferredLanguage('default')).assertEqual(LanguageMode.SYSTEM);
      expect(languageModeFromPreferredLanguage('zh_CN')).assertEqual(LanguageMode.ZH_CN);
      expect(languageModeFromPreferredLanguage('zh-Hans-CN')).assertEqual(LanguageMode.ZH_CN);
      expect(languageModeFromPreferredLanguage('en-US')).assertEqual(LanguageMode.EN_US);
      expect(languageModeFromPreferredLanguage('en-GB')).assertEqual(LanguageMode.EN_US);
      expect(languageModeFromPreferredLanguage('fr-FR')).assertEqual(LanguageMode.SYSTEM);
      expect(preferredLanguageFromMode(LanguageMode.SYSTEM)).assertEqual('default');
      expect(preferredLanguageFromMode(LanguageMode.ZH_CN)).assertEqual('zh-Hans-CN');
      expect(preferredLanguageFromMode(LanguageMode.EN_US)).assertEqual('en-US');
      expect(resolveEffectiveLocale(LanguageMode.SYSTEM, ['zh-Hans-CN']))
        .assertEqual(SupportedLocale.ZH_CN);
      expect(resolveEffectiveLocale(LanguageMode.SYSTEM, ['fr-FR']))
        .assertEqual(SupportedLocale.EN_US);
    });

    it('readsAndWritesHarmonyAppLanguageWithoutRdbSettings', 0, async () => {
      const gateway = new TestAppLanguageGateway();
      const modeStore = new TestLanguageModeStore();
      const service = new LanguagePreferenceService(gateway, modeStore);

      gateway.systemPreferredLanguage = 'zh-CN';
      expect(service.loadMode()).assertEqual(LanguageMode.SYSTEM);
      expect(service.currentLocale()).assertEqual(SupportedLocale.ZH_CN);

      await service.saveMode(LanguageMode.EN_US);
      expect(gateway.savedLanguage).assertEqual('en-US');
      expect(service.loadMode()).assertEqual(LanguageMode.EN_US);
      expect(service.currentLocale()).assertEqual(SupportedLocale.EN_US);

      await service.saveMode(LanguageMode.SYSTEM);
      gateway.systemPreferredLanguage = 'zh-Hans-CN';
      gateway.appPreferredLanguage = gateway.systemPreferredLanguage;
      expect(gateway.savedLanguage).assertEqual('default');
      expect(service.loadMode()).assertEqual(LanguageMode.SYSTEM);
      expect(service.currentLocale()).assertEqual(SupportedLocale.ZH_CN);

      gateway.systemPreferredLanguage = 'en-GB';
      expect(service.currentLocale()).assertEqual(SupportedLocale.EN_US);
    });

    it('keepsHarmonyClipboardWritesBehindAnExplicitUserAction', 0, () => {
      const staleSettings = cloneSettings(createInitialSettingsSnapshot().settings);
      staleSettings.autoWriteEnabled = true;

      const normalized = normalizeHarmonySettings(staleSettings);

      expect(normalized.autoWriteEnabled).assertEqual(false);
      expect(staleSettings.autoWriteEnabled).assertEqual(true);
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

      expect(CURRENT_SCHEMA_VERSION).assertEqual(2);
      expect(DATABASE_VERSION).assertEqual(CURRENT_SCHEMA_VERSION);
      expect(STORE_CONFIG.name).assertEqual(DATABASE_NAME);
      expect(pending.length).assertEqual(2);
      expect(pendingMigrations(1).length).assertEqual(1);
      expect(pendingMigrations(CURRENT_SCHEMA_VERSION).length).assertEqual(0);
      expect(validateSchemaPlan()).assertEqual(true);
      expect(INITIAL_SCHEMA_TABLES.length).assertEqual(6);
      expect(sql.indexOf('create table if not exists clipboard_items') >= 0).assertEqual(true);
      expect(sql.indexOf('encrypted_content') >= 0).assertEqual(true);
      expect(sql.indexOf('unique(origin_device_id, origin_seq)') >= 0).assertEqual(true);
      expect(sql.indexOf('idx_clipboard_items_retention') >= 0).assertEqual(true);
      expect(sql.indexOf('add column name_origin') >= 0).assertEqual(true);
      expect(sql.indexOf("name_origin = 'generated'") >= 0).assertEqual(true);
    });

    it('protectsCustomNamesWhenClassifyingLegacyGeneratedNames', 0, () => {
      expect(isLegacyGeneratedSpaceName('同步空间 #018ff6ef')).assertEqual(true);
      expect(isLegacyGeneratedSpaceName('默认空间')).assertEqual(true);
      expect(isLegacyGeneratedSpaceName('我的默认空间')).assertEqual(false);
      expect(isLegacyGeneratedDeviceName('桌面端 #018ff6ef')).assertEqual(true);
      expect(isLegacyGeneratedDeviceName('EggClip 设备 #Abc_123')).assertEqual(true);
      expect(isLegacyGeneratedDeviceName('我的桌面端 #018ff6ef')).assertEqual(false);
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
        nameOrigin: DisplayNameOrigin.GENERATED,
        encryptedSpaceKeyRef: 'huks://space-key',
        updatedAt: 1700000000000
      });
      expect(space.sql.indexOf('INSERT INTO spaces') >= 0).assertEqual(true);
      expect(space.args[2]).assertEqual(DisplayNameOrigin.GENERATED);
      expect(space.args[3]).assertEqual('huks://space-key');

      const device = devices.upsert({
        device: {
          deviceId: localDeviceId,
          spaceId,
          displayName: 'HarmonyOS',
          identityPublicKeyRef: 'huks://identity-public-key',
          trustState: DomainDeviceTrustState.TRUSTED,
          connectionState: DomainDeviceConnectionState.OFFLINE
        },
        nameOrigin: DisplayNameOrigin.GENERATED,
        pairedAt: 1700000000000
      });
      expect(device.sql.indexOf('INSERT INTO devices') >= 0).assertEqual(true);
      expect(device.sql.indexOf('NULL') >= 0).assertEqual(true);
      for (const arg of device.args) {
        expect(arg === null).assertEqual(false);
      }
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
        nameOrigin: DisplayNameOrigin.GENERATED,
        encryptedSpaceKeyRef: alias.alias,
        updatedAt: 1700000000000
      });

      expect(command.args[3]).assertEqual(alias.alias);
      let containsRawKey = false;
      for (const arg of command.args) {
        if (arg instanceof Uint8Array) {
          containsRawKey = true;
        }
      }
      expect(containsRawKey).assertEqual(false);
    });

    it('buildsSpaceKeyHuksImportOptionsForAesGcmRawKey', 0, () => {
      const spaceId = '018ff6ef-c394-7d08-8b99-4b7d10f2767a';
      const service = new SpaceKeyHuksService();
      const keyRef = `huks://eggclip/space-key/${spaceId}/v1`;
      const alias = service.huksAliasFromRef(keyRef);
      const hmacAlias = service.hmacAliasFromSpaceKeyRef(keyRef);
      const options = service.importOptions(new Uint8Array(SPACE_KEY_BYTES));
      const hmacOptions = service.hmacImportOptions(new Uint8Array(SPACE_KEY_BYTES));
      const encryptOptions = service.operationOptions(1, new Uint8Array(12), new Uint8Array(4));
      const decryptOptions = service.operationOptions(2, new Uint8Array(12), new Uint8Array(4), new Uint8Array(16));

      expect(alias.ok).assertEqual(true);
      expect(alias.huksAlias).assertEqual(`eggclip.space-key.${spaceId}.v1`);
      expect(hmacAlias.ok).assertEqual(true);
      expect(hmacAlias.huksAlias).assertEqual(`eggclip.space-key-hmac.${spaceId}.v1`);
      expect(service.huksAliasFromRef('huks://eggclip/space-key/not-a-space/v1').error)
        .assertEqual(SpaceKeyHuksError.INVALID_KEY_REF);
      expect(options.inData?.length).assertEqual(SPACE_KEY_BYTES);
      expect(options.properties?.length).assertEqual(6);
      expect(hmacOptions.inData?.length).assertEqual(SPACE_KEY_BYTES);
      expect(hmacOptions.properties?.length).assertEqual(5);
      expect(encryptOptions.properties?.length).assertEqual(9);
      expect(decryptOptions.properties?.length).assertEqual(10);
      expect(encryptOptions.inData === undefined).assertEqual(true);
    });

    it('rejectsInvalidSpaceKeyHuksAesGcmInputsBeforePlatformCrypto', 0, async () => {
      const spaceId = '018ff6ef-c394-7d08-8b99-4b7d10f2767a';
      const service = new SpaceKeyHuksService();
      const keyRef = `huks://eggclip/space-key/${spaceId}/v1`;
      const invalidRef = await service.encryptBase64Url(
        'huks://eggclip/space-key/not-a-space/v1',
        encodeBase64Url(new Uint8Array(12)),
        encodeBase64Url(new Uint8Array(0)),
        encodeBase64Url(new Uint8Array(1))
      );
      const invalidNonce = await service.encryptBase64Url(
        keyRef,
        encodeBase64Url(new Uint8Array(11)),
        encodeBase64Url(new Uint8Array(0)),
        encodeBase64Url(new Uint8Array(1))
      );
      const invalidTag = await service.decryptBase64Url(
        keyRef,
        encodeBase64Url(new Uint8Array(12)),
        encodeBase64Url(new Uint8Array(0)),
        encodeBase64Url(new Uint8Array(1)),
        encodeBase64Url(new Uint8Array(15))
      );

      expect(invalidRef.error).assertEqual(SpaceKeyHuksError.INVALID_KEY_REF);
      expect(invalidNonce.error).assertEqual(SpaceKeyHuksError.INVALID_LENGTH);
      expect(invalidNonce.field).assertEqual('nonce');
      expect(invalidTag.error).assertEqual(SpaceKeyHuksError.INVALID_LENGTH);
      expect(invalidTag.field).assertEqual('tag');
    });

    it('runsSpaceKeyHuksAesGcmSelfTestWithoutReturningSensitiveMaterial', 0, async () => {
      const provider = new FakeSpaceKeyRefProvider('huks://eggclip/space-key/018ff6ef-c394-7d08-8b99-4b7d10f2767a/v1');
      const crypto = new FakeSpaceKeyAesGcmGateway();
      const service = new SpaceKeyCryptoSelfTestService(provider, crypto);
      const result = await service.run();

      expect(result.ok).assertEqual(true);
      expect(crypto.encryptCalls).assertEqual(1);
      expect(crypto.decryptCalls).assertEqual(1);
      expect(JSON.stringify(result).indexOf('EggClip')).assertEqual(-1);
      expect(JSON.stringify(result).indexOf('cipher-body')).assertEqual(-1);
    });

    it('derivesCrossPlatformHmacConfirmationCodeFromSharedVector', 0, () => {
      const vector = JSON.parse(HMAC_SHA256_VECTOR) as Record<string, string>;

      expect(hmacConfirmationCode(vector.digest)).assertEqual(vector.confirmationCode);
      expect(hmacConfirmationCode('AA')).assertEqual(null);
    });

    it('rejectsSpaceKeyHuksAesGcmSelfTestWhenKeyIsMissingOrPlaintextDiffers', 0, async () => {
      const missing = await new SpaceKeyCryptoSelfTestService(
        new FakeSpaceKeyRefProvider(null),
        new FakeSpaceKeyAesGcmGateway()
      ).run();
      const crypto = new FakeSpaceKeyAesGcmGateway();
      crypto.returnMismatchedPlaintext = true;
      const mismatch = await new SpaceKeyCryptoSelfTestService(
        new FakeSpaceKeyRefProvider('huks://eggclip/space-key/018ff6ef-c394-7d08-8b99-4b7d10f2767a/v1'),
        crypto
      ).run();

      expect(missing.error).assertEqual(SpaceKeyCryptoSelfTestError.NO_SPACE_KEY);
      expect(mismatch.error).assertEqual(SpaceKeyCryptoSelfTestError.PLAINTEXT_MISMATCH);
    });

    it('acceptsEncryptedSpaceKeyDeliveryPayloadWithoutReturningRawKey', 0, async () => {
      const spaceId = '018ff6ef-c394-7d08-8b99-4b7d10f2767a';
      const importer = new FakeSpaceKeyImporter();
      const service = new SpaceKeyDeliveryService(new SpaceKeyReferenceService(), importer);
      const result = await service.acceptInitialDelivery(spaceKeyDeliveryInput(
        spaceKeyDeliveryPayload(spaceId, INITIAL_SPACE_KEY_VERSION, SPACE_KEY_BYTES, 'pairing-v1'),
        spaceId,
        INITIAL_SPACE_KEY_VERSION
      ));

      expect(result.ok).assertEqual(true);
      expect(result.encryptedSpaceKeyRef).assertEqual(`huks://eggclip/space-key/${spaceId}/v1`);
      expect(importer.importCalls).assertEqual(1);
      expect(importer.importedRef).assertEqual(`huks://eggclip/space-key/${spaceId}/v1`);
      expect(importer.importedKeyLength).assertEqual(SPACE_KEY_BYTES);
      expect(JSON.stringify(result).indexOf('spaceKey')).assertEqual(-1);
    });

    it('acceptsOnlyNewerRotationSpaceKeyDelivery', 0, async () => {
      const spaceId = '018ff6ef-c394-7d08-8b99-4b7d10f2767a';
      const importer = new FakeSpaceKeyImporter();
      const service = new SpaceKeyDeliveryService(new SpaceKeyReferenceService(), importer);
      const payload = spaceKeyDeliveryPayload(spaceId, 3, SPACE_KEY_BYTES, 'rotation-v1');
      const accepted = await service.acceptRotation({
        payload,
        expectedSpaceId: spaceId,
        currentKeyVersion: 1
      });
      const stale = await service.acceptRotation({
        payload: spaceKeyDeliveryPayload(spaceId, 1, SPACE_KEY_BYTES, 'rotation-v1'),
        expectedSpaceId: spaceId,
        currentKeyVersion: 1
      });

      expect(accepted.ok).assertEqual(true);
      expect(accepted.encryptedSpaceKeyRef.endsWith('/v3')).assertEqual(true);
      expect(stale.error).assertEqual(SpaceKeyDeliveryError.INVALID_KEY_VERSION);
    });

    it('rejectsInvalidEncryptedSpaceKeyDeliveryPayloads', 0, async () => {
      const spaceId = '018ff6ef-c394-7d08-8b99-4b7d10f2767a';
      const service = new SpaceKeyDeliveryService(new SpaceKeyReferenceService(), new FakeSpaceKeyImporter());

      expect((await service.acceptInitialDelivery(spaceKeyDeliveryInput(
        undefined,
        spaceId,
        INITIAL_SPACE_KEY_VERSION
      ))).error).assertEqual(SpaceKeyDeliveryError.MISSING_PAYLOAD);
      expect((await service.acceptInitialDelivery(spaceKeyDeliveryInput(
        spaceKeyDeliveryPayload('018ff6ef-c394-7d08-8b99-4b7d10f2767b', INITIAL_SPACE_KEY_VERSION, SPACE_KEY_BYTES, 'pairing-v1'),
        spaceId,
        INITIAL_SPACE_KEY_VERSION
      ))).error).assertEqual(SpaceKeyDeliveryError.INVALID_SPACE_ID);
      expect((await service.acceptInitialDelivery(spaceKeyDeliveryInput(
        spaceKeyDeliveryPayload(spaceId, 2, SPACE_KEY_BYTES, 'pairing-v1'),
        spaceId,
        INITIAL_SPACE_KEY_VERSION
      ))).error).assertEqual(SpaceKeyDeliveryError.INVALID_KEY_VERSION);
      expect((await service.acceptInitialDelivery(spaceKeyDeliveryInput(
        spaceKeyDeliveryPayload(spaceId, INITIAL_SPACE_KEY_VERSION, SPACE_KEY_BYTES, 'unexpected'),
        spaceId,
        INITIAL_SPACE_KEY_VERSION
      ))).error).assertEqual(SpaceKeyDeliveryError.INVALID_DELIVERY);
      expect((await service.acceptInitialDelivery(spaceKeyDeliveryInput(
        spaceKeyDeliveryPayload(spaceId, INITIAL_SPACE_KEY_VERSION, SPACE_KEY_BYTES - 1, 'pairing-v1'),
        spaceId,
        INITIAL_SPACE_KEY_VERSION
      ))).error).assertEqual(SpaceKeyDeliveryError.INVALID_SPACE_KEY);
    });

    it('rejectsEncryptedSpaceKeyDeliveryWhenSecureImportFails', 0, async () => {
      const spaceId = '018ff6ef-c394-7d08-8b99-4b7d10f2767a';
      const importer = new FakeSpaceKeyImporter();
      importer.failImport = true;
      const service = new SpaceKeyDeliveryService(new SpaceKeyReferenceService(), importer);
      const result = await service.acceptInitialDelivery(spaceKeyDeliveryInput(
        spaceKeyDeliveryPayload(spaceId, INITIAL_SPACE_KEY_VERSION, SPACE_KEY_BYTES, 'pairing-v1'),
        spaceId,
        INITIAL_SPACE_KEY_VERSION
      ));

      expect(result.ok).assertEqual(false);
      expect(result.error).assertEqual(SpaceKeyDeliveryError.IMPORT_FAILED);
      expect(result.encryptedSpaceKeyRef).assertEqual('');
      expect(importer.importCalls).assertEqual(1);
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
      const publicKey = '11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo';
      const privateKeyRef = 'huks://eggclip/local-identity/ed25519/v1';

      const loadDeviceId = identity.loadLocalDeviceId();
      expect(loadDeviceId.sql.indexOf('SELECT value FROM app_metadata') >= 0).assertEqual(true);
      expect(loadDeviceId.args[0]).assertEqual(LOCAL_DEVICE_ID_KEY);

      const insertDeviceId = identity.insertLocalDeviceId(deviceId, 1700000000000);
      expect(insertDeviceId.sql.indexOf('INSERT OR IGNORE INTO app_metadata') >= 0).assertEqual(true);
      expect(insertDeviceId.args[0]).assertEqual(LOCAL_DEVICE_ID_KEY);
      expect(insertDeviceId.args[1]).assertEqual(deviceId);

      const loadPublicKey = identity.loadLocalIdentityPublicKey();
      expect(loadPublicKey.args[0]).assertEqual(LOCAL_IDENTITY_PUBLIC_KEY_KEY);
      const savePublicKey = identity.saveLocalIdentityPublicKey(publicKey, 1700000000001);
      expect(savePublicKey === null).assertEqual(false);
      if (savePublicKey === null) {
        expect(false).assertEqual(true);
        return;
      }
      expect(savePublicKey.sql.indexOf('ON CONFLICT(key) DO UPDATE') >= 0).assertEqual(true);
      expect(savePublicKey.args[0]).assertEqual(LOCAL_IDENTITY_PUBLIC_KEY_KEY);
      expect(savePublicKey.args[1]).assertEqual(publicKey);
      expect(identity.saveLocalIdentityPublicKey('AA', 1700000000001)).assertEqual(null);

      const loadPrivateKeyRef = identity.loadLocalIdentityPrivateKeyRef();
      expect(loadPrivateKeyRef.args[0]).assertEqual(LOCAL_IDENTITY_PRIVATE_KEY_REF_KEY);
      const savePrivateKeyRef = identity.saveLocalIdentityPrivateKeyRef(privateKeyRef, 1700000000001);
      expect(savePrivateKeyRef === null).assertEqual(false);
      if (savePrivateKeyRef === null) {
        expect(false).assertEqual(true);
        return;
      }
      expect(savePrivateKeyRef.args[0]).assertEqual(LOCAL_IDENTITY_PRIVATE_KEY_REF_KEY);
      expect(savePrivateKeyRef.args[1]).assertEqual(privateKeyRef);
      expect(identity.saveLocalIdentityPrivateKeyRef(publicKey, 1700000000001)).assertEqual(null);

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

    it('buildsClientToServerEncryptedBusinessFramesWithIndependentCounters', 0, () => {
      const crypto: ProtocolAesGcmGateway = new FakeProtocolAesGcmGateway();
      const session = new ProtocolTransportSession(ProtocolSessionState.AUTHENTICATED, {
        clientToServerKey: '_CuE_7SfzdShnxyzHQy4IJ0zQjMAUVq-tynBZ2lBPYQ',
        serverToClientKey: 'TSo91xPhGNnQb2KPW6xyjJJFeHsimcUss0Rm2Tnbo2M'
      }, crypto);
      const first = session.encodeBusinessFrame(
        MessageType.ITEM_LIVE,
        '018ff6f3-0d8c-7d1e-a38a-f308c64de79f',
        outboundPayloadFixture()
      );
      const second = session.encodeBusinessFrame(
        MessageType.PING,
        '018ff6f4-0d8c-7d1e-a38a-f308c64de79f',
        emptyOutboundPayloadFixture()
      );

      expect(first.ok).assertEqual(true);
      expect(first.sessionCounter).assertEqual(0);
      expect(second.ok).assertEqual(true);
      expect(second.sessionCounter).assertEqual(1);
      const firstEnvelope = new ProtocolParser().parseEnvelope(first.frame ?? '');
      expect(firstEnvelope.ok).assertEqual(true);
      expect(firstEnvelope.envelope?.messageType).assertEqual(MessageType.ITEM_LIVE);
      expect(firstEnvelope.envelope?.ciphertext?.keyId).assertEqual('session-v1-client-to-server');
      expect(firstEnvelope.envelope?.ciphertext?.nonce).assertEqual('YzJzAQAAAAAAAAAA');
    });

    it('rejectsProtocolTransportEncryptedFrameWithAadMismatchWhenKeysArePresent', 0, () => {
      const session = new ProtocolTransportSession(ProtocolSessionState.AUTHENTICATED, {
        clientToServerKey: '_CuE_7SfzdShnxyzHQy4IJ0zQjMAUVq-tynBZ2lBPYQ',
        serverToClientKey: 'TSo91xPhGNnQb2KPW6xyjJJFeHsimcUss0Rm2Tnbo2M'
      });
      const result = session.acceptTextFrame(ENCRYPTED_ITEM_LIVE_FIXTURE);

      expect(result.ok).assertEqual(false);
      expect(result.error).assertEqual(ProtocolTransportFrameError.AAD_MISMATCH);
      expect(session.isClosed()).assertEqual(true);
      expect(session.state()).assertEqual(ProtocolSessionState.FAILED);
    });

    it('closesProtocolTransportOnDecryptFailureWhenAadMatches', 0, () => {
      const session = new ProtocolTransportSession(ProtocolSessionState.AUTHENTICATED, {
        clientToServerKey: '_CuE_7SfzdShnxyzHQy4IJ0zQjMAUVq-tynBZ2lBPYQ',
        serverToClientKey: 'TSo91xPhGNnQb2KPW6xyjJJFeHsimcUss0Rm2Tnbo2M'
      });
      const frame = encryptedFrameWithCanonicalAad(
        MessageType.ITEM_LIVE,
        '018ff6f3-0d8c-7d1e-a38a-f308c64de79f',
        12,
        'session-v1-client-to-server'
      );
      const result = session.acceptTextFrame(frame);

      expect(result.ok).assertEqual(false);
      expect(result.error).assertEqual(ProtocolTransportFrameError.DECRYPT_FAILED);
      expect(session.isClosed()).assertEqual(true);
      expect(session.state()).assertEqual(ProtocolSessionState.FAILED);
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
      expect(diagnostics.lastRejection)
        .assertEqual(`${TransportReasonCode.PROTOCOL_REJECTED}:sessionClosed`);
    });

    it('routesPairingHandshakeFramesThroughWebSocketTransportDiagnostics', 0, () => {
      const transport = new WebSocketTransportService();
      const session = new ProtocolHandshakeTransportSession();

      const hello = transport.decodeHandshakeFrameMessage(SERVER_HELLO_FRAME_FOR_PAIRING_FIXTURE, session);
      expect(hello.ok).assertEqual(true);
      expect(hello.envelope?.messageType).assertEqual(MessageType.SERVER_HELLO);
      expect(session.isClosed()).assertEqual(false);

      const encrypted = transport.decodeHandshakeFrameMessage(ENCRYPTED_ITEM_LIVE_FIXTURE, session);
      expect(encrypted.ok).assertEqual(false);
      expect(encrypted.error).assertEqual(ProtocolTransportFrameError.PROTOCOL_REJECTED);
      expect(session.isClosed()).assertEqual(true);

      const afterClosed = transport.decodeHandshakeFrameMessage(AUTH_OK_FIXTURE, session);
      expect(afterClosed.ok).assertEqual(false);
      expect(afterClosed.error).assertEqual(ProtocolTransportFrameError.SESSION_CLOSED);

      const diagnostics = transport.currentDiagnostics();
      expect(diagnostics.receivedFrames).assertEqual(3);
      expect(diagnostics.acceptedItems).assertEqual(1);
      expect(diagnostics.rejectedFrames).assertEqual(2);
      expect(diagnostics.lastRejection)
        .assertEqual(`${TransportReasonCode.HANDSHAKE_REJECTED}:sessionClosed`);
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

    it('parsesOfflineBackfillPayloads', 0, () => {
      const parser = new ProtocolParser();
      const batchPayload = JSON.parse('{"items":[' + CLIPBOARD_ITEM_FIXTURE + '],' +
        '"gaps":[{"originDeviceId":"018ff6f0-0a3b-7815-a4db-3eb6e23d9338",' +
        '"requestedFromSeq":1,"minimumAvailable":40}]}') as JsonObject;
      const ackPayload = JSON.parse('{"itemIds":["018ff6f3-3653-7c79-b38b-f4af3575396b"]}') as JsonObject;
      const requestPayload = JSON.parse('{"ranges":[{' +
        '"originDeviceId":"018ff6f0-0a3b-7815-a4db-3eb6e23d9338","fromSeq":40,"toSeq":42}]}') as JsonObject;
      const batch = parser.parseItemBatchPayload(batchPayload);
      const ack = parser.parseItemAckPayload(ackPayload);
      const request = parser.parseRequestRangePayload(requestPayload);

      expect(batch.ok).assertEqual(true);
      expect(batch.payload?.items.length).assertEqual(1);
      expect(batch.payload?.gaps.length).assertEqual(1);
      expect(ack.ok).assertEqual(true);
      expect(request.ok).assertEqual(true);
    });

    it('rejectsInvalidOfflineBackfillPayloads', 0, () => {
      const parser = new ProtocolParser();
      const emptyBatch = JSON.parse('{"items":[],"gaps":[]}') as JsonObject;
      const duplicateAck = JSON.parse('{"itemIds":[' +
        '"018ff6f3-3653-7c79-b38b-f4af3575396b",' +
        '"018ff6f3-3653-7c79-b38b-f4af3575396b"]}') as JsonObject;
      const reversedRange = JSON.parse('{"ranges":[{' +
        '"originDeviceId":"018ff6f0-0a3b-7815-a4db-3eb6e23d9338","fromSeq":43,"toSeq":42}]}') as JsonObject;
      expect(parser.parseItemBatchPayload(emptyBatch).ok).assertEqual(false);
      expect(parser.parseItemAckPayload(duplicateAck).ok).assertEqual(false);
      expect(parser.parseRequestRangePayload(reversedRange).ok).assertEqual(false);
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
      expect(result.summary?.issuerDeviceName).assertEqual('EggClip Desktop #11qYAYKx');
      expect(result.summary?.issuerShortFingerprint).assertEqual('11qYAYKx');
      expect(result.summary?.expiresInSeconds).assertEqual(300);
      expect(result.summary?.confirmationCode).assertEqual('130762');
    });

    it('matchesSharedPairingSecretProofVectorAndBindsClientClaim', 0, () => {
      const vector = JSON.parse(PAIRING_SECRET_PROOF_VECTOR) as PairingSecretProofVectorFixture;
      const invitation: PairingInvitationPayload = {
        app: 'eggclip',
        version: 2,
        kind: 'pairingInvitation',
        invitationId: vector.invitationId,
        spaceId: vector.spaceId,
        spaceKeyVersion: 1,
        issuerDeviceId: vector.issuerDeviceId,
        issuerIdentityPublicKey: vector.issuerIdentityPublicKey,
        pairingSecret: vector.pairingSecret,
        expiresAtMs: 1700000300000
      };
      const hello: HelloPayload = {
        spaceId: vector.spaceId,
        deviceId: vector.clientDeviceId,
        identityPublicKey: vector.clientIdentityPublicKey,
        ephemeralPublicKey: vector.clientEphemeralPublicKey,
        capabilities: [Capability.TEXT_PLAIN],
        pairingContext: `pairing-invitation:v2:${vector.invitationId}`
      };
      const proof = new PairingSecretProofService().build(invitation, hello);
      expect(proof.ok).assertEqual(true);
      expect(proof.verifier).assertEqual(vector.verifier);
      expect(proof.claim).assertEqual(vector.claim);
      expect(proof.proof).assertEqual(vector.proof);
      const reboundHello: HelloPayload = {
        spaceId: hello.spaceId,
        deviceId: '018ff6f0-4adf-7d31-a987-3ef2b25d0213',
        identityPublicKey: hello.identityPublicKey,
        ephemeralPublicKey: hello.ephemeralPublicKey,
        capabilities: hello.capabilities.slice(),
        pairingContext: hello.pairingContext
      };
      const rebound = new PairingSecretProofService().build(invitation, reboundHello);
      expect(rebound.proof === vector.proof).assertEqual(false);
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
      expect(parsed.summary?.confirmationCode).assertEqual('130762');
      expect(parsed.statusMessage.code).assertEqual(UiMessageCode.PAIRING_INVITATION_VALID);

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
      expect(pending.summary?.confirmationCode).assertEqual('130762');
      expect(pending.statusMessage.code).assertEqual(UiMessageCode.PAIRING_CODE_MATCHED);
      expect(pending.error === null).assertEqual(true);
      expect(store.hasPendingHandshakeMaterial()).assertEqual(true);

      const cleared = store.clear();
      expect(cleared.state).assertEqual(PairingStoreState.IDLE);
      expect(store.hasPendingHandshakeMaterial()).assertEqual(false);
    });

    it('keepsPairingResultVisibleAfterClearingSingleUseSecret', 0, () => {
      const store = new PairingStore();
      store.importInvitationText(PAIRING_INVITATION_FIXTURE, 1700000000000);
      store.confirmCodeMatched();

      const completed = store.completePairing();

      expect(completed.state).assertEqual(PairingStoreState.COMPLETED);
      expect(completed.invitationText).assertEqual('');
      expect(completed.summary?.confirmationCode).assertEqual('130762');
      expect(completed.statusMessage.code).assertEqual(UiMessageCode.PAIRING_COMPLETED);
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
        .assertEqual('pairing-invitation:v2:018ff6f0-1111-7222-8333-123456789abc');
      expect(draft.draft?.clientHelloPayload.deviceId).assertEqual('018ff6f0-4adf-7d31-a987-3ef2b25d0212');
      expect(draft.draft?.clientHelloPayload.identityPublicKey)
        .assertEqual('11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo');
      expect(draft.draft?.clientHelloPayload.ephemeralPublicKey)
        .assertEqual('hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo');
      const serialized = JSON.stringify(draft.draft);
      expect(serialized.indexOf('pairingSecret')).assertEqual(-1);
      expect(serialized.indexOf('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA')).assertEqual(-1);
    });

    it('buildsPendingClientHandshakeMaterialWithGeneratedEphemeralKeyPairWhenAvailable', 0, () => {
      const emptyStore = new PairingStore();
      const missing = emptyStore.buildPendingClientHandshakeMaterial(
        '018ff6f0-4adf-7d31-a987-3ef2b25d0212',
        '11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo',
        1700000000000
      );
      expect(missing.ok).assertEqual(false);
      expect(missing.handshakeError).assertEqual(PairingHandshakeDraftError.MISSING_PENDING_INVITATION);

      const store = new PairingStore();
      store.importInvitationText(PAIRING_INVITATION_FIXTURE, 1700000000000);
      const readySnapshot = store.confirmCodeMatched();
      const material = store.buildPendingClientHandshakeMaterial(
        '018ff6f0-4adf-7d31-a987-3ef2b25d0212',
        '11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo',
        1700000000000
      );

      if (material.ok) {
        expect(decodeBase64Url(material.localEphemeralPrivateKey ?? '')?.length).assertEqual(32);
        expect(decodeBase64Url(material.localEphemeralPublicKey ?? '')?.length).assertEqual(32);
        expect(material.draft?.clientHelloPayload.ephemeralPublicKey).assertEqual(material.localEphemeralPublicKey);
        expect(JSON.stringify(material.draft).indexOf(material.localEphemeralPrivateKey ?? '')).assertEqual(-1);
        expect(JSON.stringify(store.snapshot()).indexOf(material.localEphemeralPrivateKey ?? '')).assertEqual(-1);
        expect(JSON.stringify(readySnapshot).indexOf(material.localEphemeralPrivateKey ?? '')).assertEqual(-1);
      } else {
        expect(material.keyAgreementError).assertEqual(X25519KeyAgreementError.PLATFORM_CRYPTO_FAILED);
      }
    });

    it('buildsPendingClientHandshakeMaterialWithLocalDeviceIdentityProvider', 0, async () => {
      const emptyStore = new PairingStore();
      const identityService = new LocalDeviceIdentityService(
        new FakeLocalDeviceIdentityMetadataGateway(),
        new FakeSecureIdentityGateway()
      );
      const missing = await emptyStore.buildPendingClientHandshakeMaterialWithLocalIdentity(
        identityService,
        1700000000000,
        'v1'
      );
      expect(missing.ok).assertEqual(false);
      expect(missing.handshakeError).assertEqual(PairingHandshakeDraftError.MISSING_PENDING_INVITATION);

      const store = new PairingStore();
      store.importInvitationText(PAIRING_INVITATION_FIXTURE, 1700000000000);
      store.confirmCodeMatched();
      const material = await store.buildPendingClientHandshakeMaterialWithLocalIdentity(
        identityService,
        1700000000000,
        'v1'
      );

      if (material.ok) {
        expect(material.localDeviceId).assertEqual('018ff6f0-4adf-7d31-a987-3ef2b25d0212');
        expect(material.localIdentityPublicKey).assertEqual(FAKE_LOCAL_IDENTITY_PUBLIC_KEY);
        expect(material.localIdentityPrivateKeyRef).assertEqual('huks://eggclip/local-identity/ed25519/v1');
        expect(material.draft?.clientHelloPayload.deviceId).assertEqual(material.localDeviceId);
        expect(material.draft?.clientHelloPayload.identityPublicKey).assertEqual(FAKE_LOCAL_IDENTITY_PUBLIC_KEY);
        expect(decodeBase64Url(material.localEphemeralPrivateKey ?? '')?.length).assertEqual(32);
        const serializedDraft = JSON.stringify(material.draft);
        expect(serializedDraft.indexOf(material.localEphemeralPrivateKey ?? '')).assertEqual(-1);
        expect(serializedDraft.indexOf(material.localIdentityPrivateKeyRef ?? '')).assertEqual(-1);
      } else {
        expect(material.keyAgreementError).assertEqual(X25519KeyAgreementError.PLATFORM_CRYPTO_FAILED);
      }
    });

    it('rejectsPendingHandshakeMaterialWhenLocalIdentityInitializationFails', 0, async () => {
      const metadata = new FakeLocalDeviceIdentityMetadataGateway();
      const secureIdentity = new FakeSecureIdentityGateway();
      secureIdentity.failGeneration = true;
      const identityService = new LocalDeviceIdentityService(metadata, secureIdentity);
      const store = new PairingStore();
      store.importInvitationText(PAIRING_INVITATION_FIXTURE, 1700000000000);
      store.confirmCodeMatched();

      const material = await store.buildPendingClientHandshakeMaterialWithLocalIdentity(
        identityService,
        1700000000000,
        'v1'
      );

      expect(material.ok).assertEqual(false);
      expect(material.identityError).assertEqual(LocalDeviceIdentityError.HUKS_FAILED);
      expect(metadata.savedPublicKey).assertEqual('');
      expect(metadata.savedPrivateKeyRef).assertEqual('');
    });

    it('startsPairingConnectionBySendingClientHelloWithoutLeakingSecrets', 0, async () => {
      const transport = new FakePairingWebSocketTransportService();
      const identityService = new LocalDeviceIdentityService(
        new FakeLocalDeviceIdentityMetadataGateway(),
        new FakeSecureIdentityGateway()
      );
      const network = new PairingClientNetworkHandshakeService(
        new PairingClientHandshakeSessionService(new FakePairingClientAuthProofSigner())
      );
      const connection = new PairingConnectionStore(transport, identityService, network);
      connection.updateEndpoint('192.168.1.10', '4567');
      const material = pairingMaterialFixture();
      if (material === null || material.draft === undefined) {
        expect(false).assertEqual(true);
        return;
      }

      await connection.startWithPreparedMaterial(material, {
        host: '192.168.1.10',
        port: 4567
      });
      await Promise.resolve();

      expect(transport.connectedEndpoint).assertEqual('192.168.1.10:4567');
      expect(transport.sentFrames.length).assertEqual(1);
      expect(transport.sentFrames[0].indexOf('CLIENT_HELLO') >= 0).assertEqual(true);
      expect(transport.sentFrames[0].indexOf('pairingSecret')).assertEqual(-1);
      expect(transport.sentFrames[0].indexOf('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA')).assertEqual(-1);
      expect(connection.snapshot().state).assertEqual(PairingConnectionState.CLIENT_HELLO_SENT);
      expect(connection.snapshot().clientHelloSent).assertEqual(true);
    });

    it('describesLinkDownAfterClientHelloAsDesktopHandshakeClosure', 0, async () => {
      const transport = new FakePairingWebSocketTransportService();
      const identityService = new LocalDeviceIdentityService(
        new FakeLocalDeviceIdentityMetadataGateway(),
        new FakeSecureIdentityGateway()
      );
      const network = new PairingClientNetworkHandshakeService(
        new PairingClientHandshakeSessionService(new FakePairingClientAuthProofSigner())
      );
      const connection = new PairingConnectionStore(transport, identityService, network);
      const material = pairingMaterialFixture();
      if (material === null) {
        expect(false).assertEqual(true);
        return;
      }

      await connection.startWithPreparedMaterial(material, {
        host: '192.168.1.10',
        port: 4567
      });
      await Promise.resolve();
      transport.emitClose('0: the link is down');

      expect(connection.snapshot().state).assertEqual(PairingConnectionState.FAILED);
      expect(connection.snapshot().title.code).assertEqual(UiMessageCode.CONNECTION_FAILED_TITLE);
      expect(connection.snapshot().description.code).assertEqual(UiMessageCode.CONNECTION_FAILED_DESCRIPTION);
    });

    it('continuesPairingConnectionAfterServerHelloBySendingAuthProof', 0, async () => {
      const transport = new FakePairingWebSocketTransportService();
      const identityService = new LocalDeviceIdentityService(
        new FakeLocalDeviceIdentityMetadataGateway(),
        new FakeSecureIdentityGateway()
      );
      const signer = new FakePairingClientAuthProofSigner();
      const network = new PairingClientNetworkHandshakeService(
        new PairingClientHandshakeSessionService(signer, new FakePairingServerAuthProofValidator())
      );
      const connection = new PairingConnectionStore(transport, identityService, network);
      connection.updateEndpoint('192.168.1.10', '4567');
      const material = pairingMaterialFixture();
      if (material === null || material.draft === undefined) {
        expect(false).assertEqual(true);
        return;
      }

      await connection.startWithPreparedMaterial(material, {
        host: '192.168.1.10',
        port: 4567
      });
      await Promise.resolve();
      const handshakeSession = new ProtocolHandshakeTransportSession();
      const serverHello = handshakeSession.acceptTextFrame(SERVER_HELLO_FRAME_FOR_X25519_FIXTURE);
      await connection.handleHandshakeTextFrame(SERVER_HELLO_FRAME_FOR_X25519_FIXTURE, serverHello);

      expect(transport.sentFrames.length).assertEqual(2);
      expect(transport.sentFrames[1].indexOf('AUTH_PROOF') >= 0).assertEqual(true);
      expect(transport.sentFrames[1].indexOf('huks://eggclip/local-identity/ed25519/v1')).assertEqual(-1);
      expect(signer.privateKeyRef).assertEqual('huks://eggclip/local-identity/ed25519/v1');
      expect(connection.snapshot().state).assertEqual(PairingConnectionState.WAITING_AUTH_OK);
      expect(connection.snapshot().authProofSent).assertEqual(true);

      const serverProofFrame = serverAuthProofFrame(material.draft, SERVER_HELLO_FRAME_FOR_X25519_FIXTURE);
      expect(serverProofFrame.length > 0).assertEqual(true);
      const serverProof = handshakeSession.acceptTextFrame(serverProofFrame);
      await connection.handleHandshakeTextFrame(serverProofFrame, serverProof);
      expect(connection.snapshot().state).assertEqual(PairingConnectionState.WAITING_AUTH_OK);
      expect(connection.snapshot().title.code).assertEqual(UiMessageCode.CONNECTION_IDENTITY_VERIFIED_TITLE);
      expect(connection.snapshot().authenticated).assertEqual(false);
      expect(connection.snapshot().syncReady).assertEqual(false);
      expect(connection.snapshot().description.code)
        .assertEqual(UiMessageCode.CONNECTION_IDENTITY_VERIFIED_DESCRIPTION);
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
      expect(hello.payload?.pairingContext)
        .assertEqual('pairing-invitation:v2:018ff6f0-1111-7222-8333-123456789abc');

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
        identityPublicKey: '11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo',
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
        .assertEqual('11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo');
      expect(transcriptValue.canonicalTranscript.indexOf('role=client') >= 0).assertEqual(true);
      expect(transcriptValue.canonicalTranscript.indexOf(
        'pairingContext=pairing-invitation:v2:018ff6f0-1111-7222-8333-123456789abc'
      ) >= 0).assertEqual(true);

      const wrongSpace = service.buildClientAuthTranscriptDraft(draft.draft, {
        spaceId: '018ff6f0-1111-7222-8333-123456789abc',
        deviceId: '018ff6f0-0a3b-7815-a4db-3eb6e23d9338',
        identityPublicKey: '11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo',
        ephemeralPublicKey: 'Sl2dW6TOLeFyjjv0gDUPJeB-IclH0Z4zdvCbPB4WF0I',
        capabilities: [Capability.TEXT_PLAIN]
      });
      expect(wrongSpace.ok).assertEqual(false);
      expect(wrongSpace.error).assertEqual(PairingHandshakeDraftError.SERVER_HELLO_MISMATCH);
      expect(wrongSpace.field).assertEqual('spaceId');
    });

    it('buildsTrustedDeviceHandshakeDraftWithoutInvitationSecret', 0, () => {
      const service = new PairingHandshakeDraftService();
      const draft = service.buildTrustedDeviceHandshakeDraft({
        spaceId: '018ff6ef-c394-7d08-8b99-4b7d10f2767a',
        spaceKeyVersion: 1,
        remoteDeviceId: '018ff6f0-0a3b-7815-a4db-3eb6e23d9338',
        remoteIdentityPublicKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
        localDeviceId: '018ff6f0-4adf-7d31-a987-3ef2b25d0212',
        localIdentityPublicKey: '3p7bfXt9wbTTW2HC7OQ1Nz-DQ8hbeGdNrfx-FG-IK08',
        localEphemeralPublicKey: 'hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo'
      });
      expect(draft.ok).assertEqual(true);
      if (draft.draft === undefined) {
        expect(false).assertEqual(true);
        return;
      }
      expect(draft.draft.pairingContext)
        .assertEqual('trusted-device:018ff6ef-c394-7d08-8b99-4b7d10f2767a:key-v1');
      expect(draft.draft.clientHelloPayload.pairingContext)
        .assertEqual('trusted-device:018ff6ef-c394-7d08-8b99-4b7d10f2767a:key-v1');

      const transcript = service.buildClientAuthTranscriptDraft(draft.draft, {
        spaceId: '018ff6ef-c394-7d08-8b99-4b7d10f2767a',
        deviceId: '018ff6f0-0a3b-7815-a4db-3eb6e23d9338',
        identityPublicKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
        ephemeralPublicKey: 'Sl2dW6TOLeFyjjv0gDUPJeB-IclH0Z4zdvCbPB4WF0I',
        capabilities: [Capability.TEXT_PLAIN, Capability.SYNC_HEADS]
      });
      expect(transcript.ok).assertEqual(true);
      if (transcript.transcript !== undefined) {
        expect(transcript.transcript.canonicalTranscript.indexOf(
          'pairingContext=trusted-device:018ff6ef-c394-7d08-8b99-4b7d10f2767a:key-v1'
        ) >= 0).assertEqual(true);
      }

      const invalid = service.buildTrustedDeviceHandshakeDraft({
        spaceId: 'not-a-uuid',
        spaceKeyVersion: 1,
        remoteDeviceId: '018ff6f0-0a3b-7815-a4db-3eb6e23d9338',
        remoteIdentityPublicKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
        localDeviceId: '018ff6f0-4adf-7d31-a987-3ef2b25d0212',
        localIdentityPublicKey: '3p7bfXt9wbTTW2HC7OQ1Nz-DQ8hbeGdNrfx-FG-IK08',
        localEphemeralPublicKey: 'hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo'
      });
      expect(invalid.ok).assertEqual(false);
      expect(invalid.error).assertEqual(PairingHandshakeDraftError.INVALID_FIELD);
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
        identityPublicKey: '11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo',
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
      expect(proof.payload?.transcriptHash).assertEqual('DxGqgJPHNY6WFt7DbOIM4ioDGf13IEuaYjJrGuAVquM');

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
        identityPublicKey: '11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo',
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

      const service = new PairingClientHandshakeSessionService(
        new FakePairingClientAuthProofSigner(),
        new FakePairingServerAuthProofValidator()
      );
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

    it('orchestratesClientPairingHandshakeWithEd25519SigningBoundaryWhenAvailable', 0, () => {
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

      const service = new PairingClientHandshakeSessionService(
        new FakePairingClientAuthProofSigner(),
        new FakePairingServerAuthProofValidator()
      );
      const started = service.start(
        draft.draft,
        '018ff6f0-2b1f-7cc5-b5d0-7e82c5f70f01',
        0
      );
      if (!started.ok || started.session === undefined) {
        expect(false).assertEqual(true);
        return;
      }

      const result = service.acceptServerHelloAndSignAuthProof(
        started.session,
        SERVER_HELLO_FRAME_FOR_PAIRING_FIXTURE,
        'nWGxne_9WmC6hEr0kuwsxERJxWl7MmkZcDusAxyuf2A',
        '018ff6f1-1d2a-725d-8d1a-894d2f5b0a42',
        2
      );
      if (result.ok) {
        const parser = new ProtocolParser();
        const proofEnvelope = parser.parseEnvelope(result.authProofFrame ?? '');
        expect(proofEnvelope.ok).assertEqual(true);
        expect(proofEnvelope.envelope?.messageType).assertEqual(MessageType.AUTH_PROOF);
      } else {
        expect(result.error).assertEqual(PairingClientHandshakeError.AUTH_PROOF_SIGN_FAILED);
        expect(
          result.signatureError === Ed25519SignatureError.PLATFORM_CRYPTO_FAILED ||
          result.signatureError === Ed25519SignatureError.SIGNATURE_MISMATCH
        ).assertEqual(true);
      }
    });

    it('orchestratesClientPairingHandshakeWithHuksIdentityRefSigner', 0, async () => {
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

      const signer = new FakePairingClientAuthProofSigner();
      const service = new PairingClientHandshakeSessionService(signer);
      const started = service.start(
        draft.draft,
        '018ff6f0-2b1f-7cc5-b5d0-7e82c5f70f01',
        0
      );
      if (!started.ok || started.session === undefined) {
        expect(false).assertEqual(true);
        return;
      }

      const result = await service.acceptServerHelloAndSignAuthProofWithRef(
        started.session,
        SERVER_HELLO_FRAME_FOR_PAIRING_FIXTURE,
        'huks://eggclip/local-identity/ed25519/v1',
        '018ff6f1-1d2a-725d-8d1a-894d2f5b0a42',
        2
      );

      expect(result.ok).assertEqual(true);
      expect(signer.privateKeyRef).assertEqual('huks://eggclip/local-identity/ed25519/v1');
      expect(signer.canonicalTranscript.indexOf('role=client') >= 0).assertEqual(true);
      expect(signer.canonicalTranscript.indexOf('pairingSecret')).assertEqual(-1);
      expect((result.authProofFrame?.indexOf('AUTH_PROOF') ?? -1) >= 0).assertEqual(true);
      expect(result.authProofFrame?.indexOf('huks://eggclip/local-identity/ed25519/v1') ?? 0).assertEqual(-1);
      const parser = new ProtocolParser();
      const parsed = parser.parseEnvelope(result.authProofFrame ?? '');
      const proof = parser.parseAuthProofPayload(parsed.envelope?.payload);
      expect(proof.ok).assertEqual(true);
      expect(result.transcriptSaltBase64Url).assertEqual(proof.payload?.transcriptHash);
    });

    it('failsClientPairingHandshakeWhenHuksRefSigningFails', 0, async () => {
      const draft = pairingDraftFixture();
      if (draft === null) {
        expect(false).assertEqual(true);
        return;
      }

      const signer = new FakePairingClientAuthProofSigner();
      signer.failSigning = true;
      const service = new PairingClientHandshakeSessionService(signer);
      const started = service.start(
        draft,
        '018ff6f0-2b1f-7cc5-b5d0-7e82c5f70f01',
        0
      );
      if (!started.ok || started.session === undefined) {
        expect(false).assertEqual(true);
        return;
      }

      const result = await service.acceptServerHelloAndSignAuthProofWithRef(
        started.session,
        SERVER_HELLO_FRAME_FOR_PAIRING_FIXTURE,
        'huks://eggclip/local-identity/ed25519/v1',
        '018ff6f1-1d2a-725d-8d1a-894d2f5b0a42',
        2
      );

      expect(result.ok).assertEqual(false);
      expect(result.error).assertEqual(PairingClientHandshakeError.AUTH_PROOF_SIGN_FAILED);
      expect(result.huksError).assertEqual(Ed25519HuksIdentityError.PLATFORM_CRYPTO_FAILED);
      expect(result.field).assertEqual('signAuthTranscript');
    });

    it('createsProtocolTransportSessionAfterPairingAuthOkAndSessionKeyDerivation', 0, () => {
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

      const service = new PairingClientHandshakeSessionService(
        new FakePairingClientAuthProofSigner(),
        new FakePairingServerAuthProofValidator()
      );
      const started = service.start(draft.draft, '018ff6f0-2b1f-7cc5-b5d0-7e82c5f70f01', 0);
      if (!started.ok || started.session === undefined) {
        expect(false).assertEqual(true);
        return;
      }
      const authProof = service.acceptServerHelloAndBuildAuthProof(
        started.session,
        SERVER_HELLO_FRAME_FOR_PAIRING_FIXTURE,
        TEST_ED25519_SIGNATURE,
        '018ff6f1-1d2a-725d-8d1a-894d2f5b0a42',
        2
      );
      expect(authProof.ok).assertEqual(true);
      expect(service.acceptServerAuthProof(
        started.session,
        serverAuthProofFrame(draft.draft, SERVER_HELLO_FRAME_FOR_PAIRING_FIXTURE)
      ).ok).assertEqual(true);

      const authenticated = service.acceptAuthOkAndCreateTransportSession(
        started.session,
        AUTH_OK_FIXTURE,
        'Sl2dW6TOLeFyjjv0gDUPJeB-IclH0Z4zdvCbPB4WF0I',
        'RWdnQ2xpcCB2MSB0ZXN0IGhhbmRzaGFrZSBzYWx0'
      );
      expect(authenticated.ok).assertEqual(true);
      expect(authenticated.sessionKeys?.clientToServerKey).assertEqual('_CuE_7SfzdShnxyzHQy4IJ0zQjMAUVq-tynBZ2lBPYQ');
      expect(authenticated.sessionKeys?.serverToClientKey).assertEqual('TSo91xPhGNnQb2KPW6xyjJJFeHsimcUss0Rm2Tnbo2M');
      expect(authenticated.transportSession?.state()).assertEqual(ProtocolSessionState.AUTHENTICATED);
      expect(authenticated.transportSession?.isClosed()).assertEqual(false);
    });

    it('requiresValidServerAuthProofBeforeAcceptingAuthOk', 0, () => {
      const draft = pairingDraftFixture();
      if (draft === null) {
        expect(false).assertEqual(true);
        return;
      }
      const service = new PairingClientHandshakeSessionService(
        new FakePairingClientAuthProofSigner(),
        new FakePairingServerAuthProofValidator()
      );
      const started = service.start(draft, '018ff6f0-2b1f-7cc5-b5d0-7e82c5f70f01', 0);
      if (!started.ok || started.session === undefined) {
        expect(false).assertEqual(true);
        return;
      }
      const clientProof = service.acceptServerHelloAndBuildAuthProof(
        started.session,
        SERVER_HELLO_FRAME_FOR_PAIRING_FIXTURE,
        TEST_ED25519_SIGNATURE,
        '018ff6f1-1d2a-725d-8d1a-894d2f5b0a42',
        2
      );
      expect(clientProof.ok).assertEqual(true);

      const earlyAuthOk = service.acceptAuthOkAndCreateTransportSession(
        started.session,
        AUTH_OK_FIXTURE,
        'Sl2dW6TOLeFyjjv0gDUPJeB-IclH0Z4zdvCbPB4WF0I',
        'RWdnQ2xpcCB2MSB0ZXN0IGhhbmRzaGFrZSBzYWx0'
      );
      expect(earlyAuthOk.ok).assertEqual(false);
      expect(earlyAuthOk.error).assertEqual(PairingClientHandshakeError.SERVER_AUTH_PROOF_REQUIRED);

      const tamperedProof = serverAuthProofFrame(draft, SERVER_HELLO_FRAME_FOR_PAIRING_FIXTURE)
        .replace('Dkhen_', 'Akhen_');
      const rejected = service.acceptServerAuthProof(started.session, tamperedProof);
      expect(rejected.ok).assertEqual(false);
      expect(rejected.error).assertEqual(PairingClientHandshakeError.SERVER_AUTH_PROOF_INVALID);
      expect(rejected.validationError).assertEqual(PairingAuthProofValidationError.SIGNATURE_VERIFY_FAILED);
    });

    it('createsProtocolTransportSessionFromEphemeralX25519WhenPlatformSupportsIt', 0, () => {
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

      const service = new PairingClientHandshakeSessionService(
        new FakePairingClientAuthProofSigner(),
        new FakePairingServerAuthProofValidator()
      );
      const started = service.start(
        draft.draft,
        '018ff6f0-2b1f-7cc5-b5d0-7e82c5f70f01',
        0,
        'dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo'
      );
      if (!started.ok || started.session === undefined) {
        expect(false).assertEqual(true);
        return;
      }
      const authProof = service.acceptServerHelloAndBuildAuthProof(
        started.session,
        SERVER_HELLO_FRAME_FOR_X25519_FIXTURE,
        TEST_ED25519_SIGNATURE,
        '018ff6f1-1d2a-725d-8d1a-894d2f5b0a42',
        2
      );
      expect(authProof.ok).assertEqual(true);
      expect(service.acceptServerAuthProof(
        started.session,
        serverAuthProofFrame(draft.draft, SERVER_HELLO_FRAME_FOR_X25519_FIXTURE)
      ).ok).assertEqual(true);

      const authenticated = service.acceptAuthOkAndCreateTransportSessionFromEphemeral(
        started.session,
        AUTH_OK_FIXTURE,
        'RWdnQ2xpcCB2MSB0ZXN0IGhhbmRzaGFrZSBzYWx0'
      );
      if (authenticated.ok) {
        expect(authenticated.sessionKeys?.clientToServerKey).assertEqual('_CuE_7SfzdShnxyzHQy4IJ0zQjMAUVq-tynBZ2lBPYQ');
        expect(authenticated.sessionKeys?.serverToClientKey).assertEqual('TSo91xPhGNnQb2KPW6xyjJJFeHsimcUss0Rm2Tnbo2M');
        expect(authenticated.transportSession?.state()).assertEqual(ProtocolSessionState.AUTHENTICATED);
      } else {
        expect(authenticated.error).assertEqual(PairingClientHandshakeError.SHARED_SECRET_DERIVATION_FAILED);
        expect(authenticated.keyAgreementError).assertEqual(X25519KeyAgreementError.PLATFORM_CRYPTO_FAILED);
      }
    });

    it('rejectsEphemeralX25519TransportSessionWithoutLocalPrivateKey', 0, () => {
      const draft = pairingDraftFixture();
      if (draft === null) {
        expect(false).assertEqual(true);
        return;
      }
      const service = new PairingClientHandshakeSessionService(
        new FakePairingClientAuthProofSigner(),
        new FakePairingServerAuthProofValidator()
      );
      const started = service.start(draft, '018ff6f0-2b1f-7cc5-b5d0-7e82c5f70f01', 0);
      if (!started.ok || started.session === undefined) {
        expect(false).assertEqual(true);
        return;
      }
      const authProof = service.acceptServerHelloAndBuildAuthProof(
        started.session,
        SERVER_HELLO_FRAME_FOR_X25519_FIXTURE,
        TEST_ED25519_SIGNATURE,
        '018ff6f1-1d2a-725d-8d1a-894d2f5b0a42',
        2
      );
      expect(authProof.ok).assertEqual(true);
      expect(service.acceptServerAuthProof(
        started.session,
        serverAuthProofFrame(draft, SERVER_HELLO_FRAME_FOR_X25519_FIXTURE)
      ).ok).assertEqual(true);

      const authenticated = service.acceptAuthOkAndCreateTransportSessionFromEphemeral(
        started.session,
        AUTH_OK_FIXTURE,
        'RWdnQ2xpcCB2MSB0ZXN0IGhhbmRzaGFrZSBzYWx0'
      );
      expect(authenticated.ok).assertEqual(false);
      expect(authenticated.error).assertEqual(PairingClientHandshakeError.SHARED_SECRET_DERIVATION_FAILED);
      expect(authenticated.field).assertEqual('localEphemeralPrivateKey');
    });

    it('createsProtocolTransportSessionFromRememberedAuthTranscriptSaltWhenPlatformSupportsX25519', 0, () => {
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

      const service = new PairingClientHandshakeSessionService(
        new FakePairingClientAuthProofSigner(),
        new FakePairingServerAuthProofValidator()
      );
      const started = service.start(
        draft.draft,
        '018ff6f0-2b1f-7cc5-b5d0-7e82c5f70f01',
        0,
        'dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo'
      );
      if (!started.ok || started.session === undefined) {
        expect(false).assertEqual(true);
        return;
      }
      const authProof = service.acceptServerHelloAndBuildAuthProof(
        started.session,
        SERVER_HELLO_FRAME_FOR_X25519_FIXTURE,
        TEST_ED25519_SIGNATURE,
        '018ff6f1-1d2a-725d-8d1a-894d2f5b0a42',
        2
      );
      expect(authProof.ok).assertEqual(true);
      expect((authProof.transcriptSaltBase64Url?.length ?? 0) > 0).assertEqual(true);
      expect(service.acceptServerAuthProof(
        started.session,
        serverAuthProofFrame(draft.draft, SERVER_HELLO_FRAME_FOR_X25519_FIXTURE)
      ).ok).assertEqual(true);

      const authenticated = service.acceptAuthOkAndCreateTransportSessionFromRememberedTranscript(
        started.session,
        AUTH_OK_FIXTURE
      );
      if (authenticated.ok) {
        expect(authenticated.transportSession?.state()).assertEqual(ProtocolSessionState.AUTHENTICATED);
      } else {
        expect(authenticated.error).assertEqual(PairingClientHandshakeError.SHARED_SECRET_DERIVATION_FAILED);
        expect(authenticated.keyAgreementError).assertEqual(X25519KeyAgreementError.PLATFORM_CRYPTO_FAILED);
      }
    });

    it('doesNotCreateProtocolTransportSessionBeforeClientAuthProofIsBuilt', 0, () => {
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
      const started = service.start(draft.draft, '018ff6f0-2b1f-7cc5-b5d0-7e82c5f70f01', 0);
      if (!started.ok || started.session === undefined) {
        expect(false).assertEqual(true);
        return;
      }
      const result = service.acceptAuthOkAndCreateTransportSession(
        started.session,
        AUTH_OK_FIXTURE,
        'Sl2dW6TOLeFyjjv0gDUPJeB-IclH0Z4zdvCbPB4WF0I',
        'RWdnQ2xpcCB2MSB0ZXN0IGhhbmRzaGFrZSBzYWx0'
      );
      expect(result.ok).assertEqual(false);
      expect(result.error).assertEqual(PairingClientHandshakeError.AUTH_PROOF_NOT_SENT);
    });

    it('orchestratesClientNetworkHandshakeFramesUntilProtocolSessionIsReady', 0, () => {
      const draft = pairingDraftFixture();
      if (draft === null) {
        expect(false).assertEqual(true);
        return;
      }
      const service = new PairingClientNetworkHandshakeService(
        new PairingClientHandshakeSessionService(
          new FakePairingClientAuthProofSigner(),
          new FakePairingServerAuthProofValidator()
        )
      );

      const started = service.start(draft, '018ff6f0-2b1f-7cc5-b5d0-7e82c5f70f01', 0);
      expect(started.ok).assertEqual(true);
      expect(started.phase).assertEqual(PairingClientNetworkHandshakePhase.CLIENT_HELLO_READY);
      expect((started.outgoingFrame?.indexOf('CLIENT_HELLO') ?? -1) >= 0).assertEqual(true);

      const proof = service.acceptServerHelloAndBuildAuthProof(
        SERVER_HELLO_FRAME_FOR_PAIRING_FIXTURE,
        TEST_ED25519_SIGNATURE,
        '018ff6f1-1d2a-725d-8d1a-894d2f5b0a42',
        2
      );
      expect(proof.ok).assertEqual(true);
      expect(proof.phase).assertEqual(PairingClientNetworkHandshakePhase.WAITING_SERVER_AUTH_PROOF);
      expect((proof.outgoingFrame?.indexOf('AUTH_PROOF') ?? -1) >= 0).assertEqual(true);
      const serverProof = service.acceptServerAuthProof(
        serverAuthProofFrame(draft, SERVER_HELLO_FRAME_FOR_PAIRING_FIXTURE)
      );
      expect(serverProof.ok).assertEqual(true);
      expect(serverProof.phase).assertEqual(PairingClientNetworkHandshakePhase.WAITING_AUTH_OK);

      const authenticated = service.acceptAuthOkAndCreateTransportSession(
        AUTH_OK_FIXTURE,
        'Sl2dW6TOLeFyjjv0gDUPJeB-IclH0Z4zdvCbPB4WF0I',
        'RWdnQ2xpcCB2MSB0ZXN0IGhhbmRzaGFrZSBzYWx0'
      );
      expect(authenticated.ok).assertEqual(true);
      expect(authenticated.phase).assertEqual(PairingClientNetworkHandshakePhase.AUTHENTICATED);
      expect(authenticated.transportSession?.state()).assertEqual(ProtocolSessionState.AUTHENTICATED);
      expect(service.phase()).assertEqual(PairingClientNetworkHandshakePhase.AUTHENTICATED);
    });

    it('orchestratesClientNetworkHandshakeAuthProofWithHuksIdentityRefSigner', 0, async () => {
      const draft = pairingDraftFixture();
      if (draft === null) {
        expect(false).assertEqual(true);
        return;
      }
      const signer = new FakePairingClientAuthProofSigner();
      const service = new PairingClientNetworkHandshakeService(
        new PairingClientHandshakeSessionService(signer, new FakePairingServerAuthProofValidator())
      );

      const started = service.start(draft, '018ff6f0-2b1f-7cc5-b5d0-7e82c5f70f01', 0);
      expect(started.ok).assertEqual(true);
      expect(started.phase).assertEqual(PairingClientNetworkHandshakePhase.CLIENT_HELLO_READY);

      const proof = await service.acceptServerHelloAndSignAuthProofWithRef(
        SERVER_HELLO_FRAME_FOR_PAIRING_FIXTURE,
        'huks://eggclip/local-identity/ed25519/v1',
        '018ff6f1-1d2a-725d-8d1a-894d2f5b0a42',
        2
      );

      expect(proof.ok).assertEqual(true);
      expect(proof.phase).assertEqual(PairingClientNetworkHandshakePhase.WAITING_SERVER_AUTH_PROOF);
      expect(signer.privateKeyRef).assertEqual('huks://eggclip/local-identity/ed25519/v1');
      expect((proof.outgoingFrame?.indexOf('AUTH_PROOF') ?? -1) >= 0).assertEqual(true);
      expect(proof.outgoingFrame?.indexOf('huks://eggclip/local-identity/ed25519/v1') ?? 0).assertEqual(-1);
    });

    it('createsNetworkProtocolSessionFromRememberedAuthTranscriptSaltWhenPlatformSupportsX25519', 0, () => {
      const draft = pairingDraftFixture();
      if (draft === null) {
        expect(false).assertEqual(true);
        return;
      }
      const service = new PairingClientNetworkHandshakeService(
        new PairingClientHandshakeSessionService(
          new FakePairingClientAuthProofSigner(),
          new FakePairingServerAuthProofValidator()
        )
      );

      const started = service.start(
        draft,
        '018ff6f0-2b1f-7cc5-b5d0-7e82c5f70f01',
        0,
        'dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo'
      );
      expect(started.ok).assertEqual(true);
      const proof = service.acceptServerHelloAndBuildAuthProof(
        SERVER_HELLO_FRAME_FOR_X25519_FIXTURE,
        TEST_ED25519_SIGNATURE,
        '018ff6f1-1d2a-725d-8d1a-894d2f5b0a42',
        2
      );
      expect(proof.ok).assertEqual(true);
      expect((proof.transcriptSaltBase64Url?.length ?? 0) > 0).assertEqual(true);
      expect(service.acceptServerAuthProof(
        serverAuthProofFrame(draft, SERVER_HELLO_FRAME_FOR_X25519_FIXTURE)
      ).ok).assertEqual(true);

      const authenticated = service.acceptAuthOkAndCreateTransportSessionFromRememberedTranscript(
        AUTH_OK_FIXTURE
      );
      if (authenticated.ok) {
        expect(authenticated.phase).assertEqual(PairingClientNetworkHandshakePhase.AUTHENTICATED);
        expect(authenticated.transportSession?.state()).assertEqual(ProtocolSessionState.AUTHENTICATED);
      } else {
        expect(authenticated.error).assertEqual(PairingClientNetworkHandshakeError.AUTH_OK_FAILED);
        expect(authenticated.handshakeError).assertEqual(PairingClientHandshakeError.SHARED_SECRET_DERIVATION_FAILED);
      }
    });

    it('rejectsClientNetworkHandshakeFramesOutOfOrder', 0, () => {
      const draft = pairingDraftFixture();
      if (draft === null) {
        expect(false).assertEqual(true);
        return;
      }
      const service = new PairingClientNetworkHandshakeService();

      const earlyAuthOk = service.acceptAuthOkAndCreateTransportSession(
        AUTH_OK_FIXTURE,
        'Sl2dW6TOLeFyjjv0gDUPJeB-IclH0Z4zdvCbPB4WF0I',
        'RWdnQ2xpcCB2MSB0ZXN0IGhhbmRzaGFrZSBzYWx0'
      );
      expect(earlyAuthOk.ok).assertEqual(false);
      expect(earlyAuthOk.error).assertEqual(PairingClientNetworkHandshakeError.INVALID_PHASE);
      expect(earlyAuthOk.phase).assertEqual(PairingClientNetworkHandshakePhase.IDLE);

      const started = service.start(draft, '018ff6f0-2b1f-7cc5-b5d0-7e82c5f70f01', 0);
      expect(started.ok).assertEqual(true);
      const duplicateStart = service.start(draft, '018ff6f0-2b1f-7cc5-b5d0-7e82c5f70f02', 0);
      expect(duplicateStart.ok).assertEqual(false);
      expect(duplicateStart.error).assertEqual(PairingClientNetworkHandshakeError.INVALID_PHASE);
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
      expect(parsed.summary?.confirmationCode).assertEqual('130762');

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

    it('derivesSessionKeysFromSharedSecretAndTranscriptSaltVector', 0, () => {
      const service = new SessionKeyDerivationService();
      const derived = service.deriveSessionKeys(
        'Sl2dW6TOLeFyjjv0gDUPJeB-IclH0Z4zdvCbPB4WF0I',
        'RWdnQ2xpcCB2MSB0ZXN0IGhhbmRzaGFrZSBzYWx0'
      );

      expect(derived.ok).assertEqual(true);
      expect(derived.keys?.clientToServerKey).assertEqual('_CuE_7SfzdShnxyzHQy4IJ0zQjMAUVq-tynBZ2lBPYQ');
      expect(derived.keys?.serverToClientKey).assertEqual('TSo91xPhGNnQb2KPW6xyjJJFeHsimcUss0Rm2Tnbo2M');
      expect(service.sessionNonceBase64Url(SessionDirection.CLIENT_TO_SERVER, 12).nonce)
        .assertEqual('YzJzAQAAAAAAAAAM');
      expect(service.sessionNonceBase64Url(SessionDirection.SERVER_TO_CLIENT, 12).nonce)
        .assertEqual('czJjAQAAAAAAAAAM');

      const invalidSecret = service.deriveSessionKeys('AA', 'RWdnQ2xpcCB2MSB0ZXN0IGhhbmRzaGFrZSBzYWx0');
      expect(invalidSecret.ok).assertEqual(false);
      expect(invalidSecret.error).assertEqual(SessionKeyDerivationError.INVALID_LENGTH);
      expect(invalidSecret.field).assertEqual('sharedSecret');

      const invalidSalt = service.deriveSessionKeys('Sl2dW6TOLeFyjjv0gDUPJeB-IclH0Z4zdvCbPB4WF0I', '====');
      expect(invalidSalt.ok).assertEqual(false);
      expect(invalidSalt.error).assertEqual(SessionKeyDerivationError.INVALID_BASE64URL);
      expect(invalidSalt.field).assertEqual('transcriptSalt');
    });

    it('derivesX25519SharedSecretWithPlatformBoundaryWhenAvailable', 0, () => {
      const service = new X25519KeyAgreementService();
      const derived = service.deriveSharedSecret(
        'dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo',
        '3p7bfXt9wbTTW2HC7OQ1Nz-DQ8hbeGdNrfx-FG-IK08'
      );

      if (derived.ok) {
        expect(derived.sharedSecret).assertEqual('Sl2dW6TOLeFyjjv0gDUPJeB-IclH0Z4zdvCbPB4WF0I');
      } else {
        expect(derived.error).assertEqual(X25519KeyAgreementError.PLATFORM_CRYPTO_FAILED);
      }

      const generated = service.generateEphemeralKeyPair();
      if (generated.ok) {
        expect(decodeBase64Url(generated.privateKey ?? '')?.length).assertEqual(32);
        expect(decodeBase64Url(generated.publicKey ?? '')?.length).assertEqual(32);
      } else {
        expect(generated.error).assertEqual(X25519KeyAgreementError.PLATFORM_CRYPTO_FAILED);
      }

      const invalid = service.deriveSharedSecret('AA', '====');
      expect(invalid.ok).assertEqual(false);
      expect(invalid.error).assertEqual(X25519KeyAgreementError.INVALID_LENGTH);
      expect(invalid.field).assertEqual('privateKey');
    });

    it('validatesAesGcmCryptoServiceInputsBeforePlatformCrypto', 0, () => {
      const service = new AesGcmCryptoService();
      const invalidKey = service.encryptBase64Url(
        'AA',
        'AAAAAAAAAAAAAAAA',
        '',
        'AAAAAAAAAAAAAAAAAAAAAA'
      );
      expect(invalidKey.ok).assertEqual(false);
      expect(invalidKey.error).assertEqual(AesGcmCryptoError.INVALID_LENGTH);
      expect(invalidKey.field).assertEqual('key');

      const invalidNonce = service.encryptBase64Url(
        'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
        'AA',
        '',
        'AAAAAAAAAAAAAAAAAAAAAA'
      );
      expect(invalidNonce.ok).assertEqual(false);
      expect(invalidNonce.error).assertEqual(AesGcmCryptoError.INVALID_LENGTH);
      expect(invalidNonce.field).assertEqual('nonce');

      const invalidTag = service.decryptBase64Url(
        'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
        'AAAAAAAAAAAAAAAA',
        '',
        'zqdAPU1ga24HTsXTuvOdGA',
        'AA'
      );
      expect(invalidTag.ok).assertEqual(false);
      expect(invalidTag.error).assertEqual(AesGcmCryptoError.INVALID_LENGTH);
      expect(invalidTag.field).assertEqual('tag');

      const invalidBody = service.decryptBase64Url(
        'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
        'AAAAAAAAAAAAAAAA',
        '',
        '====',
        '0NHIp5mZa_AmW5i11Iq5GQ'
      );
      expect(invalidBody.ok).assertEqual(false);
      expect(invalidBody.error).assertEqual(AesGcmCryptoError.INVALID_BASE64URL);
      expect(invalidBody.field).assertEqual('body');
    });

    it('exposesEd25519SignatureVectorCryptoFrameworkBoundary', 0, () => {
      const service = new CryptoVectorService();
      const result = service.verifyEd25519SignatureVector(ED25519_SIGNATURE_VECTOR);

      expect(result.ok || result.error === CryptoVectorErrorCode.SIGNATURE_MISMATCH ||
        result.error === CryptoVectorErrorCode.PLATFORM_CRYPTO_FAILED).assertEqual(true);
    });

    it('exposesEd25519SigningVectorCryptoFrameworkBoundary', 0, () => {
      const service = new Ed25519SignatureService();
      const result = service.signVector(ED25519_SIGNATURE_VECTOR);
      if (result.ok) {
        expect(result.signature)
          .assertEqual('5VZDAMNgrHKQhuLMgG6CioSHfx645dl02HPgZSJJAVVfuIIVkKM7rMYeOXAc-bRr0lv18FlbviRlUUFDjnoQCw');
      } else {
        expect(result.error === Ed25519SignatureError.PLATFORM_CRYPTO_FAILED ||
          result.error === Ed25519SignatureError.SIGNATURE_MISMATCH).assertEqual(true);
      }

      const invalid = service.signMessage('AA', '');
      expect(invalid.ok).assertEqual(false);
      expect(invalid.error).assertEqual(Ed25519SignatureError.INVALID_LENGTH);
      expect(invalid.field).assertEqual('privateSeed');
    });

    it('generatesLocalEd25519IdentityMaterialBoundaryWhenAvailable', 0, () => {
      const service = new Ed25519IdentityService();
      const material = service.generateIdentityMaterial();

      if (material.ok) {
        expect(decodeBase64Url(material.identityPrivateKey ?? '')?.length).assertEqual(32);
        expect(decodeBase64Url(material.identityPublicKey ?? '')?.length).assertEqual(32);

        const publicOnlySnapshot = JSON.stringify({
          identityPublicKey: material.identityPublicKey
        });
        expect(publicOnlySnapshot.indexOf(material.identityPrivateKey ?? '')).assertEqual(-1);

        const signature = service.signAuthTranscript(
          material.identityPrivateKey ?? '',
          AUTH_PROOF_TRANSCRIPT
        );
        if (signature.ok) {
          expect(decodeBase64Url(signature.signature ?? '')?.length).assertEqual(64);
        } else {
          expect(signature.error).assertEqual(Ed25519IdentityError.SIGN_FAILED);
          expect(
            signature.signatureError === Ed25519SignatureError.PLATFORM_CRYPTO_FAILED ||
            signature.signatureError === Ed25519SignatureError.SIGNATURE_MISMATCH
          ).assertEqual(true);
        }
      } else {
        expect(material.error).assertEqual(Ed25519IdentityError.PLATFORM_CRYPTO_FAILED);
      }

      const invalid = service.signAuthTranscript('AA', AUTH_PROOF_TRANSCRIPT);
      expect(invalid.ok).assertEqual(false);
      expect(invalid.error).assertEqual(Ed25519IdentityError.INVALID_LENGTH);
      expect(invalid.field).assertEqual('identityPrivateKey');
    });

    it('buildsEd25519HuksIdentityAliasAndOperationOptions', 0, () => {
      const service = new Ed25519HuksIdentityService();
      const keyRef = service.buildLocalIdentityPrivateKeyRef('v1');
      expect(keyRef.ok).assertEqual(true);
      expect(keyRef.identityPrivateKeyRef).assertEqual('huks://eggclip/local-identity/ed25519/v1');

      const alias = service.huksAliasFromRef(keyRef.identityPrivateKeyRef ?? '');
      expect(alias.ok).assertEqual(true);
      expect(alias.huksAlias).assertEqual('eggclip.local-identity.ed25519.v1');

      const badSlot = service.buildLocalIdentityPrivateKeyRef('../bad');
      expect(badSlot.ok).assertEqual(false);
      expect(badSlot.error).assertEqual(Ed25519HuksIdentityError.INVALID_ALIAS_SLOT);

      const badRef = service.huksAliasFromRef('huks://eggclip/local-identity/ed25519/');
      expect(badRef.ok).assertEqual(false);
      expect(badRef.error).assertEqual(Ed25519HuksIdentityError.INVALID_KEY_REF);

      const generateOptions = service.generateOptions();
      expect((generateOptions.properties?.length ?? 0) >= 5).assertEqual(true);
      expect(generateOptions.inData === undefined).assertEqual(true);

      const signOptions = service.signOptions(AUTH_PROOF_TRANSCRIPT);
      expect((signOptions.properties?.length ?? 0) >= 3).assertEqual(true);
      expect((signOptions.inData?.length ?? 0) > 0).assertEqual(true);
    });

    it('ensuresLocalDeviceIdentityWithoutPersistingPrivateMaterial', 0, async () => {
      const metadata = new FakeLocalDeviceIdentityMetadataGateway();
      const secureIdentity = new FakeSecureIdentityGateway();
      const service = new LocalDeviceIdentityService(metadata, secureIdentity);

      const created = await service.ensureLocalIdentity(1700000000000, 'v1');
      expect(created.ok).assertEqual(true);
      expect(created.created).assertEqual(true);
      expect(created.identity?.deviceId).assertEqual('018ff6f0-4adf-7d31-a987-3ef2b25d0212');
      expect(created.identity?.identityPublicKey).assertEqual(FAKE_LOCAL_IDENTITY_PUBLIC_KEY);
      expect(created.identity?.identityPrivateKeyRef).assertEqual('huks://eggclip/local-identity/ed25519/v1');
      expect(metadata.savedPublicKey).assertEqual(FAKE_LOCAL_IDENTITY_PUBLIC_KEY);
      expect(metadata.savedPrivateKeyRef).assertEqual('huks://eggclip/local-identity/ed25519/v1');
      expect(JSON.stringify(metadata).indexOf('identityPrivateKey')).assertEqual(-1);

      const reused = await service.ensureLocalIdentity(1700000000500, 'v1');
      expect(reused.ok).assertEqual(true);
      expect(reused.created).assertEqual(false);
      expect(secureIdentity.generateCalls).assertEqual(1);
    });

    it('doesNotPersistLocalIdentityMetadataWhenHuksGenerationFails', 0, async () => {
      const metadata = new FakeLocalDeviceIdentityMetadataGateway();
      const secureIdentity = new FakeSecureIdentityGateway();
      secureIdentity.failGeneration = true;
      const service = new LocalDeviceIdentityService(metadata, secureIdentity);

      const result = await service.ensureLocalIdentity(1700000000000, 'v1');
      expect(result.ok).assertEqual(false);
      expect(result.error).assertEqual(LocalDeviceIdentityError.HUKS_FAILED);
      expect(result.huksError).assertEqual(Ed25519HuksIdentityError.PLATFORM_CRYPTO_FAILED);
      expect(metadata.savedPublicKey).assertEqual('');
      expect(metadata.savedPrivateKeyRef).assertEqual('');
    });

    it('reportsLocalIdentityMetadataStepWhenStorageFails', 0, async () => {
      const metadata = new FakeLocalDeviceIdentityMetadataGateway();
      metadata.failOnSavePrivateKeyRef = true;
      const secureIdentity = new FakeSecureIdentityGateway();
      const service = new LocalDeviceIdentityService(metadata, secureIdentity);

      const result = await service.ensureLocalIdentity(1700000000000, 'v1');

      expect(result.ok).assertEqual(false);
      expect(result.error).assertEqual(LocalDeviceIdentityError.STORAGE_FAILED);
      expect(result.field).assertEqual('saveIdentityPrivateKeyRefMetadata');
      expect(metadata.savedPublicKey).assertEqual(FAKE_LOCAL_IDENTITY_PUBLIC_KEY);
      expect(metadata.savedPrivateKeyRef).assertEqual('');
    });

    it('storesTrustedInboundItemLiveWithSpaceKeyEncryptedContent', 0, async () => {
      const storage = new FakeInboundItemLiveStorageGateway();
      const crypto = new FakeSpaceKeyAesGcmGateway();
      const service = new InboundItemLiveService(storage, crypto, new FakeSecureRandomGateway());
      const item = JSON.parse(CLIPBOARD_ITEM_FIXTURE) as JsonObject;

      const result = await service.accept({
        payload: item,
        expectedSpaceId: '018ff6ef-c394-7d08-8b99-4b7d10f2767a',
        expectedPeerDeviceId: '018ff6f0-0a3b-7815-a4db-3eb6e23d9338',
        nowMs: 1781946001123
      });

      expect(result.status).assertEqual(InboundItemLiveStatus.STORED);
      expect(storage.records.length).assertEqual(1);
      expect(storage.retentionCalls).assertEqual(1);
      expect(crypto.encryptCalls).assertEqual(1);
      const localEnvelope = String.fromCharCode(...storage.records[0].encryptedContent);
      expect(localEnvelope.indexOf('EggClip test text')).assertEqual(-1);
      expect(localEnvelope.indexOf('"body":"cipher-body"') >= 0).assertEqual(true);
    });

    it('rejectsItemLiveFromUnexpectedOriginBeforeLocalEncryption', 0, async () => {
      const storage = new FakeInboundItemLiveStorageGateway();
      const crypto = new FakeSpaceKeyAesGcmGateway();
      const service = new InboundItemLiveService(storage, crypto, new FakeSecureRandomGateway());
      const item = JSON.parse(CLIPBOARD_ITEM_FIXTURE) as JsonObject;

      const result = await service.accept({
        payload: item,
        expectedSpaceId: '018ff6ef-c394-7d08-8b99-4b7d10f2767a',
        expectedPeerDeviceId: '018ff6f0-4adf-7d31-a987-3ef2b25d0212',
        nowMs: 1781946001123
      });

      expect(result.status).assertEqual(InboundItemLiveStatus.REJECTED);
      expect(result.field).assertEqual('originDeviceId');
      expect(crypto.encryptCalls).assertEqual(0);
      expect(storage.records.length).assertEqual(0);
    });

    it('acceptsLiveRelayFromTrustedCoordinatorWithoutForgingOriginMembership', 0, async () => {
      const storage = new FakeInboundItemLiveStorageGateway();
      storage.missingDeviceId = '018ff6f0-0a3b-7815-a4db-3eb6e23d9338';
      const crypto = new FakeSpaceKeyAesGcmGateway();
      const service = new InboundItemLiveService(storage, crypto, new FakeSecureRandomGateway());
      const item = JSON.parse(CLIPBOARD_ITEM_FIXTURE) as JsonObject;

      const result = await service.accept({
        payload: item,
        expectedSpaceId: '018ff6ef-c394-7d08-8b99-4b7d10f2767a',
        expectedPeerDeviceId: '018ff6f0-4adf-7d31-a987-3ef2b25d0212',
        allowTrustedPeerRelay: true,
        nowMs: 1781946001123
      });

      expect(result.status).assertEqual(InboundItemLiveStatus.RELAYED);
      expect(crypto.encryptCalls).assertEqual(0);
      expect(storage.records.length).assertEqual(0);
      expect(storage.retentionCalls).assertEqual(0);
    });

    it('honorsInboundReceivePolicyBeforeWritingItemLiveHistory', 0, async () => {
      const storage = new FakeInboundItemLiveStorageGateway();
      storage.settings.autoReceiveEnabled = false;
      const crypto = new FakeSpaceKeyAesGcmGateway();
      const service = new InboundItemLiveService(storage, crypto, new FakeSecureRandomGateway());
      const item = JSON.parse(CLIPBOARD_ITEM_FIXTURE) as JsonObject;

      const result = await service.accept({
        payload: item,
        expectedSpaceId: '018ff6ef-c394-7d08-8b99-4b7d10f2767a',
        expectedPeerDeviceId: '018ff6f0-0a3b-7815-a4db-3eb6e23d9338',
        nowMs: 1781946001123
      });

      expect(result.status).assertEqual(InboundItemLiveStatus.IGNORED_BY_POLICY);
      expect(crypto.encryptCalls).assertEqual(0);
      expect(storage.records.length).assertEqual(0);
    });

    it('reinitializesPairingSecurityOnlyAfterAllHuksKeysAreRemoved', 0, async () => {
      const repository = new FakeSpaceKeyRecoveryRepository([
        'huks://eggclip/space-key/018ff6ef-c394-7d08-8b99-4b7d10f2767a/v1',
        'huks://eggclip/space-key/018ff6ef-c394-7d08-8b99-4b7d10f2767b/v2'
      ]);
      const destroyer = new FakeSpaceKeyDestroyer();
      const result = await new SpaceKeyRecoveryService(repository, destroyer)
        .reinitializePairingSecurityState();

      expect(result.ok).assertEqual(true);
      expect(result.clearedKeyRefs).assertEqual(2);
      expect(destroyer.deletedRefs.length).assertEqual(2);
      expect(repository.resetCalls).assertEqual(1);
    });

    it('keepsPairingDatabaseWhenHuksKeyRemovalFails', 0, async () => {
      const repository = new FakeSpaceKeyRecoveryRepository([
        'huks://eggclip/space-key/018ff6ef-c394-7d08-8b99-4b7d10f2767a/v1'
      ]);
      const destroyer = new FakeSpaceKeyDestroyer();
      destroyer.failDelete = true;
      const result = await new SpaceKeyRecoveryService(repository, destroyer)
        .reinitializePairingSecurityState();

      expect(result.ok).assertEqual(false);
      expect(result.error).assertEqual(SpaceKeyRecoveryError.HUKS_DELETE_FAILED);
      expect(repository.resetCalls).assertEqual(0);
    });

    it('clearsDamagedSpaceKeyReferenceMetadataThatCannotResolveHuksAlias', 0, async () => {
      const repository = new FakeSpaceKeyRecoveryRepository(['damaged-key-reference']);
      const destroyer = new FakeSpaceKeyDestroyer();
      destroyer.invalidRef = true;
      const result = await new SpaceKeyRecoveryService(repository, destroyer)
        .reinitializePairingSecurityState();

      expect(result.ok).assertEqual(true);
      expect(result.clearedKeyRefs).assertEqual(0);
      expect(result.invalidKeyRefs).assertEqual(1);
      expect(repository.resetCalls).assertEqual(1);
    });

    it('prefersMatchingFormalMdnsCandidateAndIgnoresUntrustedDeviceIds', 0, () => {
      const trustedDeviceId = '018ff6f0-0a3b-7815-a4db-3eb6e23d9338';
      const endpoint = trustedDiscoveryEndpoint(trustedDeviceId, [{
        instanceId: trustedDeviceId,
        serviceName: 'eggclip-desktop',
        host: '192.168.1.20',
        port: 4567,
        protocolVersion: 1
      }]);
      const rejected = trustedDiscoveryEndpoint(trustedDeviceId, [{
        instanceId: '018ff6f0-4adf-7d31-a987-3ef2b25d0212',
        serviceName: 'eggclip-other',
        host: '192.168.1.21',
        port: 4567,
        protocolVersion: 1
      }]);

      expect(endpoint?.host).assertEqual('192.168.1.20');
      expect(endpoint?.port).assertEqual(4567);
      expect(rejected === null).assertEqual(true);
    });

    it('keepsPairingAuthErrorsAsStableCodes', 0, () => {
      expect(pairingAuthErrorCode(JSON.parse('{"code":"invitationExpired"}') as JsonObject))
        .assertEqual('invitationExpired');
      expect(pairingAuthErrorCode(JSON.parse('{"code":"invitationConsumed"}') as JsonObject))
        .assertEqual('invitationConsumed');
      expect(pairingAuthErrorCode(JSON.parse('{"code":"identityOrSpaceMismatch"}') as JsonObject))
        .assertEqual('identityOrSpaceMismatch');
      const sharedError = new ProtocolParser().parseEnvelope(AUTH_ERROR_INVITATION_CONSUMED_VECTOR);
      expect(sharedError.ok).assertEqual(true);
      expect(pairingAuthErrorCode(sharedError.envelope?.payload)).assertEqual('invitationConsumed');
    });
  });
}

const FAKE_LOCAL_IDENTITY_PUBLIC_KEY: string = '11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo';

class FakeSpaceKeyRecoveryRepository implements SpaceKeyRecoveryRepository {
  private readonly refs: string[];
  resetCalls: number = 0;

  constructor(refs: string[]) {
    this.refs = refs;
  }

  async listEncryptedSpaceKeyRefs(): Promise<string[]> {
    return this.refs.slice();
  }

  async resetPairingSecurityState(): Promise<void> {
    this.resetCalls += 1;
  }
}

class FakeSpaceKeyDestroyer implements SpaceKeyDestroyer {
  deletedRefs: string[] = [];
  failDelete: boolean = false;
  invalidRef: boolean = false;

  async deleteSpaceKey(encryptedSpaceKeyRef: string): Promise<SpaceKeyHuksDeleteResult> {
    this.deletedRefs.push(encryptedSpaceKeyRef);
    if (this.failDelete) {
      return { ok: false, error: SpaceKeyHuksError.PLATFORM_CRYPTO_FAILED, field: 'deleteAesKeyItem' };
    }
    if (this.invalidRef) {
      return { ok: false, error: SpaceKeyHuksError.INVALID_KEY_REF, field: 'encryptedSpaceKeyRef' };
    }
    return { ok: true };
  }
}

function spaceKeyDeliveryPayload(
  spaceId: string,
  keyVersion: number,
  keyBytes: number,
  delivery: string
): JsonObject {
  const encodedKey = encodeBase64Url(new Uint8Array(keyBytes));
  return JSON.parse(`{"spaceId":"${spaceId}","keyVersion":${keyVersion},"spaceKey":"${encodedKey}","delivery":"${delivery}"}`) as JsonObject;
}

function spaceKeyDeliveryInput(
  payload: JsonObject | undefined,
  expectedSpaceId: string,
  expectedKeyVersion: number
): SpaceKeyDeliveryInput {
  return new FakeSpaceKeyDeliveryInput(payload, expectedSpaceId, expectedKeyVersion);
}

class FakeSpaceKeyDeliveryInput implements SpaceKeyDeliveryInput {
  payload?: JsonObject;
  expectedSpaceId: string;
  expectedKeyVersion: number;

  constructor(payload: JsonObject | undefined, expectedSpaceId: string, expectedKeyVersion: number) {
    this.payload = payload;
    this.expectedSpaceId = expectedSpaceId;
    this.expectedKeyVersion = expectedKeyVersion;
  }
}

class FakeSpaceKeyImporter implements SpaceKeySecureImporter {
  importCalls: number = 0;
  importedRef: string = '';
  importedKeyLength: number = 0;
  failImport: boolean = false;

  async importSpaceKey(encryptedSpaceKeyRef: string, key: Uint8Array): Promise<SpaceKeyHuksImportResult> {
    this.importCalls += 1;
    this.importedRef = encryptedSpaceKeyRef;
    this.importedKeyLength = key.length;
    if (this.failImport) {
      return new FakeSpaceKeyHuksImportResult(
        false,
        '',
        undefined,
        SpaceKeyHuksError.PLATFORM_CRYPTO_FAILED,
        'importKeyItem'
      );
    }
    return new FakeSpaceKeyHuksImportResult(
      true,
      encryptedSpaceKeyRef,
      'eggclip.space-key.fake',
      undefined,
      undefined
    );
  }
}

class FakeSpaceKeyHuksImportResult implements SpaceKeyHuksImportResult {
  ok: boolean;
  encryptedSpaceKeyRef: string;
  huksAlias?: string;
  error?: SpaceKeyHuksError;
  field?: string;

  constructor(
    ok: boolean,
    encryptedSpaceKeyRef: string,
    huksAlias: string | undefined,
    error: SpaceKeyHuksError | undefined,
    field: string | undefined
  ) {
    this.ok = ok;
    this.encryptedSpaceKeyRef = encryptedSpaceKeyRef;
    this.huksAlias = huksAlias;
    this.error = error;
    this.field = field;
  }
}

class FakeSpaceKeyRefProvider implements SpaceKeyRefProvider {
  private readonly encryptedSpaceKeyRef: string | null;

  constructor(encryptedSpaceKeyRef: string | null) {
    this.encryptedSpaceKeyRef = encryptedSpaceKeyRef;
  }

  async loadLatestEncryptedSpaceKeyRef(): Promise<string | null> {
    return this.encryptedSpaceKeyRef;
  }
}

class FakeSpaceKeyAesGcmGateway implements SpaceKeyAesGcmGateway {
  encryptCalls: number = 0;
  decryptCalls: number = 0;
  lastPlaintext: string = '';
  returnMismatchedPlaintext: boolean = false;

  async encryptBase64Url(
    _: string,
    __: string,
    ___: string,
    plaintextBase64Url: string
  ): Promise<SpaceKeyHuksEncryptResult> {
    this.encryptCalls += 1;
    this.lastPlaintext = plaintextBase64Url;
    return new FakeSpaceKeyHuksEncryptResult(true, 'cipher-body', 'cipher-tag', undefined, undefined);
  }

  async decryptBase64Url(
    _: string,
    __: string,
    ___: string,
    ____: string,
    _____: string
  ): Promise<SpaceKeyHuksDecryptResult> {
    this.decryptCalls += 1;
    if (this.returnMismatchedPlaintext) {
      return new FakeSpaceKeyHuksDecryptResult(true, 'mismatch', undefined, undefined);
    }
    return new FakeSpaceKeyHuksDecryptResult(true, this.lastPlaintext, undefined, undefined);
  }
}

class FakeInboundItemLiveStorageGateway implements InboundItemLiveStorageGateway {
  settings: AppSettings = defaultAppSettings();
  records: ClipboardItemRecord[] = [];
  retentionCalls: number = 0;
  decision: ClipboardDedupDecision = ClipboardDedupDecision.NEW;
  missingDeviceId: string = '';

  async loadSettings(): Promise<AppSettings> {
    return this.settings;
  }

  async loadSpace(_: string): Promise<SpaceRecord | null> {
    const space: DomainSpace = {
      spaceId: '018ff6ef-c394-7d08-8b99-4b7d10f2767a',
      displayName: '测试空间',
      keyVersion: 1,
      state: DomainSpaceState.ACTIVE,
      createdAt: 1781946000000
    };
    return {
      space,
      nameOrigin: DisplayNameOrigin.CUSTOM,
      encryptedSpaceKeyRef: 'huks://eggclip/space-key/018ff6ef-c394-7d08-8b99-4b7d10f2767a/v1',
      updatedAt: 1781946000000
    };
  }

  async loadDevice(deviceId: string): Promise<DeviceRecord | null> {
    if (deviceId === this.missingDeviceId) return null;
    const device: DomainDevice = {
      deviceId,
      spaceId: '018ff6ef-c394-7d08-8b99-4b7d10f2767a',
      displayName: '测试桌面端',
      identityPublicKeyRef: FAKE_LOCAL_IDENTITY_PUBLIC_KEY,
      trustState: DomainDeviceTrustState.TRUSTED,
      connectionState: DomainDeviceConnectionState.ONLINE,
      lastSeenAt: 1781946000000
    };
    return { device, nameOrigin: DisplayNameOrigin.CUSTOM, pairedAt: 1781946000000 };
  }

  async insertDeduplicated(record: ClipboardItemRecord): Promise<ClipboardDedupDecision> {
    if (this.decision === ClipboardDedupDecision.NEW) {
      this.records.push(record);
    }
    return this.decision;
  }

  async applyRetention(_: string, __: AppSettings, ___: number): Promise<void> {
    this.retentionCalls += 1;
  }
}

class FakeSecureRandomGateway implements SecureRandomGateway {
  async randomBytes(length: number): Promise<Uint8Array> {
    return new Uint8Array(length).fill(0x5a);
  }
}

class FakeSpaceKeyHuksEncryptResult implements SpaceKeyHuksEncryptResult {
  ok: boolean;
  body?: string;
  tag?: string;
  error?: SpaceKeyHuksError;
  field?: string;

  constructor(
    ok: boolean,
    body: string | undefined,
    tag: string | undefined,
    error: SpaceKeyHuksError | undefined,
    field: string | undefined
  ) {
    this.ok = ok;
    this.body = body;
    this.tag = tag;
    this.error = error;
    this.field = field;
  }
}

class FakeSpaceKeyHuksDecryptResult implements SpaceKeyHuksDecryptResult {
  ok: boolean;
  plaintext?: string;
  error?: SpaceKeyHuksError;
  field?: string;

  constructor(
    ok: boolean,
    plaintext: string | undefined,
    error: SpaceKeyHuksError | undefined,
    field: string | undefined
  ) {
    this.ok = ok;
    this.plaintext = plaintext;
    this.error = error;
    this.field = field;
  }
}

class FakeLocalDeviceIdentityMetadataGateway implements LocalDeviceIdentityMetadataGateway {
  savedPublicKey: string = '';
  savedPrivateKeyRef: string = '';
  failOnSavePrivateKeyRef: boolean = false;
  private readonly deviceIdValue: string = '018ff6f0-4adf-7d31-a987-3ef2b25d0212';

  async getOrCreateDeviceId(_: number): Promise<string> {
    return this.deviceIdValue;
  }

  async loadLocalIdentityPublicKey(): Promise<string | null> {
    return this.savedPublicKey.length > 0 ? this.savedPublicKey : null;
  }

  async saveLocalIdentityPublicKey(identityPublicKey: string, _: number): Promise<void> {
    this.savedPublicKey = identityPublicKey;
  }

  async loadLocalIdentityPrivateKeyRef(): Promise<string | null> {
    return this.savedPrivateKeyRef.length > 0 ? this.savedPrivateKeyRef : null;
  }

  async saveLocalIdentityPrivateKeyRef(identityPrivateKeyRef: string, _: number): Promise<void> {
    if (this.failOnSavePrivateKeyRef) {
      throw new Error('metadata write failed');
    }
    this.savedPrivateKeyRef = identityPrivateKeyRef;
  }
}

class FakeSecureIdentityGateway implements LocalDeviceSecureIdentityGateway {
  failGeneration: boolean = false;
  generateCalls: number = 0;

  buildLocalIdentityPrivateKeyRef(aliasSlot?: string): Ed25519HuksKeyRefResult {
    return {
      ok: true,
      identityPrivateKeyRef: `huks://eggclip/local-identity/ed25519/${aliasSlot ?? 'v1'}`
    };
  }

  async generateOrLoadIdentity(identityPrivateKeyRef: string): Promise<Ed25519HuksIdentityMaterialResult> {
    this.generateCalls += 1;
    if (this.failGeneration) {
      return {
        ok: false,
        error: Ed25519HuksIdentityError.PLATFORM_CRYPTO_FAILED,
        field: 'generateKeyItem'
      };
    }
    return {
      ok: true,
      identityPublicKey: FAKE_LOCAL_IDENTITY_PUBLIC_KEY,
      identityPrivateKeyRef
    };
  }
}

class FakePairingClientAuthProofSigner implements PairingClientAuthProofSigner {
  failSigning: boolean = false;
  privateKeyRef: string = '';
  canonicalTranscript: string = '';

  async signAuthTranscriptWithRef(
    identityPrivateKeyRef: string,
    canonicalTranscript: string
  ): Promise<Ed25519HuksSignatureResult> {
    this.privateKeyRef = identityPrivateKeyRef;
    this.canonicalTranscript = canonicalTranscript;
    if (this.failSigning) {
      return {
        ok: false,
        error: Ed25519HuksIdentityError.PLATFORM_CRYPTO_FAILED,
        field: 'signAuthTranscript'
      };
    }
    return {
      ok: true,
      signature: TEST_ED25519_SIGNATURE
    };
  }
}

class FakePairingServerAuthProofValidator implements PairingAuthProofValidator {
  verifyPayloadSignatureAgainstTranscript(
    payload: AuthProofPayload,
    expectedRole: AuthRole,
    transcript: PairingAuthTranscriptDraft,
    remoteIdentityPublicKey: string
  ): PairingAuthProofValidationResult {
    const shape = new PairingAuthProofValidationService()
      .validatePayloadAgainstTranscript(payload, expectedRole, transcript);
    if (!shape.ok) return shape;
    const expectedSignature = serverAuthProofSignature(
      transcript.input.remoteIdentityPublicKey,
      transcript.input.localEphemeralPublicKey
    );
    if (remoteIdentityPublicKey !== transcript.input.localIdentityPublicKey ||
      expectedSignature.length === 0 || payload.signature !== expectedSignature) {
      return {
        ok: false,
        error: PairingAuthProofValidationError.SIGNATURE_VERIFY_FAILED,
        field: 'signature'
      };
    }
    return { ok: true };
  }
}

class FakePairingWebSocketTransportService extends WebSocketTransportService {
  sentFrames: string[] = [];
  connectedEndpoint: string = '';
  private callbacks: PairingHandshakeTransportCallbacks | null = null;

  async connectPairingHandshake(
    endpoint: ManualEndpoint,
    _: ProtocolHandshakeTransportSession,
    callbacks: PairingHandshakeTransportCallbacks
  ): Promise<EndpointValidationResult> {
    this.callbacks = callbacks;
    this.connectedEndpoint = `${endpoint.host}:${endpoint.port}`;
    callbacks.onOpen();
    return {
      ok: true,
      normalizedUrl: `ws://${endpoint.host}:${endpoint.port}`
    };
  }

  async sendTextFrame(frame: string): Promise<boolean> {
    this.sentFrames.push(frame);
    return true;
  }

  emitTextFrame(message: string, result: ProtocolTransportFrameResult): void {
    if (this.callbacks !== null && this.callbacks.onTextFrame !== undefined) {
      this.callbacks.onTextFrame(message, result);
    }
  }

  emitClose(reason: string): void {
    if (this.callbacks !== null) {
      this.callbacks.onClose(reason);
    }
  }

  close(): void {
    this.callbacks = null;
  }
}

class FakeProtocolAesGcmGateway implements ProtocolAesGcmGateway {
  encryptBase64Url(
    _key: string,
    _nonce: string,
    _aad: string,
    _plaintext: string
  ): AesGcmEncryptResult {
    return {
      ok: true,
      body: encodeBase64Url(new Uint8Array([1, 2, 3])),
      tag: encodeBase64Url(new Uint8Array(16))
    };
  }

  decryptBase64Url(
    _key: string,
    _nonce: string,
    _aad: string,
    _body: string,
    _tag: string
  ): AesGcmDecryptResult {
    return { ok: false, error: AesGcmCryptoError.PLATFORM_CRYPTO_FAILED, field: 'test' };
  }
}

function outboundPayloadFixture(): JsonObject {
  return JSON.parse('{"itemId":"018ff6f3-3653-7c79-b38b-f4af3575396b"}') as JsonObject;
}

function emptyOutboundPayloadFixture(): JsonObject {
  return JSON.parse('{}') as JsonObject;
}

function encryptedFrameWithCanonicalAad(
  messageType: MessageType,
  messageId: string,
  sessionCounter: number,
  keyId: string
): string {
  const aad = canonicalEncryptedAad(messageType, messageId, sessionCounter, keyId) ?? '';
  const envelope: EncryptedFrameFixture = {
    version: PROTOCOL_VERSION,
    type: messageType,
    messageId,
    sessionCounter,
    ciphertext: {
      algorithm: AeadAlgorithm.AES_256_GCM,
      keyId,
      nonce: 'YzJzAQAAAAAAAAAM',
      aad: encodeBase64Url(asciiBytes(aad)),
      body: 'FFFFFFFFFFFFFFFF',
      tag: 'GGGGGGGGGGGGGGGGGGGGGG'
    }
  };
  return JSON.stringify(envelope);
}

interface EncryptedFrameFixture {
  version: number;
  type: MessageType;
  messageId: string;
  sessionCounter: number;
  ciphertext: EncryptedCiphertextFixture;
}

interface EncryptedCiphertextFixture {
  algorithm: AeadAlgorithm;
  keyId: string;
  nonce: string;
  aad: string;
  body: string;
  tag: string;
}

function pairingDraftFixture(): PairingHandshakeDraft | null {
  const store = new PairingStore();
  store.importInvitationText(PAIRING_INVITATION_FIXTURE, 1700000000000);
  store.confirmCodeMatched();
  const draft = store.buildPendingClientHandshakeDraft(
    '018ff6f0-4adf-7d31-a987-3ef2b25d0212',
    '3p7bfXt9wbTTW2HC7OQ1Nz-DQ8hbeGdNrfx-FG-IK08',
    'hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo',
    1700000000000
  );
  return draft.ok && draft.draft !== undefined ? draft.draft : null;
}

function serverAuthProofFrame(
  draft: PairingHandshakeDraft,
  serverHelloFrame: string
): string {
  const parser = new ProtocolParser();
  const envelope = parser.parseEnvelope(serverHelloFrame);
  const serverHello = parser.parseHelloPayload(envelope.envelope?.payload);
  if (!serverHello.ok || serverHello.payload === undefined) return '';
  const transcript = new PairingHandshakeDraftService()
    .buildServerAuthTranscriptDraft(draft, serverHello.payload);
  if (!transcript.ok || transcript.transcript === undefined) return '';
  const signature = serverAuthProofSignature(
    draft.clientHelloPayload.identityPublicKey,
    serverHello.payload.ephemeralPublicKey
  );
  if (signature.length === 0) return '';
  const frame = new ProtocolFrameBuilderService().buildAuthProofFrame(
    AuthRole.SERVER,
    transcript.transcript.canonicalTranscript,
    signature,
    '018ff6f1-2d2a-725d-8d1a-894d2f5b0a43',
    3
  );
  return frame.ok ? frame.frame ?? '' : '';
}

function serverAuthProofSignature(clientIdentityPublicKey: string, serverEphemeralPublicKey: string): string {
  if (clientIdentityPublicKey === '3p7bfXt9wbTTW2HC7OQ1Nz-DQ8hbeGdNrfx-FG-IK08') {
    if (serverEphemeralPublicKey === 'Sl2dW6TOLeFyjjv0gDUPJeB-IclH0Z4zdvCbPB4WF0I') {
      return 'Dkhen_0izxf7UiTfsR3G8OMkeZlmc3_hHbrUulWleqSHR5qy13fU_UmKfj4xUvJqeEDX7vWbdDBb1uJst6wfCA';
    }
    if (serverEphemeralPublicKey === '3p7bfXt9wbTTW2HC7OQ1Nz-DQ8hbeGdNrfx-FG-IK08') {
      return 'qlkErZkC7rsPLlQKa46Yc5BfzB70TuiOiPYMHKUvA-yLM93b1zT_QbGiSuxJkg2BAb1brY4CGPIJSf8qpzeBDg';
    }
  }
  if (clientIdentityPublicKey === '11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo') {
    if (serverEphemeralPublicKey === 'Sl2dW6TOLeFyjjv0gDUPJeB-IclH0Z4zdvCbPB4WF0I') {
      return '-iGNKJQCjfdqKSBo7eIDq5DmsbHBemI8ObJmte4dHEMj7fcn0pafjGd6mp9iGQBm97Yhsi4CfEYIylII6T30DA';
    }
    if (serverEphemeralPublicKey === '3p7bfXt9wbTTW2HC7OQ1Nz-DQ8hbeGdNrfx-FG-IK08') {
      return 'KbteWArU3Lr9SwMWNcduS18z9kqoOmicWN0YZUBbxT23FhLCLYniOeHrJ7G-FaRto4G_ePkAHxvzC6Azad_YDw';
    }
  }
  return '';
}

function pairingMaterialFixture(): PairingGeneratedHandshakeMaterialResult | null {
  const draft = pairingDraftFixture();
  if (draft === null) {
    return null;
  }
  return {
    ok: true,
    draft,
    localDeviceId: '018ff6f0-4adf-7d31-a987-3ef2b25d0212',
    localIdentityPublicKey: '3p7bfXt9wbTTW2HC7OQ1Nz-DQ8hbeGdNrfx-FG-IK08',
    localIdentityPrivateKeyRef: 'huks://eggclip/local-identity/ed25519/v1',
    localEphemeralPrivateKey: 'dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo',
    localEphemeralPublicKey: 'hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo'
  };
}

const PAIRING_INVITATION_FIXTURE: string = 'eggclip://pair?p=eyJhcHAiOiJlZ2djbGlwIiwidmVyc2lvbiI6Miwia2luZCI6InBhaXJpbmdJbnZpdGF0aW9uIiwiaW52aXRhdGlvbklkIjoiMDE4ZmY2ZjAtMTExMS03MjIyLTgzMzMtMTIzNDU2Nzg5YWJjIiwic3BhY2VJZCI6IjAxOGZmNmVmLWMzOTQtN2QwOC04Yjk5LTRiN2QxMGYyNzY3YSIsInNwYWNlS2V5VmVyc2lvbiI6MSwiaXNzdWVyRGV2aWNlSWQiOiIwMThmZjZmMC0wYTNiLTc4MTUtYTRkYi0zZWI2ZTIzZDkzMzgiLCJpc3N1ZXJJZGVudGl0eVB1YmxpY0tleSI6IjExcVlBWUt4Q3JmVlNfN1R5V1FIT2c3aGN2UGFwaU1scndJYWFQY0hVUm8iLCJwYWlyaW5nU2VjcmV0IjoiQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQSIsImV4cGlyZXNBdE1zIjoxNzAwMDAwMzAwMDAwfQ';

const BAD_PAIRING_SECRET_INVITATION_FIXTURE: string = 'eggclip://pair?p=eyJhcHAiOiJlZ2djbGlwIiwidmVyc2lvbiI6Miwia2luZCI6InBhaXJpbmdJbnZpdGF0aW9uIiwic3BhY2VJZCI6IjAxOGZmNmVmLWMzOTQtN2QwOC04Yjk5LTRiN2QxMGYyNzY3YSIsInNwYWNlS2V5VmVyc2lvbiI6MSwiaXNzdWVyRGV2aWNlSWQiOiIwMThmZjZmMC0wYTNiLTc4MTUtYTRkYi0zZWI2ZTIzZDkzMzgiLCJpc3N1ZXJJZGVudGl0eVB1YmxpY0tleSI6IjExcVlBWUt4Q3JmVlNfN1R5V1FIT2c3aGN2UGFwaU1scndJYWFQY0hVUm8iLCJwYWlyaW5nU2VjcmV0IjoiQUEiLCJleHBpcmVzQXRNcyI6MTcwMDAwMDMwMDAwMH0';

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
    version: 2,
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

const SERVER_HELLO_FRAME_FOR_PAIRING_FIXTURE: string = '{"version":1,"type":"SERVER_HELLO","messageId":"018ff6f1-0000-7000-8000-000000000001","sessionCounter":1,"payload":{"spaceId":"018ff6ef-c394-7d08-8b99-4b7d10f2767a","deviceId":"018ff6f0-0a3b-7815-a4db-3eb6e23d9338","identityPublicKey":"11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo","ephemeralPublicKey":"Sl2dW6TOLeFyjjv0gDUPJeB-IclH0Z4zdvCbPB4WF0I","capabilities":["textPlain","syncHeads"]}}';

const SERVER_HELLO_FRAME_FOR_X25519_FIXTURE: string = '{"version":1,"type":"SERVER_HELLO","messageId":"018ff6f1-0000-7000-8000-000000000003","sessionCounter":1,"payload":{"spaceId":"018ff6ef-c394-7d08-8b99-4b7d10f2767a","deviceId":"018ff6f0-0a3b-7815-a4db-3eb6e23d9338","identityPublicKey":"11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo","ephemeralPublicKey":"3p7bfXt9wbTTW2HC7OQ1Nz-DQ8hbeGdNrfx-FG-IK08","capabilities":["textPlain","syncHeads"]}}';

const SERVER_HELLO_FRAME_WITH_WRONG_IDENTITY_FIXTURE: string = '{"version":1,"type":"SERVER_HELLO","messageId":"018ff6f1-0000-7000-8000-000000000002","sessionCounter":1,"payload":{"spaceId":"018ff6ef-c394-7d08-8b99-4b7d10f2767a","deviceId":"018ff6f0-0a3b-7815-a4db-3eb6e23d9338","identityPublicKey":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","ephemeralPublicKey":"Sl2dW6TOLeFyjjv0gDUPJeB-IclH0Z4zdvCbPB4WF0I","capabilities":["textPlain","syncHeads"]}}';

const AUTH_OK_FIXTURE: string = '{"version":1,"type":"AUTH_OK","messageId":"018ff6f1-25f0-7c09-a4cf-3d683ebfae33","sessionCounter":4,"payload":{}}';

const AUTH_OK_OLD_COUNTER_FIXTURE: string = '{"version":1,"type":"AUTH_OK","messageId":"018ff6f1-25f0-7c09-a4cf-3d683ebfae33","sessionCounter":1,"payload":{}}';

const AUTH_ERROR_FIXTURE: string = '{"version":1,"type":"AUTH_ERROR","messageId":"018ff6f1-35f0-7c09-a4cf-3d683ebfae33","sessionCounter":3,"payload":{"code":"authFailed"}}';

const ENCRYPTED_ITEM_LIVE_FIXTURE: string = '{"version":1,"type":"ITEM_LIVE","messageId":"018ff6f3-0d8c-7d1e-a38a-f308c64de79f","sessionCounter":12,"ciphertext":{"algorithm":"AES-256-GCM","keyId":"session-v1-client-to-server","nonce":"DDDDDDDDDDDDDDDD","aad":"EEEEEEEEEEEEEEEE","body":"FFFFFFFFFFFFFFFF","tag":"GGGGGGGGGGGGGGGGGGGGGG"}}';

const ENCRYPTED_ERROR_FIXTURE: string = '{"version":1,"type":"ERROR","messageId":"018ff6f4-0d8c-7d1e-a38a-f308c64de79f","sessionCounter":12,"ciphertext":{"algorithm":"AES-256-GCM","keyId":"session-v1-client-to-server","nonce":"DDDDDDDDDDDDDDDD","aad":"EEEEEEEEEEEEEEEE","body":"FFFFFFFFFFFFFFFF","tag":"GGGGGGGGGGGGGGGGGGGGGG"}}';

const CLIPBOARD_ITEM_FIXTURE: string = '{"itemId":"018ff6f3-3653-7c79-b38b-f4af3575396b","spaceId":"018ff6ef-c394-7d08-8b99-4b7d10f2767a","originDeviceId":"018ff6f0-0a3b-7815-a4db-3eb6e23d9338","originSeq":42,"hlc":"1781946000123:0:018ff6f0","contentType":"text/plain","contentLength":17,"contentDigest":"CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC","createdAt":1781946000123,"content":"EggClip test text"}';

const UNKNOWN_VERSION_FIXTURE: string = '{"version":2,"type":"CLIENT_HELLO","messageId":"018ff6f0-2b1f-7cc5-b5d0-7e82c5f70f01","sessionCounter":0,"payload":{}}';

const POST_AUTH_PLAINTEXT_FIXTURE: string = '{"version":1,"type":"ITEM_LIVE","messageId":"018ff6f3-0d8c-7d1e-a38a-f308c64de79f","sessionCounter":12,"payload":{"content":"must not be plaintext after auth"}}';

const PRE_AUTH_CIPHERTEXT_FIXTURE: string = '{"version":1,"type":"CLIENT_HELLO","messageId":"018ff6f0-2b1f-7cc5-b5d0-7e82c5f70f01","sessionCounter":0,"ciphertext":{"algorithm":"AES-256-GCM","keyId":"session-v1-client-to-server","nonce":"DDDDDDDDDDDDDDDD","aad":"EEEEEEEEEEEEEEEE","body":"FFFFFFFFFFFFFFFF","tag":"GGGGGGGGGGGGGGGGGGGGGG"}}';
