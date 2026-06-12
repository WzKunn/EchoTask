import { http } from '@kit.NetworkKit';
import { promptAction } from '@kit.ArkUI';

class Message {
  public role: 'user' | 'assistant' | 'system';
  public content: string;
  constructor(role: 'user' | 'assistant' | 'system', content: string) {
    this.role = role;
    this.content = content;
  }
}

class RequestMessage {
  role: string = '';
  content: string = '';
}

class OpenAIChatRequest {
  model: string = '';
  messages: RequestMessage[] = [];
  stream: boolean = false;
}

interface LLMMessage {
  content: string;
}

interface LLMChoice {
  message: LLMMessage;
}

interface LLMResponse {
  choices: LLMChoice[];
}

class TextSegment {
  content: string = '';
  isBold: boolean = false;
  isCode: boolean = false;
  constructor(content: string, isBold: boolean, isCode: boolean) {
    this.content = content;
    this.isBold = isBold;
    this.isCode = isCode;
  }
}

class MdBlock {
  type: 'paragraph' | 'code' = 'paragraph';
  content: string = '';
  language?: string;
  constructor(type: 'paragraph' | 'code', content: string, language?: string) {
    this.type = type;
    this.content = content;
    this.language = language;
  }
}

function parseMarkdown(text: string): MdBlock[] {
  let blocks: MdBlock[] = [];
  let lines = text.split('\n');
  let inCodeBlock = false;
  let codeContent = '';
  let codeLang = '';
  let currentParagraph = '';

  for (let i = 0; i < lines.length; i++) {
    let line = lines[i];
    if (line.trim().startsWith('```')) {
      if (inCodeBlock) {
        blocks.push(new MdBlock('code', codeContent.trimEnd(), codeLang));
        inCodeBlock = false;
        codeContent = '';
        codeLang = '';
      } else {
        if (currentParagraph.trim().length > 0) {
          blocks.push(new MdBlock('paragraph', currentParagraph.trimEnd()));
          currentParagraph = '';
        }
        inCodeBlock = true;
        codeLang = line.trim().substring(3).trim();
      }
    } else {
      if (inCodeBlock) {
        codeContent += line + '\n';
      } else {
        currentParagraph += line + '\n';
      }
    }
  }
  
  if (inCodeBlock) {
    blocks.push(new MdBlock('code', codeContent.trimEnd(), codeLang));
  } else if (currentParagraph.trim().length > 0) {
    blocks.push(new MdBlock('paragraph', currentParagraph.trimEnd()));
  }
  
  return blocks;
}

function parseInline(text: string): TextSegment[] {
  let segments: TextSegment[] = [];
  let i = 0;
  let current = '';
  while (i < text.length) {
    if (text.substr(i, 2) === '**') {
      if (current.length > 0) {
        segments.push(new TextSegment(current, false, false));
        current = '';
      }
      let endIdx = text.indexOf('**', i + 2);
      if (endIdx !== -1) {
        segments.push(new TextSegment(text.substring(i + 2, endIdx), true, false));
        i = endIdx + 2;
      } else {
        current += '**';
        i += 2;
      }
    } else if (text[i] === '`') {
      if (current.length > 0) {
        segments.push(new TextSegment(current, false, false));
        current = '';
      }
      let endIdx = text.indexOf('`', i + 1);
      if (endIdx !== -1) {
        segments.push(new TextSegment(text.substring(i + 1, endIdx), false, true));
        i = endIdx + 1;
      } else {
        current += '`';
        i += 1;
      }
    } else {
      current += text[i];
      i++;
    }
  }
  if (current.length > 0) {
    segments.push(new TextSegment(current, false, false));
  }
  return segments;
}

@Component
export struct ChatView {
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  @StorageLink('cloudApiModel') cloudApiModel: string = '';
  @StorageLink('cloudApiKey') cloudApiKey: string = '';
  @StorageLink('cloudApiUrl') cloudApiUrl: string = '';

  @StorageLink('chatMessages') messages: Message[] = [];
  @State inputText: string = '';
  @State isThinking: boolean = false;
  private scroller: Scroller = new Scroller();

  aboutToAppear() {
    if (this.messages.length === 0) {
      this.messages.push(new Message('assistant', '你好！我是 Echo AI，你的私人智能助理。有什么我可以帮你的吗？'));
    }
  }

