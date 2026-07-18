import {
  PairingStore,
  PairingStoreSnapshot,
  PairingStoreState,
  createInitialPairingSnapshot
} from '../store/PairingStore';
import {
  PairingConnectionSnapshot,
  PairingConnectionState,
  pairingConnectionStore
} from '../store/PairingConnectionStore';
import { TrustedDeviceStore } from '../store/TrustedDeviceStore';
import { common } from '@kit.AbilityKit';
import {
  PairingConnectionEndpoint,
  PairingInvitationSummary
} from '../services/pairing/PairingInvitationService';
import { PairingScanService } from '../services/pairing/PairingScanService';
import { ClipboardBridgeService } from '../services/clipboard/ClipboardBridgeService';
import { EggClipColors } from '../theme/Colors';
import { EggClipSpacing } from '../theme/Spacing';
import { EggClipTypography } from '../theme/Typography';
import { UiMessageDescriptor } from '../services/localization/UiMessageCodes';
import { UiMessageFormatter } from '../services/localization/UiMessageFormatter';

@Component
export struct PairingPage {
  private readonly pairingStore: PairingStore = new PairingStore();
  private readonly clipboardBridge: ClipboardBridgeService = new ClipboardBridgeService();
  private readonly pairingScanService: PairingScanService = new PairingScanService();
  private messageFormatter: UiMessageFormatter | null = null;
  @State private snapshot: PairingStoreSnapshot = createInitialPairingSnapshot();
  @State private connectionSnapshot: PairingConnectionSnapshot = pairingConnectionStore.snapshot();
  @State private invitationInputText: string = '';
  @State private pasteImportStatus: string = '';
  @State private pairingCompleted: boolean = false;
  private pendingProgrammaticInvitationInput: string | null = null;
  private pairingHandshakeInFlight: boolean = false;
  private readonly connectionListener = (snapshot: PairingConnectionSnapshot): void => {
    this.connectionSnapshot = snapshot;
    if ((snapshot.authenticated || snapshot.state === PairingConnectionState.AUTHENTICATED) &&
      this.pairingHandshakeInFlight && this.snapshot.state === PairingStoreState.PENDING) {
      this.pairingHandshakeInFlight = false;
      this.pairingCompleted = true;
      // The invitation is single-use. Drop its secret and pending handshake
      // material only when this page's pending pairing becomes authenticated.
      // Normal traffic on an existing session must not clear a newly imported
      // invitation that the user is still reviewing.
      this.snapshot = this.pairingStore.completePairing();
    } else if (snapshot.state === PairingConnectionState.FAILED ||
      snapshot.state === PairingConnectionState.IDLE) {
      this.pairingHandshakeInFlight = false;
    }
  };

