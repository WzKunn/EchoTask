import { promptAction } from '@kit.ArkUI';
import { speechRecognizer } from '@kit.CoreSpeechKit';
import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { NLPUtils } from '../utils/NLPUtils';
import { TaskItem } from '../pages/HomeView';
import { taskStore } from '../utils/TaskStore';
import { TimeUtils } from '../utils/TimeUtils';
import { IntentManager } from '../utils/IntentManager';
import { window } from '@kit.ArkUI';

@Builder
export function AddTaskPageBuilder() {
  AddTaskPage()
}

@Component
struct AddTaskPage {
  pathStack: NavPathStack = new NavPathStack();

  // --- 模式与录音状态 ---
  @State inputMode: string = 'voice';        // 'voice' | 'manual'
  @State isListening: boolean = false;
  @State recognizedText: string = '';
  @State analyzedTask: TaskItem | null = null;
  private asrEngine: speechRecognizer.SpeechRecognitionEngine | undefined = undefined;
  @State sessionId: string = 'echo_task_session';

  // --- 可编辑表单字段 ---
  @State editContent: string = '';
  @State editDate: string = '';
  @State editTime: string = '';
  @State editTags: string[] = [];
  @State newTagInput: string = '';
  @State showForm: boolean = false;          // 语音模式下是否已完成解析并展示表单

  // ========================
  //  生命周期
  // ========================

  async aboutToAppear() {
    let hasMicPermission = await this.checkAndRequestMicPermission();
    if (!hasMicPermission) {
      await this.requestMicPermission();
    }
    this.initASREngine();
  }

  aboutToDisappear() {
    if (this.asrEngine) {
      this.asrEngine.shutdown();
    }
  }

  // ========================
  //  工具方法
  // ========================

  private getTodayDateStr(): string {
    let now = new Date();
    let y = now.getFullYear().toString();
    let m = String(now.getMonth() + 1).padStart(2, '0');
    let d = String(now.getDate()).padStart(2, '0');
    return y + '-' + m + '-' + d;
  }

  private resetFormToDefaults() {
    this.editContent = '';
    this.editDate = this.getTodayDateStr();
    this.editTime = '09:00';
    this.editTags = [];
    this.newTagInput = '';
    this.showForm = true;
  }

  private populateFormFromTask(task: TaskItem) {
    this.editContent = task.content;
    // 从时间戳反解出日期和时间字符串
    let d = new Date(task.timestamp);
    let y = d.getFullYear().toString();
    let mo = String(d.getMonth() + 1).padStart(2, '0');
    let da = String(d.getDate()).padStart(2, '0');
    this.editDate = y + '-' + mo + '-' + da;
    let h = String(d.getHours()).padStart(2, '0');
    let mi = String(d.getMinutes()).padStart(2, '0');
    this.editTime = h + ':' + mi;
    // 复制标签数组
    let tagsCopy: string[] = [];
    for (let t of task.tags) {
      tagsCopy.push(t);
    }
    this.editTags = tagsCopy;
    this.showForm = true;
  }

  private addTag() {
    let input = this.newTagInput.trim();
    if (input.length > 0) {
      let newTags: string[] = [];
      for (let t of this.editTags) {
        newTags.push(t);
      }
      let splitTags = input.split(/[\s,，]+/);
      for (let tag of splitTags) {
        let trimmed = tag.trim();
        if (trimmed.length > 0 && newTags.indexOf(trimmed) < 0) {
          newTags.push(trimmed);
        }
      }
      this.editTags = newTags;
      this.newTagInput = '';
    }
  }

  private removeTag(tagToRemove: string) {
    let newTags: string[] = [];
    for (let t of this.editTags) {
      if (t !== tagToRemove) {
        newTags.push(t);
      }
    }
    this.editTags = newTags;
  }

  // ========================
  //  权限相关
  // ========================

  async requestMicPermission() {
    let context = getContext(this) as common.UIAbilityContext;
    let atManager = abilityAccessCtrl.createAtManager();
    try {
      await atManager.requestPermissionsFromUser(context, ['ohos.permission.MICROPHONE']);
      console.info('麦克风权限申请成功');
    } catch (err) {
      console.error('麦克风权限被拒绝', err);
      promptAction.showToast({ message: '需要麦克风权限才能语音记事哦' });
    }
  }

