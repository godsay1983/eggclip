import { common } from '@kit.AbilityKit';
import {
  EGGCLIP_MDNS_SERVICE_TYPE,
  ManualEndpoint,
  MdnsServiceCandidate,
  PocLifecycleState
} from '../models/PocModels';
import { StatusDot } from '../components/common/StatusDot';
import { ConnectionState, HomeShellState } from '../models/ShellModels';
import { ClipboardBridgeService } from '../services/clipboard/ClipboardBridgeService';
import { MdnsDiscoveryService } from '../services/discovery/MdnsDiscoveryService';
import { WebSocketTransportService } from '../services/transport/WebSocketTransportService';
import { createInitialHomeShellState } from '../store/HomeStore';
import { EggClipColors } from '../theme/Colors';
import { EggClipSpacing } from '../theme/Spacing';
import { EggClipTypography } from '../theme/Typography';
import { APP_FOREGROUND_STORAGE_KEY } from '../utils/AppLifecycle';

@Component
export struct HomePage {
  private readonly state: HomeShellState = createInitialHomeShellState();
  private readonly clipboardBridge: ClipboardBridgeService = new ClipboardBridgeService();
  private readonly transport: WebSocketTransportService = new WebSocketTransportService();
  private discovery: MdnsDiscoveryService | null = null;
  private reconnectOnForeground: boolean = false;
  @StorageLink(APP_FOREGROUND_STORAGE_KEY) @Watch('onAppForegroundChanged')
  private appInForeground: boolean = false;
  @State private manualHost: string = '127.0.0.1';
  @State private manualPort: string = '0';
  @State private discoveryState: PocLifecycleState = PocLifecycleState.IDLE;
  @State private discoveryStatus: string = '等待开始局域网发现';
  @State private discoveryCandidates: MdnsServiceCandidate[] = [];
  @State private transportState: PocLifecycleState = PocLifecycleState.IDLE;
  @State private connectionState: ConnectionState = ConnectionState.OFFLINE;
  @State private connectionTitle: string = '等待桌面端';
  @State private connectionDescription: string = '正在等待 mDNS 候选，也可以使用手动 IP';
  @State private pasteStatus: string = '等待点击 PasteButton 触发一次性授权';
  @State private transportStatus: string = '输入桌面端 IP 和端口后手动连接';
  @State private transportDiagnostics: string = '帧诊断：接收 0 · 接受 0 · 拒绝 0';
  @State private copyStatus: string = '收到桌面文本后可手动复制到本机';
  @State private latestReceivedText: string = '';
  @State private latestReceivedPreview: string = '';
  @State private latestReceivedSource: string = '暂无内容';

  aboutToAppear(): void {
    if (this.discovery === null) {
      const hostContext = this.getUIContext().getHostContext();
      if (hostContext === undefined) {
        this.discoveryState = PocLifecycleState.FAILED;
        this.discoveryStatus = '无法获取页面上下文，mDNS 搜索不可用';
        return;
      }
      this.discovery = new MdnsDiscoveryService(hostContext as common.UIAbilityContext);
    }
    if (this.appInForeground) {
      this.startDiscovery();
    }
  }

  aboutToDisappear(): void {
    this.discovery?.stopSearch();
    this.transport.close();
  }

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
      StatusDot({ state: this.connectionState })

      Column({ space: 3 }) {
        Text(this.connectionTitle)
          .fontSize(EggClipTypography.bodySize)
          .fontWeight(FontWeight.Medium)
          .fontColor(EggClipColors.textPrimary)

        Text(this.connectionDescription)
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

      Text(`发现服务：${this.discoveryState} · WebSocket：${this.transportState}`)
        .width('100%')
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textSecondary)