  aboutToAppear(): void {
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext !== undefined) {
      this.messageFormatter = new UiMessageFormatter(hostContext as common.Context);
      if (this.pasteImportStatus.length === 0) {
        this.pasteImportStatus = this.resourceText('pairing_paste_help');
      }
    }
    pairingConnectionStore.subscribe(this.connectionListener);
  }

  aboutToDisappear(): void {
    pairingConnectionStore.unsubscribe(this.connectionListener);
  }

  build() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 4 }) {
          Text(this.resourceText('pairing_import_title'))
            .fontSize(EggClipTypography.bodySize)
            .fontWeight(FontWeight.Bold)
            .fontColor(EggClipColors.textPrimary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text(this.statusBadgeText())
          .fontSize(11)
          .fontColor(this.statusColor())
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor(EggClipColors.controlBackground)
          .borderRadius(14)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      if (this.snapshot.summary === null) {
        TextInput({
          text: this.invitationInputText,
          placeholder: this.resourceText('pairing_input_placeholder')
        })
          .width('100%')
          .backgroundColor(EggClipColors.controlBackground)
          .height(44)
          .borderRadius(16)
          .onChange((value: string) => {
            this.handleInvitationInputChange(value);
          })

        Column({ space: 6 }) {
          Row({ space: 8 }) {
          Button(this.resourceText('pairing_scan_qr'))
            .layoutWeight(1)
            .height(42)
            .fontColor(EggClipColors.textPrimary)
            .backgroundColor(EggClipColors.controlBackground)
            .borderRadius(21)
            .onClick(() => {
              this.importInvitationFromScan();
            })

          Row() {
            PasteButton({
              text: PasteDescription.PASTE,
              buttonType: ButtonType.Capsule
            })
              .width('100%')
              .height(42)
              .fontColor(EggClipColors.textPrimary)
              .backgroundColor(EggClipColors.controlBackground)
              .borderRadius(21)
              .onClick((_event: ClickEvent, result: PasteButtonOnClickResult) => {
                if (result !== PasteButtonOnClickResult.SUCCESS) {
                  this.pasteImportStatus = this.resourceText('paste_authorization_failed');
                  return;
                }
                this.pasteImportStatus = this.resourceText('paste_reading');
                this.clipboardBridge.readPlainTextAfterPasteButton()
                  .then((readResult) => {
                    if (!readResult.ok) {
                      this.pasteImportStatus = this.formatMessage(readResult.message);
                      return;
                    }
                    this.importInvitationText(readResult.text, this.resourceText('pairing_imported_clipboard'));
                  })
                  .catch(() => {
                    this.pasteImportStatus = this.resourceText('pairing_import_clipboard_failed');
                  });
              })
          }
          .layoutWeight(1)
          }
          .width('100%')

          Text(this.pasteImportStatus)
            .width('100%')
            .fontSize(11)
            .fontColor(EggClipColors.textSecondary)
            .lineHeight(18)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Row({ space: 8 }) {
          Button(this.resourceText('pairing_validate'))
            .layoutWeight(1)
            .height(42)
            .fontColor(EggClipColors.onPrimary)
            .backgroundColor(EggClipColors.primary)
            .borderRadius(21)
            .onClick(() => {
              this.snapshot = this.pairingStore.updateInvitationText(this.invitationInputText);
              this.snapshot = this.pairingStore.parseCurrent();
            })

          Button(this.resourceText('common_clear'))
            .width(84)
            .height(42)
            .fontColor(EggClipColors.textSecondary)
            .backgroundColor(EggClipColors.controlBackground)
            .borderRadius(21)
            .onClick(() => {
              this.snapshot = this.pairingStore.clear();
              this.updateVisibleInvitationInput('');
            })
        }
        .width('100%')
      } else {
        Button(this.resourceText('pairing_reimport'))
          .width('100%')
          .height(40)
          .fontColor(EggClipColors.textSecondary)
          .backgroundColor(EggClipColors.controlBackground)
          .borderRadius(18)
          .onClick(() => {
            this.snapshot = this.pairingStore.clear();
            this.updateVisibleInvitationInput('');
          })
      }

      Text(this.formatMessage(this.snapshot.statusMessage))
        .width('100%')
        .fontSize(EggClipTypography.captionSize)
        .fontColor(this.statusColor())
        .lineHeight(20)

      if (this.snapshot.summary !== null) {
        this.InvitationSummaryCard(this.snapshot.summary)
      }

      if (this.snapshot.summary !== null) {
        this.ConnectionHandshakeCard()
      }

      this.SecurityBoundary()
    }
    .width('100%')
    .constraintSize({ maxWidth: 600 })
    .alignSelf(ItemAlign.Center)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private InvitationSummaryCard(summary: PairingInvitationSummary) {
    Column({ space: 10 }) {
      this.SummaryRow(this.resourceText('pairing_sync_space'),
        `#${summary.spaceShortId} · key v${summary.spaceKeyVersion}`)
      this.SummaryRow(this.resourceText('pairing_issuer_device'),
        `${summary.issuerDeviceName} · #${summary.issuerShortFingerprint}`)
      this.SummaryRow(this.resourceText('pairing_time_remaining'),
        this.pluralText('pairing_seconds_plural', summary.expiresInSeconds))

      if (summary.endpoints.length > 0) {
        this.ConnectionCandidateSelector(summary)
      }

      Column({ space: 4 }) {
        Text(this.resourceText('pairing_confirmation_code'))
          .fontSize(11)
          .fontColor(EggClipColors.textSecondary)

        Text(summary.confirmationCode)
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor(EggClipColors.textPrimary)
          .letterSpacing(4)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .backgroundColor(EggClipColors.controlBackground)
      .borderRadius(16)
      .alignItems(HorizontalAlign.Center)

      Button(this.invitationConfirmButtonText())
        .width('100%')
        .height(42)
        .enabled(this.canConfirmInvitation())
        .fontColor(this.canConfirmInvitation() ? EggClipColors.onPrimary : EggClipColors.textSecondary)
        .backgroundColor(this.canConfirmInvitation() ? EggClipColors.primary : EggClipColors.controlBackground)
        .borderRadius(21)
        .onClick(() => {
          this.confirmCodeAndPrepareConnection();
        })

      if (this.connectionSnapshot.state === PairingConnectionState.AUTHENTICATED) {
        Text(this.resourceText('pairing_authenticated_notice'))
          .width('100%')
          .fontSize(11)
          .fontColor(EggClipColors.textSecondary)
          .lineHeight(18)
      }

      if (this.snapshot.state === PairingStoreState.PENDING) {
        Text(this.resourceText('pairing_invitation_cleared_notice'))
          .width('100%')
          .fontSize(11)
          .fontColor(EggClipColors.textSecondary)
          .lineHeight(18)
      }
    }
    .width('100%')
    .padding({ top: 4, bottom: 10 })
    .border({ width: { bottom: 1 }, color: EggClipColors.controlBackground })
  }

  @Builder
  private ConnectionCandidateSelector(summary: PairingInvitationSummary) {
    Column({ space: 8 }) {
      Row() {
        Text(this.resourceText('pairing_select_address'))
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(EggClipColors.textPrimary)
          .layoutWeight(1)

        Text(this.pluralText('pairing_candidates_plural', summary.endpoints.length))
          .fontSize(10)
          .fontColor(EggClipColors.textSecondary)
      }
      .width('100%')

      Scroll() {
        Row({ space: 8 }) {
          ForEach(summary.endpoints, (endpoint: PairingConnectionEndpoint) => {
            Button(`${endpoint.host}:${endpoint.port}`)
              .height(40)
              .enabled(this.connectionSnapshot.state !== PairingConnectionState.AUTHENTICATED)
              .fontSize(10)
              .fontColor(this.isSelectedEndpoint(endpoint.host, endpoint.port) ?
                EggClipColors.onPrimary : EggClipColors.textSecondary)
              .backgroundColor(this.isSelectedEndpoint(endpoint.host, endpoint.port) ?
                EggClipColors.primary : EggClipColors.cardBackground)
              .borderRadius(16)
              .onClick(() => {
                this.connectionSnapshot = pairingConnectionStore.updateEndpoint(endpoint.host, `${endpoint.port}`);
                this.pasteImportStatus = this.resourceText('pairing_endpoint_selected', `${endpoint.host}:${endpoint.port}`);
              })
          }, (endpoint: PairingConnectionEndpoint) => `${endpoint.host}:${endpoint.port}`)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')

      Text(this.resourceText('pairing_vpn_address_notice'))
        .width('100%')
        .fontSize(10)
        .fontColor(EggClipColors.textSecondary)
        .lineHeight(16)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private ConnectionHandshakeCard() {
    Column({ space: 10 }) {
      Row() {
        Column({ space: 4 }) {
          Text(this.resourceText('pairing_connect_desktop'))
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(EggClipColors.textPrimary)

          Text(this.connectionSnapshot.endpointLabel)
            .fontSize(11)
            .fontColor(EggClipColors.textSecondary)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Text(this.connectionBadgeText())
          .fontSize(11)
          .fontColor(this.connectionStatusColor())
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor(EggClipColors.cardBackground)
          .borderRadius(14)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 8 }) {
        TextInput({
          text: this.connectionSnapshot.manualHost,
          placeholder: this.resourceText('pairing_desktop_ip')
        })
          .enabled(this.connectionSnapshot.state !== PairingConnectionState.AUTHENTICATED)
          .layoutWeight(1)
          .height(40)
          .backgroundColor(EggClipColors.cardBackground)
          .borderRadius(14)
          .onChange((value: string) => {
            this.connectionSnapshot = pairingConnectionStore.updateEndpoint(value, this.connectionSnapshot.manualPort);
          })

        TextInput({
          text: this.connectionSnapshot.manualPort,
          placeholder: this.resourceText('pairing_port')
        })
          .enabled(this.connectionSnapshot.state !== PairingConnectionState.AUTHENTICATED)
          .width(92)
          .height(40)
          .backgroundColor(EggClipColors.cardBackground)
          .borderRadius(14)
          .onChange((value: string) => {
            this.connectionSnapshot = pairingConnectionStore.updateEndpoint(this.connectionSnapshot.manualHost, value);
          })
      }
      .width('100%')

      Row({ space: 8 }) {
        Button(this.connectionButtonText())
          .layoutWeight(1)
          .height(42)
          .enabled(this.canStartPairingConnection())
          .fontColor(this.canStartPairingConnection() ? EggClipColors.onPrimary : EggClipColors.textSecondary)
          .backgroundColor(this.canStartPairingConnection() ? EggClipColors.primary : EggClipColors.controlBackground)
          .borderRadius(21)
          .onClick(() => {
            this.startPairingConnection();
          })

        Button(this.resourceText('common_stop'))
          .width(76)
          .height(42)
          .fontColor(EggClipColors.textSecondary)
          .backgroundColor(EggClipColors.cardBackground)
          .borderRadius(21)
          .onClick(() => {
            pairingConnectionStore.close();
          })
      }
      .width('100%')

      Button(this.resourceText('pairing_connect_trusted'))
        .width('100%')
        .height(42)
        .enabled(!this.isPairingConnectionBusy() &&
          this.connectionSnapshot.state !== PairingConnectionState.AUTHENTICATED)
        .fontColor(EggClipColors.accentForeground)
        .backgroundColor(EggClipColors.cardBackground)
        .borderRadius(21)
        .onClick(() => {
          this.startTrustedReconnect();
        })

      Text(this.connectionDescriptionText())
        .width('100%')
        .fontSize(11)
        .fontColor(this.connectionStatusColor())
        .lineHeight(18)
    }
    .width('100%')
    .padding({ top: 4 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private SummaryRow(label: ResourceStr, value: ResourceStr) {
    Row({ space: 10 }) {
      Text(label)
        .width(78)
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textSecondary)

      Text(value)
        .layoutWeight(1)
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textPrimary)
    }
    .width('100%')
  }

  @Builder
  private SecurityBoundary() {
    Text(this.resourceText('pairing_invitation_safety'))
      .fontSize(11)
      .fontColor(EggClipColors.textSecondary)
      .lineHeight(18)
    .width('100%')
  }

  private statusBadgeText(): string {
    if (this.snapshot.state === PairingStoreState.COMPLETED) {
      return this.resourceText('pairing_badge_completed');
    }
    if (this.snapshot.state === PairingStoreState.READY) {
      return this.resourceText('pairing_badge_valid');
    }
    if (this.snapshot.state === PairingStoreState.PENDING) {
      return this.resourceText('pairing_badge_pending');
    }
    if (this.snapshot.state === PairingStoreState.ERROR) {
      return this.resourceText('pairing_badge_invalid');
    }
    return this.resourceText('pairing_badge_unvalidated');
  }

  private statusColor(): ResourceColor {
    if (this.snapshot.state === PairingStoreState.COMPLETED) {
      return EggClipColors.statusOnline;
    }
    if (this.snapshot.state === PairingStoreState.READY) {
      return EggClipColors.statusOnline;
    }
    if (this.snapshot.state === PairingStoreState.PENDING) {
      return EggClipColors.statusPending;
    }
    if (this.snapshot.state === PairingStoreState.ERROR) {
      return EggClipColors.statusError;
    }
    return EggClipColors.textSecondary;
  }

  private connectionBadgeText(): string {
    if (this.isAuthenticatedConnection()) {
      return this.connectionSnapshot.syncReady ? this.resourceText('pairing_connection_ready') :
        this.resourceText('pairing_connection_initializing');
    }
    if (this.connectionSnapshot.state === PairingConnectionState.FAILED) {
      return this.resourceText('common_failed');
    }
    if (this.connectionSnapshot.state === PairingConnectionState.CLIENT_HELLO_SENT ||
      this.connectionSnapshot.state === PairingConnectionState.WAITING_AUTH_OK) {
      return this.resourceText('pairing_connection_handshaking');
    }
    if (this.connectionSnapshot.state === PairingConnectionState.CONNECTING ||
      this.connectionSnapshot.state === PairingConnectionState.PREPARING) {
      return this.resourceText('common_connecting');
    }
    return this.resourceText('pairing_connection_waiting');
  }

  private connectionButtonText(): string {
    if (this.isAuthenticatedConnection()) {
      return this.resourceText('pairing_button_authenticated');
    }
    if (this.snapshot.state !== PairingStoreState.PENDING) {
      return this.resourceText('pairing_button_compare_code');
    }
    if (this.connectionSnapshot.state === PairingConnectionState.FAILED) {
      return this.resourceText('pairing_button_retry_handshake');
    }
    if (this.pairingCompleted) {
      return this.resourceText('pairing_button_completed');
    }
    return this.resourceText('pairing_button_send_handshake');
  }

  private invitationConfirmButtonText(): string {
    if (this.isAuthenticatedConnection()) {
      return this.resourceText('pairing_confirm_already_connected');
    }
    if (this.snapshot.state === PairingStoreState.PENDING) {
      return this.resourceText('pairing_confirm_connecting');
    }
    return this.resourceText('pairing_confirm_selected');
  }

  private canConfirmInvitation(): boolean {
    return this.snapshot.state === PairingStoreState.READY &&
      !this.isAuthenticatedConnection();
  }

  private connectionDescriptionText(): string {
    if (this.isAuthenticatedConnection()) {
      return this.resourceText('pairing_desc_authenticated');
    }
    if (this.snapshot.state !== PairingStoreState.PENDING) {
      return this.resourceText('pairing_desc_compare');
    }
    return this.formatMessage(this.connectionSnapshot.description);
  }

  private connectionStatusColor(): ResourceColor {
    if (this.isAuthenticatedConnection()) {
      return EggClipColors.statusOnline;
    }
    if (this.connectionSnapshot.state === PairingConnectionState.FAILED) {
      return EggClipColors.statusError;
    }
    if (this.connectionSnapshot.state === PairingConnectionState.IDLE) {
      return EggClipColors.textSecondary;
    }
    return EggClipColors.statusPending;
  }

  private isPairingConnectionBusy(): boolean {
    return this.connectionSnapshot.state === PairingConnectionState.PREPARING ||
      this.connectionSnapshot.state === PairingConnectionState.CONNECTING ||
      this.connectionSnapshot.state === PairingConnectionState.CLIENT_HELLO_SENT ||
      this.connectionSnapshot.state === PairingConnectionState.WAITING_AUTH_OK;
  }

  private isAuthenticatedConnection(): boolean {
    return this.connectionSnapshot.authenticated ||
      this.connectionSnapshot.state === PairingConnectionState.AUTHENTICATED;
  }

  private isSelectedEndpoint(host: string, port: number): boolean {
    return this.connectionSnapshot.manualHost === host && this.connectionSnapshot.manualPort === `${port}`;
  }

  private canStartPairingConnection(): boolean {
    return this.snapshot.state === PairingStoreState.PENDING && !this.isPairingConnectionBusy() &&
      this.connectionSnapshot.state !== PairingConnectionState.AUTHENTICATED && !this.pairingCompleted;
  }

  private startPairingConnection(): void {
    if (this.snapshot.state !== PairingStoreState.PENDING) {
      this.pasteImportStatus = this.resourceText('pairing_compare_required');
      return;
    }
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext === undefined) {
      this.pasteImportStatus = this.resourceText('pairing_context_connect_failed');
      return;
    }
    pairingConnectionStore.initialize(hostContext as common.Context);
    this.pairingHandshakeInFlight = true;
    pairingConnectionStore.startPairing(this.pairingStore)
      .then((snapshot) => {
        this.connectionSnapshot = snapshot;
      })
      .catch(() => {
        this.pairingHandshakeInFlight = false;
        this.pasteImportStatus = this.resourceText('pairing_connection_exception');
      });
  }

  private startTrustedReconnect(): void {
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext === undefined) {
      this.pasteImportStatus = this.resourceText('pairing_context_reconnect_failed');
      return;
    }
    const context = hostContext as common.Context;
    pairingConnectionStore.initialize(context);
    new TrustedDeviceStore(context).loadFirstReconnectTarget()
      .then((target) => {
        if (target === null) {
          this.pasteImportStatus = this.resourceText('pairing_no_reconnect_target');
          return;
        }
        pairingConnectionStore.startTrustedReconnect(target)
          .then((snapshot) => {
            this.connectionSnapshot = snapshot;
          })
          .catch(() => {
            this.pasteImportStatus = this.resourceText('pairing_reconnect_exception');
          });
      })
      .catch(() => {
        this.pasteImportStatus = this.resourceText('pairing_trusted_read_failed');
      });
  }

  private handleInvitationInputChange(value: string): void {
    this.pairingCompleted = false;
    this.invitationInputText = value;
    if (this.pendingProgrammaticInvitationInput !== null && value === this.pendingProgrammaticInvitationInput) {
      this.pendingProgrammaticInvitationInput = null;
      return;
    }
    this.pendingProgrammaticInvitationInput = null;
    this.snapshot = this.pairingStore.updateInvitationText(value);
  }

  private updateVisibleInvitationInput(value: string): void {
    this.pendingProgrammaticInvitationInput = value;
    this.invitationInputText = value;
  }

  private importInvitationText(value: string, successStatus: string): void {
    this.pairingCompleted = false;
    this.updateVisibleInvitationInput(value);
    this.snapshot = this.pairingStore.importInvitationText(value);
    if (this.snapshot.state === PairingStoreState.READY && this.snapshot.summary !== null &&
      this.snapshot.summary.endpoints.length > 0) {
      const endpoint = this.snapshot.summary.endpoints[0];
      this.connectionSnapshot = pairingConnectionStore.updateEndpoint(endpoint.host, `${endpoint.port}`);
    }
    this.pasteImportStatus = this.snapshot.state === PairingStoreState.READY
      ? (this.snapshot.summary !== null && this.snapshot.summary.endpoints.length > 0 ?
        this.resourceText('pairing_imported_with_endpoint', successStatus, this.connectionSnapshot.endpointLabel) :
        successStatus)
      : this.formatMessage(this.snapshot.statusMessage);
  }

  private confirmCodeAndPrepareConnection(): void {
    if (this.connectionSnapshot.state === PairingConnectionState.AUTHENTICATED) {
      this.pasteImportStatus = this.resourceText('pairing_existing_connection');
      return;
    }
    const nextSnapshot = this.pairingStore.confirmCodeMatched();
    this.snapshot = nextSnapshot;
    if (nextSnapshot.state === PairingStoreState.PENDING) {
      this.updateVisibleInvitationInput('');
      if (this.connectionSnapshot.manualPort !== '0') {
        this.pasteImportStatus = this.resourceText('pairing_code_connecting', this.connectionSnapshot.endpointLabel);
        this.startPairingConnection();
      }
    }
  }

  private importInvitationFromScan(): void {
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext === undefined) {
      this.pasteImportStatus = this.resourceText('pairing_scan_context_failed');
      return;
    }
    this.pasteImportStatus = this.resourceText('pairing_scan_opening');
    this.pairingScanService.scanPairingInvitation(hostContext as common.Context)
      .then((scanResult) => {
        if (!scanResult.ok) {
          this.pasteImportStatus = this.formatMessage(scanResult.message);
          return;
        }
        this.importInvitationText(scanResult.invitationText, this.resourceText('pairing_imported_qr'));
      })
      .catch(() => {
        this.pasteImportStatus = this.resourceText('pairing_scan_import_failed');
      });
  }

  private formatMessage(message: UiMessageDescriptor): string {
    return this.messageFormatter === null ? message.code : this.messageFormatter.format(message);
  }

  private resourceText(name: string, ...args: Array<string | number>): string {
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext === undefined) {
      return name;
    }
    try {
      return hostContext.resourceManager.getStringByNameSync(name, ...args);
    } catch (_) {
      return name;
    }
  }

  private pluralText(name: string, count: number): string {
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext === undefined) return name;
    try {
      return hostContext.resourceManager.getIntPluralStringByNameSync(name, count, count);
    } catch (_) {
      return name;
    }
  }
}
