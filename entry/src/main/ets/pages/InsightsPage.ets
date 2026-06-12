import { taskStore } from '../utils/TaskStore';
import { TaskItem } from './HomeView';
import { TimeUtils } from '../utils/TimeUtils';
import { window } from '@kit.ArkUI';

@Builder
export function InsightsPageBuilder() {
  InsightsPage()
}

@Component
export struct InsightsPage {
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  @State totalTasks: number = 0;
  @State completedTasks: number = 0;
  @State pendingTasks: number = 0;
  @State completionRate: number = 0;
  @State recentTasks: TaskItem[] = [];

  onShown() {
    this.loadData();
  }

  async loadData() {
    const allTasks = await taskStore.queryAllTasks();
    this.totalTasks = allTasks.length;
    this.completedTasks = allTasks.filter(t => t.isCompleted).length;
    this.pendingTasks = this.totalTasks - this.completedTasks;
    this.completionRate = this.totalTasks === 0 ? 0 : Math.round((this.completedTasks / this.totalTasks) * 100);
    
    // 获取最近5条已完成任务
    this.recentTasks = allTasks.filter(t => t.isCompleted).slice(0, 5);
  }

  build() {
    NavDestination() {
      Column({ space: 20 }) {
        // 数据看板：环形进度条
        Stack({ alignContent: Alignment.Center }) {
          DataPanel({
            values: [this.completedTasks, this.pendingTasks],
            max: this.totalTasks > 0 ? this.totalTasks : 1,
            type: DataPanelType.Line
          })
          .width('100%')
          .height(100)
          .valueColors([$r('app.color.success_color'), $r('app.color.divider_color')]) // 绿色和浅灰色

          Column() {
            Text(this.completionRate + '%')
              .fontSize(36)
              .fontWeight(FontWeight.Bolder)
              .fontColor($r('app.color.success_color'))
            Text('完成率')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
        }
        .width('100%')
        .padding(20)
        .backgroundColor($r('app.color.card_bg'))
        .borderRadius(20)
        .shadow({ radius: 10, color: 'rgba(0,0,0,0.05)', offsetY: 5 })

        // 数据卡片：总览
        Row({ space: 15 }) {
          Column() {
            Text('总任务数').fontSize(13).fontColor($r('app.color.text_secondary')).margin({ bottom: 8 })
            Text(this.totalTasks.toString()).fontSize(28).fontWeight(FontWeight.Bold).fontColor($r('app.color.brand_primary'))
          }
          .layoutWeight(1).padding(20).backgroundColor($r('app.color.card_bg')).borderRadius(16).shadow({ radius: 8, color: 'rgba(0,0,0,0.04)', offsetY: 4 }).alignItems(HorizontalAlign.Center)

          Column() {
            Text('待办任务').fontSize(13).fontColor($r('app.color.text_secondary')).margin({ bottom: 8 })
            Text(this.pendingTasks.toString()).fontSize(28).fontWeight(FontWeight.Bold).fontColor($r('app.color.warning_color'))
          }
          .layoutWeight(1).padding(20).backgroundColor($r('app.color.card_bg')).borderRadius(16).shadow({ radius: 8, color: 'rgba(0,0,0,0.04)', offsetY: 4 }).alignItems(HorizontalAlign.Center)

          Column() {
            Text('已完成').fontSize(13).fontColor($r('app.color.text_secondary')).margin({ bottom: 8 })
            Text(this.completedTasks.toString()).fontSize(28).fontWeight(FontWeight.Bold).fontColor($r('app.color.success_color'))
          }
          .layoutWeight(1).padding(20).backgroundColor($r('app.color.card_bg')).borderRadius(16).shadow({ radius: 8, color: 'rgba(0,0,0,0.04)', offsetY: 4 }).alignItems(HorizontalAlign.Center)
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)

        // 最近完成列表
        Column() {
          Text('近期完成里程碑')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .margin({ bottom: 15, top: 10 })

          if (this.recentTasks.length === 0) {
            Text('暂无已完成任务，继续加油！')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 20 })
          } else {
            List({ space: 10 }) {
              ForEach(this.recentTasks, (task: TaskItem) => {
                ListItem() {
                  Row() {
                    SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
                      .fontSize(20)
                      .fontColor([$r('app.color.success_color')])
                      .margin({ right: 10 })
                    Column() {
                      Text(task.content)
                        .fontSize(16)
                        .fontColor($r('app.color.text_primary'))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(TimeUtils.formatTimestamp(task.timestamp))
                        .fontSize(12)
                        .fontColor($r('app.color.text_secondary'))
                        .margin({ top: 4 })
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                  }
                  .width('100%')
                  .padding(15)
                  .backgroundColor($r('app.color.card_bg'))
                  .borderRadius(12)
                  .shadow({ radius: 5, color: 'rgba(0,0,0,0.03)', offsetY: 2 })
                }
              }, (task: TaskItem) => task.id)
            }
            .width('100%')
            .layoutWeight(1)
            .scrollBar(BarState.Off)
          }
        }
        .width('100%')
        .layoutWeight(1)

      }
      .width('100%')
      .height('100%')
      .padding({ top: 30, left: 24, right: 24 })
    }
    .linearGradient({
      direction: GradientDirection.LeftTop,
      colors: [
        [$r('app.color.page_gradient_start'), 0.0],
        [$r('app.color.page_gradient_start'), 0.4],
        [$r('app.color.page_gradient_end'), 0.9]
      ]
    })
    .title('数据洞察')
    .onShown(() => {
      this.loadData();
    })
  }

}
