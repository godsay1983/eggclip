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
  OutboundDeliveryState,
  PairingConnectionSnapshot,
  PairingConnectionState,
  pairingConnectionStore
} from '../store/PairingConnectionStore';
import { EggClipColors } from '../theme/Colors';
import { EggClipSpacing } from '../theme/Spacing';
import { EggClipTypography } from '../theme/Typography';
import { TrustedDeviceStore } from '../store/TrustedDeviceStore';
import { APP_FOREGROUND_STORAGE_KEY } from '../utils/AppLifecycle';
import {
  ConnectionExperiencePolicy,
  connectionExperiencePolicy
} from '../services/ui/ConnectionExperiencePolicy';

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
  private lastPairingHistoryRevision: number = 0;
  private readonly connectionSnapshotListener = (snapshot: PocConnectionSnapshot): void => {
    const previousReceivedText = this.latestReceivedText;
    this.latestReceivedText = snapshot.latestReceivedText;
    this.latestReceivedPreview = snapshot.latestReceivedPreview;
    this.latestReceivedSource = snapshot.latestReceivedSource;
    this.latestReceivedAt = snapshot.latestReceivedAt;
    this.latestReceivedByteLength = snapshot.latestReceivedByteLength;
    if (pairingConnectionStore.snapshot().state !== PairingConnectionState.AUTHENTICATED) {
      this.connectionTitle = snapshot.connectionTitle;
      this.connectionDescription = snapshot.connectionDescription;
    }
    if (previousReceivedText !== snapshot.latestReceivedText) {
      this.latestReceivedExpanded = false;
    }
    if (snapshot.latestReceivedText.length > 0 && this.copyStatus === '收到桌面文本后可手动复制到本机') {
      this.copyStatus = '已收到桌面端文本，可点击复制到本机';
    }
  };
  private readonly pairingSnapshotListener = (snapshot: PairingConnectionSnapshot): void => {
    if (snapshot.latestReceivedText.length > 0) {
      this.latestReceivedText = snapshot.latestReceivedText;
      this.latestReceivedPreview = snapshot.latestReceivedText.length > 180 ?
        `${snapshot.latestReceivedText.slice(0, 180)}…` : snapshot.latestReceivedText;
      this.latestReceivedSource = snapshot.latestReceivedSource;
      this.latestReceivedAt = snapshot.latestReceivedAt;
      this.latestReceivedByteLength = snapshot.latestReceivedByteLength;
      this.latestReceivedExpanded = false;
      this.copyStatus = '已收到桌面端文本，可点击复制到本机';
    }
    if (snapshot.historyRevision !== this.lastPairingHistoryRevision) {
      this.lastPairingHistoryRevision = snapshot.historyRevision;
      this.loadHistorySummary();
    }
    if (snapshot.authenticated || snapshot.state === PairingConnectionState.AUTHENTICATED) {
      this.connectionTitle = snapshot.title;
      this.connectionDescription = snapshot.syncReady
        ? '安全连接已建立，可以同步纯文本。'
        : '身份认证已完成，正在初始化同步，请稍候。';
    } else if (snapshot.state === PairingConnectionState.FAILED) {
      this.connectionTitle = snapshot.title;
      this.connectionDescription = snapshot.description;
    }
    if ((snapshot.authenticated || snapshot.state === PairingConnectionState.AUTHENTICATED) &&
      this.trustedDeviceCount === 0) {
      this.loadTrustedDeviceCount();
    }
    if (snapshot.outboundDeliveryState === OutboundDeliveryState.QUEUED) {
      this.setOutboundStatus(OutboundSendState.WAITING,
        `${snapshot.pendingOutboundCount} 条等待发送`, snapshot.outboundDeliveryDescription);
    } else if (snapshot.outboundDeliveryState === OutboundDeliveryState.SENDING) {
      this.setOutboundStatus(OutboundSendState.PENDING,
        `${snapshot.pendingOutboundCount} 条等待确认`, snapshot.outboundDeliveryDescription);
    } else if (snapshot.outboundDeliveryState === OutboundDeliveryState.SENT) {
      this.setOutboundStatus(OutboundSendState.SENT, '同步记录已确认', snapshot.outboundDeliveryDescription);
    } else if (snapshot.outboundDeliveryState === OutboundDeliveryState.FAILED) {
      this.setOutboundStatus(OutboundSendState.FAILED, '待同步状态读取失败', snapshot.outboundDeliveryDescription);
    }
  };
  @State private pasteStatus: string = '点击“粘贴”后读取并发送一次';
  @State private copyStatus: string = '桌面端文本可手动复制到本机';
  @State private outboundState: OutboundSendState = OutboundSendState.IDLE;
  @State private outboundTitle: string = '等待本机文本';
  @State private outboundDescription: string = '点击系统 PasteButton 后，会先保存本机历史，再按同步策略尝试发送。';
  @State private outboundUpdatedAt: string = '';
  @State private connectionTitle: string = '等待桌面端';
  @State private connectionDescription: string = '连接和发现入口在设备页';
  @State private latestReceivedText: string = '';
  @State private latestReceivedPreview: string = '';
  @State private latestReceivedSource: string = '暂无内容';
  @State private latestReceivedAt: string = '';
  @State private latestReceivedByteLength: number = 0;
  @State private latestReceivedExpanded: boolean = false;
  @State private historyUsed: number = 0;
  @State private historyLimit: number = 50;
  @State private historyItems: HistoryPreviewItem[] = [];
  @State private historyStatus: string = '正在读取本机历史摘要';
  @State private deletingHistoryItemId: string = '';
  @State private clearingHistory: boolean = false;
  @State private expandedHistoryItemId: string = '';
  @State private historyActionsItemId: string = '';
  @State private copiedHistoryItemId: string = '';
  @State private trustedDeviceCount: number = 0;
  @State private retryingTrustedConnection: boolean = false;
  @StorageLink(APP_FOREGROUND_STORAGE_KEY) private appInForeground: boolean = false;

  aboutToAppear(): void {
    if (this.historyStore === null) {
      const hostContext = this.getUIContext().getHostContext();
      if (hostContext !== undefined) {
        this.historyStore = new HistoryStore(hostContext as common.UIAbilityContext);
        this.trustedDeviceStore = new TrustedDeviceStore(hostContext as common.UIAbilityContext);
      }
    }
    pocConnectionStore.subscribe(this.connectionSnapshotListener);
    pairingConnectionStore.subscribe(this.pairingSnapshotListener);
    this.loadHistorySummary();
    this.loadTrustedDeviceCount();
  }

  aboutToDisappear(): void {
    pocConnectionStore.unsubscribe(this.connectionSnapshotListener);
    pairingConnectionStore.unsubscribe(this.pairingSnapshotListener);
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
        bottom: 112
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
        Text('还没有配对设备')
          .fontSize(EggClipTypography.bodySize)
          .fontWeight(FontWeight.Bold)
          .fontColor(EggClipColors.textPrimary)
          .width('100%')
        Text('请到设备页扫描二维码或粘贴桌面端邀请。')
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
            Text(this.appInForeground ? this.connectionDescription : '应用位于后台，可信连接已暂停；回到前台后会自动恢复。')
              .fontSize(EggClipTypography.captionSize)
              .fontColor(EggClipColors.textSecondary)
              .lineHeight(19)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          if (this.currentConnectionExperience().showRetry) {
            Button(this.retryingTrustedConnection ? '重试中' : '立即重试')
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
        Text('蛋定 Clip')
          .fontSize(EggClipTypography.titleSize)
          .fontWeight(FontWeight.Bold)
          .fontColor(EggClipColors.textPrimary)
          .width('100%')

        Text('剪贴板')
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
        Text('剪贴板')
          .fontSize(EggClipTypography.bodySize)
          .fontWeight(FontWeight.Bold)
          .fontColor(EggClipColors.textPrimary)
          .layoutWeight(1)

        Text(this.latestReceivedPreview.length === 0 ? '暂无内容' : this.latestReceivedSource)
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
            Button(this.latestReceivedExpanded ? '收起' : '展开')
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
              this.pasteStatus = 'PasteButton 临时授权失败，未读取系统剪贴板';
              return;
            }
            this.pasteStatus = 'PasteButton 已授权，正在读取纯文本';
            this.clipboardBridge.readPlainTextAfterPasteButton()
              .then((readResult) => {
                this.pasteStatus = readResult.message;
                if (readResult.ok) {
                  this.persistLocalHistoryThenSend(readResult.text);
                }
              })
              .catch(() => {
                this.pasteStatus = '读取剪贴板失败，请确认当前内容是纯文本并重试';
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
        Button('复制')
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
        Text(`更新时间：${this.outboundUpdatedAt}`)
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
          Text('最近记录')
            .fontSize(EggClipTypography.bodySize)
            .fontWeight(FontWeight.Bold)
            .fontColor(EggClipColors.textPrimary)
            .layoutWeight(1)

          Button(this.clearingHistory ? '清理中' : '清空')
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

        Text(`${this.historyUsed} / ${this.historyLimit} 条 · 离线补齐不会覆盖当前剪贴板`)
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
      Text(this.historyLimit === 0 ? '历史保存已关闭' : '还没有本机历史')
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
          Text(item.title)
            .fontSize(EggClipTypography.captionSize)
            .fontWeight(FontWeight.Medium)
            .fontColor(EggClipColors.textPrimary)
            .layoutWeight(1)

          Text(this.copiedHistoryItemId === item.id ? '已复制' : item.receivedAt)
            .fontSize(11)
            .fontColor(EggClipColors.textSecondary)
        }
        .width('100%')

        Row({ space: 8 }) {
          Text(this.expandedHistoryItemId === item.id && item.text.length > 0 ? item.text : item.preview)
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
            .accessibilityText('更多操作')
            .onClick(() => {
              this.historyActionsItemId = this.historyActionsItemId === item.id ? '' : item.id;
            })
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 8, right: 4, top: 8, bottom: 8 })
      .borderRadius(12)
      .accessibilityText(item.canCopy ? `复制 ${item.title}` : `${item.title}，内容暂不可用`)
      .onClick(() => {
        if (item.canCopy) this.copyHistoryItem(item.id);
      })

      if (this.historyActionsItemId === item.id) {
        Row({ space: 8 }) {
          Text(item.source)
            .fontSize(10)
            .fontColor(EggClipColors.textSecondary)
            .layoutWeight(1)

          if (item.text.length > 180) {
            Button(this.expandedHistoryItemId === item.id ? '收起详情' : '查看详情')
              .height(40)
              .fontSize(11)
              .fontColor(EggClipColors.textSecondary)
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                this.expandedHistoryItemId = this.expandedHistoryItemId === item.id ? '' : item.id;
              })
          }

          Button('删除')
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
      title: '删除这条记录？',
      message: '只会删除 EggClip 的本机历史，不会修改系统剪贴板。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '删除',
        fontColor: EggClipColors.statusError,
        action: () => { this.deleteHistoryItem(itemId); }
      }
    });
  }

  private confirmClearHistory(): void {
    this.getUIContext().showAlertDialog({
      title: '清空本机历史？',
      message: '全部 EggClip 历史会被删除，系统剪贴板不受影响。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '清空',
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
        this.historyStatus = copied ? '已复制历史正文到本机剪贴板' : '历史正文不可用，无法复制';
      })
      .catch(() => {
        this.copiedHistoryItemId = '';
        this.historyStatus = '复制历史正文失败';
      });
  }

  private sendPocClipboardText(text: string): void {
    if (this.historyStore === null) {
      this.pasteStatus = '无法读取同步策略，未发送到桌面端';
      this.setOutboundStatus(OutboundSendState.FAILED, '发送策略不可用', '无法读取本机设置，已保留本机历史但未发送。');
      return;
    }

    this.historyStore.loadLocalBroadcastPolicy()
      .then((policy: LocalBroadcastPolicySnapshot) => {
        if (!policy.allowed) {
          this.pasteStatus = policy.message;
          this.setOutboundStatus(OutboundSendState.PAUSED, '同步已暂停', '文本已进入本机历史；当前同步策略禁止发送到桌面端。');
          return;
        }
        if (!pocConnectionStore.isConnected()) {
          this.pasteStatus = '已读取纯文本；尚未连接桌面端，未发送。请到设备页连接桌面端';
          this.setOutboundStatus(OutboundSendState.WAITING, '等待桌面连接', '文本已进入本机历史；连接桌面端后可再次点击 PasteButton 发送。');
          return;
        }

        this.setOutboundStatus(OutboundSendState.PENDING, '正在发送到桌面端', '正在使用当前连接发送文本。');
        pocConnectionStore.sendClipboardText(text)
          .then((sent) => {
            this.pasteStatus = sent ? '已发送到桌面端' : '发送失败：连接已断开';
            this.setOutboundStatus(
              sent ? OutboundSendState.SENT : OutboundSendState.FAILED,
              sent ? '已发送到桌面端' : '发送失败',
              sent ? '文本已发送到桌面端。' : '连接已断开，本机历史已保留。'
            );
          })
          .catch(() => {
            this.pasteStatus = '发送到桌面端失败';
            this.setOutboundStatus(OutboundSendState.FAILED, '发送到桌面端失败', '本机历史已保留，网络恢复后可重新触发发送。');
          });
      })
      .catch(() => {
        this.pasteStatus = '读取同步策略失败，未发送到桌面端';
        this.setOutboundStatus(OutboundSendState.FAILED, '读取同步策略失败', '本机历史已保留，但未确认设置前不会发送。');
      });
  }

  private latestReceivedTextForDisplay(): string {
    return this.latestReceivedExpanded ? this.latestReceivedText : this.latestReceivedPreview;
  }

  private latestReceivedMetaText(): string {
    const receivedAt = this.latestReceivedAt.length === 0 ? '未知时间' : this.latestReceivedAt;
    return `来源：${this.latestReceivedSource} · ${receivedAt} · ${this.latestReceivedText.length} 字符 · ${this.latestReceivedByteLength} 字节`;
  }

  private emptyClipboardHelpText(): string {
    if (this.connectionTitle.indexOf('失败') >= 0 || this.connectionTitle.indexOf('不可用') >= 0) {
      return `${this.connectionTitle}：${this.connectionDescription}。可以到设备页重新发现，或使用手动 IP 连接桌面端。`;
    }
    if (this.connectionTitle.indexOf('暂停') >= 0) {
      return `${this.connectionTitle}：${this.connectionDescription}。恢复自动接收后，桌面端文本才会进入预览。`;
    }
    return '桌面端复制的文本会显示在这里；点击“粘贴”可发送手机剪贴板。';
  }

  private emptyHistoryHelpText(): string {
    if (this.historyLimit === 0) {
      return '当前只保留实时同步，不写入本机历史。可以在设置页把历史数量改为 20、50 或 100 条。';
    }
    return '发送或收到文本后，最近记录会显示在这里。';
  }

  private persistLocalHistoryThenSend(text: string): void {
    pairingConnectionStore.persistAndSendAuthenticatedLocalText(text)
      .then((result) => {
        if (result.status === AuthenticatedLocalSendStatus.SENT) {
          this.pasteStatus = '已通过认证加密会话发送到桌面端';
          this.setOutboundStatus(
            OutboundSendState.SENT,
            '已发送到桌面端',
            '文本已安全保存并发送到桌面端。'
          );
          this.loadHistorySummary();
          return;
        }
        if (result.status === AuthenticatedLocalSendStatus.SENDING) {
          this.pasteStatus = '已提交到认证会话，正在等待桌面端确认';
          this.setOutboundStatus(
            OutboundSendState.PENDING,
            '等待桌面端确认',
            '文本已安全保存，正在等待桌面端确认。'
          );
          this.loadHistorySummary();
          return;
        }
        if (result.status === AuthenticatedLocalSendStatus.QUEUED) {
          this.pasteStatus = '网络不可用，文本已进入待同步队列';
          this.setOutboundStatus(
            OutboundSendState.WAITING,
            '等待连接后自动发送',
            '本机记录已安全保存；可信连接恢复后会通过同步头和范围补齐自动重发。'
          );
          this.loadHistorySummary();
          return;
        }
        if (result.status === AuthenticatedLocalSendStatus.INITIALIZING) {
          this.pasteStatus = '同步正在初始化，文本会在就绪后自动发送';
          this.setOutboundStatus(
            OutboundSendState.WAITING,
            '等待同步初始化',
            '文本已安全保存；初始化完成后会自动发送，无需由电脑先发送。'
          );
          this.loadHistorySummary();
          return;
        }
        if (result.status === AuthenticatedLocalSendStatus.NOT_READY) {
          this.persistLocalHistoryThenSendPocFallback(text);
          return;
        }
        if (result.status === AuthenticatedLocalSendStatus.PAUSED) {
          this.captureLocalHistoryText(text)
            .then(() => {
              this.pasteStatus = '文本已保存到本机历史；同步当前已暂停';
              this.setOutboundStatus(OutboundSendState.PAUSED, '同步已暂停', '本机记录已保存，当前策略禁止发送到桌面端。');
            });
          return;
        }
        this.captureLocalHistoryText(text)
          .then(() => {
            this.pasteStatus = '正式同步处理失败，文本已保存到本机历史';
            this.setOutboundStatus(OutboundSendState.FAILED, '正式同步处理失败', '本机记录已保留；请检查可信设备和 HUKS 空间密钥状态。');
          });
      })
      .catch(() => {
        this.captureLocalHistoryText(text)
          .then(() => {
            this.pasteStatus = '正式同步处理失败，文本已保存到本机历史';
            this.setOutboundStatus(OutboundSendState.FAILED, '正式同步处理失败', '本机记录已保留；请检查可信设备和 HUKS 空间密钥状态。');
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
      this.historyStatus = '无法获取页面上下文，未保存本机历史';
      this.setOutboundStatus(OutboundSendState.FAILED, '本机历史不可用', '无法获取页面上下文，未发送到桌面端。');
      return false;
    }

    this.historyStatus = '正在保存本机历史';
    this.setOutboundStatus(OutboundSendState.LOCAL, '正在确认本机记录', '本机记录处理完成后才会按同步策略尝试发送。');
    return this.historyStore.captureLocalText(text)
      .then((snapshot: HistoryStoreSnapshot) => {
        this.historyUsed = snapshot.used;
        this.historyLimit = snapshot.limit;
        this.historyItems = snapshot.items;
        this.historyStatus = snapshot.errorMessage.length > 0 ? snapshot.errorMessage : '已保存到本机历史';
        if (snapshot.errorMessage.length > 0) {
          this.setOutboundStatus(OutboundSendState.FAILED, '保存本机历史失败', '本机事务未确认成功，已停止发送。');
          return false;
        }
        this.setOutboundStatus(OutboundSendState.LOCAL, '本机记录已确认', '本机事务已完成，准备检查同步策略。');
        return true;
      })
      .catch(() => {
        this.historyStatus = '保存本机历史失败';
        this.setOutboundStatus(OutboundSendState.FAILED, '保存本机历史失败', '本机事务未确认成功，已停止发送。');
        return false;
      });
  }

  private copyLatestReceivedToLocal(): void {
    if (this.latestReceivedText.length === 0) {
      this.copyStatus = '暂无可复制内容';
      return;
    }

    this.copyStatus = '正在写入本机剪贴板';
    this.clipboardBridge.writePlainTextByUserAction(this.latestReceivedText)
      .then((result) => {
        this.copyStatus = result.message;
      })
      .catch(() => {
        this.copyStatus = '写入本机剪贴板失败，请稍后重试';
      });
  }

  private loadHistorySummary(): void {
    if (this.historyStore === null) {
      this.historyStatus = '无法获取页面上下文，历史摘要不可用';
      return;
    }
    this.historyStatus = '正在读取本机历史摘要';
    this.historyStore.loadSummary()
      .then((snapshot: HistoryStoreSnapshot) => {
        this.historyUsed = snapshot.used;
        this.historyLimit = snapshot.limit;
        this.historyItems = snapshot.items;
        this.historyStatus = snapshot.errorMessage.length > 0 ? snapshot.errorMessage : '只显示数量，不展示历史正文';
      })
      .catch(() => {
        this.historyItems = [];
        this.historyStatus = '读取历史摘要失败';
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
        this.connectionTitle = '可信连接重试失败';
        this.connectionDescription = '请检查桌面端是否运行、当前 Wi-Fi 和 Windows 防火墙设置。';
      })
      .finally(() => {
        this.retryingTrustedConnection = false;
      });
  }

  private currentConnectionExperience(): ConnectionExperiencePolicy {
    return connectionExperiencePolicy(
      this.trustedDeviceCount,
      this.connectionTitle,
      this.appInForeground,
      this.retryingTrustedConnection
    );
  }

  private deleteHistoryItem(itemId: string): void {
    if (this.historyStore === null || this.deletingHistoryItemId.length > 0 || this.clearingHistory) {
      return;
    }

    this.deletingHistoryItemId = itemId;
    this.historyStatus = '正在删除历史记录';
    this.historyStore.deleteItem(itemId)
      .then((snapshot: HistoryStoreSnapshot) => {
        this.historyUsed = snapshot.used;
        this.historyLimit = snapshot.limit;
        this.historyItems = snapshot.items;
        this.historyActionsItemId = '';
        this.expandedHistoryItemId = '';
        this.historyStatus = snapshot.errorMessage.length > 0 ? snapshot.errorMessage : '已删除历史记录';
      })
      .catch(() => {
        this.historyStatus = '删除历史记录失败';
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
    this.historyStatus = '正在清空本机历史';
    this.historyStore.clearAll()
      .then((snapshot: HistoryStoreSnapshot) => {
        this.historyUsed = snapshot.used;
        this.historyLimit = snapshot.limit;
        this.historyItems = snapshot.items;
        this.historyActionsItemId = '';
        this.expandedHistoryItemId = '';
        this.historyStatus = snapshot.errorMessage.length > 0 ? snapshot.errorMessage : '已清空本机历史；不会修改系统剪贴板';
      })
      .catch(() => {
        this.historyStatus = '清空历史失败';
      })
      .finally(() => {
        this.clearingHistory = false;
      });
  }

  private setOutboundStatus(state: OutboundSendState, title: string, description: string): void {
    this.outboundState = state;
    this.outboundTitle = title;
    this.outboundDescription = description;
    this.outboundUpdatedAt = this.formatTime(Date.now());
  }

  private formatTime(milliseconds: number): string {
    const date = new Date(milliseconds);
    return `${this.padTime(date.getHours())}:${this.padTime(date.getMinutes())}:${this.padTime(date.getSeconds())}`;
  }

  private padTime(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }

  private outboundStateLabel(): string {
    if (this.outboundState === OutboundSendState.SENT) {
      return '已发送';
    }
    if (this.outboundState === OutboundSendState.PENDING) {
      return '发送中';
    }
    if (this.outboundState === OutboundSendState.WAITING) {
      return '待连接';
    }
    if (this.outboundState === OutboundSendState.FAILED) {
      return '失败';
    }
    if (this.outboundState === OutboundSendState.PAUSED) {
      return '已暂停';
    }
    if (this.outboundState === OutboundSendState.LOCAL) {
      return '本机';
    }
    return '空闲';
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
