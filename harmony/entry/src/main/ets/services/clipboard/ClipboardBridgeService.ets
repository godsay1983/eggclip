import { MAX_TEXT_BYTES } from '../../utils/TextLimits';

export class ClipboardBridgeService {
  validatePlainText(text: string): boolean {
    return text.length > 0 && this.estimateUtf8Bytes(text) <= MAX_TEXT_BYTES;
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
