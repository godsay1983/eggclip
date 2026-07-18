import type { MessageCatalog } from "$lib/i18n/types";

export const zhCNMessages: MessageCatalog = {
  "language.system": () => "跟随系统",
  "language.zhCN": () => "简体中文",
  "language.enUS": () => "English",
  "language.preview": (appName) => `${appName} 已切换为简体中文`,
};