  async checkAndRequestMicPermission(): Promise<boolean> {
    let context = getContext(this) as common.UIAbilityContext;
    let atManager = abilityAccessCtrl.createAtManager();
    let tokenID = context.applicationInfo.accessTokenId;
    let checkResult = await atManager.checkAccessToken(tokenID, 'ohos.permission.MICROPHONE');
    if (checkResult === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
      return true;
    }
    try {
      await atManager.requestPermissionOnSetting(context, ['ohos.permission.MICROPHONE']);
      let checkResult1 = await atManager.checkAccessToken(tokenID, 'ohos.permission.MICROPHONE');
      if (checkResult1 === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        return true;
      } else {
        promptAction.showToast({ message: '您拒绝了麦克风权限，无法录音' });
        return false;
      }
    } catch (err) {
      console.error('申请流程发生异常', err);
      return false;
    }
  }

  // ========================
  //  语音识别引擎
  // ========================

  initASREngine() {
    let extraParam: Record<string, Object> = { "locate": "CN", "recognizerMode": "short" };
    let initParams: speechRecognizer.CreateEngineParams = {
      language: 'zh-CN',
      online: 1,
      extraParams: extraParam
    };

    speechRecognizer.createEngine(initParams, (err, speechRecognitionEngine:
      speechRecognizer.SpeechRecognitionEngine) => {
      if (err) {
        console.error('ASR引擎创建失败:', err);
        return;
      }
      this.asrEngine = speechRecognitionEngine;
      console.info('ASR引擎创建成功');

      this.asrEngine.setListener({
        onStart: (sessionId: string, eventMessage: string) => {
          console.info('引擎准备就绪，开始录音: ' + sessionId);
        },
        onEvent: (sessionId: string, eventCode: number, eventMessage: string) => {
          console.info('引擎事件触发: ' + eventCode + ' - ' + eventMessage);
        },
        onResult: (sessionId: string, result: speechRecognizer.SpeechRecognitionResult) => {
          this.recognizedText = result.result;
        },
        onComplete: (sessionId: string, message: string) => {
          console.info('语音识别彻底完成');
          this.processTextToTask(this.recognizedText);
        },
        onError: (sessionId: string, errorCode: number, errorMessage: string) => {
          console.error('识别错误: ' + errorCode + ' - ' + errorMessage);
          promptAction.showToast({ message: '没听清，请再说一遍' });
        }
      });
    });
  }

  // ========================
  //  主 UI 构建
  // ========================

  build() {
    NavDestination() {
      Column() {
        // --- 模式切换器 ---
        this.ModeSelector()

        if (this.inputMode === 'voice') {
          if (!this.showForm) {
            // 语音录制区域
            this.VoiceRecordArea()
          } else {
            // 语音识别完成 → 可编辑表单
            Scroll() {
              Column() {
                // 原始识别文本参考
                if (this.recognizedText.length > 0 && this.recognizedText !== '正在听...') {
                  Row({ space: 6 }) {
                    SymbolGlyph($r('sys.symbol.mic_fill'))
                      .fontSize(12)
                      .fontColor(['#94a3b8'])
                    Text('原始语音："' + this.recognizedText + '"')
                      .fontSize(12)
                      .fontColor('#94a3b8')
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                  }
                  .width('90%')
                  .padding({ top: 4, bottom: 4 })
                }

                // 重新录制按钮
                Row({ space: 6 }) {
                  SymbolGlyph($r('sys.symbol.mic_fill'))
                    .fontSize(14)
                    .fontColor(['#3b82f6'])
                  Text('重新录制')
                    .fontSize(13)
                    .fontColor('#3b82f6')
                    .fontWeight(FontWeight.Medium)
                }
                .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                .backgroundColor('#eff6ff')
                .borderRadius(20)
                .margin({ top: 8, bottom: 16 })
                .onClick(() => {
                  this.showForm = false;
                  this.recognizedText = '';
                  this.analyzedTask = null;
                  this.editContent = '';
                  this.editDate = '';
                  this.editTime = '';
                  this.editTags = [];
                  this.newTagInput = '';
                })

                // 可编辑表单
                this.EditableForm()
              }
              .width('100%')
              .alignItems(HorizontalAlign.Center)
            }
            .layoutWeight(1)
            .scrollBar(BarState.Off)
          }
        } else {
          // 手动输入模式 → 直接展示表单
          Scroll() {
            Column() {
              this.EditableForm()
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .height('100%')
    }
    .linearGradient({
      direction: GradientDirection.LeftTop,
      colors: [
        ['#F0F9FF', 0.0],
        ['#E0F2FE', 0.4],
        ['#F9FAFB', 0.9]
      ]
    })
    .title('新日程')
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
  }

  // ========================
  //  模式切换器 UI
  // ========================

  @Builder ModeSelector() {
    Row() {
      // 语音输入 Tab
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.mic_fill'))
          .fontSize(15)
          .fontColor([this.inputMode === 'voice' ? Color.White : '#64748b'])
        Text('语音输入')
          .fontSize(14)
          .fontWeight(this.inputMode === 'voice' ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.inputMode === 'voice' ? Color.White : '#64748b')
      }
      .height(42)
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.inputMode === 'voice' ? '#3b82f6' : Color.Transparent)
      .borderRadius(16)
      .animation({ duration: 250, curve: Curve.EaseInOut })
      .onClick(() => {
        if (this.inputMode !== 'voice') {
          this.inputMode = 'voice';
          this.showForm = false;
          this.recognizedText = '';
          this.analyzedTask = null;
          this.editContent = '';
          this.editDate = '';
          this.editTime = '';
          this.editTags = [];
          this.newTagInput = '';
        }
      })

      // 手动输入 Tab
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(15)
          .fontColor([this.inputMode === 'manual' ? Color.White : '#64748b'])
        Text('手动输入')
          .fontSize(14)
          .fontWeight(this.inputMode === 'manual' ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.inputMode === 'manual' ? Color.White : '#64748b')
      }
      .height(42)
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.inputMode === 'manual' ? '#3b82f6' : Color.Transparent)
      .borderRadius(16)
      .animation({ duration: 250, curve: Curve.EaseInOut })
      .onClick(() => {
        if (this.inputMode !== 'manual') {
          this.inputMode = 'manual';
          this.resetFormToDefaults();
        }
      })
    }
    .width('90%')
    .padding(4)
    .backgroundColor('#F1F5F9')
    .borderRadius(20)
    .margin({ top: 16, bottom: 12 })
  }

