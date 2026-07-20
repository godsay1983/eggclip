import { common } from '@kit.AbilityKit';
import { ClipboardBridgeService } from '../services/clipboard/ClipboardBridgeService';
import {
  HistoryStore,
  HistoryPreviewItem,
  LocalBroadcastPolicySnapshot,
  HistoryStoreSnapshot
} from '../store/HistoryStore';
import {
  PocConnectionSnapshot,
  pocConnectionStore
} from '../store/PocConnectionStore';
import {
  AuthenticatedLocalSendStatus,
  OutboundAcknowledgementListener,
  OutboundDeliveryState,
  PairingConnectionSnapshot,
  PairingConnectionState,
  pairingConnectionStore
} from '../store/PairingConnectionStore';
import { EggClipColors } from '../theme/Colors';
import { EggClipSpacing } from '../theme/Spacing';
import { EggClipTypography } from '../theme/Typography';
import { TrustedDeviceStore } from '../store/TrustedDeviceStore';
import { settingsChangeStore } from '../store/SettingsChangeStore';
import { APP_FOREGROUND_STORAGE_KEY } from '../utils/AppLifecycle';
import {
  ConnectionExperiencePolicy,
  connectionExperiencePolicy
} from '../services/ui/ConnectionExperiencePolicy';
import { ConnectionState } from '../models/ShellModels';
import { UiMessageDescriptor } from '../services/localization/UiMessageCodes';
import { UiMessageFormatter } from '../services/localization/UiMessageFormatter';
import { LocalizedFormatter } from '../services/localization/LocalizedFormatter';
import { AppReviewPromptCoordinator } from '../services/review/AppReviewPromptCoordinator';
import { getAppReviewPromptCoordinator } from '../services/review/AppReviewRuntime';
import { AppReviewService } from '../services/review/AppReviewService';

enum OutboundSendState {
  IDLE = 'idle',
  LOCAL = 'local',
  WAITING = 'waiting',
  PENDING = 'pending',
  SENT = 'sent',
  FAILED = 'failed',
  PAUSED = 'paused'
}

