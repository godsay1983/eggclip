import { common } from '@kit.AbilityKit';
import { AppReviewPromptRepository } from '../../data/repositories/AppReviewPromptRepository';
import { AppReviewPromptCoordinator } from './AppReviewPromptCoordinator';

let sharedCoordinator: AppReviewPromptCoordinator | null = null;

export function getAppReviewPromptCoordinator(context: common.Context): AppReviewPromptCoordinator {
  if (sharedCoordinator === null) {
    sharedCoordinator = new AppReviewPromptCoordinator(new AppReviewPromptRepository(context));
  }
  return sharedCoordinator;
}
