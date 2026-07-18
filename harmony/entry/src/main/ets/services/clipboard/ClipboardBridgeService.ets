import pasteboard from '@ohos.pasteboard';
import { estimateUtf8Bytes, MAX_TEXT_BYTES } from '../../utils/TextLimits';
import { ClipboardValidationError, ClipboardValidationResult } from '../../models/PocModels';
import {
  UiMessageCode,
  UiMessageDescriptor,
  UiMessageParameterName,
  uiMessage,
  uiParameter
} from '../localization/UiMessageCodes';

export interface ClipboardPlainTextReadResult {
  ok: boolean;
  text: string;
  byteLength: number;
  error?: ClipboardValidationError;
  message: UiMessageDescriptor;
}

export interface ClipboardPlainTextWriteResult {
  ok: boolean;
  byteLength: number;
  error?: ClipboardValidationError;
  message: UiMessageDescriptor;
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
        message: uiMessage(UiMessageCode.CLIPBOARD_READ_FAILED)
      };
    }

    const mimeType = pasteData.getPrimaryMimeType();

    if (mimeType !== pasteboard.MIMETYPE_TEXT_PLAIN) {
      return {
        ok: false,
        text: '',
        byteLength: 0,
        message: uiMessage(UiMessageCode.CLIPBOARD_NOT_PLAIN_TEXT)
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
        message: uiMessage(UiMessageCode.CLIPBOARD_READ_SUCCESS, [
          uiParameter(UiMessageParameterName.BYTE_LENGTH, validation.byteLength)
        ])
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
        message: uiMessage(UiMessageCode.CLIPBOARD_WRITE_SUCCESS, [
          uiParameter(UiMessageParameterName.BYTE_LENGTH, validation.byteLength)
        ])
      };
    } catch (_) {
      return {
        ok: false,
        byteLength: validation.byteLength,
        message: uiMessage(UiMessageCode.CLIPBOARD_WRITE_FAILED)
      };
    }
  }

  inspectPlainText(text: string): ClipboardValidationResult {
    const byteLength = estimateUtf8Bytes(text);
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

  private formatValidationMessage(result: ClipboardValidationResult): UiMessageDescriptor {
    if (result.error === ClipboardValidationError.EMPTY) {
      return uiMessage(UiMessageCode.CLIPBOARD_EMPTY);
    }
    if (result.error === ClipboardValidationError.TOO_LARGE) {
      return uiMessage(UiMessageCode.CLIPBOARD_TOO_LARGE, [
        uiParameter(UiMessageParameterName.BYTE_LENGTH, result.byteLength),
        uiParameter(UiMessageParameterName.MAX_BYTES, MAX_TEXT_BYTES)
      ]);
    }
    return uiMessage(UiMessageCode.CLIPBOARD_READ_FAILED);
  }
}
