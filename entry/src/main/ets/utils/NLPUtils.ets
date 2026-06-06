import { TaskItem } from '../pages/HomeView';
import { textProcessing, EntityType } from '@kit.NaturalLanguageKit';
import { http } from '@kit.NetworkKit';
import { promptAction } from '@kit.ArkUI';
import { TimeUtils } from './TimeUtils';

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

// 2. 定义我们期望 AI 吐出的 JSON 结构（任务创建）
interface ParsedTask {
  content: string;
  time: string;
  timestamp: string;
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

// 3. 搜索意图的结构化结果
export class SearchIntent {
  keywords: string[] = [];
  startTime: number = 0;
  endTime: number = 0;
  tags: string[] = [];
}

// 搜索意图 LLM 返回的原始结构
interface ParsedSearchIntent {
  keywords: string[];
  startTime: string;
  endTime: string;
  tags: string[];
}


export class NLPUtils {

  // ========================
  //  任务创建：统一入口
  // ========================

  public static async analyzeTaskSemantic(rawText: string): Promise<TaskItem> {
    // 1. 从内存管家里拿出用户在 MineView 里设置的配置
    let useCloud = AppStorage.get<boolean>('useCloudModel') || false;
    let apiKey = AppStorage.get<string>('cloudApiKey') || '';

    // 2. 智能路由
    if (useCloud && apiKey.length > 0) {
      console.info('路由走向：云端大模型');
      return await NLPUtils.analyzeWithCloudModel(rawText);
    } else {
      console.info('路由走向：本地离线正则');
      return await NLPUtils.analyzeWithLocalRegEx(rawText);
    }
  }

  /**
   * 接入官方 Natural Language Kit 进行实体抽取
   */
  public static async analyzeWithLocalRegEx(rawText: string): Promise<TaskItem> {
    console.info('[NLP Engine] 开始解析文本: ' + rawText);

    if (rawText.length < 2) {
      throw new Error("文本太短，无法解析意图");
    }

    let extractedTime = "稍后";
    let pureContent = rawText;
    let tags: string[] = ["语音记录"];

    try {
      // 1. 调用官方实体抽取接口
      let entities = await textProcessing.getEntity(rawText, {
        entityTypes: [EntityType.DATETIME, EntityType.LOCATION, EntityType.NAME]
      });

      // 2. 解析官方返回的实体数组
      if (entities && entities.length > 0) {
        let entitiesToStrip: string[] = [];

        for (let entity of entities) {
          if (entity.type === EntityType.DATETIME) {
            extractedTime = entity.text;
            entitiesToStrip.push(entity.text);
          } else if (entity.type === EntityType.LOCATION) {
            tags.push('地点:' + entity.text);
            entitiesToStrip.push(entity.text);
          } else if (entity.type === EntityType.NAME) {
            tags.push('人物:' + entity.text);
            entitiesToStrip.push(entity.text);
          }
        }

        // 3. 动作提纯：剔除实体词
        for (let word of entitiesToStrip) {
          pureContent = pureContent.replace(word, '');
        }
      }
    } catch (err) {
      console.error('官方NLP接口调用失败: ' + JSON.stringify(err));
      tags.push("解析降级");
    }

    // 4. 清理口语化的冗余词汇
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

    if (pureContent.length === 0) pureContent = rawText;

    // 5. 补充业务强相关的自定义标签
    if (pureContent.includes("代码") || pureContent.includes("C++") || pureContent.includes("Bug")) {
      tags.push("技术");
    }
    if (pureContent.includes("紧急") || pureContent.includes("马上")) {
      tags.push("紧急");
    }

    let taskId = Date.now().toString();
    // 6. 使用 TimeUtils 将相对时间转换为标准时间戳
    let timestamp = TimeUtils.parseChineseTimeToTimestamp(extractedTime);
    console.info('[NLP Engine] 解析完成 -> 动作: ' + pureContent + ', 时间: ' + extractedTime + ', 时间戳: ' + timestamp);

    return new TaskItem(taskId, pureContent, extractedTime, timestamp, tags);
  }

  // ========================
  //  任务创建：云端模型路径
  // ========================

