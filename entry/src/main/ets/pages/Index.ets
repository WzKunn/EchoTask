import { HomeView } from './HomeView'
import { ChatView } from './ChatPage'
import { MineView } from './MineView'

// 导航栏 Tab 项的数据结构
interface TabItemInfo {
  label: string;
  icon: string;       // 未选中图标
  activeIcon: string;  // 选中图标
}

@Entry
@Component
struct Index {

  pathStack: NavPathStack = new NavPathStack();

  @State currentIndex: number = 0

  // Tab 配置：统一管理图标和文案
  private tabItems: TabItemInfo[] = [
    { label: '日程', icon: 'sys.symbol.house', activeIcon: 'sys.symbol.house_fill' },
    { label: '对话', icon: 'sys.symbol.message', activeIcon: 'sys.symbol.message_fill' },
    { label: '我的', icon: 'sys.symbol.person', activeIcon: 'sys.symbol.person_fill' }
  ];

  build() {

    Stack({ alignContent: Alignment.Bottom }) {
      // --- 渐变背景层 ---
      Row()
        .height('100%')
        .width('100%')
        .linearGradient({
          direction: GradientDirection.LeftTop,
          colors: [
            ['#F0F9FF', 0.0],
            ['#E0F2FE', 0.4],
            ['#F9FAFB', 0.9]
          ]
        })

      // --- 主内容区 ---
      Navigation(this.pathStack) {
        if (this.currentIndex === 0) {
          HomeView({ pathStack: this.pathStack })
        } else if (this.currentIndex === 1) {
          ChatView()
        } else {
          MineView()
        }
      }
      .backgroundColor(Color.Transparent)
      .hideTitleBar(true)
      .hideToolBar(true) // 隐藏系统导航栏，用自定义的
      .padding({
        top: 40,
        bottom: 75 // 为自定义导航栏留出空间
      })

      // --- 自定义磨砂玻璃底部导航栏 ---
      this.FrostedTabBar()
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder FrostedTabBar() {
    Row() {
      ForEach(this.tabItems, (item: TabItemInfo, index: number) => {
        // 每个 Tab 按钮
        Column() {
          // 图标
          SymbolGlyph($r(this.currentIndex === index ? item.activeIcon : item.icon))
            .fontSize(22)
            .fontColor([this.currentIndex === index ? '#3b82f6' : '#94a3b8'])
            .animation({ duration: 250, curve: Curve.EaseOut })

          // 文字
          Text(item.label)
            .fontSize(11)
            .fontWeight(this.currentIndex === index ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.currentIndex === index ? '#3b82f6' : '#94a3b8')
            .margin({ top: 3 })
            .animation({ duration: 250, curve: Curve.EaseOut })
        }
        .layoutWeight(1)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        // 选中项背景胶囊高亮
        .backgroundColor(this.currentIndex === index ? 'rgba(59, 130, 246, 0.1)' : Color.Transparent)
        .borderRadius(18)
        .margin({ left: 6, right: 6 })
        .padding({ top: 8, bottom: 8 })
        .animation({ duration: 300, curve: Curve.EaseInOut })
        // 选中项微缩放效果
        .scale({ x: this.currentIndex === index ? 1.05 : 1.0, y: this.currentIndex === index ? 1.05 : 1.0 })
        .onClick(() => {
          this.currentIndex = index;
          this.pathStack.clear();
        })
      })
    }
    .width('92%')
    .height(62)
    .padding({ left: 6, right: 6 })
    // 磨砂玻璃核心样式
    .backgroundColor('rgba(255, 255, 255, 0.72)')
    .backdropBlur(25)
    .borderRadius(22)
    // 精致边框 + 阴影
    .border({ width: 0.5, color: 'rgba(255, 255, 255, 0.8)' })
    .shadow({ radius: 25, color: 'rgba(0, 0, 0, 0.08)', offsetY: 4 })
    .margin({ bottom: 28 })
  }
}
