// 1. 定义消息模型
class Message {
  public role: 'user' | 'ai';
  public content: string;
  constructor(role: 'user' | 'ai', content: string) {
    this.role = role;
    this.content = content;
  }
}

@Builder
export function ChatPageBuilder() {
  ChatPage()
}

@Component
struct ChatPage {
  pathStack: NavPathStack = new NavPathStack();
  @State tags: string[] = [];
  @State messages: Message[] = [];
  @State inputText: string = '';
  private scroller: Scroller = new Scroller();

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        // --- 1. 背景层 ---
        Row().width('100%').height('100%').backgroundColor('#F4F7FB')

        // --- 2. 对话列表区 ---
        Column() {
          List({ space: 20, scroller: this.scroller }) {
            ForEach(this.messages, (msg: Message) => {
              ListItem() {
                this.MessageBubble(msg)
              }
            })
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 16, right: 16, top: 20, bottom: 100 })
          .edgeEffect(EdgeEffect.Spring) // 增加回弹效果
        }
        .width('100%')
        .height('100%')

        // --- 3. 底部输入区 (玻璃质感) ---
        Row() {
          TextInput({ placeholder: '给 AI 传达你的决策...', text: this.inputText })
            .layoutWeight(1)
            .height(45)
            .backgroundColor('rgba(255,255,255,0.9)')
            .borderRadius(20)
            .onChange((val) => this.inputText = val)

          Button('发送')
            .margin({ left: 10 })
            .fontColor(Color.White)
            .backgroundColor('#3b82f6')
            .onClick(() => this.sendMessage())
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 15, bottom: 30 })
        .backgroundColor('rgba(255, 255, 255, 0.7)')
        .backdropBlur(20)
      }
    }
    .title('EchoSaga 互动中')
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      // 【核心】：获取从 GenreSelection 传过来的标签
      const params = context.pathStack.getParamByName('ChatPage')[0] as Record<string, Object>;
      if (params && params.tags) {
        this.tags = params.tags as string[];
        // 初始化 AI 的第一句话
        this.initStory();
      }
    })
  }

  // 自定义消息气泡
  @Builder MessageBubble(msg: Message) {
    Row() {
      if (msg.role === 'user') Blank() // 用户消息靠右

      Column() {
        Text(msg.content)
          .fontSize(16)
          .fontColor(msg.role === 'user' ? Color.White : '#1e293b')
          .padding(12)
      }
      .backgroundColor(msg.role === 'user' ? '#3b82f6' : Color.White)
      .borderRadius(15)
      .shadow({ radius: 5, color: 'rgba(0,0,0,0.05)' })
      .constraintSize({ maxWidth: '75%' }) // 限制最大宽度

      if (msg.role === 'ai') Blank() // AI 消息靠左
    }
    .width('100%')
  }

  initStory() {
    this.messages.push(new Message('ai', `正在为你构建基于【${this.tags.join('、')}】的世界... 你睁开眼，发现自己身处一片迷雾之中。`));
  }

  sendMessage() {
    if (this.inputText.trim() === '') return;
    this.messages.push(new Message('user', this.inputText));
    this.inputText = '';
    // 这里未来接入 AI 接口
    setTimeout(() => {
      this.messages.push(new Message('ai', '这是一个来自 Echo 引擎的模拟回应。'));
      this.scroller.scrollToIndex(this.messages.length - 1);
    }, 1000);
  }
}