@Component
export struct HomePage {
  private readonly clipboardBridge: ClipboardBridgeService = new ClipboardBridgeService();
  private historyStore: HistoryStore | null = null;
  private trustedDeviceStore: TrustedDeviceStore | null = null;
  private messageFormatter: UiMessageFormatter | null = null;
  private appReviewPromptCoordinator: AppReviewPromptCoordinator | null = null;
  private readonly appReviewService: AppReviewService = new AppReviewService();
  private readonly localizedFormatter: LocalizedFormatter = new LocalizedFormatter();
  private lastPairingHistoryRevision: number = 0;
  private historyLoadRequestId: number = 0;
  private appReviewTimer: number = -1;
  private pendingReviewOutboundActions: number = 0;
  private readonly settingsChangeListener = (_revision: number): void => {
    this.loadHistorySummary();
  };
  private readonly connectionSnapshotListener = (snapshot: PocConnectionSnapshot): void => {
    const previousReceivedText = this.latestReceivedText;
    this.latestReceivedText = snapshot.latestReceivedText;
    this.latestReceivedPreview = snapshot.latestReceivedPreview;
    this.latestReceivedSource = this.formatMessage(snapshot.latestReceivedSource);
    this.latestReceivedAtMs = snapshot.latestReceivedAtMs;
    this.latestReceivedByteLength = snapshot.latestReceivedByteLength;
    if (pairingConnectionStore.snapshot().state !== PairingConnectionState.AUTHENTICATED) {
      this.connectionState = snapshot.connectionState;
      this.connectionTitle = this.formatMessage(snapshot.connectionTitle);
      this.connectionDescription = this.formatMessage(snapshot.connectionDescription);
    }
    if (previousReceivedText !== snapshot.latestReceivedText) {
      this.latestReceivedExpanded = false;
    }
    if (snapshot.latestReceivedText.length > 0) {
      this.copyStatus = this.resourceText('home_copy_ready');
    }
  };
  private readonly pairingSnapshotListener = (snapshot: PairingConnectionSnapshot): void => {
    if (snapshot.latestReceivedText.length > 0) {
      this.latestReceivedText = snapshot.latestReceivedText;
      this.latestReceivedPreview = snapshot.latestReceivedText.length > 180 ?
        `${snapshot.latestReceivedText.slice(0, 180)}…` : snapshot.latestReceivedText;
      this.latestReceivedSource = this.formatMessage(snapshot.latestReceivedSource);
      this.latestReceivedAtMs = snapshot.latestReceivedAtMs;
      this.latestReceivedByteLength = snapshot.latestReceivedByteLength;
      this.latestReceivedExpanded = false;
      this.copyStatus = this.resourceText('home_copy_ready');
    }
    if (snapshot.historyRevision !== this.lastPairingHistoryRevision) {
      this.lastPairingHistoryRevision = snapshot.historyRevision;
      this.loadHistorySummary();
    }
    if (snapshot.authenticated || snapshot.state === PairingConnectionState.AUTHENTICATED) {
      this.connectionState = ConnectionState.ONLINE;
      this.connectionTitle = this.formatMessage(snapshot.title);
      this.connectionDescription = this.formatMessage(snapshot.description);
    } else if (snapshot.state === PairingConnectionState.FAILED) {
      this.connectionState = ConnectionState.AUTH_FAILED;
      this.connectionTitle = this.formatMessage(snapshot.title);
      this.connectionDescription = this.formatMessage(snapshot.description);
    }
    if ((snapshot.authenticated || snapshot.state === PairingConnectionState.AUTHENTICATED) &&
      this.trustedDeviceCount === 0) {
      this.loadTrustedDeviceCount();
    }
    if (snapshot.outboundDeliveryState === OutboundDeliveryState.QUEUED) {
      this.setOutboundStatus(OutboundSendState.WAITING,
        this.resourceText('home_outbound_queued_title', snapshot.pendingOutboundCount),
        this.formatMessage(snapshot.outboundDeliveryDescription));
    } else if (snapshot.outboundDeliveryState === OutboundDeliveryState.SENDING) {
      this.setOutboundStatus(OutboundSendState.PENDING,
        this.resourceText('home_outbound_pending_title', snapshot.pendingOutboundCount),
        this.formatMessage(snapshot.outboundDeliveryDescription));
    } else if (snapshot.outboundDeliveryState === OutboundDeliveryState.SENT) {
      this.setOutboundStatus(OutboundSendState.SENT, this.resourceText('home_outbound_confirmed_title'),
        this.formatMessage(snapshot.outboundDeliveryDescription));
    } else if (snapshot.outboundDeliveryState === OutboundDeliveryState.FAILED) {
      this.setOutboundStatus(OutboundSendState.FAILED, this.resourceText('home_outbound_read_failed_title'),
        this.formatMessage(snapshot.outboundDeliveryDescription));
    }
  };
  private readonly outboundAcknowledgementListener: OutboundAcknowledgementListener =
    (confirmedCount: number): void => {
      const eligibleCount = Math.min(confirmedCount, this.pendingReviewOutboundActions);
      if (eligibleCount <= 0) {
        return;
      }
      this.pendingReviewOutboundActions -= eligibleCount;
      this.recordSuccessfulAppReviewActions(eligibleCount);
    };
  @State private pasteStatus: string = '';
  @State private copyStatus: string = '';
  @State private outboundState: OutboundSendState = OutboundSendState.IDLE;
  @State private outboundTitle: string = '';
  @State private outboundDescription: string = '';
  @State private outboundUpdatedAt: string = '';
  @State private connectionTitle: string = '';
  @State private connectionDescription: string = '';
  @State private connectionState: ConnectionState = ConnectionState.OFFLINE;
  @State private latestReceivedText: string = '';
  @State private latestReceivedPreview: string = '';
  @State private latestReceivedSource: string = '';
  @State private latestReceivedAtMs: number = 0;
  @State private latestReceivedByteLength: number = 0;
  @State private latestReceivedExpanded: boolean = false;
  @State private historyUsed: number = 0;
  @State private historyLimit: number = 50;
  @State private historyItems: HistoryPreviewItem[] = [];
  @State private historyStatus: string = '';
  @State private deletingHistoryItemId: string = '';
  @State private clearingHistory: boolean = false;
  @State private expandedHistoryItemId: string = '';
  @State private historyActionsItemId: string = '';
  @State private copiedHistoryItemId: string = '';
  @State private trustedDeviceCount: number = 0;
  @State private retryingTrustedConnection: boolean = false;
  @State private appReviewBusy: boolean = false;
  @StorageLink(APP_FOREGROUND_STORAGE_KEY) private appInForeground: boolean = false;

  aboutToAppear(): void {
    if (this.historyStore === null) {
      const hostContext = this.getUIContext().getHostContext();
      if (hostContext !== undefined) {
        const context = hostContext as common.UIAbilityContext;
        this.messageFormatter = new UiMessageFormatter(context);
        this.historyStore = new HistoryStore(context);
        this.trustedDeviceStore = new TrustedDeviceStore(context);
        this.appReviewPromptCoordinator = getAppReviewPromptCoordinator(context);
        if (this.pasteStatus.length === 0) {
          this.pasteStatus = this.resourceText('home_paste_help');
        }
        if (this.copyStatus.length === 0) this.copyStatus = this.resourceText('home_copy_initial');
        if (this.outboundTitle.length === 0) this.outboundTitle = this.resourceText('home_outbound_initial_title');
        if (this.outboundDescription.length === 0) {
          this.outboundDescription = this.resourceText('home_outbound_initial_desc');
        }
        if (this.historyStatus.length === 0) this.historyStatus = this.resourceText('home_history_loading');
      }
    }
    pocConnectionStore.subscribe(this.connectionSnapshotListener);
    pairingConnectionStore.subscribe(this.pairingSnapshotListener);
    pairingConnectionStore.subscribeOutboundAcknowledgements(this.outboundAcknowledgementListener);
    settingsChangeStore.subscribe(this.settingsChangeListener);
    this.loadHistorySummary();
    this.loadTrustedDeviceCount();
  }

  aboutToDisappear(): void {
    pocConnectionStore.unsubscribe(this.connectionSnapshotListener);
    pairingConnectionStore.unsubscribe(this.pairingSnapshotListener);
    pairingConnectionStore.unsubscribeOutboundAcknowledgements(this.outboundAcknowledgementListener);
    settingsChangeStore.unsubscribe(this.settingsChangeListener);
    this.clearAppReviewTimer();
  }

