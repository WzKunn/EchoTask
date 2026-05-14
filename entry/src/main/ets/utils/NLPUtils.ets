import { TaskItem } from '../pages/HomeView';
import { textProcessing, EntityType } from '@kit.NaturalLanguageKit';

export class NLPUtils {

  /**
   * 接入官方 Natural Language Kit 进行实体抽取
   */
  public static async analyzeTaskSemantic(rawText: string): Promise<TaskItem> {
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
}
