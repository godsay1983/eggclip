import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { pairingConnectionStore } from '../store/PairingConnectionStore';
import {
  PocConnectionSnapshot,
  pocConnectionStore
} from '../store/PocConnectionStore';
import {
  APP_FOREGROUND_STORAGE_KEY,
  APP_LOCALE_REVISION_STORAGE_KEY
} from '../utils/AppLifecycle';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  private readonly discoveryListener = (snapshot: PocConnectionSnapshot): void => {
    pairingConnectionStore.updateTrustedDiscoveryCandidates(snapshot.discoveryCandidates);
  };

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    AppStorage.setOrCreate<boolean>(APP_FOREGROUND_STORAGE_KEY, false);
    AppStorage.setOrCreate<number>(APP_LOCALE_REVISION_STORAGE_KEY, 0);
    // Trusted reconnect belongs to the ability lifecycle, not to the Devices
    // tab. Initialize it before the first page is shown and only connect while
    // the application is in the foreground.
    pairingConnectionStore.setForeground(false);
    pairingConnectionStore.initialize(this.context);
    pocConnectionStore.initialize(this.context);
    pocConnectionStore.subscribe(this.discoveryListener);
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    pocConnectionStore.unsubscribe(this.discoveryListener);
    pocConnectionStore.stopDiscovery();
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onConfigurationUpdate(): void {
    const currentRevision = AppStorage.get<number>(APP_LOCALE_REVISION_STORAGE_KEY) ?? 0;
    AppStorage.setOrCreate<number>(APP_LOCALE_REVISION_STORAGE_KEY, currentRevision + 1);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability configuration updated');
  }

  onForeground(): void {
    pairingConnectionStore.setForeground(true);
    pocConnectionStore.startDiscovery();
    AppStorage.setOrCreate<boolean>(APP_FOREGROUND_STORAGE_KEY, true);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    pocConnectionStore.stopDiscovery();
    pairingConnectionStore.setForeground(false);
    AppStorage.setOrCreate<boolean>(APP_FOREGROUND_STORAGE_KEY, false);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