  private static async analyzeWithCloudModel(rawText: string): Promise<TaskItem> {
    let apiUrl = AppStorage.get<string>('cloudApiUrl') || '';
    let apiKey = AppStorage.get<string>('cloudApiKey') || '';
    let apiModel = AppStorage.get<string>('cloudApiModel') || '';

    // 智能拼接：用户只需填 Base URL，自动补全 /chat/completions
    if (!apiUrl.endsWith('/chat/completions')) {
      let trimmed = apiUrl.replace(/\/+$/, '');
      apiUrl = trimmed + '/chat/completions';
    }

    // 1. 创建 HTTP 请求任务
    let httpRequest = http.createHttp();

    // 2. 编写系统提示词（注入当前真实日期，要求返回 ISO 时间戳）
    let now = new Date();
    let yearStr = now.getFullYear().toString();
    let monthStr = String(now.getMonth() + 1).padStart(2, '0');
    let dayStr = String(now.getDate()).padStart(2, '0');
    let currentDateStr = yearStr + '-' + monthStr + '-' + dayStr;

    let systemPrompt = '你是一个日程管家API。当前日期是 ' + currentDateStr + '。'
      + '请从用户的输入中提取以下字段：'
      + 'content：任务内容；'
      + 'time：用户友好的时间描述（如"明天 14:00"）；'
      + 'timestamp：基于当前日期换算出的 ISO 8601 格式绝对时间（如"' + yearStr + '-05-27T14:00:00"）。如果用户未指定具体时间，默认为当天 09:00；'
      + 'tags：标签数组。'
      + '请严格且仅返回JSON格式，不要包含任何额外的markdown标记或解释性文字。'
      + '范例：{"content": "去机房写实验报告", "time": "明天 14:30", "timestamp": "' + yearStr + '-05-27T14:30:00", "tags": ["学习", "重要"]}';

    // 3. 按照各大模型通用标准 (OpenAI/GLM 格式) 组装请求体
    let msgList: ReqMessage[] = [
      { role: "system", content: systemPrompt },
      { role: "user", content: rawText }
    ];
    let requestData: LLMRequest = {
      model: apiModel,
      messages: msgList,
      temperature: 0.1
    };

    try {
      // 4. 发起异步 POST 请求
      let response = await httpRequest.request(
        apiUrl,
        {
          method: http.RequestMethod.POST,
          header: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ' + apiKey
          },
          extraData: JSON.stringify(requestData),
          connectTimeout: 15000,
          readTimeout: 60000
        }
      );

      if (response.responseCode === 200) {
        // 5. 解析 HTTP 响应
        let resData = JSON.parse(response.result as string) as LLMResponse;
        let aiOutput: string = resData.choices[0].message.content;

        // 6. 清洗 AI 可能误带的 Markdown 代码块残留
        let cleanJsonStr = NLPUtils.cleanMarkdownJson(aiOutput);
        let parsedObj = JSON.parse(cleanJsonStr) as ParsedTask;

        let taskId = Date.now().toString();
        let timestamp = new Date(parsedObj.timestamp).getTime();
        if (isNaN(timestamp) || timestamp <= 0) {
          timestamp = TimeUtils.parseChineseTimeToTimestamp(parsedObj.time);
        }

        console.info('云端解析成功: ' + cleanJsonStr);
        return new TaskItem(taskId, parsedObj.content, parsedObj.time, timestamp, parsedObj.tags);

      } else {
        console.error('云端请求失败，HTTP状态码: ' + response.responseCode);
        promptAction.showToast({ message: '云端请求失败，已切换至本地解析模式' });
        return await NLPUtils.analyzeWithLocalRegEx(rawText);
      }

    } catch (err) {
      console.error('云端大模型网络请求异常: ' + JSON.stringify(err));
      promptAction.showToast({ message: '网络异常，已切换至本地解析服务' });
      return await NLPUtils.analyzeWithLocalRegEx(rawText);
    } finally {
      httpRequest.destroy();
    }
  }

  /**
   * 清洗 AI 返回内容中的 Markdown 代码块标记
   */
  private static cleanMarkdownJson(raw: string): string {
    let result = raw.trim();
    // 去掉开头的 ```json 或 ```
    if (result.startsWith('```json')) {
      result = result.substring(7);
    } else if (result.startsWith('```')) {
      result = result.substring(3);
    }
    // 去掉结尾的 ```
    if (result.endsWith('```')) {
      result = result.substring(0, result.length - 3);
    }
    return result.trim();
  }

  // ========================
  //  搜索意图解析
  // ========================

