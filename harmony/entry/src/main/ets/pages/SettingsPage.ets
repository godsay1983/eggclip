import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { AppSettings, ThemeMode, defaultAppSettings } from '../models/DomainModels';
import { PocLifecycleState } from '../models/PocModels';
import {
  PocConnectionSnapshot,
  pocConnectionStore
} from '../store/PocConnectionStore';
import {
  SettingsStore,
  SettingsStoreSnapshot,
  SettingsStoreState
} from '../store/SettingsStore';
import {
  SpaceKeyCryptoSelfTestError,
  SpaceKeyCryptoSelfTestResult
} from '../services/crypto/SpaceKeyCryptoSelfTestService';
import { EggClipColors } from '../theme/Colors';
import { EggClipSpacing } from '../theme/Spacing';
import { EggClipTypography } from '../theme/Typography';

@Component
export struct SettingsPage {
  private settingsStore: SettingsStore | null = null;
  private readonly connectionSnapshotListener = (snapshot: PocConnectionSnapshot): void => {
    this.discoveryState = snapshot.discoveryState;
    this.discoveryStatus = snapshot.discoveryStatus;
    this.discoveryCandidateCount = snapshot.discoveryCandidates.length;
    this.transportState = snapshot.transportState;
    this.transportStatus = snapshot.transportStatus;
    this.transportDiagnostics = snapshot.transportDiagnostics;
    this.connectionTitle = snapshot.connectionTitle;
    this.connectionDescription = snapshot.connectionDescription;
  };
  @State private storeState: SettingsStoreState = SettingsStoreState.IDLE;
  @State private statusText: string = '设置尚未加载';
  @State private syncEnabled: boolean = true;
  @State private autoReceiveEnabled: boolean = true;
  @State private autoWriteEnabled: boolean = false;
  @State private historyEnabled: boolean = true;
  @State private historyLimit: number = 50;
  @State private retentionDays: number = 7;
  @State private themeMode: ThemeMode = ThemeMode.SYSTEM;
  @State private historyActionStatus: string = '清空历史只影响本机历史，不会修改系统剪贴板';
  @State private discoveryState: PocLifecycleState = PocLifecycleState.IDLE;
  @State private discoveryStatus: string = '等待开始局域网发现';
  @State private discoveryCandidateCount: number = 0;
  @State private transportState: PocLifecycleState = PocLifecycleState.IDLE;
  @State private transportStatus: string = '输入桌面端 IP 和端口后手动连接';
  @State private transportDiagnostics: string = '帧诊断：接收 0 · 接受 0 · 拒绝 0';
  @State private connectionTitle: string = '等待桌面端';
  @State private connectionDescription: string = '正在等待 mDNS 候选，也可以使用手动 IP';
  @State private spaceKeyDiagnosticRunning: boolean = false;
  @State private spaceKeyDiagnosticStatus: string = '配对成功后可运行 HUKS 空间密钥与摘要自检';
  @State private spaceKeyDiagnosticDetail: string = '自检只使用固定测试文本，不读取或显示剪贴板内容。';
  @State private spaceKeyDiagnosticTone: number = 0;
  @State private spaceKeyDiagnosticUpdatedAt: string = '尚未运行';

  aboutToAppear(): void {
    if (this.settingsStore === null) {
      const hostContext = this.getUIContext().getHostContext();
      if (hostContext === undefined) {
        this.storeState = SettingsStoreState.ERROR;
        this.statusText = '无法获取页面上下文，设置不可用';
        return;
      }
      this.settingsStore = new SettingsStore(hostContext as common.UIAbilityContext);
      pocConnectionStore.initialize(hostContext as common.UIAbilityContext);
    }
    pocConnectionStore.subscribe(this.connectionSnapshotListener);
    this.loadSettings();
  }

  aboutToDisappear(): void {
    pocConnectionStore.unsubscribe(this.connectionSnapshotListener);
  }

