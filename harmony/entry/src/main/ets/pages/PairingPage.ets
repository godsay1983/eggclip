import {
  PairingStore,
  PairingStoreSnapshot,
  PairingStoreState,
  createInitialPairingSnapshot
} from '../store/PairingStore';
import { PairingInvitationSummary } from '../services/pairing/PairingInvitationService';
import { ClipboardBridgeService } from '../services/clipboard/ClipboardBridgeService';
import { EggClipColors } from '../theme/Colors';
import { EggClipSpacing } from '../theme/Spacing';
import { EggClipTypography } from '../theme/Typography';

@Component
export struct PairingPage {
  private readonly pairingStore: PairingStore = new PairingStore();
  private readonly clipboardBridge: ClipboardBridgeService = new ClipboardBridgeService();
  @State private snapshot: PairingStoreSnapshot = createInitialPairingSnapshot();
  @State private pasteImportStatus: string = '也可以点击系统 PasteButton，从剪贴板读取桌面端复制的邀请。';

  build() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 4 }) {
          Text('设备配对')
            .fontSize(EggClipTypography.bodySize)
            .fontWeight(FontWeight.Bold)
            .fontColor(EggClipColors.textPrimary)

          Text('导入桌面端生成的 eggclip://pair 邀请。当前只做格式、过期和字段校验，暂不建立信任。')
            .fontSize(EggClipTypography.captionSize)
            .fontColor(EggClipColors.textSecondary)
            .lineHeight(20)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text(this.statusBadgeText())
          .fontSize(11)
          .fontColor(this.statusColor())
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor(EggClipColors.controlBackground)
          .borderRadius(14)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      TextInput({
        text: this.snapshot.invitationText,
        placeholder: '粘贴 eggclip://pair?p=...'
      })
        .width('100%')
        .height(44)
        .backgroundColor(EggClipColors.controlBackground)
        .borderRadius(16)
        .onChange((value: string) => {
          this.snapshot = this.pairingStore.updateInvitationText(value);
        })

      Column({ space: 6 }) {
        PasteButton({
          text: PasteDescription.PASTE,
          buttonType: ButtonType.Capsule
        })
          .width('100%')
          .height(42)
          .fontColor(EggClipColors.onPrimary)
          .backgroundColor(EggClipColors.primary)
          .borderRadius(21)
          .onClick((_event: ClickEvent, result: PasteButtonOnClickResult) => {
            if (result !== PasteButtonOnClickResult.SUCCESS) {
              this.pasteImportStatus = 'PasteButton 临时授权失败，未读取系统剪贴板';
              return;
            }
            this.pasteImportStatus = 'PasteButton 已授权，正在读取邀请文本';
            this.clipboardBridge.readPlainTextAfterPasteButton()
              .then((readResult) => {
                if (!readResult.ok) {
                  this.pasteImportStatus = readResult.message;
                  return;
                }
                this.snapshot = this.pairingStore.importInvitationText(readResult.text);
                this.pasteImportStatus = this.snapshot.state === PairingStoreState.READY
                  ? '已从剪贴板读取并校验邀请'
                  : this.snapshot.statusText;
              })
              .catch(() => {
                this.pasteImportStatus = '读取剪贴板失败，请确认当前内容是纯文本邀请';
              });
          })

        Text(this.pasteImportStatus)
          .width('100%')
          .fontSize(11)
          .fontColor(EggClipColors.textSecondary)
          .lineHeight(18)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Row({ space: 8 }) {
        Button('校验邀请')
          .layoutWeight(1)
          .height(42)
          .fontColor(EggClipColors.onPrimary)
          .backgroundColor(EggClipColors.primary)
          .borderRadius(21)
          .onClick(() => {
            this.snapshot = this.pairingStore.parseCurrent();
          })

        Button('清空')
          .width(84)
          .height(42)
          .fontColor(EggClipColors.textSecondary)
          .backgroundColor(EggClipColors.controlBackground)
          .borderRadius(21)
          .onClick(() => {
            this.snapshot = this.pairingStore.clear();
          })
      }
      .width('100%')

      Text(this.snapshot.statusText)
        .width('100%')
        .fontSize(EggClipTypography.captionSize)
        .fontColor(this.statusColor())
        .lineHeight(20)

      if (this.snapshot.summary !== null) {
        this.InvitationSummaryCard(this.snapshot.summary)
      }

      this.SecurityBoundary()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(EggClipSpacing.cardPadding)
    .backgroundColor(EggClipColors.cardBackground)
    .borderRadius(EggClipSpacing.radiusMedium)
  }

  @Builder
  private InvitationSummaryCard(summary: PairingInvitationSummary) {
    Column({ space: 10 }) {
      this.SummaryRow('同步空间', `#${summary.spaceShortId} · key v${summary.spaceKeyVersion}`)
      this.SummaryRow('发行设备', `#${summary.issuerShortFingerprint}`)
      this.SummaryRow('剩余时间', `${summary.expiresInSeconds} 秒`)

      Column({ space: 4 }) {
        Text('人工确认码')
          .fontSize(11)
          .fontColor(EggClipColors.textSecondary)

        Text(summary.confirmationCode)
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor(EggClipColors.textPrimary)
          .letterSpacing(4)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .backgroundColor(EggClipColors.controlBackground)
      .borderRadius(16)
      .alignItems(HorizontalAlign.Center)

      Button(this.snapshot.state === PairingStoreState.PENDING ? '等待正式配对接入' : '确认码一致，继续配对')
        .width('100%')
        .height(42)
        .enabled(this.snapshot.state === PairingStoreState.READY)
        .fontColor(EggClipColors.onPrimary)
        .backgroundColor(this.snapshot.state === PairingStoreState.READY ? EggClipColors.primary : EggClipColors.textSecondary)
        .borderRadius(21)
        .onClick(() => {
          this.snapshot = this.pairingStore.confirmCodeMatched();
        })

      if (this.snapshot.state === PairingStoreState.PENDING) {
        Text('当前只推进到内存 pending 状态，不创建可信设备、不保存邀请 secret、不接收 spaceKey。正式握手和 HUKS 接入后会继续完成配对。')
          .width('100%')
          .fontSize(11)
          .fontColor(EggClipColors.textSecondary)
          .lineHeight(18)
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(EggClipColors.controlBackground)
    .borderRadius(16)
  }

  @Builder
  private SummaryRow(label: string, value: string) {
    Row({ space: 10 }) {
      Text(label)
        .width(78)
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textSecondary)

      Text(value)
        .layoutWeight(1)
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textPrimary)
    }
    .width('100%')
  }

  @Builder
  private SecurityBoundary() {
    Column({ space: 6 }) {
      Text('安全边界')
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(EggClipColors.textPrimary)

      Text('邀请字符串包含一次性 pairingSecret。导入校验不会把邀请保存到历史，也不会写入 RDB；正式配对接入后才会消费 secret 并清理。')
        .fontSize(11)
        .fontColor(EggClipColors.textSecondary)
        .lineHeight(18)
    }
    .width('100%')
    .padding(12)
    .backgroundColor(EggClipColors.controlBackground)
    .borderRadius(16)
    .alignItems(HorizontalAlign.Start)
  }

  private statusBadgeText(): string {
    if (this.snapshot.state === PairingStoreState.READY) {
      return '有效邀请';
    }
    if (this.snapshot.state === PairingStoreState.PENDING) {
      return '待握手';
    }
    if (this.snapshot.state === PairingStoreState.ERROR) {
      return '校验失败';
    }
    return '待校验';
  }

  private statusColor(): ResourceColor {
    if (this.snapshot.state === PairingStoreState.READY) {
      return EggClipColors.statusOnline;
    }
    if (this.snapshot.state === PairingStoreState.PENDING) {
      return EggClipColors.primary;
    }
    if (this.snapshot.state === PairingStoreState.ERROR) {
      return Color.Red;
    }
    return EggClipColors.textSecondary;
  }
}