  // ========================
  //  语音录制区域
  // ========================

  @Builder VoiceRecordArea() {
    // 中央提示 / 识别中文字
    Column() {
      if (this.isListening) {
        // 正在录音中
        Column({ space: 12 }) {
          Text(this.recognizedText.length > 0 && this.recognizedText !== '正在听...'
            ? this.recognizedText : '正在聆听...')
            .fontSize(20)
            .fontColor('#3b82f6')
            .fontWeight(FontWeight.Medium)
            .textAlign(TextAlign.Center)
            .padding({ left: 30, right: 30 })
            .animation({ duration: 200, curve: Curve.EaseOut })

          // 录音中提示
          Text('松手结束录音')
            .fontSize(13)
            .fontColor('#94a3b8')
        }
      } else if (this.recognizedText.length > 0 && this.recognizedText !== '正在听...') {
        // 录完等待解析
        Column({ space: 12 }) {
          Text(this.recognizedText)
            .fontSize(20)
            .fontColor('#3b82f6')
            .fontWeight(FontWeight.Medium)
            .textAlign(TextAlign.Center)
            .padding({ left: 30, right: 30 })
          Text('正在分析语义...')
            .fontSize(14)
            .fontColor('#94a3b8')
        }
      } else {
        // 未开始录音
        Column({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.mic_fill'))
            .fontSize(48)
            .fontColor(['#cbd5e1'])
          Text('长按下方按钮，说出你的安排')
            .fontSize(15)
            .fontColor('#94a3b8')
            .margin({ top: 8 })
        }
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)

    // 底部麦克风按钮
    Column() {
      Stack() {
        // 脉冲波纹
        if (this.isListening) {
          Circle()
            .width(110)
            .height(110)
            .fill('#3b82f6')
            .opacity(0.08)
          Circle()
            .width(96)
            .height(96)
            .fill('#3b82f6')
            .opacity(0.14)
        }

        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.mic_fill'))
            .fontSize(35)
            .fontColor([Color.White])
        }
        .width(80)
        .height(80)
        .backgroundColor(this.isListening ? '#ef4444' : '#3b82f6')
        .shadow({
          radius: 20,
          color: this.isListening ? 'rgba(239,68,68,0.3)' : 'rgba(59,130,246,0.3)',
          offsetY: 6
        })
        .animation({ duration: 200, curve: Curve.EaseOut })
        .gesture(
          LongPressGesture()
            .onAction(async () => {
              let hasPermission = await this.checkAndRequestMicPermission();
              if (hasPermission) {
                this.isListening = true;
                this.recognizedText = '正在听...';
                let audioParam: speechRecognizer.AudioInfo = {
                  audioType: 'pcm', sampleRate: 16000, soundChannel: 1, sampleBit: 16
                };
                let extraParam: Record<string, Object> = {
                  'recognitionMode': 0,
                  'vadBegin': 2000,
                  'vadEnd': 3000,
                  'maxAudioDuration': 20000
                };
                let startParams: speechRecognizer.StartParams = {
                  sessionId: this.sessionId,
                  audioInfo: audioParam,
                  extraParams: extraParam
                };
                this.asrEngine?.startListening(startParams);
              } else {
                console.warn('无权限，放弃录音执行');
              }
            })
            .onActionEnd(() => {
              if (this.isListening) {
                this.isListening = false;
                this.asrEngine?.finish(this.sessionId);
              }
            })
        )
      }
    }
    .margin({ bottom: 50 })
  }

  // ========================
  //  可编辑表单（语音结果 / 手动输入 共用）
  // ========================

  @Builder EditableForm() {
    Column() {
      // --- 表单标题 ---
      Row({ space: 8 }) {
        Text(this.inputMode === 'voice' ? '📋' : '✏️')
          .fontSize(20)
        Text(this.inputMode === 'voice' ? 'AI 识别结果' : '添加新日程')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1e293b')
      }
      .width('100%')
      .margin({ bottom: 24 })

      // --- 事件内容 ---
      Column({ space: 8 }) {
        Row({ space: 4 }) {
          Text('📝')
            .fontSize(13)
          Text('事件内容')
            .fontSize(13)
            .fontColor('#64748b')
            .fontWeight(FontWeight.Medium)
        }

        TextInput({ placeholder: '请输入日程内容...', text: $$this.editContent })
          .height(50)
          .fontSize(16)
          .fontColor('#1e293b')
          .placeholderColor('#94a3b8')
          .backgroundColor('#F1F5F9')
          .borderRadius(14)
          .padding({ left: 16, right: 16 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      // --- 日期与时间 ---
      Row({ space: 12 }) {
        // 日期输入
        Column({ space: 8 }) {
          Row({ space: 4 }) {
            Text('📅')
              .fontSize(13)
            Text('日期')
              .fontSize(13)
              .fontColor('#64748b')
              .fontWeight(FontWeight.Medium)
          }

          TextInput({ placeholder: 'YYYY-MM-DD', text: $$this.editDate })
            .height(50)
            .fontSize(15)
            .fontColor('#1e293b')
            .placeholderColor('#94a3b8')
            .backgroundColor('#F1F5F9')
            .borderRadius(14)
            .padding({ left: 16, right: 16 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        // 时间输入
        Column({ space: 8 }) {
          Row({ space: 4 }) {
            Text('⏰')
              .fontSize(13)
            Text('时间')
              .fontSize(13)
              .fontColor('#64748b')
              .fontWeight(FontWeight.Medium)
          }

          TextInput({ placeholder: 'HH:mm', text: $$this.editTime })
            .height(50)
            .fontSize(15)
            .fontColor('#1e293b')
            .placeholderColor('#94a3b8')
            .backgroundColor('#F1F5F9')
            .borderRadius(14)
            .padding({ left: 16, right: 16 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .margin({ top: 20 })

      // --- 标签管理 ---
      Column({ space: 10 }) {
        Row({ space: 4 }) {
          Text('🏷️')
            .fontSize(13)
          Text('标签')
            .fontSize(13)
            .fontColor('#64748b')
            .fontWeight(FontWeight.Medium)
        }

        Flex({ wrap: FlexWrap.Wrap }) {
          // 已有标签胶囊
          ForEach(this.editTags, (tag: string) => {
            Row({ space: 6 }) {
              Text(tag)
                .fontSize(13)
                .fontColor('#3b82f6')
                .fontWeight(FontWeight.Medium)
              Text('×')
                .fontSize(16)
                .fontColor('#93c5fd')
                .fontWeight(FontWeight.Bold)
                .onClick(() => {
                  this.removeTag(tag);
                })
            }
            .padding({ left: 14, right: 10, top: 7, bottom: 7 })
            .backgroundColor('#eff6ff')
            .borderRadius(20)
            .border({ width: 0.5, color: '#dbeafe' })
            .margin({ right: 8, bottom: 8 })
            .animation({ duration: 200, curve: Curve.EaseOut })
          }, (tag: string) => tag)

          // 添加标签输入框
          TextInput({ placeholder: '+ 添加标签', text: $$this.newTagInput })
            .width(140)
            .height(36)
            .fontSize(13)
            .fontColor('#1e293b')
            .placeholderColor('#94a3b8')
            .backgroundColor('#F1F5F9')
            .borderRadius(20)
            .padding({ left: 14, right: 14 })
            .enterKeyType(EnterKeyType.Done)
            .onSubmit((enterKey: EnterKeyType) => {
              this.addTag();
            })
            .margin({ bottom: 8 })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ top: 20 })

      // --- 确认添加按钮 ---
      Button('确认添加')
        .width('100%')
        .height(52)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .backgroundColor('#3b82f6')
        .borderRadius(16)
        .shadow({ radius: 14, color: 'rgba(59,130,246,0.25)', offsetY: 4 })
        .margin({ top: 32 })
        .onClick(() => {
          this.confirmAddTask();
        })
    }
    .width('90%')
    .padding(24)
    .backgroundColor(Color.White)
    .borderRadius(24)
    .shadow({ radius: 20, color: 'rgba(0,0,0,0.06)', offsetY: 4 })
    .margin({ top: 8, bottom: 30 })
    .transition({ type: TransitionType.All, opacity: 0, scale: { x: 0.95, y: 0.95 } })
  }

  // ========================
  //  核心逻辑
  // ========================

  // 语音文本 → 结构化任务 → 填充表单
  async processTextToTask(text: string) {
    if (!text || text === '正在听...') {
      promptAction.showToast({ message: '未识别到语音，请重试' });
      this.recognizedText = '';
      return;
    }
    promptAction.showToast({ message: '正在提取时间与意图...' });

    try {
      let parsedTask = await NLPUtils.analyzeTaskSemantic(text);
      this.analyzedTask = parsedTask;
      // 将解析结果自动填入可编辑表单
      this.populateFormFromTask(parsedTask);
    } catch (error) {
      console.error('NLP 解析失败', error);
      promptAction.showToast({ message: '语义太复杂啦，请换个说法' });
    }
  }

  // 从编辑字段组装 TaskItem 并写入数据库
  async confirmAddTask() {
    // 内容校验
    if (this.editContent.trim().length === 0) {
      promptAction.showToast({ message: '请输入日程内容' });
      return;
    }

    // 从日期 + 时间字段安全计算时间戳（使用 Date 构造函数，避免跨平台字符串解析异常）
    let timestamp = 0;
    try {
      let dateParts = this.editDate.split('-');
      let timeParts = this.editTime.split(':');
      if (dateParts.length >= 3 && timeParts.length >= 2) {
        let year = parseInt(dateParts[0]);
        let month = parseInt(dateParts[1]) - 1; // JS Date 月份为 0-11
        let day = parseInt(dateParts[2]);
        let hour = parseInt(timeParts[0]);
        let minute = parseInt(timeParts[1]);
        timestamp = new Date(year, month, day, hour, minute, 0).getTime();
      } else {
        timestamp = new Date(this.editDate + 'T' + this.editTime + ':00').getTime();
      }
    } catch (e) {
      timestamp = 0;
    }

    if (isNaN(timestamp) || timestamp <= 0) {
      // 时间格式无效，兜底使用当前时间
      timestamp = Date.now();
      promptAction.showToast({ message: '时间格式有误，已使用当前时间' });
    }

    // 整理标签数组（深拷贝脱离 ObservedArray 代理，防止数据库 JSON 序列化异常，同时自动收取未按回车提交的标签）
    let tagsList: string[] = [];
    for (let t of this.editTags) {
      tagsList.push(t);
    }
    let remainingTag = this.newTagInput.trim();
    if (remainingTag.length > 0) {
      let splitTags = remainingTag.split(/[\s,，]+/);
      for (let tag of splitTags) {
        let trimmed = tag.trim();
        if (trimmed.length > 0 && tagsList.indexOf(trimmed) < 0) {
          tagsList.push(trimmed);
        }
      }
    }

    let taskId = Date.now().toString();
    let timeDisplay = this.editDate + ' ' + this.editTime;
    let newTask = new TaskItem(
      taskId,
      this.editContent.trim(),
      timeDisplay,
      timestamp,
      tagsList
    );

    // 写入数据库
    await taskStore.insertTask(newTask);
    
    // 共享意图至小艺建议
    let context = getContext(this) as common.UIAbilityContext;
    IntentManager.shareTaskIntent(context, newTask);

    // 更新全局内存列表 (通过新建数组以确保触发 AppStorage 监听刷新)
    let currentTasks = AppStorage.get<TaskItem[]>('taskList') || [];
    let updatedTasks: TaskItem[] = [newTask];
    for (let t of currentTasks) {
      updatedTasks.push(t);
    }
    AppStorage.setOrCreate('taskList', updatedTasks);

    promptAction.showToast({ message: '添加成功' });
    this.pathStack.pop();
  }
}