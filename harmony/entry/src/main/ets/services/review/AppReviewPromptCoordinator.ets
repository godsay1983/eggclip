import {
  APP_REVIEW_AUTO_YEAR_LIMIT,
  APP_REVIEW_FAILURE_COOLDOWN_MS,
  APP_REVIEW_MIN_ACTIVE_DAYS,
  APP_REVIEW_MIN_USAGE_DAYS,
  APP_REVIEW_PROMPT_COOLDOWN_MS,
  AppReviewPromptState,
  copyAppReviewPromptState
} from '../../models/AppReviewPrompt';
import { AppReviewPromptDataSource } from '../../data/repositories/AppReviewPromptRepository';

const DAY_MS: number = 24 * 60 * 60 * 1000;

export function appReviewLocalDateKey(now: number): string {
  const date = new Date(now);
  const month = `${date.getMonth() + 1}`.padStart(2, '0');
  const day = `${date.getDate()}`.padStart(2, '0');
  return `${date.getFullYear()}-${month}-${day}`;
}

export function recordAppReviewActiveDay(
  source: AppReviewPromptState,
  now: number
): AppReviewPromptState {
  const state = copyAppReviewPromptState(source);
  const dateKey = appReviewLocalDateKey(now);
  if (state.lastActiveDate !== dateKey) {
    state.lastActiveDate = dateKey;
    state.activeDayCount += 1;
  }
  return state;
}

export function recordAppReviewSuccessfulActions(
  source: AppReviewPromptState,
  count: number
): AppReviewPromptState {
  const state = copyAppReviewPromptState(source);
  if (!Number.isInteger(count) || count <= 0) {
    return state;
  }
  const previousCount = state.successfulActionCount;
  const nextCount = previousCount + count;
  state.successfulActionCount = nextCount;
  state.pendingMilestone = state.pendingMilestone || crossedReviewMilestone(previousCount, nextCount);
  return state;
}

export function isAutoAppReviewEligible(
  state: AppReviewPromptState,
  now: number,
  versionName: string
): boolean {
  if (!state.pendingMilestone || versionName.length === 0) {
    return false;
  }
  if (now - state.firstUsedAt < APP_REVIEW_MIN_USAGE_DAYS * DAY_MS ||
    state.activeDayCount < APP_REVIEW_MIN_ACTIVE_DAYS) {
    return false;
  }
  if (state.lastPromptAt > 0 && now - state.lastPromptAt < APP_REVIEW_PROMPT_COOLDOWN_MS) {
    return false;
  }
  if (state.lastPromptVersion === versionName) {
    return false;
  }
  if (state.lastFailureAt > 0 && now - state.lastFailureAt < APP_REVIEW_FAILURE_COOLDOWN_MS) {
    return false;
  }
  const currentYear = new Date(now).getFullYear();
  const promptCount = state.promptYear === currentYear ? state.promptCountInYear : 0;
  return promptCount < APP_REVIEW_AUTO_YEAR_LIMIT;
}

export function recordAppReviewPromptShown(
  source: AppReviewPromptState,
  now: number,
  versionName: string
): AppReviewPromptState {
  const state = copyAppReviewPromptState(source);
  const currentYear = new Date(now).getFullYear();
  if (state.promptYear !== currentYear) {
    state.promptYear = currentYear;
    state.promptCountInYear = 0;
  }
  state.promptYear = currentYear;
  state.promptCountInYear += 1;
  state.lastPromptAt = now;
  state.lastPromptVersion = versionName;
  state.lastFailureAt = 0;
  state.pendingMilestone = false;
  return state;
}

export function recordAppReviewPromptFailure(
  source: AppReviewPromptState,
  now: number
): AppReviewPromptState {
  const state = copyAppReviewPromptState(source);
  state.lastFailureAt = now;
  return state;
}

export class AppReviewPromptCoordinator {
  private readonly dataSource: AppReviewPromptDataSource;
  private mutationQueue: Promise<void> = Promise.resolve();

  constructor(dataSource: AppReviewPromptDataSource) {
    this.dataSource = dataSource;
  }

  recordActiveDay(now: number = Date.now()): Promise<void> {
    return this.enqueueMutation(async (): Promise<void> => {
      const state = await this.dataSource.load();
      await this.dataSource.save(recordAppReviewActiveDay(state, now));
    });
  }

  recordSuccessfulActions(count: number): Promise<void> {
    return this.enqueueMutation(async (): Promise<void> => {
      const state = await this.dataSource.load();
      await this.dataSource.save(recordAppReviewSuccessfulActions(state, count));
    });
  }

  async isAutoPromptEligible(now: number, versionName: string): Promise<boolean> {
    await this.mutationQueue;
    const state = await this.dataSource.load();
    return isAutoAppReviewEligible(state, now, versionName);
  }

  markPromptShown(now: number, versionName: string): Promise<void> {
    return this.enqueueMutation(async (): Promise<void> => {
      const state = await this.dataSource.load();
      await this.dataSource.save(recordAppReviewPromptShown(state, now, versionName));
    });
  }

  markPromptFailed(now: number): Promise<void> {
    return this.enqueueMutation(async (): Promise<void> => {
      const state = await this.dataSource.load();
      await this.dataSource.save(recordAppReviewPromptFailure(state, now));
    });
  }

  private enqueueMutation(operation: () => Promise<void>): Promise<void> {
    const queued = this.mutationQueue.then(operation);
    this.mutationQueue = queued.catch((): void => {
      // Preserve the queue after a Preferences failure; the caller still receives the rejection.
    });
    return queued;
  }
}

function crossedReviewMilestone(previousCount: number, nextCount: number): boolean {
  return nextCount >= nextReviewMilestone(previousCount);
}

function nextReviewMilestone(successfulActionCount: number): number {
  if (successfulActionCount < 10) {
    return 10;
  }
  if (successfulActionCount < 50) {
    return 50;
  }
  if (successfulActionCount < 100) {
    return 100;
  }
  return (Math.floor(successfulActionCount / 100) + 1) * 100;
}
