import { common } from '@kit.AbilityKit';
import { scanBarcode, scanCore } from '@kit.ScanKit';

export interface PairingScanResult {
  ok: boolean;
  invitationText: string;
  message: string;
}

export class PairingScanService {
  async scanPairingInvitation(context: common.Context): Promise<PairingScanResult> {
    try {
      const result = await scanBarcode.startScanForResult(context, {
        scanTypes: [scanCore.ScanType.QR_CODE],
        enableMultiMode: false,
        enableAlbum: false
      });
      const invitationText = result.originalValue.trim();
      if (invitationText.length === 0) {
        return {
          ok: false,
          invitationText: '',
          message: '扫码结果为空，请重新扫描桌面端二维码'
        };
      }
      return {
        ok: true,
        invitationText,
        message: '已扫描二维码，正在校验邀请'
      };
    } catch (_) {
      return {
        ok: false,
        invitationText: '',
        message: '扫码未完成，请确认已授权相机并重新扫描'
      };
    }
  }
}
