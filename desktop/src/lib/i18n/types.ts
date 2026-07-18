export type LanguageMode = "system" | "zh-CN" | "en-US";

export type SupportedLocale = Exclude<LanguageMode, "system">;

export interface MessageArguments {
  "language.system": [];
  "language.zhCN": [];
  "language.enUS": [];
  "language.preview": [appName: string];
}

export type MessageKey = keyof MessageArguments;

export type MessageCatalog = {
  [Key in MessageKey]: (...args: MessageArguments[Key]) => string;
};
