import { promptAction } from '@kit.ArkUI';
import { speechRecognizer } from '@kit.CoreSpeechKit'; // 引入语音识别 Kit
import { abilityAccessCtrl, common } from '@kit.AbilityKit'; // 引入权限控制
import { NLPUtils } from '../utils/NLPUtils'; // 引入自然语言理解工具类
import { TaskItem } from '../pages/HomeView';
import { taskStore } from '../utils/TaskStore';

@Builder
export function AddTaskPageBuilder() {
  AddTaskPage()
}


@Component
struct AddTaskPage {
  pathStack : NavPathStack = new NavPathStack();

  @State isListening: boolean = false;
  @State analyzedTask: TaskItem | null = null;
  @State recognizedText: string = "";
  private asrEngine: speechRecognizer.SpeechRecognitionEngine | undefined = undefined;
  @State sessionId: string = 'echo_task_session'; // 会话ID

  async aboutToAppear() {
    let hasMicPermission = await this.checkAndRequestMicPermission();
    if (!hasMicPermission) {
      // 1. 页面加载时，动态向用户弹窗申请麦克风权限
      await this.requestMicPermission();
    }
    // 2. 初始化语音识别引擎
    this.initASREngine();
  }

  aboutToDisappear() {
    // 页面销毁时，必须释放引擎，防止内存泄漏和麦克风被占用
    if (this.asrEngine) {
      this.asrEngine.shutdown();
    }
  }

  // --- 申请权限 ---
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

  // 检测并请求麦克风权限
  async checkAndRequestMicPermission(): Promise<boolean> {
    let context = getContext(this) as common.UIAbilityContext;
    let atManager = abilityAccessCtrl.createAtManager();
    let tokenID = context.applicationInfo.accessTokenId;

    // 1. 先检查当前实时权限状态
    let checkResult = await atManager.checkAccessToken(tokenID, 'ohos.permission.MICROPHONE');

    if (checkResult === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
      return true; // 已经有权限，直接通过
    }

    // 2. 如果没有权限，发起弹窗申请
    try {
      // 再次申请权限
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

  // --- 核心：初始化语音识别引擎 ---
  initASREngine() {
    // 设置参数：中文、在线识别模式 (由于端侧模型较大，通常默认使用在线服务，速度极快)
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

      // 绑定监听器，接收语音识别的结果
      this.asrEngine.setListener({
        onStart: (sessionId: string, eventMessage: string) => {
          console.info(`引擎准备就绪，开始录音: ${sessionId}`);
        },
        onEvent: (sessionId: string, eventCode: number, eventMessage: string) => {
          console.info(`引擎事件触发: ${eventCode} - ${eventMessage}`);
        },
        // 当识别有进展时触发（比如你说了一半，它先识别出几个字）
        onResult: (sessionId: string, result: speechRecognizer.SpeechRecognitionResult) => {
          this.recognizedText = result.result; // 实时更新到 UI
        },
        // 当一句话说完，引擎判定结束时触发
        onComplete: (sessionId: string, message: string) => {
          console.info('语音识别彻底完成');
          this.processTextToTask(this.recognizedText); // 丢给 AI 去提取实体
        },
        onError: (sessionId: string, errorCode: number, errorMessage: string) => {
          console.error(`识别错误: ${errorCode} - ${errorMessage}`);
          promptAction.showToast({ message: '没听清，请再说一遍' });
        }
      });
    });
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        // --- 背景层 ---
        Column().width('100%').height('100%').backgroundColor('#F8FAFC')

        // --- 内容层 ---
        Column() {
          Text('语音添加日程')
            .fontSize(24).fontWeight(FontWeight.Bold).margin({ top: 40 })

          if (this.recognizedText) {
            Text(this.recognizedText)
              .fontSize(22)
              .fontColor('#3b82f6') // 科技感的蓝色
              .fontWeight(FontWeight.Medium)
              .margin({ top: 40, left: 20, right: 20 })
              .textAlign(TextAlign.Center)
              .animation({ duration: 200, curve: Curve.EaseOut }) // 加上极其丝滑的文字变换动画
          } else {
            Text('长按下方按钮，说出你的安排')
              .fontSize(14).fontColor('#94a3b8').margin({ top: 8, bottom: 40 })
          }

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

        // --- 底部录音按钮 ---
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
              .onAction(async () => {
                // 先检查权限
                let hasPermission = await this.checkAndRequestMicPermission();
                if (hasPermission) {
                  this.isListening = true;
                  this.recognizedText = "正在听...";
                  // 权限通过，启动引擎
                  let audioParam: speechRecognizer.AudioInfo = { audioType: 'pcm', sampleRate: 16000, soundChannel: 1, sampleBit: 16 };
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
                  // 权限没过，checkAndRequestMicPermission 内部已经弹了 Toast，这里保持静默即可
                  console.warn('无权限，放弃录音执行');
                }
              })
              .onActionEnd(() => {
                if (this.isListening) { // 只有在真正开始录音的情况下才结束
                  this.isListening = false;
                  this.asrEngine?.finish(this.sessionId);
                }
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

  // 文本转结构化任务，调用自然语言理解kit
  async processTextToTask(text: string) {
    if (!text || text === "正在听...") {
      promptAction.showToast({ message: '未识别到语音，请重试' });
      this.recognizedText = "";
      return;
    };
    promptAction.showToast({ message: '正在提取时间与意图...' });

    try {
      // 调用封装好的 NLP 引擎，利用 async/await 等待解析结果
      let parsedTask = await NLPUtils.analyzeTaskSemantic(text);

      // 将结构化的结果赋值给 UI 绑定的变量，触发确认卡片的显示
      this.analyzedTask = parsedTask;

    } catch (error) {
      console.error('NLP 解析失败', error);
      promptAction.showToast({ message: '语义太复杂啦，请换个说法' });
    }
  }

  async confirmAddTask() {
    if (this.analyzedTask) {
      // 写入数据库
      await taskStore.insertTask(this.analyzedTask);
      // 从全局存储中拿到列表并更新
      let currentTasks = AppStorage.get<TaskItem[]>('taskList') || [];
      currentTasks.unshift(this.analyzedTask);
      AppStorage.setOrCreate('taskList', currentTasks);

      promptAction.showToast({ message: '添加成功' });
      this.pathStack.pop(); // 返回主界面
    }
  }
}