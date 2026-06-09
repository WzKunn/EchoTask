import { InsightIntentExecutor, insightIntent } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';

export default class ViewTaskExecutor extends InsightIntentExecutor {
  // 当配置为前台模式时，系统会在需要拉起应用时调用此方法
  async onExecuteInUIAbilityForegroundMode(
    intentName: string, 
    params: Record<string, Object>, 
    windowStage: window.WindowStage
  ): Promise<insightIntent.ExecuteResult> {
    
    console.info(`[InsightIntent] Executing intent: ${intentName}, params: ${JSON.stringify(params)}`);
    
    // 如果是 ViewTask 意图
    if (intentName === 'ViewTask') {
      let taskId = params.taskId as string;
      if (taskId) {
        // 由于应用被拉起且可能需要显示特定页面
        // 在此处可以使用 AppStorage 传递任务ID，让页面监听到后高亮显示或打开详情
        AppStorage.setOrCreate('targetTaskIdFromIntent', taskId);
      }
    }

    // 返回执行成功的结果
    const result: insightIntent.ExecuteResult = { 
      code: 0, 
      result: { message: "Intent executed successfully" } 
    };
    return Promise.resolve(result);
  }
}
