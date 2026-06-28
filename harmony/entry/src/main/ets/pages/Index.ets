import { EggBottomNav, EggNavTab } from '../components/navigation/EggBottomNav';
import { DevicesPage } from './DevicesPage';
import { HomePage } from './HomePage';
import { SettingsPage } from './SettingsPage';

@Entry
@Component
struct Index {
  @State private selectedTab: EggNavTab = EggNavTab.HOME;

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      this.CurrentPage()

      EggBottomNav({
        selected: this.selectedTab,
        onSelected: (tab: EggNavTab) => {
          this.selectedTab = tab;
        }
      })
        .margin({ bottom: 18 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private CurrentPage() {
    if (this.selectedTab === EggNavTab.HOME) {
      HomePage()
    } else if (this.selectedTab === EggNavTab.DEVICES) {
      DevicesPage()
    } else {
      SettingsPage()
    }
  }
}
