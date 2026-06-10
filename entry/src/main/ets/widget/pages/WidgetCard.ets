@Entry
@Component
struct WidgetCard {
  @LocalStorageProp('taskTitle') taskTitle: string = '暂无待办日程';
  @LocalStorageProp('taskTime') taskTime: string = '点击添加新任务';
  @LocalStorageProp('taskCount') taskCount: string = '0';

  build() {
    Column() {
      // 头部区域：Logo + 应用名 + 日程数量
      Row() {
        Image($r('app.media.foreground'))
          .width(22)
          .height(22)
          .margin({ right: 6 })

        Text('EchoTask')
          .fontSize(13)
          .fontColor('#ffffffcc')
          .fontWeight(FontWeight.Bold)

        Blank()

        Text(this.taskCount + ' 项待办')
          .fontSize(11)
          .fontColor('#ffffff99')
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 14, bottom: 6 })

      // 分隔线
      Divider()
        .width('85%')
        .strokeWidth(0.5)
        .color('#ffffff30')

      // 日程内容区
      Column() {
        Text(this.taskTitle)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#ffffffe6')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.taskTime)
          .fontSize(11)
          .fontColor('#ffffff99')
          .margin({ top: 6 })
      }
      .width('100%')
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 14, right: 14, top: 8, bottom: 14 })
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height('100%')
    .borderRadius(16)
    .linearGradient({
      angle: 135,
      colors: [
        ['#a8d8ea', 0.0],
        ['#c3bef7', 0.5],
        ['#e8c8f8', 1.0]
      ]
    })
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: {
          message: 'From Widget'
        }
      });
    })
  }
}
