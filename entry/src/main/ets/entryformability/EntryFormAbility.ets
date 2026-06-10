import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import relationalStore from '@ohos.data.relationalStore';

interface FormData {
  taskTitle: string;
  taskTime: string;
  taskCount: string;
}

const STORE_CONFIG: relationalStore.StoreConfig = {
  name: 'EchoTask.db',
  securityLevel: relationalStore.SecurityLevel.S1
};
const TABLE_NAME = 'TASK_TABLE';

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    // 先返回默认数据，然后异步加载真实日程
    let formData: FormData = {
      taskTitle: '加载中...',
      taskTime: '',
      taskCount: '0'
    };

    // 异步从数据库读取真实日程
    this.loadTasksForWidget(want);

    return formBindingData.createFormBindingData(formData);
  }

  private async loadTasksForWidget(want: Want): Promise<void> {
    try {
      // 使用 FormExtensionAbility 自带的 context 打开同一个数据库
      let rdbStore = await relationalStore.getRdbStore(this.context, STORE_CONFIG);

      // 优先查询未来即将发生的未完成任务（最近的排前面）
      let now = Date.now();
      let predicates = new relationalStore.RdbPredicates(TABLE_NAME);
      predicates.equalTo('isCompleted', 0);
      predicates.greaterThanOrEqualTo('timestamp', now);
      predicates.orderByAsc('timestamp');

      let resultSet = await rdbStore.query(predicates, ['content', 'time', 'timestamp']);
      let totalCount = resultSet.rowCount;
      
      // 如果未来没有日程，尝试获取过去未完成的日程（最近过期的排前面）
      if (totalCount === 0) {
        resultSet.close();
        let pastPredicates = new relationalStore.RdbPredicates(TABLE_NAME);
        pastPredicates.equalTo('isCompleted', 0);
        pastPredicates.lessThan('timestamp', now);
        pastPredicates.orderByDesc('timestamp'); // 最近过期的优先
        resultSet = await rdbStore.query(pastPredicates, ['content', 'time', 'timestamp']);
        
        // 我们还需要查一下数据库总共有多少未完成的，因为刚刚查的只是过期的
        let allUncompleted = new relationalStore.RdbPredicates(TABLE_NAME);
        allUncompleted.equalTo('isCompleted', 0);
        let countSet = await rdbStore.query(allUncompleted, ['id']);
        totalCount = countSet.rowCount;
        countSet.close();
      } else {
        // 如果有未来的任务，需要查一下真正的总未完成数量
        let allUncompleted = new relationalStore.RdbPredicates(TABLE_NAME);
        allUncompleted.equalTo('isCompleted', 0);
        let countSet = await rdbStore.query(allUncompleted, ['id']);
        totalCount = countSet.rowCount;
        countSet.close();
      }

      let nextTitle = '暂无待办日程';
      let nextTime = '点击添加新任务';

      // 取第一条任务作为卡片展示内容
      if (resultSet.goToNextRow()) {
        nextTitle = resultSet.getString(resultSet.getColumnIndex('content'));
        nextTime = resultSet.getString(resultSet.getColumnIndex('time'));
      }

      resultSet.close();

      let formData: FormData = {
        taskTitle: nextTitle,
        taskTime: nextTime,
        taskCount: totalCount.toString()
      };

      // 获取 formId 并更新卡片
      if (want.parameters) {
        let formId = want.parameters['ohos.extra.param.key.form_identity'] as string;
        if (formId) {
          let bindingData = formBindingData.createFormBindingData(formData);
          formProvider.updateForm(formId, bindingData);
          console.info(`[Widget] 卡片已更新: ${nextTitle}, 共 ${totalCount} 项待办`);
        }
      }
    } catch (err) {
      console.error('[Widget] 读取数据库失败: ' + JSON.stringify(err));
    }
  }

  onUpdateForm(formId: string) {
    // 定时刷新时也从数据库读取最新数据
    this.refreshWidget(formId);
  }

  private async refreshWidget(formId: string): Promise<void> {
    try {
      let rdbStore = await relationalStore.getRdbStore(this.context, STORE_CONFIG);

      // 优先查询未来即将发生的未完成任务
      let now = Date.now();
      let predicates = new relationalStore.RdbPredicates(TABLE_NAME);
      predicates.equalTo('isCompleted', 0);
      predicates.greaterThanOrEqualTo('timestamp', now);
      predicates.orderByAsc('timestamp');

      let resultSet = await rdbStore.query(predicates, ['content', 'time', 'timestamp']);
      let totalCount = resultSet.rowCount;
      
      if (totalCount === 0) {
        resultSet.close();
        let pastPredicates = new relationalStore.RdbPredicates(TABLE_NAME);
        pastPredicates.equalTo('isCompleted', 0);
        pastPredicates.lessThan('timestamp', now);
        pastPredicates.orderByDesc('timestamp');
        resultSet = await rdbStore.query(pastPredicates, ['content', 'time', 'timestamp']);
        
        let allUncompleted = new relationalStore.RdbPredicates(TABLE_NAME);
        allUncompleted.equalTo('isCompleted', 0);
        let countSet = await rdbStore.query(allUncompleted, ['id']);
        totalCount = countSet.rowCount;
        countSet.close();
      } else {
        let allUncompleted = new relationalStore.RdbPredicates(TABLE_NAME);
        allUncompleted.equalTo('isCompleted', 0);
        let countSet = await rdbStore.query(allUncompleted, ['id']);
        totalCount = countSet.rowCount;
        countSet.close();
      }

      let nextTitle = '暂无待办日程';
      let nextTime = '点击添加新任务';

      if (resultSet.goToNextRow()) {
        nextTitle = resultSet.getString(resultSet.getColumnIndex('content'));
        nextTime = resultSet.getString(resultSet.getColumnIndex('time'));
      }

      resultSet.close();

      let formData: FormData = {
        taskTitle: nextTitle,
        taskTime: nextTime,
        taskCount: totalCount.toString()
      };

      let bindingData = formBindingData.createFormBindingData(formData);
      formProvider.updateForm(formId, bindingData);
      console.info(`[Widget] 定时刷新完成: ${nextTitle}`);
    } catch (err) {
      console.error('[Widget] 定时刷新失败: ' + JSON.stringify(err));
    }
  }

  onChangeFormVisibility(newStatus: Record<string, number>) {
    // 状态变化
  }

  onFormEvent(formId: string, message: string) {
    // 处理卡片内部事件
  }

  onRemoveForm(formId: string) {
    // 销毁清理
  }

  onAcquireFormState(want: Want) {
    return formInfo.FormState.READY;
  }
}
