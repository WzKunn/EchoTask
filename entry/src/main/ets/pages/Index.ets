import { HomeView } from './HomeView'
import { MineView } from './MineView'

@Entry
@Component
struct Index {

  pathStack : NavPathStack = new NavPathStack();

  @State currentIndex: number = 0

  build() {

    Stack() {
      Row()
        .height('100%')
        .width('100%')
        .linearGradient({
          direction: GradientDirection.LeftTop,
          colors: [
            ['#F0F9FF', 0.0], // 极浅天蓝
            ['#E0F2FE', 0.4], // 原浅天蓝
            ['#F9FAFB', 0.9]  // 极淡暖白
          ]
        })

      Navigation(this.pathStack) {
        if (this.currentIndex === 0) {
          HomeView({ pathStack: this.pathStack })
        } else {
          MineView()
        }

      }
      .backgroundColor(Color.Transparent)
      .hideTitleBar(true)
      .padding({
        top: 40,
        bottom: 20
      })
      .toolbarConfiguration([
        {
          // $r("app.string.navigation_toolbar_add")和$r("app.media.ic_public_highlights_ed")需要替换为开发者所需的资源文件
          value: '探索',
          // icon: $r("app.media.ic_public_highlights_ed")
          action: () => {
            this.currentIndex = 0;
          }
        },
        {
          // $r("app.string.navigation_toolbar_app")和$r("app.media.ic_public_highlights")需要替换为开发者所需的资源文件
          value: '我的',
          action: () => {
            this.currentIndex = 1;
          }
          // icon: $r("app.media.ic_public_highlights")
        }
      ])
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}

