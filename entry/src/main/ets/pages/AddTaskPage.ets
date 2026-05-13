import { promptAction } from '@kit.ArkUI';

@Builder
export function AddTaskPageBuilder() {
  AddTaskPage()
}

class TaskItem {
  public id: string;
  public content: string; // 任务内容
  public time: string;    // 时间
  public tags: string[];  // 自动提取的标签

  constructor(id: string, content: string, time: string, tags: string[]) {
    this.id = id;
    this.content = content;
    this.time = time;
    this.tags = tags;
  }
}

@Component
struct AddTaskPage {
  pathStack : NavPathStack = new NavPathStack();

  @State isListening: boolean = false;
  @State analyzedTask: TaskItem | null = null;


  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        // --- 背景层 ---
        Column().width('100%').height('100%').backgroundColor('#F8FAFC')

        // --- 内容层 ---
        Column() {
          Text('语音添加日程')
            .fontSize(24).fontWeight(FontWeight.Bold).margin({ top: 40 })

          Text('长按下方按钮，说出你的安排')
            .fontSize(14).fontColor('#94a3b8').margin({ top: 8, bottom: 40 })

          if (this.analyzedTask) {
            Column() {
              Text('AI 识别结果').fontSize(12).fontColor('#3b82f6').margin({ bottom: 10 })
              Text(this.analyzedTask.content).fontSize(18).fontWeight(FontWeight.Medium)
              Text(`预设时间：${this.analyzedTask.time}`).fontSize(14).margin({ top: 10 }).fontColor('#64748b')

              Button('确认添加并返回')
                .margin({ top: 25 })
                .width('100%')
                .backgroundColor('#3b82f6')
                .onClick(() => {
                  this.confirmAddTask();
                })
            }
            .width('90%')
            .padding(25)
            .backgroundColor(Color.White)
            .borderRadius(24)
            .shadow({ radius: 20, color: 'rgba(0,0,0,0.05)' })
            .transition({ type: TransitionType.All, opacity: 0, scale: { x: 0.9, y: 0.9 } })
          }
        }
        .width('100%')
        .height('100%')

        // --- 底部确认按钮 ---
        Column() {
          if (this.isListening) {
            // 模拟波纹动效
            Circle().width(100).height(100).fill('#3b82f6').opacity(0.2).scale({x: 1.2, y: 1.2})
          }

          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.mic_fill')).fontSize(35).fontColor([Color.White])
          }
          .width(80).height(80)
          .backgroundColor(this.isListening ? '#ef4444' : '#3b82f6')
          .margin({ bottom: 50 })
          .gesture(
            LongPressGesture()
              .onAction(() => { this.isListening = true; })
              .onActionEnd(() => {
                this.isListening = false;
                this.onVoiceFinish();
              })
          )
        }
      }
    }
    .title('新日程')
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
  }
  // 模拟语音识别及端侧 AI 分析
  onVoiceFinish() {
    // 这里未来接入 Speech Kit 和 CoreText Kit
    setTimeout(() => {
      this.analyzedTask = new TaskItem(
        Date.now().toString(),
        "完成 Git 冲突处理笔记",
        "今天 18:00",
        ["待分类", "AI提取"]
      );
    }, 500);
  }

  confirmAddTask() {
    if (this.analyzedTask) {
      // 从全局存储中拿到列表并更新
      let currentTasks = AppStorage.get<TaskItem[]>('taskList') || [];
      currentTasks.unshift(this.analyzedTask);
      AppStorage.setOrCreate('taskList', currentTasks);

      promptAction.showToast({ message: '添加成功' });
      this.pathStack.pop(); // 返回主界面
    }
  }
}