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
import { EggClipColors } from '../theme/Colors';
import { EggClipSpacing } from '../theme/Spacing';
import { EggClipTypography } from '../theme/Typography';

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
  private readonly connectionSnapshotListener = (snapshot: PocConnectionSnapshot): void => {
    const previousReceivedText = this.latestReceivedText;
    this.latestReceivedText = snapshot.latestReceivedText;
    this.latestReceivedPreview = snapshot.latestReceivedPreview;
    this.latestReceivedSource = snapshot.latestReceivedSource;
    this.latestReceivedAt = snapshot.latestReceivedAt;
    this.latestReceivedByteLength = snapshot.latestReceivedByteLength;
    this.transportDiagnostics = snapshot.transportDiagnostics;
    this.connectionTitle = snapshot.connectionTitle;
    this.connectionDescription = snapshot.connectionDescription;
    if (previousReceivedText !== snapshot.latestReceivedText) {
      this.latestReceivedExpanded = false;
    }
    if (snapshot.latestReceivedText.length > 0 && this.copyStatus === '收到桌面文本后可手动复制到本机') {
      this.copyStatus = '已收到桌面端文本，可点击复制到本机';
    }
  };
  @State private pasteStatus: string = '等待点击 PasteButton 触发一次性授权';
  @State private transportDiagnostics: string = '帧诊断：接收 0 · 接受 0 · 拒绝 0';
  @State private copyStatus: string = '收到桌面文本后可手动复制到本机';
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

  aboutToAppear(): void {
    pocConnectionStore.subscribe(this.connectionSnapshotListener);
    if (this.historyStore === null) {
      const hostContext = this.getUIContext().getHostContext();
      if (hostContext !== undefined) {
        this.historyStore = new HistoryStore(hostContext as common.UIAbilityContext);
      }
    }
    this.loadHistorySummary();
  }

  aboutToDisappear(): void {
    pocConnectionStore.unsubscribe(this.connectionSnapshotListener);
  }

  build() {
    Scroll() {
      Column({ space: EggClipSpacing.sectionGap }) {
        this.Header()
        this.LatestClipboardCard()
        this.HistoryPlaceholder()
      }
      .width('100%')
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
  private Header() {
    Row({ space: 12 }) {
      Image($r('app.media.startIcon'))
        .width(54)
        .height(54)
        .objectFit(ImageFit.Contain)

      Column({ space: 4 }) {
        Row({ space: 8 }) {
          Text('蛋定 Clip')
            .fontSize(EggClipTypography.titleSize)
            .fontWeight(FontWeight.Bold)
            .fontColor(EggClipColors.textPrimary)

          Text('Beta')
            .fontSize(EggClipTypography.captionSize)
            .fontWeight(FontWeight.Medium)
            .fontColor(EggClipColors.onPrimary)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .backgroundColor(EggClipColors.primary)
            .borderRadius(16)
        }
        .width('100%')

        Text('剪贴板收发')
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
        Text('剪贴板收发')
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
              .height(28)
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
          .fontColor(EggClipColors.onPrimary)
          .backgroundColor(EggClipColors.primary)
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

      this.OutboundStatusCard()

      Button('复制到本机')
        .width('100%')
        .height(46)
        .enabled(this.latestReceivedText.length > 0)
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

      Text(this.transportDiagnostics)
        .width('100%')
        .fontSize(11)
        .fontColor(EggClipColors.textSecondary)
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
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor(EggClipColors.controlBackground)
    .borderRadius(14)
  }

  @Builder
  private HistoryPlaceholder() {
    Row({ space: 12 }) {
      Text('☰')
        .fontSize(22)
        .fontColor(EggClipColors.primary)

      Column({ space: 6 }) {
        Row({ space: 8 }) {
          Text('最近记录')
            .fontSize(EggClipTypography.bodySize)
            .fontWeight(FontWeight.Bold)
            .fontColor(EggClipColors.textPrimary)
            .layoutWeight(1)

          Button(this.clearingHistory ? '清理中' : '清空')
            .height(28)
            .enabled(this.historyUsed > 0 && !this.clearingHistory && this.deletingHistoryItemId.length === 0)
            .fontSize(11)
            .fontColor(EggClipColors.textSecondary)
            .backgroundColor(EggClipColors.controlBackground)
            .borderRadius(14)
            .onClick(() => {
              this.clearHistory();
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(`当前本机历史 ${this.historyUsed} / ${this.historyLimit}；离线补齐只进历史，不覆盖当前剪贴板。`)
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
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor(EggClipColors.controlBackground)
    .borderRadius(14)
  }

  @Builder
  private HistoryItem(item: HistoryPreviewItem) {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        Column({ space: 4 }) {
          Text(item.title)
            .fontSize(EggClipTypography.captionSize)
            .fontWeight(FontWeight.Medium)
            .fontColor(EggClipColors.textPrimary)

          Text(item.preview)
            .width('100%')
            .fontSize(11)
            .fontColor(EggClipColors.textSecondary)
            .lineHeight(18)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text(item.receivedAt)
          .fontSize(11)
          .fontColor(EggClipColors.textSecondary)
      }
      .width('100%')

      Row({ space: 8 }) {
        Text(item.source)
          .fontSize(10)
          .fontColor(EggClipColors.textSecondary)
          .layoutWeight(1)

        Button(this.deletingHistoryItemId === item.id ? '删除中' : '删除')
          .height(28)
          .enabled(this.deletingHistoryItemId.length === 0 && !this.clearingHistory)
          .fontSize(11)
          .fontColor(EggClipColors.textSecondary)
          .backgroundColor(EggClipColors.cardBackground)
          .borderRadius(14)
          .onClick(() => {
            this.deleteHistoryItem(item.id);
          })
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor(EggClipColors.controlBackground)
    .borderRadius(14)
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

        this.setOutboundStatus(OutboundSendState.PENDING, '正在发送到桌面端', '正在通过当前 POC WebSocket 连接发送文本。');
        pocConnectionStore.sendClipboardText(text)
          .then((sent) => {
            this.pasteStatus = sent ? '已发送到桌面端' : '发送失败：WebSocket 未连接';
            this.setOutboundStatus(
              sent ? OutboundSendState.SENT : OutboundSendState.FAILED,
              sent ? '已发送到桌面端' : '发送失败',
              sent ? '已通过 POC 连接发送；正式协议接入后会改为 ITEM_LIVE。' : 'WebSocket 已断开，本机历史已保留。'
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
    return '桌面端发来的文本会先显示在这里，点击后才会复制到本机剪贴板。发送手机剪贴板必须点击系统 PasteButton。连接和发现入口已移到设备页。';
  }

  private emptyHistoryHelpText(): string {
    if (this.historyLimit === 0) {
      return '当前只保留实时同步，不写入本机历史。可以在设置页把历史数量改为 20、50 或 100 条。';
    }
    return '点击 PasteButton 发送本机剪贴板，或接收桌面端文本后，这里会显示最近记录的元数据；正文预览等待加密/解密链路接入。';
  }

  private persistLocalHistoryThenSend(text: string): void {
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
      return Color.Red;
    }
    if (this.outboundState === OutboundSendState.PENDING || this.outboundState === OutboundSendState.WAITING) {
      return EggClipColors.primary;
    }
    return EggClipColors.textSecondary;
  }
}
