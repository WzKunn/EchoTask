import router from '@ohos.router';
import { promptAction, SymbolGlyphModifier, TextModifier } from '@kit.ArkUI';
import { HdsListItem } from '@kit.UIDesignKit';
import { calendarMgr } from '../utils/CalendarManager';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';

// 数据模型 日程任务
export class TaskItem {
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
export struct HomeView {

  pathStack : NavPathStack = new NavPathStack();

  @State dataSource: LazyDataSource<TaskItem> = new LazyDataSource();
  @State isListening: boolean = false;
  // 使用 StorageLink 绑定全局任务列表，实现跨页面同步
  @StorageLink('taskList') @Watch('onTasksChange') tasks: TaskItem[] = [];

  // 2. 定义监听回调函数
  // 当 AppStorage 里的 taskList 发生任何改变（添加、删除、替换）时，都会触发此函数
  onTasksChange() {
    console.info('数据已同步更新，正在刷新列表...');
    // 手动同步数据源并触发 LazyForEach 刷新
    this.dataSource.setItems(this.tasks);
  }

  async aboutToAppear() {

    if (this.tasks.length === 0) {
      this.tasks = [
        new TaskItem('1', '修复 MiniEngine 向量数学模块报错', '明天 09:00', ['技术', '紧急']),
        new TaskItem('2', '复习 C++ 算法：优先队列优化', '后天 14:30', ['学习'])
      ];
      AppStorage.setOrCreate('taskList', this.tasks);
    }
    // 将数据源与全局状态同步
    this.dataSource.setItems(this.tasks);
    try {
      let haspermission = await this.checkAndRequestCalendarPermission();
      if (haspermission) {
        // 初始化日历服务
        await calendarMgr.init(getContext(this) as common.UIAbilityContext);
      } else {
        console.error('未授权日历权限');
      }
    } catch (err) {
      console.error('日历初始化失败', err);
    }
  }

  // 自定义左滑按钮
  @Builder swipeActionsBuilder(task: TaskItem) {
    Row() {
      // 添加至日历按钮
      Button() {
        SymbolGlyph($r('sys.symbol.calendar_badge_plus')).fontColor([Color.White])
      }
      .backgroundColor('#3b82f6')
      .width(75)
      .height('100%')
      .type(ButtonType.Normal)
      .onClick(async () => {
        let haspermission = await this.checkAndRequestCalendarPermission();
        if (haspermission) {
          let success = await calendarMgr.addEvent(task);
          if (success) {
            promptAction.showToast({ message: '已同步至系统日历' });
          }
        }
      })

      // 删除按钮
      // 按钮 2：删除任务 (警示红)
      Button() {
        SymbolGlyph($r('sys.symbol.trash')).fontColor([Color.White]).fontSize(24)
      }
      .backgroundColor('#ef4444')
      .width(75)
      .height('100%')
      .type(ButtonType.Normal)
      .onClick((item) => {
        // 1. 从全局大管家 AppStorage 里把当前的列表拿出来
        let currentTasks = AppStorage.get<TaskItem[]>('taskList') || [];

        // 2. 找到并剔除掉当前这一项 (利用 filter 过滤)
        // 只要 id 不等于当前这个任务 id 的，都保留下来
        let updatedTasks = currentTasks.filter(t => t.id !== task.id);

        // 3. 把更新后的新数组重新塞回 AppStorage
        // 重点：这一步执行后，HomeView 里的 @Watch('onTasksChange') 会瞬间被触发
        // 它会自动调用你的 dataSource.setItems(updatedTasks)，列表里的卡片就消失了
        AppStorage.setOrCreate('taskList', updatedTasks);

        promptAction.showToast({ message: '任务已删除' });
      })
    }
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {

      Column() {
        Text('EchoTask')
          .width('100%')
          .fontColor('#1e3a8a')
          .fontSize(32)
          .fontWeight(FontWeight.Bolder)
          .margin({ bottom: 20 })

        List({ space: 12 }) {
          LazyForEach(this.dataSource, (item: TaskItem) => {
            ListItem() {
              this.TaskCard(item)
            }
            .swipeAction({
              end: this.swipeActionsBuilder(item),
              edgeEffect: SwipeEdgeEffect.Spring
            })
          }, (item: TaskItem) => item.id)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .padding({ left: 24, right: 24 })

      // --- 底部双按钮区域 ---
      Row({ space: 20 }) {
        // 按钮 1：添加日程
        this.IconButton('添加日程', 'sys.symbol.plus', '#3b82f6', () => {
          this.pathStack.pushPathByName('AddTaskPage', null);
        })

        // 按钮 2：搜索日程 (进阶任务入口)
        this.IconButton('搜索回溯', 'sys.symbol.magnifyingglass', '#64748b', () => {
          promptAction.showToast({ message: '语义搜索功能开发中...' });
        })
      }
      .width('100%')
      .padding({ left: 30, right: 30, bottom: 40 })
      .justifyContent(FlexAlign.Center)

      // --- 3. 底部语音按钮 ---
      // this.VoiceButton()



    }
    .width('100%')
    .height('100%')
    .padding({ left: 20, right: 24 })
  }

  @Builder IconButton(text: string, icon: string, color: string, action: () => void) {
    Column() {
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r(icon)).fontSize(24).fontColor([Color.White])
      }
      .width(60).height(60)
      .backgroundColor(color)
      .shadow({ radius: 15, color: 'rgba(0,0,0,0.1)', offsetY: 8 })
      .onClick(action)

      Text(text).fontSize(12).margin({ top: 8 }).fontColor('#64748b')
    }
  }

