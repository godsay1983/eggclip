import { EGGCLIP_MDNS_SERVICE_TYPE, ManualEndpoint, PocLifecycleState, PocRuntimeState } from '../models/PocModels';
import { StatusDot } from '../components/common/StatusDot';
import { HomeShellState } from '../models/ShellModels';
import { ClipboardBridgeService } from '../services/clipboard/ClipboardBridgeService';
import { WebSocketTransportService } from '../services/transport/WebSocketTransportService';
import { createInitialHomeShellState } from '../store/HomeStore';
import { createInitialPocRuntimeState } from '../store/PocStore';
import { EggClipColors } from '../theme/Colors';
import { EggClipSpacing } from '../theme/Spacing';
import { EggClipTypography } from '../theme/Typography';

@Component
export struct HomePage {
  private readonly state: HomeShellState = createInitialHomeShellState();
  private readonly pocState: PocRuntimeState = createInitialPocRuntimeState();
  private readonly clipboardBridge: ClipboardBridgeService = new ClipboardBridgeService();
  private readonly transport: WebSocketTransportService = new WebSocketTransportService();
  @State private manualHost: string = '127.0.0.1';
  @State private manualPort: string = '0';
  @State private pasteStatus: string = '等待点击 PasteButton 触发一次性授权';
  @State private transportStatus: string = '输入桌面端 IP 和端口后手动连接';
  @State private copyStatus: string = '收到桌面文本后可手动复制到本机';
  @State private latestReceivedText: string = '';
  @State private latestReceivedPreview: string = '';
  @State private latestReceivedSource: string = '暂无内容';

