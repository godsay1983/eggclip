import { common } from '@kit.AbilityKit';
import {
  UiMessageCode,
  UiMessageDescriptor,
  UiMessageParameter
} from './UiMessageCodes';

export interface UiStringResolver {
  getStringByNameSync(resourceName: string, ...args: Array<string | number>): string;
}

export class UiMessageFormatter {
  private readonly resolver: UiStringResolver;

  constructor(context: common.Context, resolver?: UiStringResolver) {
    this.resolver = resolver ?? context.resourceManager;
  }

  format(message: UiMessageDescriptor): string {
    return formatUiMessage(this.resolver, message);
  }
}

export function formatUiMessage(resolver: UiStringResolver, message: UiMessageDescriptor): string {
    const values: Array<string | number> = message.parameters.map(
      (parameter: UiMessageParameter): string | number => parameter.value
    );
    try {
      return resolver.getStringByNameSync(message.code, ...values);
    } catch (_) {
      try {
        return resolver.getStringByNameSync(UiMessageCode.UNKNOWN);
      } catch (_) {
        return 'Something went wrong';
      }
    }
}
