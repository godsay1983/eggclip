import { EggClipColors } from '../../theme/Colors';
import { EggClipTypography } from '../../theme/Typography';

export enum EggNavTab {
  HOME = 'home',
  DEVICES = 'devices',
  SETTINGS = 'settings'
}

@Component
export struct EggBottomNav {
  selected: EggNavTab = EggNavTab.HOME;
  onSelected: (tab: EggNavTab) => void = () => {};

  build() {
    Row({ space: 8 }) {
      this.NavItem(EggNavTab.HOME, '⌂', '首页')
      this.NavItem(EggNavTab.DEVICES, '▣', '设备')
      this.NavItem(EggNavTab.SETTINGS, '⚙', '设置')
    }
    .height(64)
    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
    .backgroundColor(EggClipColors.cardBackground)
    .borderRadius(32)
    .shadow({
      radius: 24,
      color: 'rgba(39, 33, 20, 0.16)',
      offsetX: 0,
      offsetY: 8
    })
  }

  @Builder
  private NavItem(tab: EggNavTab, icon: string, label: string) {
    Column({ space: 3 }) {
      Text(icon)
        .width(24)
        .height(24)
        .textAlign(TextAlign.Center)
        .fontSize(16)
        .fontColor(this.selected === tab ? EggClipColors.onPrimary : EggClipColors.textPrimary)
        .backgroundColor(this.selected === tab ? EggClipColors.primary : Color.Transparent)
        .borderRadius(7)

      Text(label)
        .fontSize(EggClipTypography.captionSize)
        .fontColor(this.selected === tab ? EggClipColors.primary : EggClipColors.textPrimary)
        .fontWeight(this.selected === tab ? FontWeight.Bold : FontWeight.Regular)
    }
    .width(48)
    .height(48)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.onSelected(tab);
    })
  }
}
