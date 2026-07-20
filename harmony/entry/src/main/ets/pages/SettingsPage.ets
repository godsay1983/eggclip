import { common, ConfigurationConstant, Want } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppSettings, ThemeMode, defaultAppSettings } from '../models/DomainModels';
import {
  SettingsStore,
  SettingsStoreSnapshot,
  SettingsStoreState
} from '../store/SettingsStore';
import { settingsChangeStore } from '../store/SettingsChangeStore';
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
import { UiMessageDescriptor } from '../services/localization/UiMessageCodes';
import { UiMessageFormatter } from '../services/localization/UiMessageFormatter';
import {
  LanguageMode,
  LanguagePreferenceService,
  createPersistentLanguagePreferenceService
} from '../services/localization/LanguagePreferenceService';
import { LocalizedFormatter } from '../services/localization/LocalizedFormatter';

@Component
export struct SettingsPage {
  private settingsStore: SettingsStore | null = null;
  private messageFormatter: UiMessageFormatter | null = null;
  private languagePreferenceService: LanguagePreferenceService | null = null;
  private readonly localizedFormatter: LocalizedFormatter = new LocalizedFormatter();
  @State private storeState: SettingsStoreState = SettingsStoreState.IDLE;
  @State private statusText: string = '';
  @State private syncEnabled: boolean = true;
  @State private autoReceiveEnabled: boolean = true;
  @State private autoWriteEnabled: boolean = false;
  @State private historyEnabled: boolean = true;
  @State private historyLimit: number = 50;
  @State private retentionDays: number = 7;
  @State private themeMode: ThemeMode = ThemeMode.SYSTEM;
  @State private languageMode: LanguageMode = LanguageMode.SYSTEM;
  @State private languageRestarting: boolean = false;
  @State private languageReopenHintVisible: boolean = false;
  @State private historyActionStatus: string = '';
  @State private spaceKeyDiagnosticRunning: boolean = false;
  @State private spaceKeyDiagnosticStatus: string = '';
  @State private spaceKeyDiagnosticDetail: string = '';
  @State private spaceKeyDiagnosticTone: number = 0;
  @State private spaceKeyDiagnosticUpdatedAt: string = '';
  @State private spaceKeyRecoveryRunning: boolean = false;

  aboutToAppear(): void {
    if (this.settingsStore === null) {
      const hostContext = this.getUIContext().getHostContext();
      if (hostContext === undefined) {
        this.storeState = SettingsStoreState.ERROR;
        this.statusText = this.resourceText('settings_context_failed');
        return;
      }
      const context = hostContext as common.UIAbilityContext;
      this.messageFormatter = new UiMessageFormatter(context);
      this.settingsStore = new SettingsStore(context);
      this.languagePreferenceService = createPersistentLanguagePreferenceService(context);
      this.languageMode = this.languagePreferenceService.loadMode();
      this.statusText = this.resourceText('settings_not_loaded');
      this.historyActionStatus = this.resourceText('settings_history_clear_notice');
      this.spaceKeyDiagnosticStatus = this.resourceText('settings_self_test_intro');
      this.spaceKeyDiagnosticDetail = this.resourceText('settings_self_test_privacy');
      this.spaceKeyDiagnosticUpdatedAt = this.resourceText('settings_not_run');
    }
    this.loadSettings();
  }