  build() {
    Scroll() {
      Column({ space: EggClipSpacing.sectionGap }) {
        this.Header()
        this.SyncPolicyCard()
        this.HistoryPolicyCard()
        this.AppearanceCard()
        this.DiagnosticsCard()
        this.PrivacyCard()
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
      Text('设置')
        .fontSize(EggClipTypography.titleSize)
        .fontWeight(FontWeight.Bold)
        .fontColor(EggClipColors.textPrimary)
        .width('100%')

      Text(this.statusText)
        .fontSize(EggClipTypography.captionSize)
        .fontColor(this.storeState === SettingsStoreState.ERROR ? Color.Red : EggClipColors.textSecondary)
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  private SyncPolicyCard() {
    Column({ space: 12 }) {
      Text('同步策略')
        .fontSize(EggClipTypography.bodySize)
        .fontWeight(FontWeight.Bold)
        .fontColor(EggClipColors.textPrimary)
        .width('100%')

      this.SyncEnabledRow()
      this.AutoReceiveEnabledRow()
      this.AutoWriteEnabledRow()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(EggClipSpacing.cardPadding)
    .backgroundColor(EggClipColors.cardBackground)
    .borderRadius(EggClipSpacing.radiusMedium)
  }

  @Builder
  private HistoryPolicyCard() {
    Column({ space: 12 }) {
      Text('历史策略')
        .fontSize(EggClipTypography.bodySize)
        .fontWeight(FontWeight.Bold)
        .fontColor(EggClipColors.textPrimary)
        .width('100%')

      this.HistoryEnabledRow()

      Text(`历史数量：${this.historyLimit === 0 ? '不保存' : `${this.historyLimit} 条`}`)
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textSecondary)
        .width('100%')

      Row({ space: 8 }) {
        this.HistoryLimitButton(0)
        this.HistoryLimitButton(20)
        this.HistoryLimitButton(50)
        this.HistoryLimitButton(100)
      }
      .width('100%')

      Text(`最长保留：${this.retentionDays} 天`)
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textSecondary)
        .width('100%')

      Row({ space: 8 }) {
        this.RetentionButton(0)
        this.RetentionButton(7)
        this.RetentionButton(14)
        this.RetentionButton(30)
      }
      .width('100%')

      Button(this.storeState === SettingsStoreState.SAVING ? '处理中' : '清空本机历史')
        .width('100%')
        .height(40)
        .enabled(this.storeState !== SettingsStoreState.SAVING)
        .fontColor(EggClipColors.textSecondary)
        .backgroundColor(EggClipColors.controlBackground)
        .borderRadius(20)
        .onClick(() => {
          this.clearLocalHistory();
        })

      Text(this.historyActionStatus)
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textSecondary)
        .lineHeight(20)
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(EggClipSpacing.cardPadding)
    .backgroundColor(EggClipColors.cardBackground)
    .borderRadius(EggClipSpacing.radiusMedium)
  }

  @Builder
  private AppearanceCard() {
    Column({ space: 12 }) {
      Text('外观')
        .fontSize(EggClipTypography.bodySize)
        .fontWeight(FontWeight.Bold)
        .fontColor(EggClipColors.textPrimary)
        .width('100%')

      Text('主题设置保存在本机，只影响当前应用界面。')
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textSecondary)
        .lineHeight(20)
        .width('100%')

      Row({ space: 8 }) {
        this.ThemeModeButton(ThemeMode.SYSTEM, '跟随')
        this.ThemeModeButton(ThemeMode.LIGHT, '浅色')
        this.ThemeModeButton(ThemeMode.DARK, '深色')
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(EggClipSpacing.cardPadding)
    .backgroundColor(EggClipColors.cardBackground)
    .borderRadius(EggClipSpacing.radiusMedium)
  }

  @Builder
  private PrivacyCard() {
    Column({ space: 10 }) {
      Text('隐私说明')
        .fontSize(EggClipTypography.bodySize)
        .fontWeight(FontWeight.Bold)
        .fontColor(EggClipColors.textPrimary)
        .width('100%')

      Text('EggClip v1 只在局域网内同步 text/plain，不使用账号、云同步、中心服务器或公网中继。')
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textSecondary)
        .lineHeight(20)
        .width('100%')

      this.PrivacyPoint('剪贴板读取', 'HarmonyOS 端必须点击系统 PasteButton 才会读取一次剪贴板，应用不会静默读取。')
      this.PrivacyPoint('历史保留', '历史只保存在本机 RDB，可关闭、限制数量和保留天数，也可清空本机历史。')
      this.PrivacyPoint('诊断信息', '局域网诊断只显示连接状态、候选数量、错误类型和帧统计，不显示正文、摘要、邀请或密钥。')
      this.PrivacyPoint('前台同步', '移动端只在前台发现和连接；进入后台会停止发现和 WebSocket 连接。')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(EggClipSpacing.cardPadding)
    .backgroundColor(EggClipColors.cardBackground)
    .borderRadius(EggClipSpacing.radiusMedium)
  }

  @Builder
  private PrivacyPoint(label: string, value: string) {
    Row({ space: 10 }) {
      Text(label)
        .width(72)
        .fontSize(EggClipTypography.captionSize)
        .fontWeight(FontWeight.Medium)
        .fontColor(EggClipColors.textPrimary)

      Text(value)
        .layoutWeight(1)
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textSecondary)
        .lineHeight(18)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  private DiagnosticsCard() {
    Column({ space: 10 }) {
      Row() {
        Text('局域网诊断')
          .fontSize(EggClipTypography.bodySize)
          .fontWeight(FontWeight.Bold)
          .fontColor(EggClipColors.textPrimary)
          .layoutWeight(1)

        Text(this.transportState)
          .fontSize(EggClipTypography.captionSize)
          .fontColor(this.transportState === PocLifecycleState.FAILED ? Color.Red : EggClipColors.textSecondary)
      }
      .width('100%')

      Text(`${this.connectionTitle}：${this.connectionDescription}`)
        .width('100%')
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textSecondary)
        .lineHeight(20)

      this.DiagnosticsRow('mDNS', `${this.discoveryState} · ${this.discoveryStatus}`)
      this.DiagnosticsRow('候选地址', `${this.discoveryCandidateCount} 个`)
      this.DiagnosticsRow('WebSocket', `${this.transportState} · ${this.transportStatus}`)
      this.DiagnosticsRow('帧统计', this.transportDiagnostics)
      this.SpaceKeyDiagnosticResult()

      Button(this.spaceKeyDiagnosticRunning ? '自检中' : '自检空间密钥与摘要')
        .width('100%')
        .height(38)
        .enabled(!this.spaceKeyDiagnosticRunning)
        .fontColor(this.spaceKeyDiagnosticRunning ? EggClipColors.textSecondary : EggClipColors.onPrimary)
        .backgroundColor(this.spaceKeyDiagnosticRunning ? EggClipColors.controlBackground : EggClipColors.primary)
        .borderRadius(19)
        .onClick(() => {
          this.runSpaceKeySelfTest();
        })

      Text('诊断只显示连接状态、候选数量和错误类型，不显示剪贴板正文、摘要、邀请或密钥。')
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
  private SpaceKeyDiagnosticResult() {
    Column({ space: 6 }) {
      Row() {
        Text('空间密钥自检')
          .fontSize(EggClipTypography.captionSize)
          .fontWeight(FontWeight.Medium)
          .fontColor(EggClipColors.textPrimary)
          .layoutWeight(1)

        Text(this.spaceKeyDiagnosticUpdatedAt)
          .fontSize(11)
          .fontColor(EggClipColors.textSecondary)
      }
      .width('100%')

      Text(this.spaceKeyDiagnosticStatus)
        .fontSize(EggClipTypography.captionSize)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.spaceKeyDiagnosticColor())
        .width('100%')

      Text(this.spaceKeyDiagnosticDetail)
        .fontSize(11)
        .fontColor(EggClipColors.textSecondary)
        .lineHeight(18)
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({
      left: 12,
      right: 12,
      top: 10,
      bottom: 10
    })
    .backgroundColor(EggClipColors.controlBackground)
    .borderRadius(14)
  }

  @Builder
  private DiagnosticsRow(label: string, value: string) {
    Row({ space: 10 }) {
      Text(label)
        .width(78)
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textPrimary)

      Text(value)
        .layoutWeight(1)
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textSecondary)
        .lineHeight(18)
    }
    .width('100%')
  }

  @Builder
  private SyncEnabledRow() {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text('自动同步')
          .fontSize(EggClipTypography.bodySize)
          .fontColor(EggClipColors.textPrimary)
        Text(this.syncEnabled ? '已开启' : '已关闭')
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button(this.syncEnabled ? '关闭' : '开启')
        .height(34)
        .enabled(this.storeState !== SettingsStoreState.SAVING)
        .fontColor(this.syncEnabled ? EggClipColors.textSecondary : EggClipColors.onPrimary)
        .backgroundColor(this.syncEnabled ? EggClipColors.controlBackground : EggClipColors.primary)
        .borderRadius(17)
        .onClick(() => {
          this.syncEnabled = !this.syncEnabled;
          this.saveCurrentSettings();
        })
    }
    .width('100%')
  }

  @Builder
  private AutoReceiveEnabledRow() {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text('自动接收')
          .fontSize(EggClipTypography.bodySize)
          .fontColor(EggClipColors.textPrimary)
        Text(this.autoReceiveEnabled ? '已开启' : '已关闭')
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button(this.autoReceiveEnabled ? '关闭' : '开启')
        .height(34)
        .enabled(this.storeState !== SettingsStoreState.SAVING)
        .fontColor(this.autoReceiveEnabled ? EggClipColors.textSecondary : EggClipColors.onPrimary)
        .backgroundColor(this.autoReceiveEnabled ? EggClipColors.controlBackground : EggClipColors.primary)
        .borderRadius(17)
        .onClick(() => {
          this.autoReceiveEnabled = !this.autoReceiveEnabled;
          this.saveCurrentSettings();
        })
    }
    .width('100%')
  }

  @Builder
  private AutoWriteEnabledRow() {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text('自动写入剪贴板')
          .fontSize(EggClipTypography.bodySize)
          .fontColor(EggClipColors.textPrimary)
        Text(this.autoWriteEnabled ? '已开启' : '已关闭')
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button(this.autoWriteEnabled ? '关闭' : '开启')
        .height(34)
        .enabled(this.storeState !== SettingsStoreState.SAVING)
        .fontColor(this.autoWriteEnabled ? EggClipColors.textSecondary : EggClipColors.onPrimary)
        .backgroundColor(this.autoWriteEnabled ? EggClipColors.controlBackground : EggClipColors.primary)
        .borderRadius(17)
        .onClick(() => {
          this.autoWriteEnabled = !this.autoWriteEnabled;
          this.saveCurrentSettings();
        })
    }
    .width('100%')
  }

