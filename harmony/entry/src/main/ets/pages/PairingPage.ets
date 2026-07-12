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

@Component
export struct PairingPage {
  private readonly pairingStore: PairingStore = new PairingStore();
  private readonly clipboardBridge: ClipboardBridgeService = new ClipboardBridgeService();
  private readonly pairingScanService: PairingScanService = new PairingScanService();
  @State private snapshot: PairingStoreSnapshot = createInitialPairingSnapshot();
  @State private connectionSnapshot: PairingConnectionSnapshot = pairingConnectionStore.snapshot();
  @State private invitationInputText: string = '';
  @State private pasteImportStatus: string = '可以扫码导入，或点击系统 PasteButton 从剪贴板读取邀请。';
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
    pairingConnectionStore.subscribe(this.connectionListener);
  }

  aboutToDisappear(): void {
    pairingConnectionStore.unsubscribe(this.connectionListener);
  }

  build() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 4 }) {
          Text('导入邀请')
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
          placeholder: '粘贴 eggclip://pair?p=...'
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
          Button('扫码导入桌面端二维码')
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
                  this.pasteImportStatus = 'PasteButton 临时授权失败，未读取系统剪贴板';
                  return;
                }
                this.pasteImportStatus = 'PasteButton 已授权，正在读取邀请文本';
                this.clipboardBridge.readPlainTextAfterPasteButton()
                  .then((readResult) => {
                    if (!readResult.ok) {
                      this.pasteImportStatus = readResult.message;
                      return;
                    }
                    this.importInvitationText(readResult.text, '已从剪贴板读取并校验邀请');
                  })
                  .catch(() => {
                    this.pasteImportStatus = '读取剪贴板失败，请确认当前内容是纯文本邀请';
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
          Button('校验邀请')
            .layoutWeight(1)
            .height(42)
            .fontColor(EggClipColors.onPrimary)
            .backgroundColor(EggClipColors.primary)
            .borderRadius(21)
            .onClick(() => {
              this.snapshot = this.pairingStore.updateInvitationText(this.invitationInputText);
              this.snapshot = this.pairingStore.parseCurrent();
            })

          Button('清空')
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
        Button('重新导入邀请')
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

      Text(this.snapshot.statusText)
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
      this.SummaryRow('同步空间', `#${summary.spaceShortId} · key v${summary.spaceKeyVersion}`)
      this.SummaryRow('发行设备', `${summary.issuerDeviceName} · #${summary.issuerShortFingerprint}`)
      this.SummaryRow('剩余时间', `${summary.expiresInSeconds} 秒`)

      if (summary.endpoints.length > 0) {
        this.ConnectionCandidateSelector(summary)
      }

      Column({ space: 4 }) {
        Text('人工确认码')
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
        .fontColor(EggClipColors.onPrimary)
        .backgroundColor(this.canConfirmInvitation() ? EggClipColors.primary : EggClipColors.textSecondary)
        .borderRadius(21)
        .onClick(() => {
          this.confirmCodeAndPrepareConnection();
        })

      if (this.connectionSnapshot.state === PairingConnectionState.AUTHENTICATED) {
        Text('当前已经建立认证连接，无需重复配对。如需使用这份新邀请，请先停止当前连接。')
          .width('100%')
          .fontSize(11)
          .fontColor(EggClipColors.textSecondary)
          .lineHeight(18)
      }

      if (this.snapshot.state === PairingStoreState.PENDING) {
        Text('邀请已从输入框安全清理，继续连接即可完成配对。')
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
        Text('选择桌面端地址')
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(EggClipColors.textPrimary)
          .layoutWeight(1)

        Text(`${summary.endpoints.length} 个候选`)
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
                this.pasteImportStatus = `已选择桌面端地址 ${endpoint.host}:${endpoint.port}`;
              })
          }, (endpoint: PairingConnectionEndpoint) => `${endpoint.host}:${endpoint.port}`)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')

      Text('电脑使用 VPN 或多个网络时，请确认选择的是当前局域网地址。')
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
          Text('连接桌面端')
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
          placeholder: '桌面端 IP'
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
          placeholder: '端口'
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
          .fontColor(EggClipColors.onPrimary)
          .backgroundColor(this.canStartPairingConnection() ? EggClipColors.primary : EggClipColors.textSecondary)
          .borderRadius(21)
          .onClick(() => {
            this.startPairingConnection();
          })

        Button('停止')
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

      Button('连接已配对设备')
        .width('100%')
        .height(42)
        .enabled(!this.isPairingConnectionBusy() &&
          this.connectionSnapshot.state !== PairingConnectionState.AUTHENTICATED)
        .fontColor(EggClipColors.primary)
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
  private SummaryRow(label: string, value: string) {
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
    Text('邀请仅使用一次，5 分钟后失效，也不会保存到剪贴板历史。')
      .fontSize(11)
      .fontColor(EggClipColors.textSecondary)
      .lineHeight(18)
    .width('100%')
  }

  private statusBadgeText(): string {
    if (this.snapshot.state === PairingStoreState.COMPLETED) {
      return '配对完成';
    }
    if (this.snapshot.state === PairingStoreState.READY) {
      return '有效邀请';
    }
    if (this.snapshot.state === PairingStoreState.PENDING) {
      return '待握手';
    }
    if (this.snapshot.state === PairingStoreState.ERROR) {
      return '校验失败';
    }
    return '待校验';
  }

  private statusColor(): ResourceColor {
    if (this.snapshot.state === PairingStoreState.COMPLETED) {
      return EggClipColors.statusOnline;
    }
    if (this.snapshot.state === PairingStoreState.READY) {
      return EggClipColors.statusOnline;
    }
    if (this.snapshot.state === PairingStoreState.PENDING) {
      return EggClipColors.primary;
    }
    if (this.snapshot.state === PairingStoreState.ERROR) {
      return Color.Red;
    }
    return EggClipColors.textSecondary;
  }

  private connectionBadgeText(): string {
    if (this.isAuthenticatedConnection()) {
      return this.connectionSnapshot.syncReady ? '已就绪' : '初始化中';
    }
    if (this.connectionSnapshot.state === PairingConnectionState.FAILED) {
      return '失败';
    }
    if (this.connectionSnapshot.state === PairingConnectionState.CLIENT_HELLO_SENT ||
      this.connectionSnapshot.state === PairingConnectionState.WAITING_AUTH_OK) {
      return '握手中';
    }
    if (this.connectionSnapshot.state === PairingConnectionState.CONNECTING ||
      this.connectionSnapshot.state === PairingConnectionState.PREPARING) {
      return '连接中';
    }
    return '待连接';
  }

  private connectionButtonText(): string {
    if (this.isAuthenticatedConnection()) {
      return '已认证连接';
    }
    if (this.snapshot.state !== PairingStoreState.PENDING) {
      return '先确认六位码';
    }
    if (this.connectionSnapshot.state === PairingConnectionState.FAILED) {
      return '重试配对握手';
    }
    if (this.pairingCompleted) {
      return '邀请已完成配对';
    }
    return '连接并发送握手';
  }

  private invitationConfirmButtonText(): string {
    if (this.isAuthenticatedConnection()) {
      return '已连接，无需重复配对';
    }
    if (this.snapshot.state === PairingStoreState.PENDING) {
      return '已确认，正在连接桌面端';
    }
    return '确认码一致，连接所选地址';
  }

  private canConfirmInvitation(): boolean {
    return this.snapshot.state === PairingStoreState.READY &&
      !this.isAuthenticatedConnection();
  }

  private connectionDescriptionText(): string {
    if (this.isAuthenticatedConnection()) {
      return '认证会话已建立，当前无需再次发送配对握手。';
    }
    if (this.snapshot.state !== PairingStoreState.PENDING) {
      return '首次配对请先核对六位确认码；已经配对过的设备可直接使用下方按钮恢复可信连接。';
    }
    return this.connectionSnapshot.description;
  }

  private connectionStatusColor(): ResourceColor {
    if (this.isAuthenticatedConnection()) {
      return EggClipColors.statusOnline;
    }
    if (this.connectionSnapshot.state === PairingConnectionState.FAILED) {
      return Color.Red;
    }
    if (this.connectionSnapshot.state === PairingConnectionState.IDLE) {
      return EggClipColors.textSecondary;
    }
    return EggClipColors.primary;
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
      this.pasteImportStatus = '请先核对六位确认码，并点击“确认码一致，继续配对”';
      return;
    }
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext === undefined) {
      this.pasteImportStatus = '无法连接桌面端：未获取到页面上下文';
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
        this.pasteImportStatus = '配对连接异常，请检查桌面端地址、端口和邀请是否仍有效';
      });
  }

  private startTrustedReconnect(): void {
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext === undefined) {
      this.pasteImportStatus = '无法恢复可信连接：未获取到页面上下文';
      return;
    }
    const context = hostContext as common.Context;
    pairingConnectionStore.initialize(context);
    new TrustedDeviceStore(context).loadFirstReconnectTarget()
      .then((target) => {
        if (target === null) {
          this.pasteImportStatus = '没有可重连的可信桌面端，请先完成一次配对。';
          return;
        }
        pairingConnectionStore.startTrustedReconnect(target)
          .then((snapshot) => {
            this.connectionSnapshot = snapshot;
          })
          .catch(() => {
            this.pasteImportStatus = '恢复可信连接异常，请检查桌面端地址和网络。';
          });
      })
      .catch(() => {
        this.pasteImportStatus = '无法读取可信设备记录，请重启应用后重试。';
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
        `${successStatus}；已识别桌面端地址 ${this.connectionSnapshot.endpointLabel}` : successStatus)
      : this.snapshot.statusText;
  }

  private confirmCodeAndPrepareConnection(): void {
    if (this.connectionSnapshot.state === PairingConnectionState.AUTHENTICATED) {
      this.pasteImportStatus = '当前已经建立认证连接；如需重新配对，请先停止当前连接。';
      return;
    }
    const nextSnapshot = this.pairingStore.confirmCodeMatched();
    this.snapshot = nextSnapshot;
    if (nextSnapshot.state === PairingStoreState.PENDING) {
      this.updateVisibleInvitationInput('');
      if (this.connectionSnapshot.manualPort !== '0') {
        this.pasteImportStatus = `确认码一致，正在连接 ${this.connectionSnapshot.endpointLabel}`;
        this.startPairingConnection();
      }
    }
  }

  private importInvitationFromScan(): void {
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext === undefined) {
      this.pasteImportStatus = '无法打开扫码界面：未获取到页面上下文';
      return;
    }
    this.pasteImportStatus = '正在打开系统扫码界面';
    this.pairingScanService.scanPairingInvitation(hostContext as common.Context)
      .then((scanResult) => {
        if (!scanResult.ok) {
          this.pasteImportStatus = scanResult.message;
          return;
        }
        this.importInvitationText(scanResult.invitationText, '已从二维码读取并校验邀请');
      })
      .catch(() => {
        this.pasteImportStatus = '扫码导入失败，请改用复制邀请字符串导入';
      });
  }
}
