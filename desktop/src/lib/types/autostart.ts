export type AutostartLoadState = "idle" | "loading" | "ready" | "saving" | "error";

export interface AutostartSnapshot {
  state: AutostartLoadState;
  enabled: boolean;
  errorMessage: string | null;
}
