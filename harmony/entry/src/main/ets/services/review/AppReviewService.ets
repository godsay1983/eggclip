import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { commentManager } from '@kit.AppGalleryKit';
import { bundleManager } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const APP_REVIEW_LOG_DOMAIN: number = 0xD0F1;
const APP_REVIEW_LOG_TAG: string = 'AppReview';
const APP_GALLERY_REVIEW_URL: string =
  'https://appgallery.huawei.com/app/detail?id=com.eggclip.app&action=write-review';

export interface AppReviewRequestResult {
  shown: boolean;
  errorCode: number;
}

export class AppReviewService {
  async requestReview(context: common.UIAbilityContext): Promise<AppReviewRequestResult> {
    try {
      await commentManager.showCommentDialog(context);
      return { shown: true, errorCode: 0 };
    } catch (error) {
      const businessError = error as BusinessError;
      const errorCode = typeof businessError.code === 'number' ? businessError.code : -1;
      hilog.warn(APP_REVIEW_LOG_DOMAIN, APP_REVIEW_LOG_TAG,
        'showCommentDialog failed code=%{public}d', errorCode);
      return { shown: false, errorCode };
    }
  }

  async openAppGalleryReviewPage(context: common.UIAbilityContext): Promise<boolean> {
    try {
      await context.openLink(APP_GALLERY_REVIEW_URL, { appLinkingOnly: false });
      return true;
    } catch (error) {
      const businessError = error as BusinessError;
      const errorCode = typeof businessError.code === 'number' ? businessError.code : -1;
      hilog.warn(APP_REVIEW_LOG_DOMAIN, APP_REVIEW_LOG_TAG,
        'open review page failed code=%{public}d', errorCode);
      return false;
    }
  }

  currentAppVersionName(): string {
    try {
      return bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT
      ).versionName;
    } catch (_) {
      return '';
    }
  }
}
