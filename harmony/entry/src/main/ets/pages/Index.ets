import { HomePage } from './HomePage';
import { SettingsPage } from './SettingsPage';

@Entry
@Component
struct Index {
  build() {
    Tabs({ barPosition: BarPosition.End }) {
      TabContent() {
        HomePage()
      }
      .tabBar('首页')

      TabContent() {
        SettingsPage()
      }
      .tabBar('设置')
    }
    .width('100%')
    .height('100%')
  }
}
