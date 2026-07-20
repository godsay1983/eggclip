import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import {
  AppReviewPromptState,
  createAppReviewPromptState,
  parseAppReviewPromptState,
  serializeAppReviewPromptState
} from '../../models/AppReviewPrompt';

const PREFERENCES_NAME: string = 'eggclip_app_review_prompt';
const STATE_KEY: string = 'state';

export interface AppReviewPromptDataSource {
  load(): Promise<AppReviewPromptState>;
  save(state: AppReviewPromptState): Promise<void>;
}

export class AppReviewPromptRepository implements AppReviewPromptDataSource {
  private readonly context: common.Context;

  constructor(context: common.Context) {
    this.context = context;
  }

  async load(): Promise<AppReviewPromptState> {
    const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
    const value = await store.get(STATE_KEY, '');
    if (typeof value !== 'string') {
      return createAppReviewPromptState();
    }
    return parseAppReviewPromptState(value) ?? createAppReviewPromptState();
  }

  async save(state: AppReviewPromptState): Promise<void> {
    const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
    await store.put(STATE_KEY, serializeAppReviewPromptState(state));
    await store.flush();
  }
}