  // 任务卡片 UI
  @Builder TaskCard(item: TaskItem) {
    Column() {
      Row() {
        Text(item.content)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1e293b')
          .layoutWeight(1)
      }
      .width('100%')

      Row() {
        Text(item.time)
          .fontSize(13)
          .fontColor('#64748b')

        Blank()

        ForEach(item.tags, (tag: string) => {
          Text(tag)
            .fontSize(10)
            .fontColor('#3b82f6')
            .backgroundColor('#eff6ff')
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .borderRadius(4)
            .margin({ left: 4 })
        })
      }
      .width('100%')
      .margin({ top: 10 })
    }
    .padding(20)
    .backgroundColor(Color.White)
    .borderRadius(20)
    .shadow({ radius: 8, color: 'rgba(0,0,0,0.05)', offsetY: 4 })
  }

  @Builder VoiceButton() {
    Column() {
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.mic_fill'))
          .fontSize(30)
          .fontColor([Color.White])
      }
      .width(70)
      .height(70)
      .backgroundColor(this.isListening ? '#ef4444' : '#3b82f6')
      .shadow({ radius: 20, color: 'rgba(59, 130, 246, 0.4)', offsetY: 8 })
      .gesture(
        LongPressGesture()
          .onAction(() => {
            this.isListening = true;
            // TODO: 调用 Speech Kit 开始录音
          })
          .onActionEnd(() => {
            this.isListening = false;
            // TODO: 停止录音，并把识别结果传给 CoreText 处理
            this.mockCreateTask("明天下午三点去机房调代码"); // 模拟识别成功
          })
      )
    }
    .margin({ bottom: 40 })
  }

  mockCreateTask(text: string) {
    // 实际开发中，这里调用 CoreTextKit 提取信息
    this.dataSource.pushItem(new TaskItem(
      Date.now().toString(),
      "新任务：" + text,
      "自动识别中...",
      ["待分类"]
    ));
    promptAction.showToast({ message: '已通过语音创建日程' });
  }

  @Builder deleteBuilder(item: TaskItem) {
    Button() {
      SymbolGlyph($r('sys.symbol.trash'))
    }
    .backgroundColor(Color.Red)
    .onClick(() => this.dataSource.deleteItem(item))
  }

  // 检测并请求日历权限
  async checkAndRequestCalendarPermission(): Promise<boolean> {
    let context = getContext(this) as common.UIAbilityContext;
    let atManager = abilityAccessCtrl.createAtManager();
    let tokenID = context.applicationInfo.accessTokenId;

    try {
      // 1. 先检查当前的读写权限状态
      let readCheck = await atManager.checkAccessToken(tokenID, 'ohos.permission.READ_CALENDAR');
      let writeCheck = await atManager.checkAccessToken(tokenID, 'ohos.permission.WRITE_CALENDAR');

      // 只要读和写都有权限，直接放行
      if (readCheck === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED &&
        writeCheck === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        return true;
      }

      // 2. 如果没有权限，发起弹窗申请 (同时申请读和写)
      let requestResult = await atManager.requestPermissionOnSetting(context, [
        'ohos.permission.READ_CALENDAR',
        'ohos.permission.WRITE_CALENDAR'
      ]);

      let checkResult_cld1 = await atManager.checkAccessToken(tokenID, 'ohos.permission.READ_CALENDAR');
      let checkResult_cld2 = await atManager.checkAccessToken(tokenID, 'ohos.permission.WRITE_CALENDAR');
      if (checkResult_cld1 === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED &&
          checkResult_cld2 === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        return true;
      } else {
        promptAction.showToast({ message: '您拒绝了麦克风权限，无法录音' });
        return false;
      }

    } catch (err) {
      console.error('日历权限申请发生异常:', err);
      return false;
    }
  }
}


export class LazyDataSource<T> implements IDataSource {
  private elements: T[];
  private listeners: Set<DataChangeListener>;

  constructor(elements: T[] = []) {
    this.elements = elements;
    this.listeners = new Set();
  }

  public totalCount(): number { return this.elements.length; }
  public getData(index: number): T { return this.elements[index]; }
  public indexOf(item: T): number { return this.elements.indexOf(item); }

  public pushItem(item: T) {
    this.elements.push(item);
    this.listeners.forEach(listener => listener.onDataAdd(this.elements.length - 1));
  }

  public deleteItem(item: T): void {
    const index = this.elements.indexOf(item);
    if (index < 0) return;
    this.elements.splice(index, 1);
    this.listeners.forEach(listener => listener.onDataDelete(index));
  }

  public setItems(items: T[]): void {
    this.elements = items;
    // 核心：调用 onDataReloaded 通知 LazyForEach 重新加载所有数据
    this.listeners.forEach(listener => listener.onDataReloaded());
  }

  public registerDataChangeListener(listener: DataChangeListener): void { this.listeners.add(listener); }
  public unregisterDataChangeListener(listener: DataChangeListener): void { this.listeners.delete(listener); }
}