  build() {
    Column() {
      // 顶部标题
      Row() {
        Text('Echo AI')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .padding({ left: 24, top: 16, bottom: 16 })

      // 消息列表区
      List({ space: 20, scroller: this.scroller }) {
        ForEach(this.messages, (msg: Message, index: number) => {
          ListItem() {
            this.MessageBubble(msg)
          }
        })
        if (this.isThinking) {
          ListItem() {
            this.ThinkingBubble()
          }
        }
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 16, right: 16, top: 10, bottom: 20 })
      .edgeEffect(EdgeEffect.Spring)

      // 底部输入区
      Column() {
        Row() {
          TextInput({ 
            placeholder: this.cloudApiKey ? '向 AI 提问...' : '请先前往"我的"配置 API Key', 
            text: this.inputText 
          })
            .layoutWeight(1)
            .height(45)
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(20)
            .onChange((val) => this.inputText = val)
            .enabled(!this.isThinking)
            .onSubmit(() => this.sendMessage())

          Button('发送')
            .margin({ left: 10 })
            .fontColor(Color.White)
            .backgroundColor(this.inputText.trim() && !this.isThinking ? $r('app.color.brand_primary') : $r('app.color.text_tertiary'))
            .enabled(this.inputText.trim().length > 0 && !this.isThinking)
            .onClick(() => this.sendMessage())
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 15, bottom: 6 })

        Text('此对话调用您填入的API，请注意Token消耗')
          .fontSize(10)
          .fontColor($r('app.color.text_secondary'))
          .margin({ bottom: 30 })
      }
      .width('100%')
      .backgroundColor(Color.Transparent)
    }
    .width('100%')
    .height('100%')
  }

  @Builder MessageBubble(msg: Message) {
    if (msg.role !== 'system') {
      Row() {
        if (msg.role === 'user') Blank()

        Column() {
          if (msg.role === 'user') {
            Text(msg.content)
              .fontSize(16)
              .fontColor(Color.White)
              .padding(12)
          } else {
            Column({ space: 8 }) {
              ForEach(parseMarkdown(msg.content), (block: MdBlock) => {
                if (block.type === 'paragraph') {
                  Text() {
                    ForEach(parseInline(block.content), (seg: TextSegment) => {
                      Span(seg.content)
                        .fontWeight(seg.isBold ? FontWeight.Bold : FontWeight.Normal)
                        .fontColor(seg.isCode ? $r('app.color.danger_color') : $r('app.color.text_primary'))
                        .fontFamily(seg.isCode ? 'monospace' : '')
                    })
                  }
                  .fontSize(16)
                  .lineHeight(24)
                  .copyOption(CopyOptions.LocalDevice)
                } else if (block.type === 'code') {
                  Column() {
                    if (block.language) {
                      Row() {
                        Text(block.language)
                          .fontSize(12)
                          .fontColor($r('app.color.text_secondary'))
                      }
                      .width('100%')
                      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                      .backgroundColor($r('app.color.app_bg'))
                      .borderRadius({ topLeft: 8, topRight: 8 })
                    }
                    Text(block.content)
                      .fontSize(13)
                      .fontFamily('monospace')
                      .fontColor($r('app.color.text_primary'))
                      .padding(12)
                      .copyOption(CopyOptions.LocalDevice)
                      .wordBreak(WordBreak.BREAK_ALL)
                      .width('100%')
                  }
                  .width('100%')
                  .backgroundColor($r('app.color.card_bg'))
                  .borderRadius(8)
                  .border({ width: 1, color: $r('app.color.divider_color') })
                  .clip(true)
                }
              })
            }
            .alignItems(HorizontalAlign.Start)
            .padding(12)
          }
        }
        .backgroundColor(msg.role === 'user' ? $r('app.color.brand_primary') : $r('app.color.card_bg'))
        .borderRadius(15)
        .shadow({ radius: 5, color: 'rgba(0,0,0,0.05)' })
        .width(msg.role === 'assistant' ? '100%' : undefined)
        .constraintSize(msg.role === 'user' ? { maxWidth: '85%' } : {})
      }
      .width('100%')
    }
  }

  @Builder ThinkingBubble() {
    Row() {
      Column() {
        Text('思考中...')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .padding(12)
      }
      .backgroundColor($r('app.color.card_bg'))
      .borderRadius(15)
      .shadow({ radius: 5, color: 'rgba(0,0,0,0.05)' })
      
      Blank()
    }
    .width('100%')
  }

  async sendMessage() {
    if (this.inputText.trim() === '' || this.isThinking) return;
    if (!this.cloudApiKey || !this.cloudApiUrl || !this.cloudApiModel) {
      promptAction.showToast({ message: '请先前往"我的"页面配置大模型信息' });
      return;
    }

    let userText = this.inputText;
    this.inputText = '';
    this.messages.push(new Message('user', userText));
    this.scrollToBottom();

    this.isThinking = true;
    this.scrollToBottom();

    let httpRequest: http.HttpRequest | null = null;

    try {
      httpRequest = http.createHttp();
      
      let requestBody: OpenAIChatRequest = {
        model: this.cloudApiModel,
        messages: this.messages.map(m => {
          let reqMsg: RequestMessage = { role: m.role, content: m.content };
          return reqMsg;
        }),
        stream: false
      };

      let finalUrl = this.cloudApiUrl.trim();
      if (!finalUrl.endsWith('/chat/completions')) {
        finalUrl = finalUrl.endsWith('/') ? finalUrl + 'chat/completions' : finalUrl + '/chat/completions';
      }

      let response = await httpRequest.request(
        finalUrl,
        {
          method: http.RequestMethod.POST,
          header: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${this.cloudApiKey}`
          },
          extraData: JSON.stringify(requestBody),
          readTimeout: 60000,
          connectTimeout: 60000
        }
      );

      if (response.responseCode === 200) {
        let result = JSON.parse(response.result as string) as LLMResponse;
        if (result.choices && result.choices.length > 0) {
          let aiText = result.choices[0].message.content;
          this.messages.push(new Message('assistant', aiText));
        } else {
          this.messages.push(new Message('assistant', '（返回数据格式异常）'));
        }
      } else {
        this.messages.push(new Message('assistant', `（请求失败，状态码：${response.responseCode}）`));
        console.error('API Error:', response.result);
      }
    } catch (err) {
      console.error('Network Error:', err);
      this.messages.push(new Message('assistant', '（网络请求异常，请检查配置或网络连接）'));
    } finally {
      this.isThinking = false;
      this.scrollToBottom();
      if (httpRequest) {
        httpRequest.destroy();
      }
    }
  }

  scrollToBottom() {
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 100);
  }
}