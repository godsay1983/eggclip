import type { UiMessageDescriptor } from "$lib/i18n";

export type AutostartLoadState = "idle" | "loading" | "ready" | "saving" | "error";

export interface AutostartSnapshot {
  state: AutostartLoadState;
  enabled: boolean;
  errorMessage: UiMessageDescriptor | null;
}
