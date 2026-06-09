import { insightIntent } from '@kit.IntentsKit';
import { common } from '@kit.AbilityKit';
import { TaskItem } from '../pages/HomeView';

export class IntentManager {
  /**
   * 将任务共享给小艺建议
   * 系统会根据此共享意图数据，学习用户习惯并在负一屏进行日程提醒和建议推荐
   * @param context UIAbility 上下文
   * @param task 用户新创建的任务
   */
  public static async shareTaskIntent(context: common.UIAbilityContext, task: TaskItem): Promise<void> {
    // 构建符合 InsightIntent 接口规范的完整意图对象
    let intentData: insightIntent.InsightIntent = {
      // 意图名称，必须与 insight_intent.json 配置的 intentName 一致
      intentName: 'ViewTask',
      // 意图版本号，与 insight_intent.json 中的 intentVersion 一致
      intentVersion: '1.0.0',
      // 唯一标识符，用于区分每条共享记录
      identifier: task.id,
      // 意图动作信息：描述动作类型和触发时间
      intentActionInfo: {
        actionId: 'view_task_' + task.id,
        actionName: '查看日程',
        actionType: 'viewSchedule',
        triggerTime: task.timestamp.toString()
      },
      // 意图实体信息：包含具体的业务数据
      intentEntityInfo: {
        entityId: task.id,
        entityName: task.content,
        taskId: task.id,
        content: task.content,
        timestamp: task.timestamp.toString(),
        tags: task.tags.join(',')
      }
    };

    try {
      // 调用系统 API 共享意图（第二个参数为 InsightIntent 数组）
      let result = await insightIntent.shareIntent(context, [intentData]);
      console.info('[IntentManager] 意图共享至小艺建议成功:', JSON.stringify(result));
    } catch (error) {
      console.error('[IntentManager] 意图共享失败:', JSON.stringify(error));
    }
  }
}
