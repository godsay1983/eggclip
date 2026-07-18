import { common, ConfigurationConstant } from '@kit.AbilityKit';
import {
  DividerMode,
  ExtendBarMode,
  HdsTabs,
  HdsTabsAttribute,
  HdsTabsController,
  hdsMaterial
} from '@kit.UIDesignKit';
import { DevicesPage } from './DevicesPage';
import { HomePage } from './HomePage';
import { SettingsPage } from './SettingsPage';
import { ThemeMode } from '../models/DomainModels';
import { SettingsStore } from '../store/SettingsStore';
import { EggClipColors } from '../theme/Colors';
import { EggClipSpacing } from '../theme/Spacing';
import { APP_LOCALE_REVISION_STORAGE_KEY } from '../utils/AppLifecycle';

@Entry
@Component
struct Index {
  private readonly tabsController: HdsTabsController = new HdsTabsController();
  private settingsStore: SettingsStore | null = null;
  @State private selectedIndex: number = 0;
  @StorageLink(APP_LOCALE_REVISION_STORAGE_KEY) private localeRevision: number = 0;

  aboutToAppear(): void {
    if (this.settingsStore !== null) {
      return;
    }
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext === undefined) {
      return;
    }
    const abilityContext = hostContext as common.UIAbilityContext;
    this.settingsStore = new SettingsStore(abilityContext);
    this.settingsStore.load()
      .then((snapshot) => {
        this.applyThemeMode(abilityContext, snapshot.settings.themeMode);
      })
      .catch(() => {
        abilityContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      });
  }

  build() {
    HdsTabs({ controller: this.tabsController }) {
      TabContent() {
        HomePage()
      }
      .tabBar(this.TabBarItem(this.resourceText('nav_home'), 0))

      TabContent() {
        DevicesPage()
      }
      .tabBar(this.TabBarItem(this.resourceText('nav_devices'), 1))

      TabContent() {
        SettingsPage()
      }
      .tabBar(this.TabBarItem(this.resourceText('nav_settings'), 2))
    }
    .barOverlap(true)
    .barPosition(BarPosition.End)
    .barMode(ExtendBarMode.HALF_SCREEN_FIXED)
    .vertical(false)
    .animationDuration(160)
    .divider({ mode: DividerMode.NONE })
    .onSelected((index: number) => {
      this.selectedIndex = index;
    })
    .barFloatingStyle({
      barWidth: {
        smallWidth: 204,
        mediumWidth: 216,
        largeWidth: 228
      },
      barBottomMargin: EggClipSpacing.floatingNavigationBottomMargin,
      gradientMask: {
        maskColor: EggClipColors.pageBackground,
        maskHeight: EggClipSpacing.floatingNavigationMaskHeight
      },
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.ADAPTIVE,
        materialLevel: hdsMaterial.MaterialLevel.GENTLE
      },
      barOpacity: 0.98
    })
    .width('100%')
    .height('100%')
    .id(`eggclip-localized-${this.localeRevision}`)
  }

  @Builder
  private TabBarItem(label: ResourceStr, index: number) {
    Column({ space: 2 }) {
      this.TabIcon(index, this.selectedIndex === index)

      Text(label)
        .fontSize(11)
        .fontWeight(this.selectedIndex === index ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(EggClipColors.textPrimary)
        .lineHeight(14)
    }
    .width(64)
    .height(EggClipSpacing.floatingNavigationItemHeight)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private TabIcon(index: number, selected: boolean) {
    Stack() {
      if (index === 0) {
        this.HomeGlyph(selected)
      } else if (index === 1) {
        this.DevicesGlyph(selected)
      } else {
        this.SettingsGlyph(selected)
      }
    }
    .width(32)
    .height(26)
    .alignContent(Alignment.Center)
    .backgroundColor(selected ? EggClipColors.primary : Color.Transparent)
    .borderRadius(13)
  }

  @Builder
  private HomeGlyph(selected: boolean) {
    Stack() {
      Row() {}
        .width(10)
        .height(3)
        .backgroundColor(selected ? EggClipColors.onPrimary : EggClipColors.textPrimary)
        .borderRadius(2)
        .rotate({ angle: -38 })
        .offset({ x: -4, y: -5 })

      Row() {}
        .width(10)
        .height(3)
        .backgroundColor(selected ? EggClipColors.onPrimary : EggClipColors.textPrimary)
        .borderRadius(2)
        .rotate({ angle: 38 })
        .offset({ x: 4, y: -5 })

      Row() {
        Row() {}
          .width(4)
          .height(7)
          .backgroundColor(selected ? EggClipColors.onPrimary : EggClipColors.textPrimary)
          .borderRadius(2)
          .margin({ top: 7 })
      }
      .width(16)
      .height(15)
      .justifyContent(FlexAlign.Center)
      .border({
        width: 2,
        color: selected ? EggClipColors.onPrimary : EggClipColors.textPrimary
      })
      .borderRadius(5)
      .offset({ x: 0, y: 4 })
    }
    .width(22)
    .height(22)
    .alignContent(Alignment.Center)
  }

  @Builder
  private DevicesGlyph(selected: boolean) {
    Stack() {
      Row() {}
        .width(13)
        .height(17)
        .border({
          width: 2,
          color: selected ? EggClipColors.onPrimary : EggClipColors.textPrimary
        })
        .borderRadius(5)
        .offset({ x: -4, y: -3 })

      Row() {}
        .width(13)
        .height(17)
        .backgroundColor(Color.Transparent)
        .border({
          width: 2,
          color: selected ? EggClipColors.onPrimary : EggClipColors.textPrimary
        })
        .borderRadius(5)
        .offset({ x: 5, y: 4 })

      Row() {}
        .width(5)
        .height(2)
        .backgroundColor(selected ? EggClipColors.onPrimary : EggClipColors.textPrimary)
        .borderRadius(1)
        .offset({ x: 5, y: 10 })
    }
    .width(24)
    .height(24)
    .alignContent(Alignment.Center)
  }

  @Builder
  private SettingsGlyph(selected: boolean) {
    Stack() {
      this.SettingsTooth(selected, 4, 7, 0, -10, 0)
      this.SettingsTooth(selected, 4, 7, 0, 10, 0)
      this.SettingsTooth(selected, 7, 4, -10, 0, 0)
      this.SettingsTooth(selected, 7, 4, 10, 0, 0)
      this.SettingsTooth(selected, 4, 7, -7, -7, -45)
      this.SettingsTooth(selected, 4, 7, 7, -7, 45)
      this.SettingsTooth(selected, 4, 7, -7, 7, 45)
      this.SettingsTooth(selected, 4, 7, 7, 7, -45)

      Row() {}
        .width(17)
        .height(17)
        .border({
          width: 2,
          color: selected ? EggClipColors.onPrimary : EggClipColors.textPrimary
        })
        .borderRadius(9)

      Row() {}
        .width(6)
        .height(6)
        .border({
          width: 2,
          color: selected ? EggClipColors.onPrimary : EggClipColors.textPrimary
        })
        .borderRadius(3)
    }
    .width(24)
    .height(24)
    .alignContent(Alignment.Center)
  }

  @Builder
  private SettingsTooth(selected: boolean, width: number, height: number, x: number, y: number, angle: number) {
    Row() {}
      .width(width)
      .height(height)
      .backgroundColor(selected ? EggClipColors.onPrimary : EggClipColors.textPrimary)
      .borderRadius(2)
      .rotate({ angle })
      .offset({ x, y })
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

  private applyThemeMode(context: common.UIAbilityContext, mode: ThemeMode): void {
    if (mode === ThemeMode.DARK) {
      context.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
      return;
    }
    if (mode === ThemeMode.LIGHT) {
      context.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
      return;
    }
    context.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
  }
}