      Text(this.discoveryStatus)
        .width('100%')
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textSecondary)

      Text(this.transportDiagnostics)
        .width('100%')
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.primary)

      Row({ space: 8 }) {
        Button('开始发现')
          .layoutWeight(1)
          .height(38)
          .fontColor(EggClipColors.onPrimary)
          .backgroundColor(EggClipColors.primary)
          .borderRadius(19)
          .onClick(() => {
            this.startDiscovery();
          })

        Button('停止发现')
          .layoutWeight(1)
          .height(38)
          .fontColor(EggClipColors.textSecondary)
          .backgroundColor(EggClipColors.controlBackground)
          .borderRadius(19)
          .onClick(() => {
            this.discovery?.stopSearch();
          })
      }
      .width('100%')

      if (this.discoveryCandidates.length === 0) {
        Text('暂未发现桌面端；手动 IP 连接始终可用。')
          .width('100%')
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
      } else {
        ForEach(this.discoveryCandidates, (candidate: MdnsServiceCandidate) => {
          Row({ space: 8 }) {
            Column({ space: 2 }) {
              Text(`${candidate.host}:${candidate.port}`)
                .fontSize(EggClipTypography.captionSize)
                .fontColor(EggClipColors.textPrimary)
              Text(`协议版本 ${candidate.protocolVersion === 0 ? 'POC' : candidate.protocolVersion}`)
                .fontSize(EggClipTypography.captionSize)
                .fontColor(EggClipColors.textSecondary)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Button('连接')
              .height(34)
              .fontColor(EggClipColors.onPrimary)
              .backgroundColor(EggClipColors.primary)
              .borderRadius(17)
              .onClick(() => {
                this.connectCandidate(candidate);
              })
          }
          .width('100%')
          .padding(10)
          .backgroundColor(EggClipColors.controlBackground)
          .borderRadius(14)
        }, (candidate: MdnsServiceCandidate) => candidate.instanceId)
      }
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

      Button('断开 POC 连接')
        .width('100%')
        .height(40)
        .fontColor(EggClipColors.textSecondary)
        .backgroundColor(EggClipColors.controlBackground)
        .borderRadius(20)
        .onClick(() => {
          this.disconnectManualEndpoint();
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
    this.transportState = PocLifecycleState.STARTING;
    this.connectionState = ConnectionState.CONNECTING;
    this.connectionTitle = '正在连接桌面 POC';
    this.connectionDescription = `${endpoint.host}:${endpoint.port}`;
    this.transport.connect(endpoint, {
      onOpen: () => {
        this.reconnectOnForeground = true;
        this.transportState = PocLifecycleState.RUNNING;
        this.transportStatus = '已连接桌面 POC，PasteButton 读取后会发送文本';
        this.connectionState = ConnectionState.ONLINE;
        this.connectionTitle = '已连接桌面 POC';
        this.connectionDescription = `${endpoint.host}:${endpoint.port} · 当前连接尚未认证`;
        this.refreshTransportDiagnostics();
      },
      onClose: (reason: string) => {
        this.transportState = PocLifecycleState.IDLE;
        this.transportStatus = `连接已关闭：${reason}`;
        this.connectionState = ConnectionState.OFFLINE;
        this.connectionTitle = '桌面 POC 已断开';
        this.connectionDescription = reason;
      },
      onError: (reason: string) => {
        this.transportState = PocLifecycleState.FAILED;
        this.transportStatus = `连接失败：${reason}`;
        this.connectionState = ConnectionState.OFFLINE;
        this.connectionTitle = '连接桌面 POC 失败';
        this.connectionDescription = `${reason}；可尝试其他候选或手动 IP`;
        this.refreshTransportDiagnostics();
      },
      onMessage: (message: string) => {
        const decoded = this.transport.decodeClipboardTextMessage(message);
        this.refreshTransportDiagnostics();
        if (decoded.ok) {
          this.latestReceivedText = decoded.text;
          this.latestReceivedPreview = this.trimPreview(decoded.text);
          this.latestReceivedSource = 'Desktop POC';
          this.copyStatus = '已收到桌面 POC 文本，可点击复制到本机';
          this.transportStatus = `收到桌面 POC 文本：${decoded.text.length} 字符`;
          this.connectionState = ConnectionState.ONLINE;
          this.connectionTitle = '已收到桌面 POC 文本';
          this.connectionDescription = '内容只进入预览，点击后才会复制到本机';
        } else {
          this.transportStatus = `${decoded.reason}，已忽略`;
        }
      }
    })
      .then((result) => {
        if (!result.ok) {
          this.transportState = PocLifecycleState.FAILED;
          this.transportStatus = result.reason === undefined ? '连接参数无效' : `连接参数无效：${result.reason}`;
          this.connectionState = ConnectionState.OFFLINE;
          this.connectionTitle = '连接参数无效';
          this.connectionDescription = result.reason ?? '请检查桌面端 IP 和端口';
        }
      })
      .catch(() => {
        this.transportState = PocLifecycleState.FAILED;
        this.transportStatus = '连接桌面 POC 失败';
        this.connectionState = ConnectionState.OFFLINE;
        this.connectionTitle = '连接桌面 POC 失败';
        this.connectionDescription = '请检查候选地址、Windows 防火墙和当前网络';
      });
  }

  private startDiscovery(): void {
    if (this.discovery === null) {
      return;
    }
    this.discovery.startSearch({
      onStateChanged: (state: PocLifecycleState, reason: string) => {
        this.discoveryState = state;
        this.discoveryStatus = reason;
        if (this.transportState !== PocLifecycleState.RUNNING) {
          this.connectionState = state === PocLifecycleState.STARTING || state === PocLifecycleState.RUNNING
            ? ConnectionState.CONNECTING
            : ConnectionState.OFFLINE;
          this.connectionTitle = state === PocLifecycleState.FAILED ? '局域网发现不可用' : '正在发现桌面端';
          this.connectionDescription = reason;
        }
      },
      onCandidatesChanged: (candidates: MdnsServiceCandidate[]) => {
        this.discoveryCandidates = candidates;
        if (candidates.length > 0) {
          this.discoveryStatus = `已发现 ${candidates.length} 个候选地址；mDNS 仅用于发现，不代表设备可信`;
          if (this.transportState !== PocLifecycleState.RUNNING) {
            this.connectionState = ConnectionState.CONNECTING;
            this.connectionTitle = `已发现 ${candidates.length} 个桌面候选`;
            this.connectionDescription = '请选择候选连接；候选地址不代表设备已经认证';
          }
        }
      }
    });
  }

  private connectCandidate(candidate: MdnsServiceCandidate): void {
    this.manualHost = candidate.host;
    this.manualPort = candidate.port.toString();
    this.connectManualEndpoint();
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

  private disconnectManualEndpoint(): void {
    this.reconnectOnForeground = false;
    this.transport.close();
    this.transportState = PocLifecycleState.IDLE;
    this.transportStatus = '已主动断开桌面 POC';
    this.connectionState = ConnectionState.OFFLINE;
    this.connectionTitle = '已主动断开桌面 POC';
    this.connectionDescription = 'mDNS 发现仍可继续运行';
  }

  private onAppForegroundChanged(): void {
    if (this.appInForeground) {
      this.startDiscovery();
      if (this.reconnectOnForeground) {
        this.connectManualEndpoint();
      }
      return;
    }

    this.reconnectOnForeground = this.transport.isConnected();
    this.discovery?.stopSearch();
    this.transport.close();
    this.transportState = PocLifecycleState.IDLE;
    this.transportStatus = this.reconnectOnForeground
      ? '应用进入后台，已断开；回到前台后将重新连接'
      : '应用进入后台，已停止发现和连接';
    this.connectionState = ConnectionState.OFFLINE;
    this.connectionTitle = '应用已进入后台';
    this.connectionDescription = '前台同步已停止，回到前台后会重新发现';
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

  private refreshTransportDiagnostics(): void {
    const diagnostics = this.transport.currentDiagnostics();
    const rejection = diagnostics.lastRejection.length > 0
      ? ` · 上次拒绝：${diagnostics.lastRejection}`
      : '';
    this.transportDiagnostics = `帧诊断：接收 ${diagnostics.receivedFrames} · 接受 ${diagnostics.acceptedItems} · 拒绝 ${diagnostics.rejectedFrames}${rejection}`;
  }
}
