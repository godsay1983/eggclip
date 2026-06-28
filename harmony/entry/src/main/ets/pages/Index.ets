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

@Entry
@Component
struct Index {
  private readonly tabsController: HdsTabsController = new HdsTabsController();
  private settingsStore: SettingsStore | null = null;
  @State private selectedIndex: number = 0;

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
      .tabBar(this.TabBarItem('首页', 0))

      TabContent() {
        DevicesPage()
      }
      .tabBar(this.TabBarItem('设备', 1))

      TabContent() {
        SettingsPage()
      }
      .tabBar(this.TabBarItem('设置', 2))
    }
    .barOverlap(true)
    .barPosition(BarPosition.End)
    .barMode(ExtendBarMode.HALF_SCREEN_FIXED)
    .vertical(false)
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
      barBottomMargin: 18,
      gradientMask: {
        maskColor: EggClipColors.pageBackground,
        maskHeight: 118
      },
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.ADAPTIVE,
        materialLevel: hdsMaterial.MaterialLevel.GENTLE
      },
      barOpacity: 0.98
    })
    .width('100%')
    .height('100%')
  }

  @Builder
  private TabBarItem(label: string, index: number) {
    Column({ space: 2 }) {
      this.TabIcon(index, this.selectedIndex === index)

      Text(label)
        .fontSize(11)
        .fontWeight(this.selectedIndex === index ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.selectedIndex === index ? EggClipColors.primary : EggClipColors.textPrimary)
        .lineHeight(14)
    }
    .width(64)
    .height(54)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private TabIcon(index: number, selected: boolean) {
    Stack() {
      if (index === 0) {
        Column({ space: 2 }) {
          Row() {}
            .width(18)
            .height(6)
            .backgroundColor(selected ? EggClipColors.onPrimary : EggClipColors.textPrimary)
            .borderRadius(3)
          Row() {}
            .width(14)
            .height(10)
            .backgroundColor(selected ? EggClipColors.onPrimary : EggClipColors.textPrimary)
            .borderRadius(4)
        }
        .alignItems(HorizontalAlign.Center)
      } else if (index === 1) {
        Row({ space: 3 }) {
          Column({ space: 3 }) {
            Row() {}
              .width(8)
              .height(8)
              .backgroundColor(selected ? EggClipColors.onPrimary : EggClipColors.textPrimary)
              .borderRadius(3)
            Row() {}
              .width(8)
              .height(8)
              .backgroundColor(selected ? EggClipColors.onPrimary : EggClipColors.textPrimary)
              .borderRadius(3)
          }
          Column({ space: 3 }) {
            Row() {}
              .width(8)
              .height(8)
              .backgroundColor(selected ? EggClipColors.onPrimary : EggClipColors.textPrimary)
              .borderRadius(3)
            Row() {}
              .width(8)
              .height(8)
              .backgroundColor(selected ? EggClipColors.onPrimary : EggClipColors.textPrimary)
              .borderRadius(3)
          }
        }
      } else {
        Column({ space: 4 }) {
          this.SettingsSliderLine(selected, 0)
          this.SettingsSliderLine(selected, 1)
          this.SettingsSliderLine(selected, 2)
        }
      }
    }
    .width(26)
    .height(26)
    .alignContent(Alignment.Center)
    .backgroundColor(selected ? EggClipColors.primary : EggClipColors.controlBackground)
    .borderRadius(9)
  }

  @Builder
  private SettingsSliderLine(selected: boolean, knobIndex: number) {
    Row({ space: 1 }) {
      if (knobIndex === 0) {
        this.SettingsKnob(selected)
      } else {
        this.SettingsLineSegment(selected, 5)
      }
      if (knobIndex === 1) {
        this.SettingsKnob(selected)
      } else {
        this.SettingsLineSegment(selected, 5)
      }
      if (knobIndex === 2) {
        this.SettingsKnob(selected)
      } else {
        this.SettingsLineSegment(selected, 5)
      }
    }
    .width(20)
    .height(5)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private SettingsLineSegment(selected: boolean, width: number) {
    Row() {}
      .width(width)
      .height(3)
      .backgroundColor(selected ? EggClipColors.onPrimary : EggClipColors.textPrimary)
      .borderRadius(2)
  }

  @Builder
  private SettingsKnob(selected: boolean) {
    Row() {}
      .width(5)
      .height(5)
      .backgroundColor(selected ? EggClipColors.onPrimary : EggClipColors.textPrimary)
      .borderRadius(3)
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
