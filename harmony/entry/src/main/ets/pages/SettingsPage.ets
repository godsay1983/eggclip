import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { AppSettings, ThemeMode, defaultAppSettings } from '../models/DomainModels';
import {
  SettingsStore,
  SettingsStoreSnapshot,
  SettingsStoreState
} from '../store/SettingsStore';
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
        this.SyncPolicyCard()
        this.HistoryPolicyCard()
        this.AppearanceCard()
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
    Column({ space: 8 }) {
      Text('隐私说明')
        .fontSize(EggClipTypography.bodySize)
        .fontWeight(FontWeight.Bold)
        .fontColor(EggClipColors.textPrimary)
        .width('100%')

      Text('设置只保存在本机 RDB。EggClip v1 不使用账号、云同步或公网中继。HarmonyOS 端读取剪贴板必须由 PasteButton 触发。')
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
  private SyncEnabledRow() {
    this.BooleanSettingRow('自动同步', this.syncEnabled, () => {
      this.syncEnabled = !this.syncEnabled;
      this.saveCurrentSettings();
    })
  }

  @Builder
  private AutoReceiveEnabledRow() {
    this.BooleanSettingRow('自动接收', this.autoReceiveEnabled, () => {
      this.autoReceiveEnabled = !this.autoReceiveEnabled;
      this.saveCurrentSettings();
    })
  }

  @Builder
  private AutoWriteEnabledRow() {
    this.BooleanSettingRow('自动写入剪贴板', this.autoWriteEnabled, () => {
      this.autoWriteEnabled = !this.autoWriteEnabled;
      this.saveCurrentSettings();
    })
  }

  @Builder
  private HistoryEnabledRow() {
    this.BooleanSettingRow('保存历史', this.historyEnabled, () => {
      this.historyEnabled = !this.historyEnabled;
      this.saveCurrentSettings();
    })
  }

  @Builder
  private BooleanSettingRow(label: string, enabled: boolean, action: () => void) {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text(label)
          .fontSize(EggClipTypography.bodySize)
          .fontColor(EggClipColors.textPrimary)
        Text(enabled ? '已开启' : '已关闭')
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button(enabled ? '关闭' : '开启')
        .height(34)
        .enabled(this.storeState !== SettingsStoreState.SAVING)
        .fontColor(enabled ? EggClipColors.textSecondary : EggClipColors.onPrimary)
        .backgroundColor(enabled ? EggClipColors.controlBackground : EggClipColors.primary)
        .borderRadius(17)
        .onClick(action)
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