  @Builder
  private HistoryEnabledRow() {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text('保存历史')
          .fontSize(EggClipTypography.bodySize)
          .fontColor(EggClipColors.textPrimary)
        Text(this.historyEnabled ? '已开启' : '已关闭')
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button(this.historyEnabled ? '关闭' : '开启')
        .height(34)
        .enabled(this.storeState !== SettingsStoreState.SAVING)
        .fontColor(this.historyEnabled ? EggClipColors.textSecondary : EggClipColors.onPrimary)
        .backgroundColor(this.historyEnabled ? EggClipColors.controlBackground : EggClipColors.primary)
        .borderRadius(17)
        .onClick(() => {
          this.historyEnabled = !this.historyEnabled;
          this.saveCurrentSettings();
        })
    }
    .width('100%')
  }

  @Builder
  private ThemeModeButton(mode: ThemeMode, label: string) {
    Button(label)
      .layoutWeight(1)
      .height(36)
      .enabled(this.storeState !== SettingsStoreState.SAVING)
      .fontColor(this.themeMode === mode ? EggClipColors.onPrimary : EggClipColors.textSecondary)
      .backgroundColor(this.themeMode === mode ? EggClipColors.primary : EggClipColors.controlBackground)
      .borderRadius(18)
      .onClick(() => {
        this.themeMode = mode;
        this.applyThemeMode(mode);
        this.saveCurrentSettings();
      })
  }

  @Builder
  private HistoryLimitButton(limit: number) {
    Button(limit === 0 ? '0' : limit.toString())
      .layoutWeight(1)
      .height(36)
      .enabled(this.storeState !== SettingsStoreState.SAVING)
      .fontColor(this.historyLimit === limit ? EggClipColors.onPrimary : EggClipColors.textSecondary)
      .backgroundColor(this.historyLimit === limit ? EggClipColors.primary : EggClipColors.controlBackground)
      .borderRadius(18)
      .onClick(() => {
        this.historyLimit = limit;
        this.saveCurrentSettings();
      })
  }

  @Builder
  private RetentionButton(days: number) {
    Button(days === 0 ? '0' : days.toString())
      .layoutWeight(1)
      .height(36)
      .enabled(this.storeState !== SettingsStoreState.SAVING)
      .fontColor(this.retentionDays === days ? EggClipColors.onPrimary : EggClipColors.textSecondary)
      .backgroundColor(this.retentionDays === days ? EggClipColors.primary : EggClipColors.controlBackground)
      .borderRadius(18)
      .onClick(() => {
        this.retentionDays = days;
        this.saveCurrentSettings();
      })
  }

  private loadSettings(): void {
    if (this.settingsStore === null) {
      return;
    }
    this.storeState = SettingsStoreState.LOADING;
    this.statusText = '正在读取本机设置';
    this.settingsStore.load()
      .then((snapshot: SettingsStoreSnapshot) => {
        this.applySnapshot(snapshot);
        this.statusText = snapshot.state === SettingsStoreState.ERROR ? snapshot.errorMessage : '设置已从本机 RDB 读取';
      })
      .catch(() => {
        this.storeState = SettingsStoreState.ERROR;
        this.statusText = '读取设置失败';
      });
  }

  private saveCurrentSettings(): void {
    if (this.settingsStore === null) {
      this.statusText = '设置服务未初始化';
      return;
    }
    const settings: AppSettings = {
      syncEnabled: this.syncEnabled,
      autoReceiveEnabled: this.autoReceiveEnabled,
      autoWriteEnabled: this.autoWriteEnabled,
      historyEnabled: this.historyEnabled,
      historyLimit: this.historyLimit,
      retentionDays: this.retentionDays,
      themeMode: this.themeMode
    };
    this.storeState = SettingsStoreState.SAVING;
    this.statusText = '正在保存设置';
    this.settingsStore.save(settings)
      .then((snapshot: SettingsStoreSnapshot) => {
        this.applySnapshot(snapshot);
        this.statusText = snapshot.state === SettingsStoreState.ERROR ? snapshot.errorMessage : '设置已保存到本机';
      })
      .catch(() => {
        this.storeState = SettingsStoreState.ERROR;
        this.statusText = '保存设置失败';
      });
  }

  private clearLocalHistory(): void {
    if (this.settingsStore === null) {
      this.historyActionStatus = '设置服务未初始化，无法清空历史';
      return;
    }
    this.storeState = SettingsStoreState.SAVING;
    this.historyActionStatus = '正在清空本机历史';
    this.settingsStore.clearLocalHistory()
      .then((snapshot: SettingsStoreSnapshot) => {
        this.applySnapshot(snapshot);
        this.historyActionStatus = snapshot.state === SettingsStoreState.ERROR
          ? snapshot.errorMessage
          : '已清空本机历史；系统剪贴板不受影响';
        this.statusText = snapshot.state === SettingsStoreState.ERROR
          ? snapshot.errorMessage
          : '本机历史已清空';
      })
      .catch(() => {
        this.storeState = SettingsStoreState.ERROR;
        this.historyActionStatus = '清空历史失败';
        this.statusText = '清空历史失败';
      });
  }

  private runSpaceKeySelfTest(): void {
    if (this.settingsStore === null) {
      this.spaceKeyDiagnosticStatus = '设置服务未初始化，无法运行自检';
      this.spaceKeyDiagnosticDetail = '请重新打开设置页后再试。';
      this.spaceKeyDiagnosticTone = 3;
      this.spaceKeyDiagnosticUpdatedAt = this.formatDiagnosticTime(new Date());
      return;
    }
    this.spaceKeyDiagnosticRunning = true;
    this.spaceKeyDiagnosticTone = 1;
    this.spaceKeyDiagnosticStatus = '正在自检';
      this.spaceKeyDiagnosticDetail = '正在使用已保存的空间密钥引用进行固定文本加解密和 HMAC 摘要校验。';
    this.spaceKeyDiagnosticUpdatedAt = this.formatDiagnosticTime(new Date());
    this.settingsStore.runSpaceKeyCryptoSelfTest()
      .then((result: SpaceKeyCryptoSelfTestResult) => {
        this.spaceKeyDiagnosticStatus = this.describeSpaceKeySelfTest(result);
        this.spaceKeyDiagnosticDetail = this.describeSpaceKeySelfTestDetail(result);
        this.spaceKeyDiagnosticTone = result.ok ? 2 : 3;
        this.spaceKeyDiagnosticUpdatedAt = this.formatDiagnosticTime(new Date());
        this.spaceKeyDiagnosticRunning = false;
      })
      .catch(() => {
        this.spaceKeyDiagnosticStatus = '空间密钥自检异常';
        this.spaceKeyDiagnosticDetail = '自检流程出现未分类异常，未读取或展示任何密钥材料。';
        this.spaceKeyDiagnosticTone = 3;
        this.spaceKeyDiagnosticUpdatedAt = this.formatDiagnosticTime(new Date());
        this.spaceKeyDiagnosticRunning = false;
      });
  }

  private describeSpaceKeySelfTest(result: SpaceKeyCryptoSelfTestResult): string {
    if (result.ok) {
      return 'HUKS 空间密钥加解密与摘要自检通过';
    }
    if (result.error === SpaceKeyCryptoSelfTestError.NO_SPACE_KEY) {
      return '未找到已配对的同步空间密钥引用';
    }
    if (result.error === SpaceKeyCryptoSelfTestError.ENCRYPT_FAILED) {
      return 'HUKS 空间密钥加密自检失败';
    }
    if (result.error === SpaceKeyCryptoSelfTestError.DECRYPT_FAILED) {
      return 'HUKS 空间密钥解密自检失败';
    }
    if (result.error === SpaceKeyCryptoSelfTestError.PLAINTEXT_MISMATCH) {
      return 'HUKS 空间密钥自检结果不一致';
    }
    if (result.error === SpaceKeyCryptoSelfTestError.HMAC_FAILED) {
      return 'HUKS 空间密钥摘要自检失败';
    }
    if (result.error === SpaceKeyCryptoSelfTestError.STORE_FAILED) {
      return '读取同步空间密钥引用失败';
    }
    return '空间密钥自检失败';
  }

  private describeSpaceKeySelfTestDetail(result: SpaceKeyCryptoSelfTestResult): string {
    if (result.ok) {
      return '已完成固定文本加密、解密、一致性和 HMAC 摘要校验；未展示明文、密文、tag、摘要或密钥引用。';
    }
    if (result.error === SpaceKeyCryptoSelfTestError.NO_SPACE_KEY) {
      return '请先完成一次桌面端配对，让本机保存同步空间密钥引用。';
    }
    if (result.error === SpaceKeyCryptoSelfTestError.ENCRYPT_FAILED) {
      return `失败阶段：${result.field ?? 'encryptBase64Url'}。`;
    }
    if (result.error === SpaceKeyCryptoSelfTestError.DECRYPT_FAILED) {
      return `失败阶段：${result.field ?? 'decryptBase64Url'}。`;
    }
    if (result.error === SpaceKeyCryptoSelfTestError.PLAINTEXT_MISMATCH) {
      return '加解密往返完成，但解密结果与固定测试文本不一致。';
    }
    if (result.error === SpaceKeyCryptoSelfTestError.HMAC_FAILED) {
      return `摘要失败阶段：${result.field ?? 'hmacSha256Base64Url'}。请重新配对后重试。`;
    }
    if (result.error === SpaceKeyCryptoSelfTestError.STORE_FAILED) {
      return '读取本机同步空间记录失败，请检查数据库状态或重新配对。';
    }
    return '自检失败，未读取或展示任何密钥材料。';
  }

  private spaceKeyDiagnosticColor(): ResourceColor {
    if (this.spaceKeyDiagnosticTone === 1) {
      return EggClipColors.primary;
    }
    if (this.spaceKeyDiagnosticTone === 2) {
      return EggClipColors.statusOnline;
    }
    if (this.spaceKeyDiagnosticTone === 3) {
      return Color.Red;
    }
    return EggClipColors.textSecondary;
  }

  private formatDiagnosticTime(date: Date): string {
    return `${this.pad2(date.getHours())}:${this.pad2(date.getMinutes())}:${this.pad2(date.getSeconds())}`;
  }

  private pad2(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }

  private applySnapshot(snapshot: SettingsStoreSnapshot): void {
    const settings = snapshot.settings ?? defaultAppSettings();
    this.storeState = snapshot.state;
    this.syncEnabled = settings.syncEnabled;
    this.autoReceiveEnabled = settings.autoReceiveEnabled;
    this.autoWriteEnabled = settings.autoWriteEnabled;
    this.historyEnabled = settings.historyEnabled;
    this.historyLimit = settings.historyLimit;
    this.retentionDays = settings.retentionDays;
    this.themeMode = settings.themeMode;
    this.applyThemeMode(settings.themeMode);
  }

  private applyThemeMode(mode: ThemeMode): void {
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext === undefined) {
      return;
    }
    const abilityContext = hostContext as common.UIAbilityContext;
    if (mode === ThemeMode.DARK) {
      abilityContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
      return;
    }
    if (mode === ThemeMode.LIGHT) {
      abilityContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
      return;
    }
    abilityContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
  }
}
