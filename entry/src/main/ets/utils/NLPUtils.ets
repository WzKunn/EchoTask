import { TaskItem } from '../pages/HomeView';
import { textProcessing, EntityType } from '@kit.NaturalLanguageKit';
import { http } from '@kit.NetworkKit';
import { promptAction } from '@kit.ArkUI';

// 1. 定义大模型 API 返回的结构
interface LLMMessage {
  content: string;
}
interface LLMChoice {
  message: LLMMessage;
}
interface LLMResponse {
  choices: LLMChoice[];
}

// 2. 定义我们期望 AI 吐出的 JSON 结构
interface ParsedTask {
  content: string;
  time: string;
  tags: string[];
}
// 定义请求里的消息对象长什么样
interface ReqMessage {
  role: string;
  content: string;
}
// 定义整个请求体的结构
interface LLMRequest {
  model: string;
  messages: ReqMessage[];
  temperature: number;
}


export class NLPUtils {

  // 统一的入口方法
  public static async analyzeTaskSemantic(rawText: string): Promise<TaskItem> {
    // 1. 从内存管家里拿出用户在 MineView 里设置的配置
    let useCloud = AppStorage.get<boolean>('useCloudModel') || false;
    let apiKey = AppStorage.get<string>('cloudApiKey') || '';

    // 2. 智能路由
    if (useCloud && apiKey.length > 0) {
      console.info('☁️ 路由走向：云端大模型');
      return await NLPUtils.analyzeWithCloudModel(rawText);
    } else {
      console.info('📱 路由走向：本地离线正则');
      return await NLPUtils.analyzeWithLocalRegEx(rawText);
    }
  }

  /**
   * 接入官方 Natural Language Kit 进行实体抽取
   */
  public static async analyzeWithLocalRegEx(rawText: string): Promise<TaskItem> {
    console.info(`[NLP Engine] 开始解析文本: ${rawText}`);

    if (rawText.length < 2) {
      throw new Error("文本太短，无法解析意图");
    }

    let extractedTime = "稍后";
    let pureContent = rawText;
    let tags: string[] = ["语音记录"];

    try {
      // 1. 调用官方实体抽取接口
      // 针对日程场景，我们重点请求提取：时间、地点、人名
      let entities = await textProcessing.getEntity(rawText, {
        entityTypes: [EntityType.DATETIME, EntityType.LOCATION, EntityType.NAME]
      });

      // 2. 解析官方返回的实体数组
      if (entities && entities.length > 0) {
        // 为了防止剥离实体后破坏原句连贯性，我们可以将所有提取到的实体从原文中剔除，剩下的就是“纯动作”
        let entitiesToStrip: string[] = [];

        for (let entity of entities) {
          if (entity.type === EntityType.DATETIME) {
            extractedTime = entity.text; // 捕获最核心的时间
            entitiesToStrip.push(entity.text);
          } else if (entity.type === EntityType.LOCATION) {
            tags.push(`地点:${entity.text}`); // 把地点变成高亮标签
            entitiesToStrip.push(entity.text);
          } else if (entity.type === EntityType.NAME) {
            tags.push(`人物:${entity.text}`); // 把人名变成高亮标签
            entitiesToStrip.push(entity.text);
          }
        }

        // 3. 动作提纯：剔除实体词
        entitiesToStrip.forEach(word => {
          pureContent = pureContent.replace(word, '');
        });
      }
    } catch (err) {
      // 容错降级：如果系统语言服务未就绪或报错，不让 APP 崩溃，降级使用原文本
      console.error(`官方NLP接口调用失败: errorCode: ${err?.code}, errorMessage: ${err?.message}`);
      // 这里可以悄悄把 tags 标为解析失败，方便后续排查
      tags.push("解析降级");
    }

    // 4. 清理口语化的冗余词汇 (结合我们的业务进行微调)
    pureContent = pureContent
      .replace(/帮我/g, "")
      .replace(/提醒我/g, "")
      .replace(/那个/g, "")
      .replace(/一下/g, "")
      .replace(/嗯/g, "")
      .replace(/要/g, "")
      .replace(/在/, "")
      .replace(/到/, "")
      .replace(/去/, "")
      .trim();

    // 如果剥离完没字了，就兜底使用原话
    if (pureContent.length === 0) pureContent = rawText;

    // 5. 补充业务强相关的自定义标签 (这部分端侧 NER 无法直接给出，需结合关键字规则)
    if (pureContent.includes("代码") || pureContent.includes("C++") || pureContent.includes("Bug")) {
      tags.push("技术");
    }
    if (pureContent.includes("紧急") || pureContent.includes("马上")) {
      tags.push("紧急");
    }

    let taskId = Date.now().toString();
    console.info(`[NLP Engine] 解析完成 -> 动作: ${pureContent}, 时间: ${extractedTime}, 标签: ${tags.join(',')}`);

    return new TaskItem(taskId, pureContent, extractedTime, tags);
  }

