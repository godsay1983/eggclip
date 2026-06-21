import { EGGCLIP_MDNS_SERVICE_TYPE, PocRuntimeState } from '../models/PocModels';
import { StatusDot } from '../components/common/StatusDot';
import { HomeShellState } from '../models/ShellModels';
import { createInitialHomeShellState } from '../store/HomeStore';
import { createInitialPocRuntimeState } from '../store/PocStore';
import { EggClipColors } from '../theme/Colors';
import { EggClipSpacing } from '../theme/Spacing';
import { EggClipTypography } from '../theme/Typography';

@Component
export struct HomePage {
  private readonly state: HomeShellState = createInitialHomeShellState();
  private readonly pocState: PocRuntimeState = createInitialPocRuntimeState();
  @State private pasteStatus: string = '等待点击 PasteButton 触发一次性授权';

  build() {
    Scroll() {
      Column({ space: EggClipSpacing.sectionGap }) {
        this.Header()
        this.ConnectionCard()
        this.PocStatusCard()
        this.LatestClipboardCard()
        this.HistoryPlaceholder()
      }
      .width('100%')
      .padding(EggClipSpacing.pagePadding)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(EggClipColors.pageBackground)
  }

  @Builder
  private Header() {
    Row() {
      Column({ space: 4 }) {
        Text('蛋定 Clip')
          .fontSize(EggClipTypography.titleSize)
          .fontWeight(FontWeight.Bold)
          .fontColor(EggClipColors.textPrimary)

        Text('局域网剪贴板同步')
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text('设置')
        .fontSize(EggClipTypography.bodySize)
        .fontColor(EggClipColors.textSecondary)
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .backgroundColor(EggClipColors.controlBackground)
        .borderRadius(18)
    }
    .width('100%')
  }

  @Builder
  private ConnectionCard() {
    Row({ space: 10 }) {
      StatusDot({ state: this.state.connection.state })

      Column({ space: 3 }) {
        Text(this.state.connection.title)
          .fontSize(EggClipTypography.bodySize)
          .fontWeight(FontWeight.Medium)
          .fontColor(EggClipColors.textPrimary)

        Text(this.state.connection.description)
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(EggClipSpacing.cardPadding)
    .backgroundColor(EggClipColors.cardBackground)
    .borderRadius(EggClipSpacing.radiusMedium)
  }

  @Builder
  private PocStatusCard() {
    Column({ space: 10 }) {
      Row() {
        Text('POC 状态')
          .fontSize(EggClipTypography.bodySize)
          .fontWeight(FontWeight.Bold)
          .fontColor(EggClipColors.textPrimary)
          .layoutWeight(1)

        Text('H1')
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
      }
      .width('100%')

      Text(`mDNS: ${EGGCLIP_MDNS_SERVICE_TYPE}`)
        .width('100%')
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textSecondary)

      Text(`发现服务：${this.pocState.discoveryState} · WebSocket：${this.pocState.transportState}`)
        .width('100%')
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textSecondary)

      Text('已声明局域网网络权限；PasteButton 安全组件已接入，pasteboard 读取和真机连接待接入。')
        .width('100%')
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textSecondary)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(EggClipSpacing.cardPadding)
    .backgroundColor(EggClipColors.cardBackground)
    .borderRadius(EggClipSpacing.radiusMedium)
  }

  @Builder
  private LatestClipboardCard() {
    Column({ space: 14 }) {
      Row() {
        Text('最新收到')
          .fontSize(EggClipTypography.bodySize)
          .fontWeight(FontWeight.Bold)
          .fontColor(EggClipColors.textPrimary)
          .layoutWeight(1)

        Text(this.state.latest === null ? '暂无内容' : this.state.latest.source)
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
      }
      .width('100%')

      Text(this.state.latest === null ? '完成配对后，桌面端的最新文本会显示在这里。历史补同步不会覆盖本机剪贴板。' : this.state.latest.preview)
        .fontSize(EggClipTypography.bodySize)
        .fontColor(EggClipColors.textSecondary)
        .lineHeight(24)

      Column({ space: 6 }) {
        PasteButton({
          text: PasteDescription.PASTE,
          buttonType: ButtonType.Capsule
        })
          .width('100%')
          .height(46)
          .fontColor(EggClipColors.onPrimary)
          .backgroundColor(EggClipColors.primary)
          .borderRadius(23)
          .onClick((_event: ClickEvent, result: PasteButtonOnClickResult) => {
            this.pasteStatus = result === PasteButtonOnClickResult.SUCCESS
              ? 'PasteButton 已授权；下一步接入 pasteboard.getData() 读取纯文本'
              : 'PasteButton 临时授权失败，未读取系统剪贴板';
          })

        Text(this.pasteStatus)
          .width('100%')
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Button('复制到本机')
        .width('100%')
        .height(46)
        .enabled(this.state.latest !== null && this.state.latest.canCopy)
        .fontColor(EggClipColors.onPrimary)
        .backgroundColor(EggClipColors.primary)
        .borderRadius(23)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(EggClipSpacing.cardPadding)
    .backgroundColor(EggClipColors.cardBackground)
    .borderRadius(EggClipSpacing.radiusLarge)
  }

  @Builder
  private HistoryPlaceholder() {
    Column({ space: 8 }) {
      Text('最近记录')
        .width('100%')
        .fontSize(EggClipTypography.bodySize)
        .fontWeight(FontWeight.Bold)
        .fontColor(EggClipColors.textPrimary)

      Text(`这里会保存最近 ${this.state.history.limit} 条记录，最长保留 7 天。`)
        .width('100%')
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textSecondary)
    }
    .width('100%')
    .padding(EggClipSpacing.cardPadding)
    .backgroundColor(EggClipColors.cardBackground)
    .borderRadius(EggClipSpacing.radiusMedium)
  }
}
