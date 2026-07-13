import { common } from '@kit.AbilityKit';
import {
  EGGCLIP_MDNS_SERVICE_TYPE,
  MdnsServiceCandidate,
  PocLifecycleState
} from '../models/PocModels';
import { StatusDot } from '../components/common/StatusDot';
import { ConnectionState } from '../models/ShellModels';
import {
  PocConnectionSnapshot,
  pocConnectionStore
} from '../store/PocConnectionStore';
import { TrustedDeviceStore, TrustedDeviceSummary } from '../store/TrustedDeviceStore';
import {
  PairingConnectionSnapshot,
  PairingConnectionState,
  pairingConnectionStore
} from '../store/PairingConnectionStore';
import { EggClipColors } from '../theme/Colors';
import { EggClipSpacing } from '../theme/Spacing';
import { EggClipTypography } from '../theme/Typography';
import { APP_FOREGROUND_STORAGE_KEY } from '../utils/AppLifecycle';
import { PairingPage } from './PairingPage';

@Component
export struct DevicesPage {
  private trustedDeviceStore: TrustedDeviceStore | null = null;
  private readonly connectionSnapshotListener = (snapshot: PocConnectionSnapshot): void => {
    this.manualHost = snapshot.manualHost;
    this.manualPort = snapshot.manualPort;
    this.lastSuccessfulHost = snapshot.lastSuccessfulHost;
    this.lastSuccessfulPort = snapshot.lastSuccessfulPort;
    this.lastSuccessfulEndpointLabel = snapshot.lastSuccessfulEndpointLabel;
    this.lastSuccessfulAt = snapshot.lastSuccessfulAt;
    this.discoveryState = snapshot.discoveryState;
    this.discoveryStatus = snapshot.discoveryStatus;
    this.discoveryCandidates = snapshot.discoveryCandidates;
    this.transportState = snapshot.transportState;
    this.transportStatus = snapshot.transportStatus;
    this.transportDiagnostics = snapshot.transportDiagnostics;
    this.connectionState = snapshot.connectionState;
    this.connectionTitle = snapshot.connectionTitle;
    this.connectionDescription = snapshot.connectionDescription;
  };
  private readonly pairingSnapshotListener = (snapshot: PairingConnectionSnapshot): void => {
    this.pairingConnectionState = snapshot.state;
    this.pairingAuthenticated = snapshot.authenticated;
    this.pairingTrustedDeviceId = snapshot.trustedDeviceId;
    this.loadTrustedDevices();
  };
  @StorageLink(APP_FOREGROUND_STORAGE_KEY) @Watch('onAppForegroundChanged')
  private appInForeground: boolean = false;
  @State private manualHost: string = '127.0.0.1';
  @State private manualPort: string = '0';
  @State private lastSuccessfulHost: string = '';
  @State private lastSuccessfulPort: string = '';
  @State private lastSuccessfulEndpointLabel: string = '';
  @State private lastSuccessfulAt: string = '';
  @State private discoveryState: PocLifecycleState = PocLifecycleState.IDLE;
  @State private discoveryStatus: string = '等待开始局域网发现';
  @State private discoveryCandidates: MdnsServiceCandidate[] = [];
  @State private transportState: PocLifecycleState = PocLifecycleState.IDLE;
  @State private transportStatus: string = '输入桌面端 IP 和端口后手动连接';
  @State private transportDiagnostics: string = '帧诊断：接收 0 · 接受 0 · 拒绝 0';
  @State private connectionState: ConnectionState = ConnectionState.OFFLINE;
  @State private connectionTitle: string = '等待桌面端';
  @State private connectionDescription: string = '正在等待 mDNS 候选，也可以使用手动 IP';
  @State private pairingExpanded: boolean = false;
  @State private diagnosticsExpanded: boolean = false;
  @State private trustedDevices: TrustedDeviceSummary[] = [];
  @State private pairingConnectionState: PairingConnectionState = PairingConnectionState.IDLE;
  @State private pairingAuthenticated: boolean = false;
  @State private pairingTrustedDeviceId: string = '';
  @State private editingDeviceId: string = '';
  @State private deviceNameDraft: string = '';
  @State private busyDeviceId: string = '';
  @State private deviceActionStatus: string = '';
  @State private gettingStartedDetail: string = '';