  // 云端模型
  private static async analyzeWithCloudModel(rawText: string): Promise<TaskItem> {
    let apiUrl = AppStorage.get<string>('cloudApiUrl') || '';
    let apiKey = AppStorage.get<string>('cloudApiKey') || '';
    let apiModel = AppStorage.get<string>('cloudApiModel') || '';

    // 1. 创建 HTTP 请求任务
    let httpRequest = http.createHttp();

    // 2. 编写系统提示词
    let systemPrompt = `你是一个日程管家API。请从用户的输入中提取任务内容(content)、时间(time，格式如'明天 14:00')和标签(tags，字符串数组)。
请严格且仅返回JSON格式，绝对不要包含任何额外的markdown标记(如 \`\`\`json)或解释性文字。
范例：{"content": "去机房写实验报告", "time": "明天 14:30", "tags": ["学习", "重要"]}`;

    // 3. 按照各大模型通用标准 (OpenAI/GLM 格式) 组装请求体
    let msgList: ReqMessage[] = [
      { role: "system", content: systemPrompt },
      { role: "user", content: rawText }
    ];
    let requestData: LLMRequest = {
      model: apiModel,
      messages: msgList,
      temperature: 0.1 // 温度调低，让 AI 的输出更加确定、不发散
    };

    try {
      // 4. 发起异步 POST 请求
      let response = await httpRequest.request(
        apiUrl,
        {
          method: http.RequestMethod.POST,
          header: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${apiKey}`
          },
          extraData: JSON.stringify(requestData),
          connectTimeout: 10000, // 10秒连不上就放弃
          readTimeout: 10000
        }
      );

      if (response.responseCode === 200) {
        // 5. 解析 HTTP 响应
        let resData = JSON.parse(response.result as string) as LLMResponse;
        let aiOutput: string = resData.choices[0].message.content;

        // 6. 防御性编程：清洗 AI 可能误带的 Markdown 代码块残留
        let cleanJsonStr = aiOutput.replace(/```json/g, '').replace(/```/g, '').trim();
        let parsedObj = JSON.parse(cleanJsonStr) as ParsedTask;

        let taskId = Date.now().toString();
        console.info('☁️ 云端解析成功:', cleanJsonStr);
        return new TaskItem(taskId, parsedObj.content, parsedObj.time, parsedObj.tags);

      } else {
        console.error(`云端请求失败，HTTP状态码: ${response.responseCode}`);
        promptAction.showToast({ message: '云端请求失败，请您检查URL和API是否填写正确\n已为您切换至本地解析模式' });
        // 请求失败，立刻触发【优雅降级】，用本地正则解析顶上
        return await NLPUtils.analyzeWithLocalRegEx(rawText);
      }

    } catch (err) {
      console.error('云端大模型网络请求异常:', err);
      promptAction.showToast({ message: '网络异常，已为您切换至本地解析服务' });
      // 网络断开或超时，触发本地降级
      return await NLPUtils.analyzeWithLocalRegEx(rawText);
    } finally {
      // 7. 无论成功失败，必须销毁请求释放系统资源
      httpRequest.destroy();
    }
  }

}
