import { common } from '@kit.AbilityKit';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { UiMessageCode, UiMessageDescriptor, uiMessage } from '../localization/UiMessageCodes';

export interface PairingScanResult {
  ok: boolean;
  invitationText: string;
  message: UiMessageDescriptor;
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
          message: uiMessage(UiMessageCode.SCAN_EMPTY)
        };
      }
      return {
        ok: true,
        invitationText,
        message: uiMessage(UiMessageCode.SCAN_SUCCESS)
      };
    } catch (_) {
      return {
        ok: false,
        invitationText: '',
        message: uiMessage(UiMessageCode.SCAN_FAILED)
      };
    }
  }
}
