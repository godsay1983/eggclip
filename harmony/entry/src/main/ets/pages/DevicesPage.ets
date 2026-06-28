import { EggClipColors } from '../theme/Colors';
import { EggClipSpacing } from '../theme/Spacing';
import { EggClipTypography } from '../theme/Typography';

@Component
export struct DevicesPage {
  build() {
    Scroll() {
      Column({ space: EggClipSpacing.sectionGap }) {
        this.Header()
        this.EmptyDeviceCard()
        this.DevicePolicyCard()
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
      Text('设备')
        .fontSize(EggClipTypography.titleSize)
        .fontWeight(FontWeight.Bold)
        .fontColor(EggClipColors.textPrimary)
        .width('100%')

      Text('管理局域网内可信设备')
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textSecondary)
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private EmptyDeviceCard() {
    Column({ space: 14 }) {
      Text('◌')
        .fontSize(42)
        .fontColor(EggClipColors.primary)

      Column({ space: 6 }) {
        Text('还没有可信设备')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(EggClipColors.textPrimary)

        Text('完成配对后，这里会显示设备名称、在线状态、公钥短指纹和最后在线时间。')
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
          .textAlign(TextAlign.Center)
          .lineHeight(20)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)

      Button('添加设备')
        .width('100%')
        .height(44)
        .enabled(false)
        .fontColor(EggClipColors.onPrimary)
        .backgroundColor(EggClipColors.primary)
        .borderRadius(22)

      Text('配对流程会在安全握手完成后开放。')
        .fontSize(11)
        .fontColor(EggClipColors.textSecondary)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding(EggClipSpacing.cardPadding)
    .backgroundColor(EggClipColors.cardBackground)
    .borderRadius(EggClipSpacing.radiusLarge)
  }

  @Builder
  private DevicePolicyCard() {
    Column({ space: 12 }) {
      Text('设备规则')
        .fontSize(EggClipTypography.bodySize)
        .fontWeight(FontWeight.Bold)
        .fontColor(EggClipColors.textPrimary)
        .width('100%')

      this.PolicyRow('最多 5 台', 'v1 建议每个同步空间保持小规模，降低冲突和误连成本。')
      this.PolicyRow('先配对再同步', 'mDNS 只负责发现地址，不能代表设备可信。')
      this.PolicyRow('移除需轮换', '设备移除后会进入 revoked 状态，并触发空间密钥轮换流程。')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(EggClipSpacing.cardPadding)
    .backgroundColor(EggClipColors.cardBackground)
    .borderRadius(EggClipSpacing.radiusMedium)
  }

  @Builder
  private PolicyRow(title: string, description: string) {
    Row({ space: 10 }) {
      Text('•')
        .fontSize(20)
        .fontColor(EggClipColors.primary)

      Column({ space: 3 }) {
        Text(title)
          .fontSize(EggClipTypography.bodySize)
          .fontWeight(FontWeight.Medium)
          .fontColor(EggClipColors.textPrimary)
        Text(description)
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
          .lineHeight(19)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
  }
}