  build() {
    Scroll() {
      Column({ space: EggClipSpacing.sectionGap }) {
        this.Header()
        this.ConnectionCard()
        this.PocStatusCard()
        this.ManualTransportCard()
        this.LatestClipboardCard()
        this.HistoryPlaceholder()
      }
      .width('100%')
      .padding(EggClipSpacing.pagePadding)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(EggClipColors.pageBackground)
  }

  @Builder
  private Header() {
    Row() {
      Column({ space: 4 }) {
        Text('蛋定 Clip')
          .fontSize(EggClipTypography.titleSize)
          .fontWeight(FontWeight.Bold)
          .fontColor(EggClipColors.textPrimary)

        Text('局域网剪贴板同步')
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text('设置')
        .fontSize(EggClipTypography.bodySize)
        .fontColor(EggClipColors.textSecondary)
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .backgroundColor(EggClipColors.controlBackground)
        .borderRadius(18)
    }
    .width('100%')
  }

  @Builder
  private ConnectionCard() {
    Row({ space: 10 }) {
      StatusDot({ state: this.state.connection.state })

      Column({ space: 3 }) {
        Text(this.state.connection.title)
          .fontSize(EggClipTypography.bodySize)
          .fontWeight(FontWeight.Medium)
          .fontColor(EggClipColors.textPrimary)

        Text(this.state.connection.description)
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(EggClipSpacing.cardPadding)
    .backgroundColor(EggClipColors.cardBackground)
    .borderRadius(EggClipSpacing.radiusMedium)
  }

  @Builder
  private PocStatusCard() {
    Column({ space: 10 }) {
      Row() {
        Text('POC 状态')
          .fontSize(EggClipTypography.bodySize)
          .fontWeight(FontWeight.Bold)
          .fontColor(EggClipColors.textPrimary)
          .layoutWeight(1)

        Text('H1')
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
      }
      .width('100%')

      Text(`mDNS: ${EGGCLIP_MDNS_SERVICE_TYPE}`)
        .width('100%')
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textSecondary)

      Text(`发现服务：${this.pocState.discoveryState} · WebSocket：${this.pocState.transportState}`)
        .width('100%')
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textSecondary)

      Text('已声明局域网网络权限；PasteButton 已接入 pasteboard 纯文本读取，真机连接待接入。')
        .width('100%')
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textSecondary)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(EggClipSpacing.cardPadding)
    .backgroundColor(EggClipColors.cardBackground)
    .borderRadius(EggClipSpacing.radiusMedium)
  }

  @Builder
  private ManualTransportCard() {
    Column({ space: 10 }) {
      Row() {
        Text('手动连接')
          .fontSize(EggClipTypography.bodySize)
          .fontWeight(FontWeight.Bold)
          .fontColor(EggClipColors.textPrimary)
          .layoutWeight(1)

        Text(this.transport.currentState())
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
      }
      .width('100%')

      Row({ space: 8 }) {
        TextInput({ text: this.manualHost, placeholder: '桌面端 IP' })
          .layoutWeight(1)
          .height(42)
          .backgroundColor(EggClipColors.controlBackground)
          .borderRadius(14)
          .onChange((value: string) => {
            this.manualHost = value;
          })

        TextInput({ text: this.manualPort, placeholder: '端口' })
          .width(96)
          .height(42)
          .backgroundColor(EggClipColors.controlBackground)
          .borderRadius(14)
          .type(InputType.Number)
          .onChange((value: string) => {
            this.manualPort = value;
          })
      }
      .width('100%')

      Button('连接桌面 POC')
        .width('100%')
        .height(44)
        .fontColor(EggClipColors.onPrimary)
        .backgroundColor(EggClipColors.primary)
        .borderRadius(22)
        .onClick(() => {
          this.connectManualEndpoint();
        })

      Text(this.transportStatus)
        .width('100%')
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textSecondary)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(EggClipSpacing.cardPadding)
    .backgroundColor(EggClipColors.cardBackground)
    .borderRadius(EggClipSpacing.radiusMedium)
  }

  @Builder
  private LatestClipboardCard() {
    Column({ space: 14 }) {
      Row() {
        Text('最新收到')
          .fontSize(EggClipTypography.bodySize)
          .fontWeight(FontWeight.Bold)
          .fontColor(EggClipColors.textPrimary)
          .layoutWeight(1)

        Text(this.latestReceivedPreview.length === 0 ? '暂无内容' : this.latestReceivedSource)
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
      }
      .width('100%')

      Text(this.latestReceivedPreview.length === 0 ? '完成配对后，桌面端的最新文本会显示在这里。历史补同步不会覆盖本机剪贴板。' : this.latestReceivedPreview)
        .fontSize(EggClipTypography.bodySize)
        .fontColor(EggClipColors.textSecondary)
        .lineHeight(24)

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
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(EggClipSpacing.cardPadding)
    .backgroundColor(EggClipColors.cardBackground)
    .borderRadius(EggClipSpacing.radiusLarge)
  }

  @Builder
  private HistoryPlaceholder() {
    Column({ space: 8 }) {
      Text('最近记录')
        .width('100%')
        .fontSize(EggClipTypography.bodySize)
        .fontWeight(FontWeight.Bold)
        .fontColor(EggClipColors.textPrimary)

      Text(`这里会保存最近 ${this.state.history.limit} 条记录，最长保留 7 天。`)
        .width('100%')
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textSecondary)
    }
    .width('100%')
    .padding(EggClipSpacing.cardPadding)
    .backgroundColor(EggClipColors.cardBackground)
    .borderRadius(EggClipSpacing.radiusMedium)
  }

  private connectManualEndpoint(): void {
    const port = Number(this.manualPort);
    const endpoint: ManualEndpoint = {
      host: this.manualHost,
      port
    };
    this.transportStatus = '正在连接桌面 POC';
    this.transport.connect(endpoint, {
      onOpen: () => {
        this.transportStatus = '已连接桌面 POC，PasteButton 读取后会发送文本';
      },
      onClose: (reason: string) => {
        this.transportStatus = `连接已关闭：${reason}`;
      },
      onError: (reason: string) => {
        this.transportStatus = `连接失败：${reason}`;
      },
      onMessage: (message: string) => {
        const text = this.transport.parseClipboardTextMessage(message);
        if (text !== null) {
          this.latestReceivedText = text;
          this.latestReceivedPreview = this.trimPreview(text);
          this.latestReceivedSource = 'Desktop POC';
          this.copyStatus = '已收到桌面 POC 文本，可点击复制到本机';
          this.transportStatus = `收到桌面 POC 文本：${text.length} 字符`;
        }
      }
    })
      .then((result) => {
        if (!result.ok) {
          this.transportStatus = result.reason === undefined ? '连接参数无效' : `连接参数无效：${result.reason}`;
        }
      })
      .catch(() => {
        this.transportStatus = '连接桌面 POC 失败';
      });
  }

  private sendPocClipboardText(text: string): void {
    if (!this.transport.isConnected()) {
      this.pasteStatus = '已读取纯文本；尚未连接桌面 POC，未发送';
      return;
    }

    this.transport.sendClipboardText(text)
      .then((sent) => {
        this.pasteStatus = sent ? '已发送到桌面 POC' : '发送失败：WebSocket 未连接';
      })
      .catch(() => {
        this.pasteStatus = '发送到桌面 POC 失败';
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

  private trimPreview(text: string): string {
    if (text.length <= 180) {
      return text;
    }
    return `${text.slice(0, 90)}\n……\n${text.slice(-60)}`;
  }
}
