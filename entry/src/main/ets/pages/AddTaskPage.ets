import { promptAction } from '@kit.ArkUI';
import { speechRecognizer } from '@kit.CoreSpeechKit';
import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { NLPUtils } from '../utils/NLPUtils';
import { TaskItem } from '../pages/HomeView';
import { taskStore } from '../utils/TaskStore';
import { TimeUtils } from '../utils/TimeUtils';
import { IntentManager } from '../utils/IntentManager';
import { window } from '@kit.ArkUI';
import { textRecognition } from '@kit.CoreVisionKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import picker from '@ohos.file.picker';
import { cameraPicker, camera } from '@kit.CameraKit';
import { BusinessError } from '@kit.BasicServicesKit';

@Builder
export function AddTaskPageBuilder() {
  AddTaskPage()
}

@Component
struct AddTaskPage {
  pathStack: NavPathStack = new NavPathStack();

  @StorageProp('isDarkMode') isDarkMode: boolean = false;

  // --- 模式与录音状态 ---
  @State inputMode: string = 'voice';        // 'voice' | 'image' | 'manual'
  @State isListening: boolean = false;
  @State isParsingImage: boolean = false;    // 图像识别 Loading 状态
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
                      .fontColor([$r('app.color.text_tertiary')])
                    Text('原始语音："' + this.recognizedText + '"')
                      .fontSize(12)
                      .fontColor($r('app.color.text_tertiary'))
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
                    .fontColor([$r('app.color.brand_primary')])
                  Text('重新录制')
                    .fontSize(13)
                    .fontColor($r('app.color.brand_primary'))
                    .fontWeight(FontWeight.Medium)
                }
                .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                .backgroundColor($r('app.color.brand_primary_bg'))
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
        } else if (this.inputMode === 'image') {
          if (!this.showForm) {
            // 图像识别区域
            this.ImageRecordArea()
          } else {
            // 图像识别完成 → 可编辑表单
            Scroll() {
              Column() {
                // 重新选择/拍照按钮
                Row({ space: 6 }) {
                  SymbolGlyph($r('sys.symbol.picture'))
                    .fontSize(14)
                    .fontColor([$r('app.color.brand_primary')])
                  Text('重新识别')
                    .fontSize(13)
                    .fontColor($r('app.color.brand_primary'))
                    .fontWeight(FontWeight.Medium)
                }
                .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                .backgroundColor($r('app.color.brand_primary_bg'))
                .borderRadius(20)
                .margin({ top: 8, bottom: 16 })
                .onClick(() => {
                  this.showForm = false;
                  this.isParsingImage = false;
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
        [$r('app.color.page_gradient_start'), 0.0],
        [$r('app.color.page_gradient_start'), 0.4],
        [$r('app.color.page_gradient_end'), 0.9]
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
          .fontColor([this.inputMode === 'voice' ? Color.White : $r('app.color.text_secondary')])
        Text('语音输入')
          .fontSize(14)
          .fontWeight(this.inputMode === 'voice' ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.inputMode === 'voice' ? Color.White : $r('app.color.text_secondary'))
      }
      .height(42)
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.inputMode === 'voice' ? $r('app.color.brand_primary') : Color.Transparent)
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

      // 图像识别 Tab
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.picture'))
          .fontSize(15)
          .fontColor([this.inputMode === 'image' ? Color.White : $r('app.color.text_secondary')])
        Text('图像识别')
          .fontSize(14)
          .fontWeight(this.inputMode === 'image' ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.inputMode === 'image' ? Color.White : $r('app.color.text_secondary'))
      }
      .height(42)
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.inputMode === 'image' ? $r('app.color.brand_primary') : Color.Transparent)
      .borderRadius(16)
      .animation({ duration: 250, curve: Curve.EaseInOut })
      .onClick(() => {
        if (this.inputMode !== 'image') {
          this.inputMode = 'image';
          this.showForm = false;
          this.recognizedText = '';
          this.analyzedTask = null;
          this.editContent = '';
          this.editDate = '';
          this.editTime = '';
          this.editTags = [];
          this.newTagInput = '';
          this.isParsingImage = false;
        }
      })

      // 手动输入 Tab
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(15)
          .fontColor([this.inputMode === 'manual' ? Color.White : $r('app.color.text_secondary')])
        Text('手动输入')
          .fontSize(14)
          .fontWeight(this.inputMode === 'manual' ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.inputMode === 'manual' ? Color.White : $r('app.color.text_secondary'))
      }
      .height(42)
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.inputMode === 'manual' ? $r('app.color.brand_primary') : Color.Transparent)
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
    .backgroundColor($r('app.color.app_bg'))
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
            .fontColor($r('app.color.brand_primary'))
            .fontWeight(FontWeight.Medium)
            .textAlign(TextAlign.Center)
            .padding({ left: 30, right: 30 })
            .animation({ duration: 200, curve: Curve.EaseOut })

          // 录音中提示
          Text('松手结束录音')
            .fontSize(13)
            .fontColor($r('app.color.text_tertiary'))
        }
      } else if (this.recognizedText.length > 0 && this.recognizedText !== '正在听...') {
        // 录完等待解析
        Column({ space: 12 }) {
          Text(this.recognizedText)
            .fontSize(20)
            .fontColor($r('app.color.brand_primary'))
            .fontWeight(FontWeight.Medium)
            .textAlign(TextAlign.Center)
            .padding({ left: 30, right: 30 })
          Text('正在分析语义...')
            .fontSize(14)
            .fontColor($r('app.color.text_tertiary'))
        }
      } else {
        // 未开始录音
        Column({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.mic_fill'))
            .fontSize(48)
            .fontColor([$r('app.color.text_tertiary')])
          Text('长按下方按钮，说出你的安排')
            .fontSize(15)
            .fontColor($r('app.color.text_tertiary'))
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
            .fill($r('app.color.brand_primary'))
            .opacity(0.08)
          Circle()
            .width(96)
            .height(96)
            .fill($r('app.color.brand_primary'))
            .opacity(0.14)
        }

        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.mic_fill'))
            .fontSize(35)
            .fontColor([Color.White])
        }
        .width(80)
        .height(80)
        .backgroundColor(this.isListening ? $r('app.color.danger_color') : $r('app.color.brand_primary'))
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
  //  图像识别区域与逻辑
  // ========================

  @Builder ImageRecordArea() {
    Column() {
      if (this.isParsingImage) {
        // 正在解析中
        Column({ space: 16 }) {
          LoadingProgress()
            .width(60)
            .height(60)
            .color($r('app.color.brand_primary'))
          Text('正在提取图片文字与日程信息...')
            .fontSize(16)
            .fontColor($r('app.color.brand_primary'))
            .fontWeight(FontWeight.Medium)
        }
      } else {
        // 未选择图片
        Column({ space: 16 }) {
          SymbolGlyph($r('sys.symbol.picture'))
            .fontSize(64)
            .fontColor([$r('app.color.text_tertiary')])
          Text('上传海报、截图或拍照，AI自动提取日程')
            .fontSize(15)
            .fontColor($r('app.color.text_tertiary'))
            .textAlign(TextAlign.Center)
            .padding({ left: 30, right: 30 })
        }
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)

    // 底部按钮组
    if (!this.isParsingImage) {
      Row({ space: 24 }) {
        // 相册按钮
        Column({ space: 8 }) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.picture'))
              .fontSize(28)
              .fontColor([$r('app.color.brand_primary')])
          }
          .width(64)
          .height(64)
          .backgroundColor($r('app.color.card_bg'))
          .border({ width: 1, color: $r('app.color.divider_color') })
          .shadow({ radius: 10, color: 'rgba(0,0,0,0.05)', offsetY: 4 })
          .onClick(() => {
            this.pickFromGallery();
          })
          Text('相册提取')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }

        // 拍照按钮
        Column({ space: 8 }) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.camera'))
              .fontSize(28)
              .fontColor([Color.White])
          }
          .width(64)
          .height(64)
          .backgroundColor($r('app.color.brand_primary'))
          .shadow({ radius: 15, color: 'rgba(59,130,246,0.3)', offsetY: 4 })
          .onClick(() => {
            this.takePhoto();
          })
          Text('拍照识别')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }
      }
      .margin({ bottom: 60 })
    }
  }

  async pickFromGallery() {
    try {
      let photoPicker = new picker.PhotoViewPicker();
      let options = new picker.PhotoSelectOptions();
      options.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      let result = await photoPicker.select(options);
      if (result && result.photoUris && result.photoUris.length > 0) {
        this.processImageToTask(result.photoUris[0]);
      }
    } catch (err) {
      console.error('选择相册图片失败:', err);
      promptAction.showToast({ message: '选择图片失败' });
    }
  }

  async takePhoto() {
    try {
      let context = getContext(this) as common.UIAbilityContext;
      let pickerProfile: cameraPicker.PickerProfile = {
        cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK
      };
      let pickerResult = await cameraPicker.pick(context,
        [cameraPicker.PickerMediaType.PHOTO], pickerProfile);
      if (pickerResult && pickerResult.resultUri) {
        this.processImageToTask(pickerResult.resultUri);
      }
    } catch (err) {
      let e = err as BusinessError;
      if (e.code === 201) {
        console.info('用户取消了拍照');
      } else {
        console.error('调用相机失败:', err);
        promptAction.showToast({ message: '调用相机失败' });
      }
    }
  }

  async processImageToTask(uri: string) {
    let useCloudModel = AppStorage.get<boolean>('useCloudModel');
    if (!useCloudModel) {
      promptAction.showToast({ message: '请先在“我的”页面开启大模型调用能力', duration: 3000 });
      return;
    }

    this.isParsingImage = true;
    try {
      // 1. 获取 PixelMap
      let file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      let imageSource = image.createImageSource(file.fd);
      let pixelMap = await imageSource.createPixelMap();
      
      // 2. OCR 识别
      let visionInfo: textRecognition.VisionInfo = { pixelMap: pixelMap };
      let textConfig: textRecognition.TextRecognitionConfiguration = { 
        isDirectionDetectionSupported: false 
      };
      let recognitionResult = await textRecognition.recognizeText(visionInfo, textConfig);
      
      let extractedText = recognitionResult.value;
      console.info('OCR 提取出的文本:', extractedText);
      
      // 释放资源
      pixelMap.release();
      imageSource.release();
      fileIo.closeSync(file);

      if (!extractedText || extractedText.trim().length === 0) {
        promptAction.showToast({ message: '未能在图片中识别到清晰的文字' });
        this.isParsingImage = false;
        return;
      }

      // 3. 传给大模型解析（在 Prompt 前增加上下文以适应杂乱文本）
      let promptText = `请从以下OCR识别的截图文字中，提取日程信息（包含标题、时间、地点）。文字可能会有乱码或排版错乱：\n\n${extractedText}`;
      
      let parsedTask = await NLPUtils.analyzeTaskSemantic(promptText);
      this.analyzedTask = parsedTask;
      
      // 4. 填入表单
      this.populateFormFromTask(parsedTask);
      
    } catch (error) {
      console.error('图片识别/解析失败:', error);
      promptAction.showToast({ message: '图片解析失败，可能图片太模糊或文字不清晰' });
    } finally {
      this.isParsingImage = false;
    }
  }

  // ========================
  //  可编辑表单（语音结果 / 手动输入 / 图像结果 共用）
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
          .fontColor($r('app.color.text_primary'))
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
            .fontColor($r('app.color.text_secondary'))
            .fontWeight(FontWeight.Medium)
        }

        TextInput({ placeholder: '请输入日程内容...', text: $$this.editContent })
          .height(50)
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_tertiary'))
          .backgroundColor($r('app.color.app_bg'))
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
              .fontColor($r('app.color.text_secondary'))
              .fontWeight(FontWeight.Medium)
          }

          TextInput({ placeholder: 'YYYY-MM-DD', text: $$this.editDate })
            .height(50)
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
            .placeholderColor($r('app.color.text_tertiary'))
            .backgroundColor($r('app.color.app_bg'))
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
              .fontColor($r('app.color.text_secondary'))
              .fontWeight(FontWeight.Medium)
          }

          TextInput({ placeholder: 'HH:mm', text: $$this.editTime })
            .height(50)
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
            .placeholderColor($r('app.color.text_tertiary'))
            .backgroundColor($r('app.color.app_bg'))
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
            .fontColor($r('app.color.text_secondary'))
            .fontWeight(FontWeight.Medium)
        }

        Flex({ wrap: FlexWrap.Wrap }) {
          // 已有标签胶囊
          ForEach(this.editTags, (tag: string) => {
            Row({ space: 6 }) {
              Text(tag)
                .fontSize(13)
                .fontColor($r('app.color.brand_primary'))
                .fontWeight(FontWeight.Medium)
              Text('×')
                .fontSize(16)
                .fontColor($r('app.color.text_tertiary'))
                .fontWeight(FontWeight.Bold)
                .onClick(() => {
                  this.removeTag(tag);
                })
            }
            .padding({ left: 14, right: 10, top: 7, bottom: 7 })
            .backgroundColor($r('app.color.brand_primary_bg'))
            .borderRadius(20)
            .border({ width: 0.5, color: $r('app.color.brand_border') })
            .margin({ right: 8, bottom: 8 })
            .animation({ duration: 200, curve: Curve.EaseOut })
          }, (tag: string) => tag)

          // 添加标签输入框
          TextInput({ placeholder: '+ 添加标签', text: $$this.newTagInput })
            .width(140)
            .height(36)
            .fontSize(13)
            .fontColor($r('app.color.text_primary'))
            .placeholderColor($r('app.color.text_tertiary'))
            .backgroundColor($r('app.color.app_bg'))
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
        .backgroundColor($r('app.color.brand_primary'))
        .borderRadius(16)
        .shadow({ radius: 14, color: 'rgba(59,130,246,0.25)', offsetY: 4 })
        .margin({ top: 32 })
        .onClick(() => {
          this.confirmAddTask();
        })
    }
    .width('90%')
    .padding(24)
    .backgroundColor($r('app.color.card_bg'))
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