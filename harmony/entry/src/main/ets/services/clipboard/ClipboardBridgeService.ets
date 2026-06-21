import pasteboard from '@ohos.pasteboard';
import { MAX_TEXT_BYTES } from '../../utils/TextLimits';
import { ClipboardValidationError, ClipboardValidationResult } from '../../models/PocModels';

export interface ClipboardPlainTextReadResult {
  ok: boolean;
  text: string;
  byteLength: number;
  error?: ClipboardValidationError;
  message: string;
}

export interface ClipboardPlainTextWriteResult {
  ok: boolean;
  byteLength: number;
  error?: ClipboardValidationError;
  message: string;
}

export class ClipboardBridgeService {
  async readPlainTextAfterPasteButton(): Promise<ClipboardPlainTextReadResult> {
    let pasteData: pasteboard.PasteData;
    try {
      const systemPasteboard = pasteboard.getSystemPasteboard();
      pasteData = await systemPasteboard.getData();
    } catch (_) {
      return {
        ok: false,
        text: '',
        byteLength: 0,
        message: '读取剪贴板失败，请确认已通过 PasteButton 授权'
      };
    }

    const mimeType = pasteData.getPrimaryMimeType();

    if (mimeType !== pasteboard.MIMETYPE_TEXT_PLAIN) {
      return {
        ok: false,
        text: '',
        byteLength: 0,
        message: '剪贴板当前内容不是 text/plain 纯文本'
      };
    }

    const text = pasteData.getPrimaryText();
    const validation = this.inspectPlainText(text);
    if (!validation.ok) {
      return {
        ok: false,
        text: '',
        byteLength: validation.byteLength,
        error: validation.error,
        message: this.formatValidationMessage(validation)
      };
    }

    return {
      ok: true,
      text,
      byteLength: validation.byteLength,
      message: `已读取 ${validation.byteLength} 字节纯文本，等待接入发送链路`
    };
  }

  validatePlainText(text: string): boolean {
    return this.inspectPlainText(text).ok;
  }

  async writePlainTextByUserAction(text: string): Promise<ClipboardPlainTextWriteResult> {
    const validation = this.inspectPlainText(text);
    if (!validation.ok) {
      return {
        ok: false,
        byteLength: validation.byteLength,
        error: validation.error,
        message: this.formatValidationMessage(validation)
      };
    }

    try {
      const systemPasteboard = pasteboard.getSystemPasteboard();
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      await systemPasteboard.setData(pasteData);
      return {
        ok: true,
        byteLength: validation.byteLength,
        message: `已复制 ${validation.byteLength} 字节纯文本到本机剪贴板`
      };
    } catch (_) {
      return {
        ok: false,
        byteLength: validation.byteLength,
        message: '写入本机剪贴板失败，请稍后重试'
      };
    }
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

  private formatValidationMessage(result: ClipboardValidationResult): string {
    if (result.error === ClipboardValidationError.EMPTY) {
      return '剪贴板为空，或当前内容不是可同步的纯文本';
    }
    if (result.error === ClipboardValidationError.TOO_LARGE) {
      return `剪贴板文本过大：${result.byteLength} 字节，当前上限为 ${MAX_TEXT_BYTES} 字节`;
    }
    return '无法读取可同步的剪贴板文本';
  }
}
