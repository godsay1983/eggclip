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
import { EggClipColors } from '../theme/Colors';

@Entry
@Component
struct Index {
  private readonly tabsController: HdsTabsController = new HdsTabsController();
  @State private selectedIndex: number = 0;

  build() {
    HdsTabs({ controller: this.tabsController }) {
      TabContent() {
        HomePage()
      }
      .tabBar(this.TabBarItem('首', '首页', 0))

      TabContent() {
        DevicesPage()
      }
      .tabBar(this.TabBarItem('备', '设备', 1))

      TabContent() {
        SettingsPage()
      }
      .tabBar(this.TabBarItem('设', '设置', 2))
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
  private TabBarItem(mark: string, label: string, index: number) {
    Column({ space: 2 }) {
      Text(mark)
        .width(24)
        .height(24)
        .textAlign(TextAlign.Center)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.selectedIndex === index ? EggClipColors.onPrimary : EggClipColors.textPrimary)
        .lineHeight(24)
        .backgroundColor(this.selectedIndex === index ? EggClipColors.primary : EggClipColors.controlBackground)
        .borderRadius(8)

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
}
