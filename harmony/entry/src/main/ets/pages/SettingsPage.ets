import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { AppSettings, ThemeMode, defaultAppSettings } from '../models/DomainModels';
import {
  SettingsStore,
  SettingsStoreSnapshot,
  SettingsStoreState
} from '../store/SettingsStore';
import { pairingConnectionStore } from '../store/PairingConnectionStore';
import {
  SpaceKeyCryptoSelfTestError,
  SpaceKeyCryptoSelfTestResult
} from '../services/crypto/SpaceKeyCryptoSelfTestService';
import {
  SpaceKeyRecoveryError,
  SpaceKeyRecoveryResult
} from '../services/crypto/SpaceKeyRecoveryService';
import { EggClipColors } from '../theme/Colors';
import { EggClipSpacing } from '../theme/Spacing';
import { EggClipTypography } from '../theme/Typography';

@Component
export struct SettingsPage {
  private settingsStore: SettingsStore | null = null;
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
  @State private spaceKeyDiagnosticRunning: boolean = false;
  @State private spaceKeyDiagnosticStatus: string = '配对成功后可运行 HUKS 空间密钥与摘要自检';
  @State private spaceKeyDiagnosticDetail: string = '自检只使用固定测试文本，不读取或显示剪贴板内容。';
  @State private spaceKeyDiagnosticTone: number = 0;
  @State private spaceKeyDiagnosticUpdatedAt: string = '尚未运行';
  @State private spaceKeyRecoveryRunning: boolean = false;

  aboutToAppear(): void {
    if (this.settingsStore === null) {
      const hostContext = this.getUIContext().getHostContext();
      if (hostContext === undefined) {
        this.storeState = SettingsStoreState.ERROR;
        this.statusText = '无法获取页面上下文，设置不可用';
        return;
      }
      this.settingsStore = new SettingsStore(hostContext as common.UIAbilityContext);
    }
    this.loadSettings();
  }