  /**
   * 统一入口：解析用户的搜索查询为结构化搜索意图
   * 云端优先，本地降级
   */
  public static async parseSearchIntent(query: string): Promise<SearchIntent> {
    let useCloud = AppStorage.get<boolean>('useCloudModel') || false;
    let apiKey = AppStorage.get<string>('cloudApiKey') || '';

    if (useCloud && apiKey.length > 0) {
      console.info('搜索意图走向：云端大模型');
      try {
        return await NLPUtils.parseSearchIntentCloud(query);
      } catch (err) {
        console.error('云端搜索意图解析失败，降级本地: ' + JSON.stringify(err));
        return NLPUtils.parseSearchIntentLocal(query);
      }
    } else {
      console.info('搜索意图走向：本地关键词');
      return NLPUtils.parseSearchIntentLocal(query);
    }
  }

  /**
   * 云端解析搜索意图
   */
  private static async parseSearchIntentCloud(query: string): Promise<SearchIntent> {
    let apiUrl = AppStorage.get<string>('cloudApiUrl') || '';
    let apiKey = AppStorage.get<string>('cloudApiKey') || '';
    let apiModel = AppStorage.get<string>('cloudApiModel') || '';

    if (!apiUrl.endsWith('/chat/completions')) {
      let trimmed = apiUrl.replace(/\/+$/, '');
      apiUrl = trimmed + '/chat/completions';
    }

    let httpRequest = http.createHttp();

    let now = new Date();
    let yearStr = now.getFullYear().toString();
    let monthStr = String(now.getMonth() + 1).padStart(2, '0');
    let dayStr = String(now.getDate()).padStart(2, '0');
    let currentDateStr = yearStr + '-' + monthStr + '-' + dayStr;
    let weekDays: string[] = ['日', '一', '二', '三', '四', '五', '六'];
    let weekDayStr = weekDays[now.getDay()];

    let systemPrompt = '你是一个搜索意图解析器。当前日期是 ' + currentDateStr + '（星期' + weekDayStr + '）。'
      + '用户输入一个搜索查询，请提取以下字段：'
      + 'keywords：搜索关键词数组（提取核心名词和动词。必须去掉"任务"、"日程"、"事情"、"帮我找"等无实际意义的词！如果没有具体内容的搜索词，请务必返回空数组 []）；'
      + 'startTime：时间范围起始（格式如 "' + yearStr + '-05-15 00:00:00"），没有时间限制则返回空字符串；'
      + 'endTime：时间范围截止（格式如 "' + yearStr + '-05-15 23:59:59"），没有时间限制则返回空字符串；'
      + 'tags：可能相关的标签（如"技术""学习""紧急"等）。'
      + '请严格且仅返回JSON格式，不要包含任何markdown标记或解释。'
      + '范例：用户输入"下周关于开会的事" 则返回 {"keywords":["开会"],"startTime":"' + yearStr + '-06-01 00:00:00","endTime":"' + yearStr + '-06-07 23:59:59","tags":[]}';

    let msgList: ReqMessage[] = [
      { role: "system", content: systemPrompt },
      { role: "user", content: query }
    ];
    let requestData: LLMRequest = {
      model: apiModel,
      messages: msgList,
      temperature: 0.1
    };

    try {
      let response = await httpRequest.request(
        apiUrl,
        {
          method: http.RequestMethod.POST,
          header: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ' + apiKey
          },
          extraData: JSON.stringify(requestData),
          connectTimeout: 15000,
          readTimeout: 30000
        }
      );

      if (response.responseCode === 200) {
        let resData = JSON.parse(response.result as string) as LLMResponse;
        let aiOutput = resData.choices[0].message.content;
        let cleanJson = NLPUtils.cleanMarkdownJson(aiOutput);
        let parsed = JSON.parse(cleanJson) as ParsedSearchIntent;

        let result = new SearchIntent();
        result.keywords = parsed.keywords || [];
        // 兼容 ArkTS 严谨的日期解析：把横杠转为斜杠，把T转为空格，避免 UTC/本地时区错乱
        let parseTime = (timeStr?: string) => {
          if (!timeStr) return 0;
          let safeStr = timeStr.replace(/-/g, '/').replace('T', ' ');
          return new Date(safeStr).getTime();
        };
        result.startTime = parseTime(parsed.startTime);
        result.endTime = parseTime(parsed.endTime);
        result.tags = parsed.tags || [];

        console.info('搜索意图解析成功: ' + cleanJson);
        return result;
      } else {
        throw new Error('HTTP ' + response.responseCode);
      }
    } finally {
      httpRequest.destroy();
    }
  }

  /**
   * 本地降级：简单关键词提取 + 基础时间范围识别
   */
  private static parseSearchIntentLocal(query: string): SearchIntent {
    let keywords: string[] = [];
    let startTime: number = 0;
    let endTime: number = 0;
    let tags: string[] = [];
    let now = new Date();

    // 1. 识别时间范围关键词
    if (query.includes('今天')) {
      let todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
      startTime = todayStart.getTime();
      endTime = todayStart.getTime() + 24 * 60 * 60 * 1000 - 1;
    } else if (query.includes('昨天')) {
      let yesterdayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1);
      startTime = yesterdayStart.getTime();
      endTime = yesterdayStart.getTime() + 24 * 60 * 60 * 1000 - 1;
    } else if (query.includes('明天')) {
      let tomorrowStart = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
      startTime = tomorrowStart.getTime();
      endTime = tomorrowStart.getTime() + 24 * 60 * 60 * 1000 - 1;
    } else if (query.includes('后天')) {
      let dayAfterTomorrowStart = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 2);
      startTime = dayAfterTomorrowStart.getTime();
      endTime = dayAfterTomorrowStart.getTime() + 24 * 60 * 60 * 1000 - 1;
    } else if (query.includes('上周') || query.includes('上个星期')) {
      let currentDay = now.getDay();
      let lastWeekEnd = new Date(now.getFullYear(), now.getMonth(), now.getDate() - currentDay);
      let lastWeekStart = new Date(lastWeekEnd.getFullYear(), lastWeekEnd.getMonth(), lastWeekEnd.getDate() - 7);
      startTime = lastWeekStart.getTime();
      endTime = lastWeekEnd.getTime() + 24 * 60 * 60 * 1000 - 1;
    } else if (query.includes('这周') || query.includes('本周')) {
      let currentDay = now.getDay();
      let weekStart = new Date(now.getFullYear(), now.getMonth(), now.getDate() - currentDay + 1);
      startTime = weekStart.getTime();
      endTime = now.getTime();
    } else if (query.includes('下周') || query.includes('下个星期')) {
      let currentDay = now.getDay();
      let nextWeekStart = new Date(now.getFullYear(), now.getMonth(), now.getDate() + (8 - currentDay));
      startTime = nextWeekStart.getTime();
      endTime = nextWeekStart.getTime() + 7 * 24 * 60 * 60 * 1000 - 1;
    } else if (query.includes('上个月')) {
      let lastMonthStart = new Date(now.getFullYear(), now.getMonth() - 1, 1);
      let lastMonthEnd = new Date(now.getFullYear(), now.getMonth(), 0);
      startTime = lastMonthStart.getTime();
      endTime = lastMonthEnd.getTime() + 24 * 60 * 60 * 1000 - 1;
    }

    // 2. 提取关键词（去掉时间词和无意义词）
    let cleanedQuery = query
      .replace(/今天|昨天|明天|后天|上周|下周|上个星期|下个星期|这周|本周|上个月|最近/g, '')
      .replace(/帮我找|帮我搜|搜索|查找|找一下|有没有|关于|的事|的任务|的日程/g, '')
      .trim();

    if (cleanedQuery.length > 0) {
      // 简单分词：按空格和常见连接词拆分
      let words = cleanedQuery.split(/[\s，,、和跟]+/);
      for (let w of words) {
        if (w.length > 0) {
          keywords.push(w);
        }
      }
    }

    // 3. 从关键词推断标签
    if (query.includes('代码') || query.includes('编程') || query.includes('Bug')) {
      tags.push('技术');
    }
    if (query.includes('紧急') || query.includes('重要')) {
      tags.push('紧急');
    }
    if (query.includes('学习') || query.includes('复习') || query.includes('作业')) {
      tags.push('学习');
    }

    console.info('本地搜索意图: keywords=' + keywords.join(',') + ', startTime=' + startTime + ', endTime=' + endTime);

    let result = new SearchIntent();
    result.keywords = keywords;
    result.startTime = startTime;
    result.endTime = endTime;
    result.tags = tags;
    return result;
  }

}
