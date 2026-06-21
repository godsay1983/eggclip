import { MAX_TEXT_BYTES } from '../../utils/TextLimits';
import { ClipboardValidationError, ClipboardValidationResult } from '../../models/PocModels';

export class ClipboardBridgeService {
  validatePlainText(text: string): boolean {
    return this.inspectPlainText(text).ok;
  }

  inspectPlainText(text: string): ClipboardValidationResult {
    const byteLength = this.estimateUtf8Bytes(text);
    if (byteLength === 0) {
      return {
        ok: false,
        byteLength,
        error: ClipboardValidationError.EMPTY
      };
    }
    if (byteLength > MAX_TEXT_BYTES) {
      return {
        ok: false,
        byteLength,
        error: ClipboardValidationError.TOO_LARGE
      };
    }
    return {
      ok: true,
      byteLength
    };
  }

  private estimateUtf8Bytes(text: string): number {
    let bytes = 0;
    for (let index = 0; index < text.length; index += 1) {
      const code = text.charCodeAt(index);
      if (code <= 0x7f) {
        bytes += 1;
      } else if (code <= 0x7ff) {
        bytes += 2;
      } else if (code >= 0xd800 && code <= 0xdbff) {
        bytes += 4;
        index += 1;
      } else {
        bytes += 3;
      }
    }
    return bytes;
  }
}