  build() {
    Scroll() {
      Column({ space: EggClipSpacing.sectionGap }) {
        this.Header()
        this.ConnectionExperienceCard()
        GridRow({ columns: { sm: 12, md: 12, lg: 12 }, gutter: { x: EggClipSpacing.sectionGap, y: EggClipSpacing.sectionGap } }) {
          GridCol({ span: { sm: 12, md: 6, lg: 5 } }) {
            this.LatestClipboardCard()
          }
          GridCol({ span: { sm: 12, md: 6, lg: 7 } }) {
            this.HistoryPlaceholder()
          }
        }
        .width('100%')
      }
      .width('100%')
      .constraintSize({ maxWidth: 960 })
      .alignSelf(ItemAlign.Center)
      .padding({
        left: EggClipSpacing.pagePadding,
        right: EggClipSpacing.pagePadding,
        top: EggClipSpacing.pagePadding,
        bottom: EggClipSpacing.floatingNavigationContentInset
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(EggClipColors.pageBackground)
  }

  @Builder
  private ConnectionExperienceCard() {
    Column({ space: 10 }) {
      if (this.currentConnectionExperience().showFirstUse) {
        Text(this.resourceText('home_unpaired_title'))
          .fontSize(EggClipTypography.bodySize)
          .fontWeight(FontWeight.Bold)
          .fontColor(EggClipColors.textPrimary)
          .width('100%')
        Text(this.resourceText('home_unpaired_description'))
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
          .lineHeight(20)
          .width('100%')
      } else {
        Row({ space: 10 }) {
          Column({ space: 4 }) {
            Text(this.connectionTitle)
              .fontSize(EggClipTypography.bodySize)
              .fontWeight(FontWeight.Medium)
              .fontColor(EggClipColors.textPrimary)
            Text(this.appInForeground ? this.connectionDescription : this.resourceText('home_background_paused'))
              .fontSize(EggClipTypography.captionSize)
              .fontColor(EggClipColors.textSecondary)
              .lineHeight(19)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          if (this.currentConnectionExperience().showRetry) {
            Button(this.retryingTrustedConnection ? this.resourceText('common_retrying') : this.resourceText('common_retry_now'))
              .height(40)
              .enabled(this.currentConnectionExperience().retryEnabled)
              .fontSize(12)
              .fontColor(this.currentConnectionExperience().retryEnabled ?
                EggClipColors.onPrimary : EggClipColors.textSecondary)
              .backgroundColor(this.currentConnectionExperience().retryEnabled ?
                EggClipColors.primary : EggClipColors.controlBackground)
              .borderRadius(17)
              .onClick(() => {
                this.retryTrustedConnection();
              })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(EggClipSpacing.cardPadding)
    .backgroundColor(EggClipColors.controlBackground)
    .borderRadius(EggClipSpacing.radiusMedium)
  }

  @Builder
  private Header() {
    Row({ space: 12 }) {
      Image($r('app.media.startIcon'))
        .width(46)
        .height(46)
        .objectFit(ImageFit.Contain)

      Column({ space: 4 }) {
        Text(this.resourceText('home_brand'))
          .fontSize(EggClipTypography.titleSize)
          .fontWeight(FontWeight.Bold)
          .fontColor(EggClipColors.textPrimary)
          .width('100%')

        Text(this.resourceText('home_clipboard_title'))
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .alignItems(VerticalAlign.Center)
    .width('100%')
  }

  @Builder
  private LatestClipboardCard() {
    Column({ space: 14 }) {
      Row() {
        Text(this.resourceText('home_clipboard_title'))
          .fontSize(EggClipTypography.bodySize)
          .fontWeight(FontWeight.Bold)
          .fontColor(EggClipColors.textPrimary)
          .layoutWeight(1)

        Text(this.latestReceivedPreview.length === 0 ? this.resourceText('home_empty_content') : this.latestReceivedSource)
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
      }
      .width('100%')

      Text(this.latestReceivedPreview.length === 0 ? this.emptyClipboardHelpText() : this.latestReceivedTextForDisplay())
        .fontSize(EggClipTypography.bodySize)
        .fontColor(EggClipColors.textSecondary)
        .lineHeight(24)

      if (this.latestReceivedText.length > 0) {
        Row({ space: 8 }) {
          Text(this.latestReceivedMetaText())
            .fontSize(11)
            .fontColor(EggClipColors.textSecondary)
            .layoutWeight(1)

          if (this.latestReceivedText.length > 180) {
            Button(this.latestReceivedExpanded ? this.resourceText('common_collapse') : this.resourceText('common_expand'))
              .height(40)
              .fontSize(11)
              .fontColor(EggClipColors.textSecondary)
              .backgroundColor(EggClipColors.controlBackground)
              .borderRadius(14)
              .onClick(() => {
                this.latestReceivedExpanded = !this.latestReceivedExpanded;
              })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }

      Column({ space: 6 }) {
        PasteButton({
          text: PasteDescription.PASTE,
          buttonType: ButtonType.Capsule
        })
          .width('100%')
          .height(46)
          .fontColor(this.latestReceivedText.length > 0 ? EggClipColors.textPrimary : EggClipColors.onPrimary)
          .backgroundColor(this.latestReceivedText.length > 0 ? EggClipColors.controlBackground : EggClipColors.primary)
          .borderRadius(23)
          .onClick((_event: ClickEvent, result: PasteButtonOnClickResult) => {
            if (result !== PasteButtonOnClickResult.SUCCESS) {
              this.pasteStatus = this.resourceText('paste_authorization_failed');
              return;
            }
            this.pasteStatus = this.resourceText('paste_reading');
            this.clipboardBridge.readPlainTextAfterPasteButton()
              .then((readResult) => {
                this.pasteStatus = this.formatMessage(readResult.message);
                if (readResult.ok) {
                  this.persistLocalHistoryThenSend(readResult.text);
                }
              })
              .catch(() => {
                this.pasteStatus = this.resourceText('ui_clipboard_read_failed');
              });
          })

        Text(this.pasteStatus)
          .width('100%')
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      if (this.outboundState !== OutboundSendState.IDLE) {
        this.OutboundStatusCard()
      }

      if (this.latestReceivedText.length > 0) {
        Button(this.resourceText('home_copy'))
          .width('100%')
          .height(46)
          .fontColor(EggClipColors.onPrimary)
          .backgroundColor(EggClipColors.primary)
          .borderRadius(23)
          .onClick(() => {
            this.copyLatestReceivedToLocal();
          })

        Text(this.copyStatus)
          .width('100%')
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(EggClipSpacing.cardPadding)
    .backgroundColor(EggClipColors.cardBackground)
    .borderRadius(EggClipSpacing.radiusLarge)
  }

  @Builder
  private OutboundStatusCard() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Column({ space: 2 }) {
          Text(this.outboundTitle)
            .fontSize(EggClipTypography.captionSize)
            .fontWeight(FontWeight.Medium)
            .fontColor(EggClipColors.textPrimary)

          Text(this.outboundDescription)
            .width('100%')
            .fontSize(11)
            .fontColor(EggClipColors.textSecondary)
            .lineHeight(18)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text(this.outboundStateLabel())
          .fontSize(11)
          .fontColor(this.outboundStateColor())
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor(EggClipColors.cardBackground)
          .borderRadius(14)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      if (this.outboundUpdatedAt.length > 0) {
        Text(this.resourceText('home_updated_at', this.outboundUpdatedAt))
          .width('100%')
          .fontSize(10)
          .fontColor(EggClipColors.textSecondary)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private HistoryPlaceholder() {
    Row({ space: 12 }) {
      Text('☰')
        .fontSize(22)
        .fontColor(EggClipColors.accentForeground)

      Column({ space: 6 }) {
        Row({ space: 8 }) {
          Text(this.resourceText('home_recent_history'))
            .fontSize(EggClipTypography.bodySize)
            .fontWeight(FontWeight.Bold)
            .fontColor(EggClipColors.textPrimary)
            .layoutWeight(1)

          Button(this.clearingHistory ? this.resourceText('home_clearing') : this.resourceText('common_clear'))
            .height(40)
            .enabled(this.historyUsed > 0 && !this.clearingHistory && this.deletingHistoryItemId.length === 0)
            .fontSize(11)
            .fontColor(EggClipColors.textSecondary)
            .backgroundColor(EggClipColors.controlBackground)
            .borderRadius(14)
            .onClick(() => {
              this.confirmClearHistory();
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(this.resourceText('home_history_count', this.historyUsed, this.historyLimit))
          .width('100%')
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
          .lineHeight(20)

        if (this.historyItems.length > 0) {
          Column({ space: 8 }) {
            ForEach(this.historyItems, (item: HistoryPreviewItem) => {
              this.HistoryItem(item)
            }, (item: HistoryPreviewItem) => item.id)
          }
          .width('100%')
        } else {
          this.EmptyHistoryState()
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding(EggClipSpacing.cardPadding)
    .backgroundColor(EggClipColors.cardBackground)
    .borderRadius(EggClipSpacing.radiusMedium)
  }

  @Builder
  private EmptyHistoryState() {
    Column({ space: 6 }) {
      Text(this.historyLimit === 0 ? this.resourceText('home_history_disabled') : this.resourceText('home_history_empty'))
        .fontSize(EggClipTypography.captionSize)
        .fontWeight(FontWeight.Medium)
        .fontColor(EggClipColors.textPrimary)
        .width('100%')

      Text(this.emptyHistoryHelpText())
        .width('100%')
        .fontSize(11)
        .fontColor(EggClipColors.textSecondary)
        .lineHeight(18)

      Text(this.historyStatus)
        .width('100%')
        .fontSize(10)
        .fontColor(EggClipColors.textSecondary)
        .lineHeight(16)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private HistoryItem(item: HistoryPreviewItem) {
    Column({ space: 5 }) {
      Column({ space: 4 }) {
        Row({ space: 8 }) {
          Text(this.historyItemTitle(item))
            .fontSize(EggClipTypography.captionSize)
            .fontWeight(FontWeight.Medium)
            .fontColor(EggClipColors.textPrimary)
            .layoutWeight(1)

          Text(this.copiedHistoryItemId === item.id ? this.resourceText('home_copied') :
            this.localizedFormatter.formatTime(item.receivedAtMs))
            .fontSize(11)
            .fontColor(EggClipColors.textSecondary)
        }
        .width('100%')

        Row({ space: 8 }) {
          Text(this.expandedHistoryItemId === item.id && item.text.length > 0 ? item.text :
            (item.preview.length > 0 ? item.preview : this.resourceText('home_history_content_unavailable')))
            .layoutWeight(1)
            .maxLines(this.expandedHistoryItemId === item.id ? 8 : 1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontSize(11)
            .fontColor(EggClipColors.textSecondary)
            .lineHeight(18)

          Button('⋯')
            .width(40)
            .height(40)
            .fontSize(18)
            .fontColor(EggClipColors.textSecondary)
            .backgroundColor(Color.Transparent)
            .accessibilityText(this.resourceText('home_more_actions'))
            .onClick(() => {
              this.historyActionsItemId = this.historyActionsItemId === item.id ? '' : item.id;
            })
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 8, right: 4, top: 8, bottom: 8 })
      .borderRadius(12)
      .accessibilityText(item.canCopy ?
        this.resourceText('home_item_copy_accessibility', this.historyItemTitle(item)) :
        this.resourceText('home_item_unavailable_accessibility', this.historyItemTitle(item)))
      .onClick(() => {
        if (item.canCopy) this.copyHistoryItem(item.id);
      })

      if (this.historyActionsItemId === item.id) {
        Row({ space: 8 }) {
          Text(this.resourceText('home_history_source', item.originDeviceId.slice(0, 8)))
            .fontSize(10)
            .fontColor(EggClipColors.textSecondary)
            .layoutWeight(1)

          if (item.text.length > 180) {
            Button(this.expandedHistoryItemId === item.id ?
              this.resourceText('home_collapse_details') : this.resourceText('home_view_details'))
              .height(40)
              .fontSize(11)
              .fontColor(EggClipColors.textSecondary)
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                this.expandedHistoryItemId = this.expandedHistoryItemId === item.id ? '' : item.id;
              })
          }

          Button(this.resourceText('common_delete'))
          .height(40)
          .enabled(this.deletingHistoryItemId.length === 0 && !this.clearingHistory)
          .fontSize(11)
          .fontColor(EggClipColors.statusError)
          .backgroundColor(Color.Transparent)
          .borderRadius(14)
          .onClick(() => {
            this.confirmDeleteHistoryItem(item.id);
          })
        }
        .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .border({ width: { bottom: 1 }, color: EggClipColors.controlBackground })
  }

  private confirmDeleteHistoryItem(itemId: string): void {
    this.getUIContext().showAlertDialog({
      title: this.resourceText('home_delete_dialog_title'),
      message: this.resourceText('home_delete_dialog_message'),
      primaryButton: { value: this.resourceText('common_cancel'), action: () => {} },
      secondaryButton: {
        value: this.resourceText('common_delete'),
        fontColor: EggClipColors.statusError,
        action: () => { this.deleteHistoryItem(itemId); }
      }
    });
  }

  private confirmClearHistory(): void {
    this.getUIContext().showAlertDialog({
      title: this.resourceText('home_clear_dialog_title'),
      message: this.resourceText('home_clear_dialog_message'),
      primaryButton: { value: this.resourceText('common_cancel'), action: () => {} },
      secondaryButton: {
        value: this.resourceText('common_clear'),
        fontColor: EggClipColors.statusError,
        action: () => { this.clearHistory(); }
      }
    });
  }

  private copyHistoryItem(itemId: string): void {
    if (this.historyStore === null) return;
    this.historyStore.copyItem(itemId)
      .then((copied: boolean) => {
        this.copiedHistoryItemId = copied ? itemId : '';
        this.historyStatus = copied ? this.resourceText('home_history_copy_success') :
          this.resourceText('home_history_copy_unavailable');
      })
      .catch(() => {
        this.copiedHistoryItemId = '';
        this.historyStatus = this.resourceText('home_history_copy_failed');
      });
  }

  private sendPocClipboardText(text: string): void {
    if (this.historyStore === null) {
      this.pasteStatus = this.resourceText('home_paste_policy_failed');
      this.setOutboundStatus(OutboundSendState.FAILED,
        this.resourceText('home_outbound_policy_unavailable_title'),
        this.resourceText('home_outbound_policy_unavailable_desc'));
      return;
    }

    this.historyStore.loadLocalBroadcastPolicy()
      .then((policy: LocalBroadcastPolicySnapshot) => {
        if (!policy.allowed) {
          this.pasteStatus = this.formatMessage(policy.message);
          this.setOutboundStatus(OutboundSendState.PAUSED,
            this.resourceText('home_outbound_paused_title'), this.resourceText('home_outbound_paused_desc'));
          return;
        }
        if (!pocConnectionStore.isConnected()) {
          this.pasteStatus = this.resourceText('home_paste_not_connected');
          this.setOutboundStatus(OutboundSendState.WAITING,
            this.resourceText('home_outbound_waiting_connection_title'),
            this.resourceText('home_outbound_waiting_connection_desc'));
          return;
        }

        this.setOutboundStatus(OutboundSendState.PENDING,
          this.resourceText('home_outbound_sending_title'), this.resourceText('home_outbound_sending_desc'));
        pocConnectionStore.sendClipboardText(text)
          .then((sent) => {
            this.pasteStatus = sent ? this.resourceText('home_paste_sent') : this.resourceText('home_paste_link_down');
            this.setOutboundStatus(
              sent ? OutboundSendState.SENT : OutboundSendState.FAILED,
              sent ? this.resourceText('home_outbound_sent_title') : this.resourceText('home_outbound_failed_title'),
              sent ? this.resourceText('home_outbound_sent_desc') : this.resourceText('home_outbound_failed_desc')
            );
          })
          .catch(() => {
            this.pasteStatus = this.resourceText('home_outbound_failed_title');
            this.setOutboundStatus(OutboundSendState.FAILED,
              this.resourceText('home_outbound_failed_title'), this.resourceText('home_outbound_retry_desc'));
          });
      })
      .catch(() => {
        this.pasteStatus = this.resourceText('home_paste_policy_failed');
        this.setOutboundStatus(OutboundSendState.FAILED,
          this.resourceText('home_outbound_policy_unavailable_title'),
          this.resourceText('home_outbound_policy_unavailable_desc'));
      });
  }

  private latestReceivedTextForDisplay(): string {
    return this.latestReceivedExpanded ? this.latestReceivedText : this.latestReceivedPreview;
  }

  private latestReceivedMetaText(): string {
    const receivedAt = this.latestReceivedAtMs === 0 ? this.resourceText('common_unknown_time') :
      this.localizedFormatter.formatTime(this.latestReceivedAtMs);
    return this.resourceText('home_latest_meta', this.latestReceivedSource, receivedAt,
      this.latestReceivedText.length, this.latestReceivedByteLength);
  }

  private emptyClipboardHelpText(): string {
    if (this.connectionState === ConnectionState.AUTH_FAILED) {
      return this.resourceText('home_empty_failed_help', this.connectionTitle, this.connectionDescription);
    }
    if (this.connectionState === ConnectionState.PAUSED) {
      return this.resourceText('home_empty_paused_help', this.connectionTitle, this.connectionDescription);
    }
    return this.resourceText('home_empty_help');
  }

  private emptyHistoryHelpText(): string {
    if (this.historyLimit === 0) {
      return this.resourceText('home_history_disabled_help');
    }
    return this.resourceText('home_history_empty_help');
  }

  private persistLocalHistoryThenSend(text: string): void {
    this.pendingReviewOutboundActions += 1;
    pairingConnectionStore.persistAndSendAuthenticatedLocalText(text)
      .then((result) => {
        if (result.status === AuthenticatedLocalSendStatus.SENT) {
          const confirmedCount = this.takePendingReviewOutboundActions(1);
          if (confirmedCount > 0) {
            this.recordSuccessfulAppReviewActions(confirmedCount);
          }
          this.pasteStatus = this.resourceText('home_secure_sent_status');
          this.setOutboundStatus(
            OutboundSendState.SENT,
            this.resourceText('home_outbound_sent_title'),
            this.resourceText('home_secure_sent_desc')
          );
          this.loadHistorySummary();
          return;
        }
        if (result.status === AuthenticatedLocalSendStatus.SENDING) {
          this.pasteStatus = this.resourceText('home_secure_pending_status');
          this.setOutboundStatus(
            OutboundSendState.PENDING,
            this.resourceText('home_outbound_pending_title', 1),
            this.resourceText('home_secure_pending_desc')
          );
          this.loadHistorySummary();
          return;
        }
        if (result.status === AuthenticatedLocalSendStatus.QUEUED) {
          this.pasteStatus = this.resourceText('home_secure_queued_status');
          this.setOutboundStatus(
            OutboundSendState.WAITING,
            this.resourceText('home_secure_queued_title'),
            this.resourceText('home_secure_queued_desc')
          );
          this.loadHistorySummary();
          return;
        }
        if (result.status === AuthenticatedLocalSendStatus.INITIALIZING) {
          this.pasteStatus = this.resourceText('home_secure_initializing_status');
          this.setOutboundStatus(
            OutboundSendState.WAITING,
            this.resourceText('home_secure_initializing_title'),
            this.resourceText('home_secure_initializing_desc')
          );
          this.loadHistorySummary();
          return;
        }
        if (result.status === AuthenticatedLocalSendStatus.NOT_READY) {
          this.takePendingReviewOutboundActions(1);
          this.persistLocalHistoryThenSendPocFallback(text);
          return;
        }
        if (result.status === AuthenticatedLocalSendStatus.PAUSED) {
          this.takePendingReviewOutboundActions(1);
          this.captureLocalHistoryText(text)
            .then(() => {
              this.pasteStatus = this.resourceText('home_secure_paused_status');
              this.setOutboundStatus(OutboundSendState.PAUSED,
                this.resourceText('home_outbound_paused_title'), this.resourceText('home_secure_paused_desc'));
            });
          return;
        }
        this.takePendingReviewOutboundActions(1);
        this.captureLocalHistoryText(text)
          .then(() => {
            this.pasteStatus = this.resourceText('home_secure_failed_status');
            this.setOutboundStatus(OutboundSendState.FAILED,
              this.resourceText('home_secure_failed_title'), this.resourceText('home_secure_failed_desc'));
          });
      })
      .catch(() => {
        this.takePendingReviewOutboundActions(1);
        this.captureLocalHistoryText(text)
          .then(() => {
            this.pasteStatus = this.resourceText('home_secure_failed_status');
            this.setOutboundStatus(OutboundSendState.FAILED,
              this.resourceText('home_secure_failed_title'), this.resourceText('home_secure_failed_desc'));
          });
      });
  }

  private persistLocalHistoryThenSendPocFallback(text: string): void {
    this.captureLocalHistoryText(text)
      .then((saved: boolean) => {
        if (saved) {
          this.sendPocClipboardText(text);
        }
      });
  }

  private async captureLocalHistoryText(text: string): Promise<boolean> {
    if (this.historyStore === null) {
      this.historyStatus = this.resourceText('home_history_context_failed');
      this.setOutboundStatus(OutboundSendState.FAILED,
        this.resourceText('home_history_unavailable_title'), this.resourceText('home_history_unavailable_desc'));
      return false;
    }

    this.historyStatus = this.resourceText('home_history_saving');
    this.setOutboundStatus(OutboundSendState.LOCAL,
      this.resourceText('home_history_confirming_title'), this.resourceText('home_history_confirming_desc'));
    return this.historyStore.captureLocalText(text)
      .then((snapshot: HistoryStoreSnapshot) => {
        this.historyUsed = snapshot.used;
        this.historyLimit = snapshot.limit;
        this.historyItems = snapshot.items;
        this.historyStatus = snapshot.errorMessage === null ? this.resourceText('home_history_saved') :
          this.formatMessage(snapshot.errorMessage);
        if (snapshot.errorMessage !== null) {
          this.setOutboundStatus(OutboundSendState.FAILED,
            this.resourceText('home_history_save_failed_title'), this.resourceText('home_history_save_failed_desc'));
          return false;
        }
        this.setOutboundStatus(OutboundSendState.LOCAL,
          this.resourceText('home_history_confirmed_title'), this.resourceText('home_history_confirmed_desc'));
        return true;
      })
      .catch(() => {
        this.historyStatus = this.resourceText('home_history_save_failed_title');
        this.setOutboundStatus(OutboundSendState.FAILED,
          this.resourceText('home_history_save_failed_title'), this.resourceText('home_history_save_failed_desc'));
        return false;
      });
  }

  private copyLatestReceivedToLocal(): void {
    if (this.latestReceivedText.length === 0) {
      this.copyStatus = this.resourceText('home_copy_empty');
      return;
    }

    this.copyStatus = this.resourceText('home_copy_writing');
    this.clipboardBridge.writePlainTextByUserAction(this.latestReceivedText)
      .then((result) => {
        this.copyStatus = this.formatMessage(result.message);
        if (result.ok) {
          this.recordSuccessfulAppReviewActions(1);
        }
      })
      .catch(() => {
        this.copyStatus = this.resourceText('home_copy_write_failed');
      });
  }

  private takePendingReviewOutboundActions(maxCount: number): number {
    const count = Math.min(Math.max(0, maxCount), this.pendingReviewOutboundActions);
    this.pendingReviewOutboundActions -= count;
    return count;
  }

  private recordSuccessfulAppReviewActions(count: number): void {
    if (count <= 0 || this.appReviewPromptCoordinator === null) {
      return;
    }
    this.appReviewPromptCoordinator.recordSuccessfulActions(count)
      .then((): void => {
        this.scheduleAutomaticAppReview();
      })
      .catch((): void => {
        // Rating metadata never changes clipboard success or user-facing status.
      });
  }

  private scheduleAutomaticAppReview(): void {
    this.clearAppReviewTimer();
    this.appReviewTimer = setTimeout((): void => {
      this.appReviewTimer = -1;
      this.tryShowAutomaticAppReview().catch((): void => {
        // Automatic review failures remain silent after a successful clipboard action.
      });
    }, 1200);
  }

  private clearAppReviewTimer(): void {
    if (this.appReviewTimer >= 0) {
      clearTimeout(this.appReviewTimer);
      this.appReviewTimer = -1;
    }
  }

  private canShowAutomaticAppReview(): boolean {
    return this.appInForeground &&
      !this.appReviewBusy &&
      !this.clearingHistory &&
      this.deletingHistoryItemId.length === 0 &&
      this.historyActionsItemId.length === 0 &&
      this.outboundState !== OutboundSendState.PENDING;
  }

  private async tryShowAutomaticAppReview(): Promise<void> {
    const coordinator = this.appReviewPromptCoordinator;
    if (coordinator === null || !this.canShowAutomaticAppReview()) {
      return;
    }
    const now = Date.now();
    const versionName = this.appReviewService.currentAppVersionName();
    try {
      if (!await coordinator.isAutoPromptEligible(now, versionName)) {
        return;
      }
      this.appReviewBusy = true;
      const hostContext = this.getUIContext().getHostContext();
      if (hostContext === undefined) {
        await coordinator.markPromptFailed(now);
        return;
      }
      const context = hostContext as common.UIAbilityContext;
      const result = await this.appReviewService.requestReview(context);
      if (result.shown) {
        await coordinator.markPromptShown(now, versionName);
      } else {
        await coordinator.markPromptFailed(now);
      }
    } catch (_) {
      await coordinator.markPromptFailed(now).catch((): void => {
        // Neither AppGallery nor Preferences failures affect clipboard behavior.
      });
    } finally {
      this.appReviewBusy = false;
    }
  }

  private loadHistorySummary(): void {
    if (this.historyStore === null) {
      this.historyStatus = this.resourceText('ui_history_load_failed');
      return;
    }
    const requestId = this.historyLoadRequestId + 1;
    this.historyLoadRequestId = requestId;
    this.historyStatus = this.resourceText('home_history_loading');
    this.historyStore.loadSummary()
      .then((snapshot: HistoryStoreSnapshot) => {
        if (requestId !== this.historyLoadRequestId) {
          return;
        }
        this.historyUsed = snapshot.used;
        this.historyLimit = snapshot.limit;
        this.historyItems = snapshot.items;
        this.historyStatus = snapshot.errorMessage === null ? this.resourceText('home_history_count_only') :
          this.formatMessage(snapshot.errorMessage);
      })
      .catch(() => {
        if (requestId !== this.historyLoadRequestId) {
          return;
        }
        this.historyItems = [];
        this.historyStatus = this.resourceText('home_history_load_failed_status');
      });
  }

  private loadTrustedDeviceCount(): void {
    if (this.trustedDeviceStore === null) return;
    this.trustedDeviceStore.load()
      .then((devices) => {
        this.trustedDeviceCount = devices.length;
      })
      .catch(() => {
        this.trustedDeviceCount = 0;
      });
  }

  private retryTrustedConnection(): void {
    if (this.retryingTrustedConnection || !this.appInForeground) return;
    this.retryingTrustedConnection = true;
    pairingConnectionStore.retryTrustedConnection()
      .catch(() => {
        this.connectionTitle = this.resourceText('home_trusted_retry_failed_title');
        this.connectionDescription = this.resourceText('home_trusted_retry_failed_desc');
      })
      .finally(() => {
        this.retryingTrustedConnection = false;
      });
  }

  private currentConnectionExperience(): ConnectionExperiencePolicy {
    return connectionExperiencePolicy(
      this.trustedDeviceCount,
      this.connectionState,
      this.appInForeground,
      this.retryingTrustedConnection
    );
  }

  private deleteHistoryItem(itemId: string): void {
    if (this.historyStore === null || this.deletingHistoryItemId.length > 0 || this.clearingHistory) {
      return;
    }

    this.deletingHistoryItemId = itemId;
    this.historyStatus = this.resourceText('home_history_deleting');
    this.historyStore.deleteItem(itemId)
      .then((snapshot: HistoryStoreSnapshot) => {
        this.historyUsed = snapshot.used;
        this.historyLimit = snapshot.limit;
        this.historyItems = snapshot.items;
        this.historyActionsItemId = '';
        this.expandedHistoryItemId = '';
        this.historyStatus = snapshot.errorMessage === null ? this.resourceText('home_history_deleted') :
          this.formatMessage(snapshot.errorMessage);
      })
      .catch(() => {
        this.historyStatus = this.resourceText('home_history_delete_failed_status');
      })
      .finally(() => {
        this.deletingHistoryItemId = '';
      });
  }

  private clearHistory(): void {
    if (this.historyStore === null || this.clearingHistory || this.deletingHistoryItemId.length > 0 || this.historyUsed === 0) {
      return;
    }

    this.clearingHistory = true;
    this.historyStatus = this.resourceText('home_history_clearing');
    this.historyStore.clearAll()
      .then((snapshot: HistoryStoreSnapshot) => {
        this.historyUsed = snapshot.used;
        this.historyLimit = snapshot.limit;
        this.historyItems = snapshot.items;
        this.historyActionsItemId = '';
        this.expandedHistoryItemId = '';
        this.historyStatus = snapshot.errorMessage === null ? this.resourceText('home_history_cleared') :
          this.formatMessage(snapshot.errorMessage);
      })
      .catch(() => {
        this.historyStatus = this.resourceText('home_history_clear_failed_status');
      })
      .finally(() => {
        this.clearingHistory = false;
      });
  }

  private setOutboundStatus(state: OutboundSendState, title: string, description: string): void {
    this.outboundState = state;
    this.outboundTitle = title;
    this.outboundDescription = description;
    this.outboundUpdatedAt = this.localizedFormatter.formatTime(Date.now());
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

  private historyItemTitle(item: HistoryPreviewItem): string {
    return this.resourceText('home_history_item_title', item.contentLength);
  }

  private outboundStateLabel(): string {
    if (this.outboundState === OutboundSendState.SENT) {
      return this.resourceText('home_outbound_state_sent');
    }
    if (this.outboundState === OutboundSendState.PENDING) {
      return this.resourceText('home_outbound_state_sending');
    }
    if (this.outboundState === OutboundSendState.WAITING) {
      return this.resourceText('home_outbound_state_waiting');
    }
    if (this.outboundState === OutboundSendState.FAILED) {
      return this.resourceText('home_outbound_state_failed');
    }
    if (this.outboundState === OutboundSendState.PAUSED) {
      return this.resourceText('home_outbound_state_paused');
    }
    if (this.outboundState === OutboundSendState.LOCAL) {
      return this.resourceText('home_outbound_state_local');
    }
    return this.resourceText('home_outbound_state_idle');
  }

  private outboundStateColor(): ResourceColor {
    if (this.outboundState === OutboundSendState.SENT) {
      return EggClipColors.statusOnline;
    }
    if (this.outboundState === OutboundSendState.FAILED) {
      return EggClipColors.statusError;
    }
    if (this.outboundState === OutboundSendState.PENDING || this.outboundState === OutboundSendState.WAITING) {
      return EggClipColors.statusPending;
    }
    return EggClipColors.textSecondary;
  }
}