  build() {
    Scroll() {
      Column({ space: EggClipSpacing.sectionGap }) {
        this.Header()
        GridRow({
          columns: { sm: 12, md: 12, lg: 12 },
          gutter: { x: EggClipSpacing.sectionGap, y: EggClipSpacing.sectionGap }
        }) {
          GridCol({ span: { sm: 12, md: 6, lg: 6 } }) {
            Column({ space: EggClipSpacing.sectionGap }) {
              this.SyncPolicyCard()
              this.HistoryPolicyCard()
            }
            .width('100%')
          }

          GridCol({ span: { sm: 12, md: 6, lg: 6 } }) {
            Column({ space: EggClipSpacing.sectionGap }) {
              this.AppearanceCard()
              this.PrivacyCard()
              this.SecurityRecoveryCard()
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
  private Header() {
    Column({ space: 6 }) {
      Text('设置')
        .fontSize(EggClipTypography.titleSize)
        .fontWeight(FontWeight.Bold)
        .fontColor(EggClipColors.textPrimary)
        .width('100%')

      if (this.storeState === SettingsStoreState.ERROR) {
        Text(this.statusText)
          .fontSize(EggClipTypography.captionSize)
          .fontColor(Color.Red)
          .width('100%')
      }
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
        this.HistoryLimitButton(20)
        this.HistoryLimitButton(50)
        this.HistoryLimitButton(100)
      }
      .width('100%')

      Text(`最长保留：${this.retentionDays === 0 ? '不限' : `${this.retentionDays} 天`}`)
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

      Text('仅在局域网同步纯文本，不使用账号或云端。')
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textSecondary)
        .lineHeight(20)
        .width('100%')

      this.PrivacyPoint('剪贴板', '只有点击系统“粘贴”后才读取一次，收到的文本由你手动复制。')
      this.PrivacyPoint('本机数据', '历史和设置保存在本机，可随时关闭或清空。')
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
  private SecurityRecoveryCard() {
    Column({ space: 10 }) {
      Text('安全与恢复')
        .fontSize(EggClipTypography.bodySize)
        .fontWeight(FontWeight.Bold)
        .fontColor(EggClipColors.textPrimary)
        .width('100%')

      this.SpaceKeyDiagnosticResult()

      Button(this.spaceKeyDiagnosticRunning ? '自检中' : '自检空间密钥与摘要')
        .width('100%')
        .height(40)
        .enabled(!this.spaceKeyDiagnosticRunning)
        .fontColor(this.spaceKeyDiagnosticRunning ? EggClipColors.textSecondary : EggClipColors.onPrimary)
        .backgroundColor(this.spaceKeyDiagnosticRunning ? EggClipColors.controlBackground : EggClipColors.primary)
        .borderRadius(19)
        .onClick(() => {
          this.runSpaceKeySelfTest();
        })

      Button(this.spaceKeyRecoveryRunning ? '正在重新初始化' : '重新初始化配对安全状态')
        .width('100%')
        .height(40)
        .enabled(!this.spaceKeyDiagnosticRunning && !this.spaceKeyRecoveryRunning)
        .fontColor(Color.Red)
        .backgroundColor(EggClipColors.controlBackground)
        .borderRadius(19)
        .onClick(() => {
          this.confirmSpaceKeyRecovery();
        })

      Text('仅在密钥异常时使用。重新初始化会清除本机配对、同步空间和历史，之后需要重新配对。')
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
  private SyncEnabledRow() {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text('自动同步')
          .fontSize(EggClipTypography.bodySize)
          .fontColor(EggClipColors.textPrimary)
        Text('控制前台连接和同步')
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button(this.syncEnabled ? '已开启' : '已关闭')
        .height(40)
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
        Text('接收桌面端实时文本')
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button(this.autoReceiveEnabled ? '已开启' : '已关闭')
        .height(40)
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
  private HistoryEnabledRow() {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text('保存历史')
          .fontSize(EggClipTypography.bodySize)
          .fontColor(EggClipColors.textPrimary)
        Text('在本机保留最近记录')
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button(this.historyEnabled ? '已开启' : '已关闭')
        .height(40)
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
      .height(40)
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
      .height(40)
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
    Button(days === 0 ? '不限' : days.toString())
      .layoutWeight(1)
      .height(40)
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

  private confirmSpaceKeyRecovery(): void {
    this.getUIContext().showAlertDialog({
      title: '重新初始化配对安全状态？',
      message: '这会断开当前连接，删除本机同步空间密钥、可信设备和剪贴板历史。应用设置与本机长期身份会保留；完成后需要重新扫码或粘贴邀请配对。',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '确认重新初始化',
        fontColor: Color.Red,
        action: () => {
          this.reinitializePairingSecurityState();
        }
      }
    });
  }

  private reinitializePairingSecurityState(): void {
    if (this.settingsStore === null || this.spaceKeyRecoveryRunning) {
      return;
    }
    this.spaceKeyRecoveryRunning = true;
    this.spaceKeyDiagnosticTone = 1;
    this.spaceKeyDiagnosticStatus = '正在重新初始化配对安全状态';
    this.spaceKeyDiagnosticDetail = '正在删除本机 HUKS 空间密钥并清理配对记录。';
    this.spaceKeyDiagnosticUpdatedAt = this.formatDiagnosticTime(new Date());
    pairingConnectionStore.close();
    this.settingsStore.reinitializePairingSecurityState()
      .then((result: SpaceKeyRecoveryResult) => {
        this.spaceKeyRecoveryRunning = false;
        this.spaceKeyDiagnosticUpdatedAt = this.formatDiagnosticTime(new Date());
        if (result.ok) {
          this.spaceKeyDiagnosticTone = 2;
          this.spaceKeyDiagnosticStatus = '配对安全状态已重新初始化';
          const invalidHint = result.invalidKeyRefs > 0 ? `；忽略 ${result.invalidKeyRefs} 条已损坏且无法定位 HUKS 别名的引用` : '';
          this.spaceKeyDiagnosticDetail = `已清理 ${result.clearedKeyRefs} 组 HUKS 空间密钥和本机配对数据${invalidHint}，请重新配对。`;
          return;
        }
        this.spaceKeyDiagnosticTone = 3;
        this.spaceKeyDiagnosticStatus = '重新初始化失败';
        this.spaceKeyDiagnosticDetail = this.describeSpaceKeyRecoveryFailure(result);
      })
      .catch(() => {
        this.spaceKeyRecoveryRunning = false;
        this.spaceKeyDiagnosticTone = 3;
        this.spaceKeyDiagnosticStatus = '重新初始化失败';
        this.spaceKeyDiagnosticDetail = '恢复流程发生异常；未生成或展示任何密钥材料，请重启应用后重试。';
        this.spaceKeyDiagnosticUpdatedAt = this.formatDiagnosticTime(new Date());
      });
  }

  private describeSpaceKeyRecoveryFailure(result: SpaceKeyRecoveryResult): string {
    if (result.error === SpaceKeyRecoveryError.STORE_READ_FAILED) {
      return '无法读取同步空间密钥引用，数据库尚未修改。';
    }
    if (result.error === SpaceKeyRecoveryError.HUKS_DELETE_FAILED) {
      return `HUKS 密钥清理失败（阶段：${result.field ?? 'deleteSpaceKey'}），配对数据库尚未清除，可重启后重试。`;
    }
    if (result.error === SpaceKeyRecoveryError.STORE_RESET_FAILED) {
      return 'HUKS 空间密钥已清理，但配对数据库重置失败；请重启应用后再次执行重新初始化。';
    }
    return '重新初始化未完成，请重启应用后重试。';
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
      if (result.hmacConfirmationCode !== undefined) {
        return `已完成加解密与 HMAC 校验。跨端确认码：${result.hmacConfirmationCode}；与桌面端一致即表示空间密钥 HMAC 互通。`;
      }
      return '已完成固定文本加密、解密和一致性校验；未展示密钥或完整摘要。';
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
