import { EggClipColors } from '../theme/Colors';
import { EggClipSpacing } from '../theme/Spacing';
import { EggClipTypography } from '../theme/Typography';

@Component
export struct DevicesPage {
  build() {
    Scroll() {
      Column({ space: EggClipSpacing.sectionGap }) {
        Column({ space: 6 }) {
          Text('设备')
            .fontSize(EggClipTypography.titleSize)
            .fontWeight(FontWeight.Bold)
            .fontColor(EggClipColors.textPrimary)
            .width('100%')

          Text('管理可信桌面端和移动端')
            .fontSize(EggClipTypography.captionSize)
            .fontColor(EggClipColors.textSecondary)
            .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Column({ space: 10 }) {
          Text('暂无已配对设备')
            .fontSize(EggClipTypography.bodySize)
            .fontWeight(FontWeight.Bold)
            .fontColor(EggClipColors.textPrimary)
            .width('100%')

          Text('后续配对完成后，这里会显示设备名称、在线状态、公钥短指纹和最后在线时间。移除设备时会提示空间密钥轮换影响。')
            .fontSize(EggClipTypography.captionSize)
            .fontColor(EggClipColors.textSecondary)
            .lineHeight(20)
            .width('100%')

          Button('添加设备')
            .width('100%')
            .height(44)
            .enabled(false)
            .fontColor(EggClipColors.onPrimary)
            .backgroundColor(EggClipColors.primary)
            .borderRadius(22)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(EggClipSpacing.cardPadding)
        .backgroundColor(EggClipColors.cardBackground)
        .borderRadius(EggClipSpacing.radiusMedium)
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
}
