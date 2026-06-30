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
import { EggClipColors } from '../theme/Colors';
import { EggClipSpacing } from '../theme/Spacing';
import { EggClipTypography } from '../theme/Typography';
import { APP_FOREGROUND_STORAGE_KEY } from '../utils/AppLifecycle';

@Component
export struct DevicesPage {
  private readonly connectionSnapshotListener = (snapshot: PocConnectionSnapshot): void => {
    this.manualHost = snapshot.manualHost;
    this.manualPort = snapshot.manualPort;
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
  @StorageLink(APP_FOREGROUND_STORAGE_KEY) @Watch('onAppForegroundChanged')
  private appInForeground: boolean = false;
  @State private manualHost: string = '127.0.0.1';
  @State private manualPort: string = '0';
  @State private discoveryState: PocLifecycleState = PocLifecycleState.IDLE;
  @State private discoveryStatus: string = '等待开始局域网发现';
  @State private discoveryCandidates: MdnsServiceCandidate[] = [];
  @State private transportState: PocLifecycleState = PocLifecycleState.IDLE;
  @State private transportStatus: string = '输入桌面端 IP 和端口后手动连接';
  @State private transportDiagnostics: string = '帧诊断：接收 0 · 接受 0 · 拒绝 0';
  @State private connectionState: ConnectionState = ConnectionState.OFFLINE;
  @State private connectionTitle: string = '等待桌面端';
  @State private connectionDescription: string = '正在等待 mDNS 候选，也可以使用手动 IP';

  aboutToAppear(): void {
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext !== undefined) {
      pocConnectionStore.initialize(hostContext as common.UIAbilityContext);
    }
    pocConnectionStore.subscribe(this.connectionSnapshotListener);
  }

  aboutToDisappear(): void {
    pocConnectionStore.unsubscribe(this.connectionSnapshotListener);
  }

  build() {
    Scroll() {
      Column({ space: EggClipSpacing.sectionGap }) {
        this.Header()
        this.ConnectionCard()
        this.DiscoveryCard()
        this.ManualTransportCard()
        this.TroubleshootingCard()
        this.EmptyDeviceCard()
        this.DevicePolicyCard()
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
    Column({ space: 6 }) {
      Text('设备')
        .fontSize(EggClipTypography.titleSize)
        .fontWeight(FontWeight.Bold)
        .fontColor(EggClipColors.textPrimary)
        .width('100%')

      Text('发现、连接和管理局域网内可信设备')
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textSecondary)
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
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

      Row({ space: 8 }) {
        Button(this.discoveryState === PocLifecycleState.RUNNING ? '重新发现' : '开始发现')
          .layoutWeight(1)
          .height(42)
          .fontColor(EggClipColors.onPrimary)
          .backgroundColor(EggClipColors.primary)
          .borderRadius(21)
          .onClick(() => {
            pocConnectionStore.startDiscovery();
          })

        Button('断开')
          .width(92)
          .height(42)
          .fontColor(EggClipColors.textSecondary)
          .backgroundColor(EggClipColors.controlBackground)
          .borderRadius(21)
          .onClick(() => {
            pocConnectionStore.disconnectManualEndpoint();
          })
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
  private DiscoveryCard() {
    Column({ space: 10 }) {
      Row() {
        Text('自动发现')
          .fontSize(EggClipTypography.bodySize)
          .fontWeight(FontWeight.Bold)
          .fontColor(EggClipColors.textPrimary)
          .layoutWeight(1)

        Text(this.discoveryState)
          .fontSize(EggClipTypography.captionSize)
          .fontColor(this.discoveryState === PocLifecycleState.FAILED ? Color.Red : EggClipColors.textSecondary)
      }
      .width('100%')

      Text(this.discoveryStatus)
        .width('100%')
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textSecondary)
        .lineHeight(20)

      Row({ space: 8 }) {
        Button('开始发现')
          .layoutWeight(1)
          .height(38)
          .fontColor(EggClipColors.onPrimary)
          .backgroundColor(EggClipColors.primary)
          .borderRadius(19)
          .onClick(() => {
            pocConnectionStore.startDiscovery();
          })

        Button('停止发现')
          .layoutWeight(1)
          .height(38)
          .fontColor(EggClipColors.textSecondary)
          .backgroundColor(EggClipColors.controlBackground)
          .borderRadius(19)
          .onClick(() => {
            pocConnectionStore.stopDiscovery();
          })
      }
      .width('100%')

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
              .height(34)
              .fontColor(EggClipColors.onPrimary)
              .backgroundColor(EggClipColors.primary)
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

      Text(`服务 ${EGGCLIP_MDNS_SERVICE_TYPE} · WebSocket ${this.transportState}`)
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

        Text(this.transportState)
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
        .fontColor(EggClipColors.primary)

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
  private EmptyDeviceCard() {
    Column({ space: 14 }) {
      Text('◌')
        .fontSize(42)
        .fontColor(EggClipColors.primary)

      Column({ space: 6 }) {
        Text('还没有可信设备')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(EggClipColors.textPrimary)

        Text('当前连接入口仍是 POC 诊断能力；正式配对完成后，这里会显示设备名称、在线状态、公钥短指纹和最后在线时间。')
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
          .textAlign(TextAlign.Center)
          .lineHeight(20)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)

      Button('添加设备')
        .width('100%')
        .height(44)
        .enabled(false)
        .fontColor(EggClipColors.onPrimary)
        .backgroundColor(EggClipColors.primary)
        .borderRadius(22)

      Text('配对流程会在安全握手完成后开放。')
        .fontSize(11)
        .fontColor(EggClipColors.textSecondary)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding(EggClipSpacing.cardPadding)
    .backgroundColor(EggClipColors.cardBackground)
    .borderRadius(EggClipSpacing.radiusLarge)
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
        .fontColor(EggClipColors.primary)

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
      return EggClipColors.primary;
    }
    if (this.connectionState === ConnectionState.AUTH_FAILED) {
      return Color.Red;
    }
    return EggClipColors.textSecondary;
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
}
