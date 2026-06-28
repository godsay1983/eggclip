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

      Text(this.latestReceivedPreview.length === 0 ? '桌面端发来的文本会先显示在这里，点击后才会复制到本机剪贴板。发送手机剪贴板必须点击系统 PasteButton。连接和发现入口已移到设备页。' : this.latestReceivedTextForDisplay())
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
                  this.captureLocalHistoryText(readResult.text);
                  this.sendPocClipboardText(readResult.text);
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
  private HistoryPlaceholder() {
    Row({ space: 12 }) {
      Text('☰')
        .fontSize(22)
        .fontColor(EggClipColors.primary)

      Column({ space: 6 }) {
        Text('最近记录')
          .width('100%')
          .fontSize(EggClipTypography.bodySize)
          .fontWeight(FontWeight.Bold)
          .fontColor(EggClipColors.textPrimary)

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
          Text(this.historyStatus)
            .width('100%')
            .fontSize(11)
            .fontColor(EggClipColors.textSecondary)
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
          .enabled(this.deletingHistoryItemId.length === 0)
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
      return;
    }

    this.historyStore.loadLocalBroadcastPolicy()
      .then((policy: LocalBroadcastPolicySnapshot) => {
        if (!policy.allowed) {
          this.pasteStatus = policy.message;
          return;
        }
        if (!pocConnectionStore.isConnected()) {
          this.pasteStatus = '已读取纯文本；尚未连接桌面端，未发送。请到设备页连接桌面端';
          return;
        }

        pocConnectionStore.sendClipboardText(text)
          .then((sent) => {
            this.pasteStatus = sent ? '已发送到桌面端' : '发送失败：WebSocket 未连接';
          })
          .catch(() => {
            this.pasteStatus = '发送到桌面端失败';
          });
      })
      .catch(() => {
        this.pasteStatus = '读取同步策略失败，未发送到桌面端';
      });
  }

  private latestReceivedTextForDisplay(): string {
    return this.latestReceivedExpanded ? this.latestReceivedText : this.latestReceivedPreview;
  }

  private latestReceivedMetaText(): string {
    const receivedAt = this.latestReceivedAt.length === 0 ? '未知时间' : this.latestReceivedAt;
    return `来源：${this.latestReceivedSource} · ${receivedAt} · ${this.latestReceivedText.length} 字符 · ${this.latestReceivedByteLength} 字节`;
  }

  private captureLocalHistoryText(text: string): void {
    if (this.historyStore === null) {
      this.historyStatus = '无法获取页面上下文，未保存本机历史';
      return;
    }

    this.historyStatus = '正在保存本机历史';
    this.historyStore.captureLocalText(text)
      .then((snapshot: HistoryStoreSnapshot) => {
        this.historyUsed = snapshot.used;
        this.historyLimit = snapshot.limit;
        this.historyItems = snapshot.items;
        this.historyStatus = snapshot.errorMessage.length > 0 ? snapshot.errorMessage : '已保存到本机历史';
      })
      .catch(() => {
        this.historyStatus = '保存本机历史失败';
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
    if (this.historyStore === null || this.deletingHistoryItemId.length > 0) {
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
}