  aboutToAppear(): void {
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext !== undefined) {
      pocConnectionStore.initialize(hostContext as common.UIAbilityContext);
      if (this.trustedDeviceStore === null) {
        this.trustedDeviceStore = new TrustedDeviceStore(hostContext as common.UIAbilityContext);
      }
    }
    pocConnectionStore.subscribe(this.connectionSnapshotListener);
    pairingConnectionStore.subscribe(this.pairingSnapshotListener);
    this.loadTrustedDevices();
  }

  aboutToDisappear(): void {
    pocConnectionStore.unsubscribe(this.connectionSnapshotListener);
    pairingConnectionStore.unsubscribe(this.pairingSnapshotListener);
  }

  build() {
    Scroll() {
      Column({ space: EggClipSpacing.sectionGap }) {
        this.Header()
        if (this.trustedDevices.length === 0) {
          this.GettingStartedSection()
        }
        GridRow({
          columns: { sm: 12, md: 12, lg: 12 },
          gutter: { x: EggClipSpacing.sectionGap, y: EggClipSpacing.sectionGap }
        }) {
          GridCol({ span: { sm: 12, md: 5, lg: 5 } }) {
            this.TrustedDevicesCard()
          }

          GridCol({ span: { sm: 12, md: 7, lg: 7 } }) {
            Column({ space: EggClipSpacing.sectionGap }) {
              this.AddDeviceSection()
              this.ConnectionDiagnosticsSection()
            }
            .width('100%')
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
  private GettingStartedSection() {
    Column({ space: 14 }) {
      Column({ space: 5 }) {
        Text('使用前准备')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(EggClipColors.textPrimary)
          .width('100%')

        Text('EggClip 需要 Windows 桌面端配合使用，首次连接约需 2 分钟。')
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
          .lineHeight(20)
          .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      GridRow({
        columns: 12,
        gutter: { x: 8, y: 8 }
      }) {
        GridCol({ span: { sm: 6, md: 3, lg: 3 } }) {
          Button('开始配对')
            .width('100%')
            .height(40)
            .fontSize(12)
            .fontColor(EggClipColors.onPrimary)
            .backgroundColor(EggClipColors.primary)
            .borderRadius(18)
            .onClick(() => {
              this.pairingExpanded = true;
            })
        }

        GridCol({ span: { sm: 6, md: 3, lg: 3 } }) {
          Button('功能演示')
            .width('100%')
            .height(40)
            .fontSize(12)
            .fontColor(EggClipColors.textPrimary)
            .backgroundColor(EggClipColors.controlBackground)
            .borderRadius(18)
            .onClick(() => {
              this.gettingStartedDetail = this.gettingStartedDetail === 'features' ? '' : 'features';
            })
        }

        GridCol({ span: { sm: 6, md: 3, lg: 3 } }) {
          Button('隐私说明')
            .width('100%')
            .height(40)
            .fontSize(12)
            .fontColor(EggClipColors.textPrimary)
            .backgroundColor(EggClipColors.controlBackground)
            .borderRadius(18)
            .onClick(() => {
              this.gettingStartedDetail = this.gettingStartedDetail === 'privacy' ? '' : 'privacy';
            })
        }

        GridCol({ span: { sm: 6, md: 3, lg: 3 } }) {
          Button('连接诊断')
            .width('100%')
            .height(40)
            .fontSize(12)
            .fontColor(EggClipColors.textPrimary)
            .backgroundColor(EggClipColors.controlBackground)
            .borderRadius(18)
            .onClick(() => {
              this.diagnosticsExpanded = true;
              this.gettingStartedDetail = 'diagnostics';
            })
        }
      }
      .width('100%')

      Column({ space: 10 }) {
        this.GettingStartedStep('1', '启动 Windows 客户端', '在电脑上打开 EggClip，保持桌面端运行。')
        this.GettingStartedStep('2', '连接同一局域网', '电脑和 HarmonyOS 设备连接同一 Wi-Fi 或可互通的局域网。')
        this.GettingStartedStep('3', '生成一次性邀请', '在桌面端“设备”页生成邀请二维码或邀请文本。')
        this.GettingStartedStep('4', '扫码或粘贴配对', '点“开始配对”，导入邀请并核对两端显示的确认码。')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      if (this.gettingStartedDetail === 'features') {
        this.FeatureGuideCard()
      } else if (this.gettingStartedDetail === 'privacy') {
        this.PrivacyGuideCard()
      } else if (this.gettingStartedDetail === 'diagnostics') {
        Text('连接诊断已在下方“连接问题”中展开。自动发现失败时可检查防火墙，或手动输入桌面端地址。')
          .width('100%')
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
          .lineHeight(20)
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .backgroundColor(EggClipColors.controlBackground)
          .borderRadius(14)
      }

      Text('邀请 5 分钟后失效且只能使用一次；只有完成确认码核对和安全认证的设备才能同步。')
        .width('100%')
        .fontSize(11)
        .fontColor(EggClipColors.textSecondary)
        .lineHeight(18)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(EggClipSpacing.cardPadding)
    .backgroundColor(EggClipColors.cardBackground)
    .borderRadius(EggClipSpacing.radiusLarge)
  }

  @Builder
  private GettingStartedStep(number: string, title: string, description: string) {
    Row({ space: 12 }) {
      Text(number)
        .width(26)
        .height(26)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(EggClipColors.onPrimary)
        .textAlign(TextAlign.Center)
        .backgroundColor(EggClipColors.primary)
        .borderRadius(13)

      Column({ space: 3 }) {
        Text(title)
          .fontSize(EggClipTypography.captionSize)
          .fontWeight(FontWeight.Medium)
          .fontColor(EggClipColors.textPrimary)

        Text(description)
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
          .lineHeight(18)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  private FeatureGuideCard() {
    Column({ space: 8 }) {
      Text('核心功能')
        .fontSize(EggClipTypography.captionSize)
        .fontWeight(FontWeight.Bold)
        .fontColor(EggClipColors.textPrimary)
        .width('100%')

      this.HelpPoint('Windows → HarmonyOS', '电脑复制文本后，已认证连接会把内容实时显示到 HarmonyOS 首页。')
      this.HelpPoint('HarmonyOS → Windows', '在首页通过系统 PasteButton 授权读取一次文本，发送后可直接在电脑粘贴。')
      this.HelpPoint('自动重连', '桌面端运行且应用回到前台时，会使用已保存的可信设备信息自动连接。')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .backgroundColor(EggClipColors.controlBackground)
    .borderRadius(14)
  }

  @Builder
  private PrivacyGuideCard() {
    Column({ space: 8 }) {
      Text('隐私与安全')
        .fontSize(EggClipTypography.captionSize)
        .fontWeight(FontWeight.Bold)
        .fontColor(EggClipColors.textPrimary)
        .width('100%')

      this.HelpPoint('纯局域网', '不需要账号，不使用中心服务器或公网中继，文本只发给已配对设备。')
      this.HelpPoint('本机保存', '历史记录保存在本机，可在底部“设置”页关闭历史或清空记录。')
      this.HelpPoint('系统保护', '设备私钥和同步空间密钥由系统安全存储保护，普通日志不记录剪贴板正文。')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .backgroundColor(EggClipColors.controlBackground)
    .borderRadius(14)
  }

  @Builder
  private HelpPoint(title: string, description: string) {
    Row({ space: 8 }) {
      Text('•')
        .fontSize(16)
        .fontColor(EggClipColors.accentForeground)

      Text(`${title}：${description}`)
        .layoutWeight(1)
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textSecondary)
        .lineHeight(18)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  private AddDeviceSection() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 3 }) {
          Text('添加设备')
            .fontSize(EggClipTypography.bodySize)
            .fontWeight(FontWeight.Bold)
            .fontColor(EggClipColors.textPrimary)

          Text('扫描或粘贴桌面端邀请。')
            .fontSize(EggClipTypography.captionSize)
            .fontColor(EggClipColors.textSecondary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Button(this.pairingExpanded ? '收起' : '开始配对')
          .height(40)
          .fontSize(12)
          .fontColor(this.pairingExpanded ? EggClipColors.textSecondary : EggClipColors.onPrimary)
          .backgroundColor(this.pairingExpanded ? EggClipColors.controlBackground : EggClipColors.primary)
          .borderRadius(16)
          .onClick(() => {
            this.pairingExpanded = !this.pairingExpanded;
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      if (this.pairingExpanded) {
        PairingPage()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(EggClipSpacing.cardPadding)
    .backgroundColor(EggClipColors.cardBackground)
    .borderRadius(EggClipSpacing.radiusLarge)
  }

  @Builder
  private Header() {
    Column({ space: 6 }) {
      Text('设备')
        .fontSize(EggClipTypography.titleSize)
        .fontWeight(FontWeight.Bold)
        .fontColor(EggClipColors.textPrimary)
        .width('100%')

      Text('已配对设备会在应用前台自动连接。')
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textSecondary)
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private ConnectionDiagnosticsSection() {
    Column({ space: 12 }) {
      Row() {
        Row({ space: 10 }) {
          StatusDot({ state: this.connectionState })

          Column({ space: 3 }) {
            Text('连接问题')
              .fontSize(EggClipTypography.bodySize)
              .fontWeight(FontWeight.Bold)
              .fontColor(EggClipColors.textPrimary)

            Text(this.diagnosticsSummary())
              .fontSize(EggClipTypography.captionSize)
              .fontColor(EggClipColors.textSecondary)
              .lineHeight(18)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .layoutWeight(1)

        Button(this.diagnosticsExpanded ? '收起' : '展开')
          .height(40)
          .fontSize(12)
          .fontColor(EggClipColors.textSecondary)
          .backgroundColor(EggClipColors.controlBackground)
          .borderRadius(16)
          .onClick(() => {
            this.diagnosticsExpanded = !this.diagnosticsExpanded;
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      Text('自动连接失败时，可在这里重新发现或手动输入地址。')
        .width('100%')
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textSecondary)
        .lineHeight(20)

      if (this.diagnosticsExpanded) {
        this.ConnectionCard()
        if (this.hasRuntimeConnection()) {
          this.RuntimeDeviceCard()
        }
        this.DiscoveryCard()
        this.ManualTransportCard()
        this.TroubleshootingCard()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(EggClipSpacing.cardPadding)
    .backgroundColor(EggClipColors.cardBackground)
    .borderRadius(EggClipSpacing.radiusLarge)
  }

  @Builder
  private ConnectionCard() {
    Column({ space: 14 }) {
      Row() {
        Row({ space: 12 }) {
          StatusDot({ state: this.connectionState })

          Column({ space: 4 }) {
            Text(this.connectionTitle)
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(EggClipColors.textPrimary)

            Text(this.connectionDescription)
              .fontSize(EggClipTypography.captionSize)
              .fontColor(EggClipColors.textSecondary)
              .lineHeight(20)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .layoutWeight(1)

        Text(this.connectionStateLabel())
          .fontSize(11)
          .fontColor(this.connectionStateColor())
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor(EggClipColors.controlBackground)
          .borderRadius(14)
      }
      .width('100%')

    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(EggClipSpacing.cardPadding)
    .backgroundColor(EggClipColors.cardBackground)
    .borderRadius(EggClipSpacing.radiusLarge)
  }

  @Builder
  private RuntimeDeviceCard() {
    Column({ space: 12 }) {
      Row() {
        Text('运行时设备')
          .fontSize(EggClipTypography.bodySize)
          .fontWeight(FontWeight.Bold)
          .fontColor(EggClipColors.textPrimary)
          .layoutWeight(1)

        Text(this.runtimeDeviceKind())
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor(EggClipColors.controlBackground)
          .borderRadius(14)
      }
      .width('100%')

      Row({ space: 10 }) {
        StatusDot({ state: this.connectionState })

        Column({ space: 4 }) {
          Text(this.runtimeDeviceName())
            .fontSize(EggClipTypography.bodySize)
            .fontWeight(FontWeight.Medium)
            .fontColor(EggClipColors.textPrimary)

          Text(this.runtimeDeviceDescription())
            .fontSize(EggClipTypography.captionSize)
            .fontColor(EggClipColors.textSecondary)
            .lineHeight(18)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      this.DeviceInfoRow('短指纹', this.transportState === PocLifecycleState.RUNNING ? '未配对' : '等待配对')
      this.DeviceInfoRow('最后在线', this.runtimeLastSeenText())
      this.DeviceInfoRow('端点', this.runtimeEndpointText())

      Text('临时连接只表示网络通道可用，不代表设备身份可信。完成配对和认证后，设备才会进入可信设备列表。')
        .width('100%')
        .fontSize(11)
        .fontColor(EggClipColors.textSecondary)
        .lineHeight(18)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(EggClipSpacing.cardPadding)
    .backgroundColor(EggClipColors.cardBackground)
    .borderRadius(EggClipSpacing.radiusMedium)
  }

  @Builder
  private DeviceInfoRow(label: string, value: string) {
    Row({ space: 10 }) {
      Text(label)
        .width(72)
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textSecondary)

      Text(value)
        .layoutWeight(1)
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textPrimary)
        .lineHeight(18)
    }
    .width('100%')
  }

  @Builder
  private DiscoveryCard() {
    Column({ space: 10 }) {
      Row() {
        Text('自动发现')
          .fontSize(EggClipTypography.bodySize)
          .fontWeight(FontWeight.Bold)
          .fontColor(EggClipColors.textPrimary)
          .layoutWeight(1)

        Text(this.lifecycleStateLabel(this.discoveryState))
          .fontSize(EggClipTypography.captionSize)
          .fontColor(this.discoveryState === PocLifecycleState.FAILED ?
            EggClipColors.statusError : EggClipColors.textSecondary)
      }
      .width('100%')

      Text(this.discoveryStatus)
        .width('100%')
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textSecondary)
        .lineHeight(20)

      Button(this.discoveryActionLabel())
        .width('100%')
        .height(40)
        .fontColor(this.isDiscoveryActive() ? EggClipColors.textSecondary : EggClipColors.onPrimary)
        .backgroundColor(this.isDiscoveryActive() ? EggClipColors.controlBackground : EggClipColors.primary)
        .borderRadius(19)
        .onClick(() => {
          this.toggleDiscovery();
        })

      if (this.discoveryCandidates.length === 0) {
        Text('暂未发现桌面端。模拟器网络受 VPN/TUN、桥接和防火墙影响时，可以使用下方手动连接。')
          .width('100%')
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
          .lineHeight(20)
      } else {
        ForEach(this.discoveryCandidates, (candidate: MdnsServiceCandidate) => {
          Row({ space: 8 }) {
            Column({ space: 2 }) {
              Text(`${candidate.host}:${candidate.port}`)
                .fontSize(EggClipTypography.captionSize)
                .fontColor(EggClipColors.textPrimary)
              Text(`协议版本 ${candidate.protocolVersion === 0 ? '实验版' : candidate.protocolVersion}`)
                .fontSize(EggClipTypography.captionSize)
                .fontColor(EggClipColors.textSecondary)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Button('连接')
              .height(40)
              .fontColor(EggClipColors.accentForeground)
              .backgroundColor(EggClipColors.cardBackground)
              .borderRadius(17)
              .onClick(() => {
                pocConnectionStore.connectCandidate(candidate);
              })
          }
          .width('100%')
          .padding(10)
          .backgroundColor(EggClipColors.controlBackground)
          .borderRadius(14)
        }, (candidate: MdnsServiceCandidate) => candidate.instanceId)
      }

      Text(`服务 ${EGGCLIP_MDNS_SERVICE_TYPE} · WebSocket ${this.lifecycleStateLabel(this.transportState)}`)
        .width('100%')
        .fontSize(11)
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
    Column({ space: 12 }) {
      Row() {
        Text('手动连接')
          .fontSize(EggClipTypography.bodySize)
          .fontWeight(FontWeight.Bold)
          .fontColor(EggClipColors.textPrimary)
          .layoutWeight(1)

        Text(this.lifecycleStateLabel(this.transportState))
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
      }
      .width('100%')

      Text('当自动发现不可用时，输入桌面端显示的 IP 和端口。连接成功后，首页 PasteButton 会通过该连接发送文本。')
        .width('100%')
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textSecondary)
        .lineHeight(20)

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

      if (this.lastSuccessfulEndpointLabel.length > 0) {
        this.RecentEndpointCard()
      }

      Button('连接桌面端')
        .width('100%')
        .height(44)
        .fontColor(EggClipColors.onPrimary)
        .backgroundColor(EggClipColors.primary)
        .borderRadius(22)
        .onClick(() => {
          pocConnectionStore.connectManualEndpoint(this.manualHost, this.manualPort);
        })

      Button('断开连接')
        .width('100%')
        .height(40)
        .fontColor(EggClipColors.textSecondary)
        .backgroundColor(EggClipColors.controlBackground)
        .borderRadius(20)
        .onClick(() => {
          pocConnectionStore.disconnectManualEndpoint();
        })

      Text(this.transportStatus)
        .width('100%')
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textSecondary)
        .lineHeight(20)

      Text(this.transportDiagnostics)
        .width('100%')
        .fontSize(11)
        .fontColor(EggClipColors.textSecondary)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(EggClipSpacing.cardPadding)
    .backgroundColor(EggClipColors.cardBackground)
    .borderRadius(EggClipSpacing.radiusMedium)
  }

  @Builder
  private RecentEndpointCard() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Column({ space: 3 }) {
          Text('最近成功地址')
            .fontSize(EggClipTypography.captionSize)
            .fontWeight(FontWeight.Medium)
            .fontColor(EggClipColors.textPrimary)

          Text(`${this.lastSuccessfulEndpointLabel} · ${this.lastSuccessfulAt} · 仅代表网络地址，不代表设备可信`)
            .fontSize(11)
            .fontColor(EggClipColors.textSecondary)
            .lineHeight(18)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Button('回填')
          .height(40)
          .fontSize(11)
          .fontColor(EggClipColors.textSecondary)
          .backgroundColor(EggClipColors.cardBackground)
          .borderRadius(15)
          .onClick(() => {
            this.manualHost = this.lastSuccessfulHost;
            this.manualPort = this.lastSuccessfulPort;
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      Button('连接上次地址')
        .width('100%')
        .height(40)
        .fontColor(EggClipColors.accentForeground)
        .backgroundColor(EggClipColors.cardBackground)
        .borderRadius(19)
        .onClick(() => {
          pocConnectionStore.connectLastSuccessfulEndpoint();
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor(EggClipColors.controlBackground)
    .borderRadius(14)
  }

  @Builder
  private TroubleshootingCard() {
    Column({ space: 12 }) {
      Text('连接排障')
        .fontSize(EggClipTypography.bodySize)
        .fontWeight(FontWeight.Bold)
        .fontColor(EggClipColors.textPrimary)
        .width('100%')

      Text(this.troubleshootingHint())
        .width('100%')
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textSecondary)
        .lineHeight(20)

      this.TroubleshootingRow('自动发现', this.discoveryCandidates.length > 0
        ? `已发现 ${this.discoveryCandidates.length} 个候选，可直接点“连接”。`
        : '没有候选时，mDNS 可能被 VPN、模拟器网络、路由器或防火墙阻断。')
      this.TroubleshootingRow('手动 IP', '在桌面端设置的局域网诊断中查看普通网卡 IPv4 和端口，填到上方手动连接。')
      this.TroubleshootingRow('VPN/TUN', '模拟器可能需要开启 VPN 的 TUN 才能访问宿主机局域网；真机通常优先使用同一 Wi‑Fi。')
      this.TroubleshootingRow('安全边界', '候选地址只代表发现到服务，不代表设备已可信；正式同步仍需要配对和认证。')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(EggClipSpacing.cardPadding)
    .backgroundColor(EggClipColors.cardBackground)
    .borderRadius(EggClipSpacing.radiusMedium)
  }

  @Builder
  private TroubleshootingRow(title: string, description: string) {
    Row({ space: 10 }) {
      Text('·')
        .fontSize(20)
        .fontColor(EggClipColors.accentForeground)

      Column({ space: 3 }) {
        Text(title)
          .fontSize(EggClipTypography.captionSize)
          .fontWeight(FontWeight.Medium)
          .fontColor(EggClipColors.textPrimary)
        Text(description)
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
          .lineHeight(18)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  private TrustedDevicesCard() {
    if (this.trustedDevices.length > 0) {
      Column({ space: 12 }) {
        Text('可信设备')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(EggClipColors.textPrimary)
          .width('100%')
        ForEach(this.trustedDevices, (device: TrustedDeviceSummary) => {
          Column({ space: 10 }) {
            Row({ space: 10 }) {
              Column({ space: 5 }) {
                Text(device.displayName)
                  .fontSize(EggClipTypography.bodySize)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(EggClipColors.textPrimary)
                Text(`指纹 ${device.shortFingerprint} · 最后在线 ${device.lastSeen}`)
                  .fontSize(EggClipTypography.captionSize)
                  .fontColor(EggClipColors.textSecondary)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Text(this.trustedDeviceStateLabel(device.deviceId))
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.trustedDeviceStateColor(device.deviceId))
                .padding({ left: 9, right: 9, top: 5, bottom: 5 })
                .backgroundColor(EggClipColors.cardBackground)
                .borderRadius(14)
            }
            .width('100%')

            if (this.editingDeviceId === device.deviceId) {
              Row({ space: 8 }) {
                TextInput({ text: this.deviceNameDraft, placeholder: '设备名称' })
                  .layoutWeight(1)
                  .height(40)
                  .fontSize(EggClipTypography.captionSize)
                  .backgroundColor(EggClipColors.cardBackground)
                  .borderRadius(18)
                  .onChange((value: string) => {
                    this.deviceNameDraft = value;
                  })

                Button('保存')
                  .height(40)
                  .fontSize(12)
                  .fontColor(this.busyDeviceId.length === 0 ?
                    EggClipColors.onPrimary : EggClipColors.textSecondary)
                  .backgroundColor(this.busyDeviceId.length === 0 ?
                    EggClipColors.primary : EggClipColors.controlBackground)
                  .borderRadius(17)
                  .enabled(this.busyDeviceId.length === 0)
                  .onClick(() => {
                    this.saveDeviceName(device.deviceId);
                  })

                Button('取消')
                  .height(40)
                  .fontSize(12)
                  .fontColor(EggClipColors.textSecondary)
                  .backgroundColor(EggClipColors.cardBackground)
                  .borderRadius(17)
                  .onClick(() => {
                    this.editingDeviceId = '';
                    this.deviceNameDraft = '';
                  })
              }
              .width('100%')
            } else {
              Row({ space: 8 }) {
                Button('重命名')
                  .height(40)
                  .fontSize(12)
                  .fontColor(EggClipColors.textPrimary)
                  .backgroundColor(EggClipColors.cardBackground)
                  .borderRadius(16)
                  .enabled(this.busyDeviceId.length === 0)
                  .onClick(() => {
                    this.editingDeviceId = device.deviceId;
                    this.deviceNameDraft = device.displayName;
                    this.deviceActionStatus = '';
                  })

                Button(this.busyDeviceId === device.deviceId ? '正在移除' : '移除设备')
                  .height(40)
                  .fontSize(12)
                  .fontColor(EggClipColors.statusError)
                  .backgroundColor(EggClipColors.cardBackground)
                  .borderRadius(16)
                  .enabled(this.busyDeviceId.length === 0)
                  .onClick(() => {
                    this.confirmRemoveDevice(device);
                  })
              }
              .width('100%')
              .justifyContent(FlexAlign.End)
            }
          }
          .width('100%')
          .padding(12)
          .backgroundColor(EggClipColors.controlBackground)
          .borderRadius(EggClipSpacing.radiusMedium)
        }, (device: TrustedDeviceSummary) => device.deviceId)

        if (this.deviceActionStatus.length > 0) {
          Text(this.deviceActionStatus)
            .width('100%')
            .fontSize(EggClipTypography.captionSize)
            .fontColor(EggClipColors.textSecondary)
            .lineHeight(18)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(EggClipSpacing.cardPadding)
      .backgroundColor(EggClipColors.cardBackground)
      .borderRadius(EggClipSpacing.radiusLarge)
    } else {
      Column({ space: 14 }) {
        Text('◌')
          .fontSize(42)
          .fontColor(EggClipColors.accentForeground)

        Column({ space: 6 }) {
          Text('可信设备')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(EggClipColors.textPrimary)

          Text('还没有可信设备。点击下方“添加设备”完成配对。')
            .fontSize(EggClipTypography.captionSize)
            .fontColor(EggClipColors.textSecondary)
            .textAlign(TextAlign.Center)
            .lineHeight(20)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)

      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding(EggClipSpacing.cardPadding)
      .backgroundColor(EggClipColors.cardBackground)
      .borderRadius(EggClipSpacing.radiusLarge)
    }
  }

  private loadTrustedDevices(): void {
    if (this.trustedDeviceStore === null) return;
    this.trustedDeviceStore.load()
      .then((devices) => { this.trustedDevices = devices; })
      .catch(() => { this.trustedDevices = []; });
  }

  private saveDeviceName(deviceId: string): void {
    if (this.trustedDeviceStore === null || this.busyDeviceId.length > 0) return;
    this.busyDeviceId = deviceId;
    this.trustedDeviceStore.rename(deviceId, this.deviceNameDraft)
      .then((result) => {
        this.busyDeviceId = '';
        if (!result.ok) {
          this.deviceActionStatus = result.reason ?? '设备重命名失败';
          return;
        }
        this.editingDeviceId = '';
        this.deviceNameDraft = '';
        this.deviceActionStatus = '设备名称已更新';
        this.loadTrustedDevices();
      })
      .catch(() => {
        this.busyDeviceId = '';
        this.deviceActionStatus = '设备重命名失败，请稍后重试';
      });
  }

  private confirmRemoveDevice(device: TrustedDeviceSummary): void {
    this.getUIContext().showAlertDialog({
      title: `移除“${device.displayName}”？`,
      message: '这会立即停止自动重连，撤销本机可信记录，并清除本机旧同步空间密钥与历史。桌面端还需移除本设备以轮换空间密钥；再次使用时需要重新配对。',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '确认移除',
        fontColor: EggClipColors.statusError,
        action: () => {
          this.removeDevice(device.deviceId);
        }
      }
    });
  }

  private removeDevice(deviceId: string): void {
    if (this.trustedDeviceStore === null || this.busyDeviceId.length > 0) return;
    this.busyDeviceId = deviceId;
    this.editingDeviceId = '';
    pairingConnectionStore.close();
    this.trustedDeviceStore.removeAndClearPairingSecurity(deviceId)
      .then((result) => {
        this.busyDeviceId = '';
        if (!result.ok) {
          this.deviceActionStatus = result.reason ?? '设备移除未完整完成，请到设置中重新初始化配对安全状态';
          this.loadTrustedDevices();
          return;
        }
        this.deviceActionStatus = '设备已移除，本机旧空间密钥和历史已清理，请在桌面端同步移除本设备';
        this.loadTrustedDevices();
      })
      .catch(() => {
        this.busyDeviceId = '';
        this.deviceActionStatus = '设备移除失败，请到设置中重新初始化配对安全状态';
        this.loadTrustedDevices();
      });
  }

  private trustedDeviceStateLabel(deviceId: string): string {
    if (deviceId !== this.pairingTrustedDeviceId) return '离线';
    if (this.pairingAuthenticated || this.pairingConnectionState === PairingConnectionState.AUTHENTICATED) return '在线';
    if (this.pairingConnectionState === PairingConnectionState.PREPARING ||
      this.pairingConnectionState === PairingConnectionState.CONNECTING ||
      this.pairingConnectionState === PairingConnectionState.CLIENT_HELLO_SENT ||
      this.pairingConnectionState === PairingConnectionState.WAITING_AUTH_OK) return '连接中';
    if (this.pairingConnectionState === PairingConnectionState.FAILED) return '连接失败';
    return '离线';
  }

  private trustedDeviceStateColor(deviceId: string): ResourceColor {
    const label = this.trustedDeviceStateLabel(deviceId);
    if (label === '在线') return EggClipColors.statusOnline;
    if (label === '连接中') return EggClipColors.statusPending;
    if (label === '连接失败') return EggClipColors.statusError;
    return EggClipColors.textSecondary;
  }

  @Builder
  private DevicePolicyCard() {
    Column({ space: 12 }) {
      Text('设备规则')
        .fontSize(EggClipTypography.bodySize)
        .fontWeight(FontWeight.Bold)
        .fontColor(EggClipColors.textPrimary)
        .width('100%')

      this.PolicyRow('最多 5 台', 'v1 建议每个同步空间保持小规模，降低冲突和误连成本。')
      this.PolicyRow('先配对再同步', 'mDNS 只负责发现地址，不能代表设备可信。')
      this.PolicyRow('移除需轮换', '设备移除后会进入 revoked 状态，并触发空间密钥轮换流程。')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(EggClipSpacing.cardPadding)
    .backgroundColor(EggClipColors.cardBackground)
    .borderRadius(EggClipSpacing.radiusMedium)
  }

  @Builder
  private PolicyRow(title: string, description: string) {
    Row({ space: 10 }) {
      Text('•')
        .fontSize(20)
        .fontColor(EggClipColors.accentForeground)

      Column({ space: 3 }) {
        Text(title)
          .fontSize(EggClipTypography.bodySize)
          .fontWeight(FontWeight.Medium)
          .fontColor(EggClipColors.textPrimary)
        Text(description)
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
          .lineHeight(19)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
  }

  private onAppForegroundChanged(): void {
    pocConnectionStore.handleForegroundChanged(this.appInForeground);
  }

  private connectionStateLabel(): string {
    if (this.connectionState === ConnectionState.ONLINE) {
      return '在线';
    }
    if (this.connectionState === ConnectionState.CONNECTING) {
      return '连接中';
    }
    if (this.connectionState === ConnectionState.AUTH_FAILED) {
      return '认证失败';
    }
    if (this.connectionState === ConnectionState.PAUSED) {
      return '已暂停';
    }
    return '离线';
  }

  private connectionStateColor(): ResourceColor {
    if (this.connectionState === ConnectionState.ONLINE) {
      return EggClipColors.statusOnline;
    }
    if (this.connectionState === ConnectionState.CONNECTING) {
      return EggClipColors.statusPending;
    }
    if (this.connectionState === ConnectionState.AUTH_FAILED) {
      return EggClipColors.statusError;
    }
    return EggClipColors.textSecondary;
  }

  private runtimeDeviceKind(): string {
    if (this.transportState === PocLifecycleState.RUNNING) {
      return '诊断连接';
    }
    return '连接记录';
  }

  private runtimeDeviceName(): string {
    if (this.transportState === PocLifecycleState.RUNNING) {
      return '桌面端临时连接';
    }
    if (this.transportState === PocLifecycleState.FAILED) {
      return '桌面端连接失败';
    }
    return '等待可信设备';
  }

  private runtimeDeviceDescription(): string {
    if (this.transportState === PocLifecycleState.RUNNING) {
      return '网络通道已建立，可回到首页使用系统粘贴按钮发送文本。';
    }
    if (this.transportState === PocLifecycleState.FAILED) {
      return '当前没有可信设备记录；可根据排障提示重试手动连接。';
    }
    return '正式配对完成后，这里会显示可信设备状态、短指纹和最后在线时间。';
  }

  private runtimeLastSeenText(): string {
    if (this.transportState === PocLifecycleState.RUNNING) {
      return '当前在线';
    }
    if (this.transportState === PocLifecycleState.FAILED) {
      return '连接失败';
    }
    return '暂无';
  }

  private runtimeEndpointText(): string {
    const port = this.manualPort.length > 0 ? this.manualPort : '未设置';
    return `${this.manualHost}:${port}`;
  }

  private hasRuntimeConnection(): boolean {
    return this.transportState !== PocLifecycleState.IDLE &&
      this.manualHost.trim().length > 0 &&
      this.manualPort.length > 0 &&
      this.manualPort !== '0';
  }

  private lifecycleStateLabel(state: PocLifecycleState): string {
    if (state === PocLifecycleState.STARTING) {
      return '启动中';
    }
    if (state === PocLifecycleState.RUNNING) {
      return '运行中';
    }
    if (state === PocLifecycleState.FAILED) {
      return '失败';
    }
    return '未启动';
  }

  private isDiscoveryActive(): boolean {
    return this.discoveryState === PocLifecycleState.STARTING ||
      this.discoveryState === PocLifecycleState.RUNNING;
  }

  private discoveryActionLabel(): string {
    if (this.isDiscoveryActive()) {
      return '停止发现';
    }
    if (this.discoveryState === PocLifecycleState.FAILED) {
      return '重新发现';
    }
    return '开始发现';
  }

  private toggleDiscovery(): void {
    if (this.isDiscoveryActive()) {
      pocConnectionStore.stopDiscovery();
      return;
    }
    pocConnectionStore.startDiscovery();
  }

  private troubleshootingHint(): string {
    if (this.transportState === PocLifecycleState.RUNNING) {
      return 'WebSocket 已连接。现在可以回到首页，通过 PasteButton 发送本机剪贴板文本。';
    }
    if (this.transportState === PocLifecycleState.FAILED) {
      return '连接失败时，优先检查桌面端是否运行、端口是否正确、Windows 防火墙是否允许，以及两端是否在同一局域网。';
    }
    if (this.discoveryState === PocLifecycleState.FAILED) {
      return '自动发现失败时，不要卡在 mDNS；直接使用桌面端显示的 IPv4 和端口进行手动连接。';
    }
    if (!this.appInForeground) {
      return '应用在后台时会停止发现和连接；回到前台后再重新发现。';
    }
    return '先开始发现桌面端；如果没有候选地址，再使用手动 IP 回退。';
  }

  private diagnosticsSummary(): string {
    if (this.transportState === PocLifecycleState.RUNNING) {
      return '桌面端连接正常';
    }
    if (this.discoveryCandidates.length > 0) {
      return `发现 ${this.discoveryCandidates.length} 个桌面端，可展开选择`;
    }
    if (this.transportState === PocLifecycleState.FAILED || this.discoveryState === PocLifecycleState.FAILED) {
      return '发现或连接失败，可展开查看排障建议';
    }
    return '自动连接异常时可展开检查';
  }
}
