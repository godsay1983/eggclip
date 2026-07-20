export const APP_REVIEW_PROMPT_SCHEMA_VERSION: number = 1;
export const APP_REVIEW_MIN_USAGE_DAYS: number = 7;
export const APP_REVIEW_MIN_ACTIVE_DAYS: number = 3;
export const APP_REVIEW_AUTO_YEAR_LIMIT: number = 2;
export const APP_REVIEW_PROMPT_COOLDOWN_MS: number = 90 * 24 * 60 * 60 * 1000;
export const APP_REVIEW_FAILURE_COOLDOWN_MS: number = 7 * 24 * 60 * 60 * 1000;

export interface AppReviewPromptState {
  schemaVersion: number;
  firstUsedAt: number;
  lastActiveDate: string;
  activeDayCount: number;
  successfulActionCount: number;
  pendingMilestone: boolean;
  lastPromptAt: number;
  lastPromptVersion: string;
  promptYear: number;
  promptCountInYear: number;
  lastFailureAt: number;
}

export function createAppReviewPromptState(now: number = Date.now()): AppReviewPromptState {
  return {
    schemaVersion: APP_REVIEW_PROMPT_SCHEMA_VERSION,
    firstUsedAt: now,
    lastActiveDate: '',
    activeDayCount: 0,
    successfulActionCount: 0,
    pendingMilestone: false,
    lastPromptAt: 0,
    lastPromptVersion: '',
    promptYear: 0,
    promptCountInYear: 0,
    lastFailureAt: 0
  };
}

export function copyAppReviewPromptState(state: AppReviewPromptState): AppReviewPromptState {
  return {
    schemaVersion: state.schemaVersion,
    firstUsedAt: state.firstUsedAt,
    lastActiveDate: state.lastActiveDate,
    activeDayCount: state.activeDayCount,
    successfulActionCount: state.successfulActionCount,
    pendingMilestone: state.pendingMilestone,
    lastPromptAt: state.lastPromptAt,
    lastPromptVersion: state.lastPromptVersion,
    promptYear: state.promptYear,
    promptCountInYear: state.promptCountInYear,
    lastFailureAt: state.lastFailureAt
  };
}

export function serializeAppReviewPromptState(state: AppReviewPromptState): string {
  return JSON.stringify(state);
}

export function parseAppReviewPromptState(content: string): AppReviewPromptState | null {
  if (content.length === 0) {
    return null;
  }
  try {
    const state = JSON.parse(content) as AppReviewPromptState;
    if (!isValidAppReviewPromptState(state)) {
      return null;
    }
    return copyAppReviewPromptState(state);
  } catch (_) {
    return null;
  }
}

function isValidAppReviewPromptState(state: AppReviewPromptState): boolean {
  return state.schemaVersion === APP_REVIEW_PROMPT_SCHEMA_VERSION &&
    isNonNegativeInteger(state.firstUsedAt) &&
    typeof state.lastActiveDate === 'string' &&
    isNonNegativeInteger(state.activeDayCount) &&
    isNonNegativeInteger(state.successfulActionCount) &&
    typeof state.pendingMilestone === 'boolean' &&
    isNonNegativeInteger(state.lastPromptAt) &&
    typeof state.lastPromptVersion === 'string' &&
    isNonNegativeInteger(state.promptYear) &&
    isNonNegativeInteger(state.promptCountInYear) &&
    isNonNegativeInteger(state.lastFailureAt);
}

function isNonNegativeInteger(value: number): boolean {
  return typeof value === 'number' && Number.isInteger(value) && value >= 0;
}