  build() {
    Scroll() {
      Column({ space: EggClipSpacing.sectionGap }) {
        this.Header()
        this.AppearanceCard()
        this.LanguageCard()
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
        bottom: EggClipSpacing.floatingNavigationContentInset
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(EggClipColors.pageBackground)
  }

  @Builder
  private Header() {
    Column({ space: 6 }) {
      Text(this.resourceText('settings_title'))
        .fontSize(EggClipTypography.titleSize)
        .fontWeight(FontWeight.Bold)
        .fontColor(EggClipColors.textPrimary)
        .width('100%')

      if (this.storeState === SettingsStoreState.ERROR) {
        Text(this.statusText)
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.statusError)
          .width('100%')
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  private SyncPolicyCard() {
    Column({ space: 12 }) {
      Text(this.resourceText('settings_sync_policy'))
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
      Text(this.resourceText('settings_history_policy'))
        .fontSize(EggClipTypography.bodySize)
        .fontWeight(FontWeight.Bold)
        .fontColor(EggClipColors.textPrimary)
        .width('100%')

      this.HistoryEnabledRow()

      Text(this.resourceText('settings_history_limit', this.historyLimit === 0 ?
        this.resourceText('common_not_saved') : this.pluralText('settings_history_items_plural', this.historyLimit)))
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textSecondary)
        .width('100%')

      Row({ space: 8 }) {
        this.HistoryLimitButton(20)
        this.HistoryLimitButton(50)
        this.HistoryLimitButton(100)
      }
      .width('100%')

      Text(this.resourceText('settings_retention', this.retentionDays === 0 ?
        this.resourceText('common_unlimited') : this.pluralText('settings_retention_days_plural', this.retentionDays)))
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

      Button(this.storeState === SettingsStoreState.SAVING ?
        this.resourceText('common_processing') : this.resourceText('settings_clear_history'))
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
      Text(this.resourceText('settings_appearance'))
        .fontSize(EggClipTypography.bodySize)
        .fontWeight(FontWeight.Bold)
        .fontColor(EggClipColors.textPrimary)
        .width('100%')

      Row({ space: 8 }) {
        this.ThemeModeButton(ThemeMode.SYSTEM, this.resourceText('settings_theme_system'))
        this.ThemeModeButton(ThemeMode.LIGHT, this.resourceText('settings_theme_light'))
        this.ThemeModeButton(ThemeMode.DARK, this.resourceText('settings_theme_dark'))
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
  private LanguageCard() {
    Column({ space: 12 }) {
      Text(this.resourceText('settings_language'))
        .fontSize(EggClipTypography.bodySize)
        .fontWeight(FontWeight.Bold)
        .fontColor(EggClipColors.textPrimary)
        .width('100%')

      Row({ space: 8 }) {
        this.LanguageModeButton(LanguageMode.SYSTEM, this.resourceText('language_system'))
        this.LanguageModeButton(LanguageMode.ZH_CN, this.resourceText('language_zh_cn'))
        this.LanguageModeButton(LanguageMode.EN_US, this.resourceText('language_en_us'))
      }
      .width('100%')

      if (this.languageReopenHintVisible) {
        Text(this.languageRestarting ?
          this.resourceText('settings_language_restarting') :
          this.resourceText('settings_language_reopen_hint'))
          .fontSize(11)
          .fontColor(EggClipColors.textSecondary)
          .lineHeight(18)
          .width('100%')
      }
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
      Text(this.resourceText('settings_privacy_title'))
        .fontSize(EggClipTypography.bodySize)
        .fontWeight(FontWeight.Bold)
        .fontColor(EggClipColors.textPrimary)
        .width('100%')

      Text(this.resourceText('settings_privacy_intro'))
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textSecondary)
        .lineHeight(20)
        .width('100%')

      this.PrivacyPoint(this.resourceText('settings_privacy_clipboard_title'),
        this.resourceText('settings_privacy_clipboard_desc'))
      this.PrivacyPoint(this.resourceText('settings_privacy_local_title'),
        this.resourceText('settings_privacy_local_desc'))
      this.PrivacyPoint(this.resourceText('settings_privacy_lan_title'),
        this.resourceText('settings_privacy_lan_desc'))
      this.PrivacyPoint(this.resourceText('settings_privacy_keys_title'),
        this.resourceText('settings_privacy_keys_desc'))
      this.PrivacyPoint(this.resourceText('settings_privacy_control_title'),
        this.resourceText('settings_privacy_control_desc'))

      Text(this.resourceText('settings_privacy_full'))
        .fontSize(11)
        .fontColor(EggClipColors.textSecondary)
        .lineHeight(18)
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(EggClipSpacing.cardPadding)
    .backgroundColor(EggClipColors.cardBackground)
    .borderRadius(EggClipSpacing.radiusMedium)
  }

  @Builder
  private PrivacyPoint(label: ResourceStr, value: ResourceStr) {
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
      Text(this.resourceText('settings_security_recovery'))
        .fontSize(EggClipTypography.bodySize)
        .fontWeight(FontWeight.Bold)
        .fontColor(EggClipColors.textPrimary)
        .width('100%')

      this.SpaceKeyDiagnosticResult()

      Button(this.spaceKeyDiagnosticRunning ?
        this.resourceText('settings_self_testing') : this.resourceText('settings_self_test'))
        .width('100%')
        .height(40)
        .enabled(!this.spaceKeyDiagnosticRunning)
        .fontColor(this.spaceKeyDiagnosticRunning ? EggClipColors.textSecondary : EggClipColors.onPrimary)
        .backgroundColor(this.spaceKeyDiagnosticRunning ? EggClipColors.controlBackground : EggClipColors.primary)
        .borderRadius(19)
        .onClick(() => {
          this.runSpaceKeySelfTest();
        })

      Button(this.spaceKeyRecoveryRunning ?
        this.resourceText('settings_reinitializing') : this.resourceText('settings_reinitialize'))
        .width('100%')
        .height(40)
        .enabled(!this.spaceKeyDiagnosticRunning && !this.spaceKeyRecoveryRunning)
        .fontColor(EggClipColors.statusError)
        .backgroundColor(EggClipColors.controlBackground)
        .borderRadius(19)
        .onClick(() => {
          this.confirmSpaceKeyRecovery();
        })

      Text(this.resourceText('settings_reinitialize_notice'))
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
        Text(this.resourceText('settings_space_key_test'))
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
        Text(this.resourceText('settings_auto_sync'))
          .fontSize(EggClipTypography.bodySize)
          .fontColor(EggClipColors.textPrimary)
        Text(this.resourceText('settings_auto_sync_desc'))
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button(this.syncEnabled ? this.resourceText('common_enabled') : this.resourceText('common_disabled'))
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
        Text(this.resourceText('settings_auto_receive'))
          .fontSize(EggClipTypography.bodySize)
          .fontColor(EggClipColors.textPrimary)
        Text(this.resourceText('settings_auto_receive_desc'))
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button(this.autoReceiveEnabled ? this.resourceText('common_enabled') : this.resourceText('common_disabled'))
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
        Text(this.resourceText('settings_save_history'))
          .fontSize(EggClipTypography.bodySize)
          .fontColor(EggClipColors.textPrimary)
        Text(this.resourceText('settings_save_history_desc'))
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button(this.historyEnabled ? this.resourceText('common_enabled') : this.resourceText('common_disabled'))
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
  private ThemeModeButton(mode: ThemeMode, label: ResourceStr) {
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
  private LanguageModeButton(mode: LanguageMode, label: ResourceStr) {
    Button(label)
      .layoutWeight(1)
      .height(40)
      .enabled(!this.languageRestarting)
      .fontSize(12)
      .fontColor(this.languageMode === mode ? EggClipColors.onPrimary : EggClipColors.textSecondary)
      .backgroundColor(this.languageMode === mode ? EggClipColors.primary : EggClipColors.controlBackground)
      .borderRadius(18)
      .onClick(() => {
        this.saveLanguageMode(mode);
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
    Button(days === 0 ? this.resourceText('common_unlimited') : days.toString())
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

  private async saveLanguageMode(mode: LanguageMode): Promise<void> {
    if (this.languagePreferenceService === null || this.languageRestarting) {
      return;
    }
    try {
      await this.languagePreferenceService.saveMode(mode);
      if (this.languagePreferenceService.loadMode() !== mode) {
        throw new Error('language preference verification failed');
      }
      this.languageMode = mode;
      this.languageReopenHintVisible = false;
    } catch (_) {
      this.statusText = this.resourceText('settings_language_save_failed');
      this.storeState = SettingsStoreState.ERROR;
      return;
    }

    const restartNow = await this.confirmLanguageRestart();
    if (!restartNow) {
      this.languageReopenHintVisible = true;
      return;
    }
    this.languageRestarting = true;
    this.languageReopenHintVisible = true;
    this.restartForLanguageChange();
  }

  private async confirmLanguageRestart(): Promise<boolean> {
    try {
      const selectedIndex = await new Promise<number>((resolve, reject) => {
        promptAction.showDialog({
          title: this.resourceText('settings_language_restart_title'),
          message: this.resourceText('settings_language_restart_message'),
          buttons: [
            {
              text: this.resourceText('settings_language_restart_now'),
              color: $r('app.color.eggclip_text_primary')
            },
            {
              text: this.resourceText('settings_language_restart_later'),
              color: $r('app.color.eggclip_text_secondary')
            }
          ]
        }, (error: BusinessError, result: promptAction.ShowDialogSuccessResponse): void => {
          if (error) {
            reject(error);
            return;
          }
          resolve(result.index);
        });
      });
      return selectedIndex === 0;
    } catch (_) {
      return false;
    }
  }

  private restartForLanguageChange(): void {
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext === undefined) {
      this.languageRestarting = false;
      return;
    }
    const abilityContext = hostContext as common.UIAbilityContext;
    const want: Want = {
      bundleName: 'com.eggclip.app',
      abilityName: 'EntryAbility'
    };
    try {
      abilityContext.restartApp(want)
        .catch(() => {
          this.languageRestarting = false;
        });
    } catch (_) {
      this.languageRestarting = false;
    }
  }

  private loadSettings(): void {
    if (this.settingsStore === null) {
      return;
    }
    this.storeState = SettingsStoreState.LOADING;
    this.statusText = this.resourceText('settings_loading');
    this.settingsStore.load()
      .then((snapshot: SettingsStoreSnapshot) => {
        this.applySnapshot(snapshot);
        this.statusText = snapshot.state === SettingsStoreState.ERROR && snapshot.errorMessage !== null ?
          this.formatMessage(snapshot.errorMessage) : this.resourceText('settings_loaded');
      })
      .catch(() => {
        this.storeState = SettingsStoreState.ERROR;
        this.statusText = this.resourceText('settings_load_failed');
      });
  }

  private saveCurrentSettings(): void {
    if (this.settingsStore === null) {
      this.statusText = this.resourceText('settings_service_unavailable');
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
    this.statusText = this.resourceText('settings_saving');
    this.settingsStore.save(settings)
      .then((snapshot: SettingsStoreSnapshot) => {
        this.applySnapshot(snapshot);
        if (snapshot.state === SettingsStoreState.READY) {
          settingsChangeStore.publish();
        }
        this.statusText = snapshot.state === SettingsStoreState.ERROR && snapshot.errorMessage !== null ?
          this.formatMessage(snapshot.errorMessage) : this.resourceText('settings_saved');
      })
      .catch(() => {
        this.storeState = SettingsStoreState.ERROR;
        this.statusText = this.resourceText('settings_save_failed_status');
      });
  }

  private clearLocalHistory(): void {
    if (this.settingsStore === null) {
      this.historyActionStatus = this.resourceText('settings_clear_service_unavailable');
      return;
    }
    this.storeState = SettingsStoreState.SAVING;
    this.historyActionStatus = this.resourceText('settings_history_clearing');
    this.settingsStore.clearLocalHistory()
      .then((snapshot: SettingsStoreSnapshot) => {
        this.applySnapshot(snapshot);
        if (snapshot.state === SettingsStoreState.READY) {
          settingsChangeStore.publish();
        }
        this.historyActionStatus = snapshot.state === SettingsStoreState.ERROR && snapshot.errorMessage !== null
          ? this.formatMessage(snapshot.errorMessage)
          : this.resourceText('settings_history_cleared');
        this.statusText = snapshot.state === SettingsStoreState.ERROR && snapshot.errorMessage !== null
          ? this.formatMessage(snapshot.errorMessage)
          : this.resourceText('settings_history_cleared_short');
      })
      .catch(() => {
        this.storeState = SettingsStoreState.ERROR;
        this.historyActionStatus = this.resourceText('settings_history_clear_failed_status');
        this.statusText = this.resourceText('settings_history_clear_failed_status');
      });
  }

  private runSpaceKeySelfTest(): void {
    if (this.settingsStore === null) {
      this.spaceKeyDiagnosticStatus = this.resourceText('settings_self_test_unavailable');
      this.spaceKeyDiagnosticDetail = this.resourceText('settings_reopen_retry');
      this.spaceKeyDiagnosticTone = 3;
      this.spaceKeyDiagnosticUpdatedAt = this.localizedFormatter.formatTime(Date.now());
      return;
    }
    this.spaceKeyDiagnosticRunning = true;
    this.spaceKeyDiagnosticTone = 1;
    this.spaceKeyDiagnosticStatus = this.resourceText('settings_self_test_running');
    this.spaceKeyDiagnosticDetail = this.resourceText('settings_self_test_running_desc');
    this.spaceKeyDiagnosticUpdatedAt = this.localizedFormatter.formatTime(Date.now());
    this.settingsStore.runSpaceKeyCryptoSelfTest()
      .then((result: SpaceKeyCryptoSelfTestResult) => {
        this.spaceKeyDiagnosticStatus = this.describeSpaceKeySelfTest(result);
        this.spaceKeyDiagnosticDetail = this.describeSpaceKeySelfTestDetail(result);
        this.spaceKeyDiagnosticTone = result.ok ? 2 : 3;
        this.spaceKeyDiagnosticUpdatedAt = this.localizedFormatter.formatTime(Date.now());
        this.spaceKeyDiagnosticRunning = false;
      })
      .catch(() => {
        this.spaceKeyDiagnosticStatus = this.resourceText('settings_self_test_exception');
        this.spaceKeyDiagnosticDetail = this.resourceText('settings_self_test_exception_desc');
        this.spaceKeyDiagnosticTone = 3;
        this.spaceKeyDiagnosticUpdatedAt = this.localizedFormatter.formatTime(Date.now());
        this.spaceKeyDiagnosticRunning = false;
      });
  }

  private confirmSpaceKeyRecovery(): void {
    this.getUIContext().showAlertDialog({
      title: this.resourceText('settings_reinitialize_dialog_title'),
      message: this.resourceText('settings_reinitialize_dialog_message'),
      primaryButton: {
        value: this.resourceText('common_cancel'),
        action: () => {
        }
      },
      secondaryButton: {
        value: this.resourceText('settings_reinitialize_confirm'),
        fontColor: EggClipColors.statusError,
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
    this.spaceKeyDiagnosticStatus = this.resourceText('settings_recovery_running');
    this.spaceKeyDiagnosticDetail = this.resourceText('settings_recovery_running_desc');
    this.spaceKeyDiagnosticUpdatedAt = this.localizedFormatter.formatTime(Date.now());
    pairingConnectionStore.close();
    this.settingsStore.reinitializePairingSecurityState()
      .then((result: SpaceKeyRecoveryResult) => {
        this.spaceKeyRecoveryRunning = false;
        this.spaceKeyDiagnosticUpdatedAt = this.localizedFormatter.formatTime(Date.now());
        if (result.ok) {
          this.spaceKeyDiagnosticTone = 2;
          this.spaceKeyDiagnosticStatus = this.resourceText('settings_recovery_success');
          this.spaceKeyDiagnosticDetail = result.invalidKeyRefs > 0 ?
            this.resourceText('settings_recovery_success_invalid_desc', result.clearedKeyRefs, result.invalidKeyRefs) :
            this.resourceText('settings_recovery_success_desc', result.clearedKeyRefs);
          return;
        }
        this.spaceKeyDiagnosticTone = 3;
        this.spaceKeyDiagnosticStatus = this.resourceText('settings_recovery_failed');
        this.spaceKeyDiagnosticDetail = this.describeSpaceKeyRecoveryFailure(result);
      })
      .catch(() => {
        this.spaceKeyRecoveryRunning = false;
        this.spaceKeyDiagnosticTone = 3;
        this.spaceKeyDiagnosticStatus = this.resourceText('settings_recovery_failed');
        this.spaceKeyDiagnosticDetail = this.resourceText('settings_recovery_exception_desc');
        this.spaceKeyDiagnosticUpdatedAt = this.localizedFormatter.formatTime(Date.now());
      });
  }

  private describeSpaceKeyRecoveryFailure(result: SpaceKeyRecoveryResult): string {
    if (result.error === SpaceKeyRecoveryError.STORE_READ_FAILED) {
      return this.resourceText('settings_recovery_read_failed');
    }
    if (result.error === SpaceKeyRecoveryError.HUKS_DELETE_FAILED) {
      return this.resourceText('settings_recovery_huks_failed', result.field ?? 'deleteSpaceKey');
    }
    if (result.error === SpaceKeyRecoveryError.STORE_RESET_FAILED) {
      return this.resourceText('settings_recovery_store_failed');
    }
    return this.resourceText('settings_recovery_incomplete');
  }

  private describeSpaceKeySelfTest(result: SpaceKeyCryptoSelfTestResult): string {
    if (result.ok) {
      return this.resourceText('settings_self_test_passed');
    }
    if (result.error === SpaceKeyCryptoSelfTestError.NO_SPACE_KEY) {
      return this.resourceText('settings_self_test_no_key');
    }
    if (result.error === SpaceKeyCryptoSelfTestError.ENCRYPT_FAILED) {
      return this.resourceText('settings_self_test_encrypt_failed');
    }
    if (result.error === SpaceKeyCryptoSelfTestError.DECRYPT_FAILED) {
      return this.resourceText('settings_self_test_decrypt_failed');
    }
    if (result.error === SpaceKeyCryptoSelfTestError.PLAINTEXT_MISMATCH) {
      return this.resourceText('settings_self_test_mismatch');
    }
    if (result.error === SpaceKeyCryptoSelfTestError.HMAC_FAILED) {
      return this.resourceText('settings_self_test_hmac_failed');
    }
    if (result.error === SpaceKeyCryptoSelfTestError.STORE_FAILED) {
      return this.resourceText('settings_self_test_store_failed');
    }
    return this.resourceText('settings_self_test_failed');
  }

  private describeSpaceKeySelfTestDetail(result: SpaceKeyCryptoSelfTestResult): string {
    if (result.ok) {
      if (result.hmacConfirmationCode !== undefined) {
        return this.resourceText('settings_self_test_code_desc', result.hmacConfirmationCode);
      }
      return this.resourceText('settings_self_test_passed_desc');
    }
    if (result.error === SpaceKeyCryptoSelfTestError.NO_SPACE_KEY) {
      return this.resourceText('settings_self_test_pair_first');
    }
    if (result.error === SpaceKeyCryptoSelfTestError.ENCRYPT_FAILED) {
      return this.resourceText('settings_self_test_stage', result.field ?? 'encryptBase64Url');
    }
    if (result.error === SpaceKeyCryptoSelfTestError.DECRYPT_FAILED) {
      return this.resourceText('settings_self_test_stage', result.field ?? 'decryptBase64Url');
    }
    if (result.error === SpaceKeyCryptoSelfTestError.PLAINTEXT_MISMATCH) {
      return this.resourceText('settings_self_test_mismatch_desc');
    }
    if (result.error === SpaceKeyCryptoSelfTestError.HMAC_FAILED) {
      return this.resourceText('settings_self_test_hmac_stage', result.field ?? 'hmacSha256Base64Url');
    }
    if (result.error === SpaceKeyCryptoSelfTestError.STORE_FAILED) {
      return this.resourceText('settings_self_test_store_desc');
    }
    return this.resourceText('settings_self_test_safe_failure');
  }

  private spaceKeyDiagnosticColor(): ResourceColor {
    if (this.spaceKeyDiagnosticTone === 1) {
      return EggClipColors.statusPending;
    }
    if (this.spaceKeyDiagnosticTone === 2) {
      return EggClipColors.statusOnline;
    }
    if (this.spaceKeyDiagnosticTone === 3) {
      return EggClipColors.statusError;
    }
    return EggClipColors.textSecondary;
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

  private formatMessage(message: UiMessageDescriptor): string {
    return this.messageFormatter === null ? message.code : this.messageFormatter.format(message);
  }

  private resourceText(name: string, ...args: Array<string | number>): string {
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext === undefined) {
      return name;
    }
    try {
      return hostContext.resourceManager.getStringByNameSync(name, ...args);
    } catch (_) {
      return name;
    }
  }

  private pluralText(name: string, count: number): string {
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext === undefined) return name;
    try {
      return hostContext.resourceManager.getIntPluralStringByNameSync(name, count, count);
    } catch (_) {
      return name;
    }
  }
}
