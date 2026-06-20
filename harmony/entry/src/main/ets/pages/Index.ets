import { HomePage } from './HomePage';

@Entry
@Component
struct Index {
  build() {
    Stack() {
      HomePage()
    }
    .width('100%')
    .height('100%')
  }
}
