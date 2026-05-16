import relationalStore from '@ohos.data.relationalStore';
import { common } from '@kit.AbilityKit';
import { TaskItem } from '../pages/HomeView';

// 2. 数据库常量与 SQL 语句
const STORE_CONFIG: relationalStore.StoreConfig = {
  name: 'EchoTask.db', // 数据库文件名
  securityLevel: relationalStore.SecurityLevel.S1 // 安全级别
};
const TABLE_NAME = 'TASK_TABLE';
// 创建表的 SQL 语句 (id 为主键，tags 存为 TEXT)
const SQL_CREATE_TABLE = `CREATE TABLE IF NOT EXISTS ${TABLE_NAME} (
  id TEXT PRIMARY KEY,
  content TEXT,
  time TEXT,
  tags TEXT
)`;

export class TaskStore {
  private rdbStore: relationalStore.RdbStore | null = null;
  private static instance: TaskStore;

  // 获取单例
  public static getInstance(): TaskStore {
    if (!TaskStore.instance) {
      TaskStore.instance = new TaskStore();
    }
    return TaskStore.instance;
  }

  // 初始化数据库并建表
  public async initDB(context: common.UIAbilityContext): Promise<void> {
    try {
      this.rdbStore = await relationalStore.getRdbStore(context, STORE_CONFIG);
      await this.rdbStore.executeSql(SQL_CREATE_TABLE);
      console.info('[DB] 数据库初始化并建表成功');
    } catch (err) {
      console.error('[DB] 数据库初始化失败:', err);
    }
  }

  // 插入新任务
  public async insertTask(task: TaskItem): Promise<boolean> {
    if (!this.rdbStore) return false;

    // 将对象转为数据库认识的键值对 (ValuesBucket)
    const valueBucket: relationalStore.ValuesBucket = {
      'id': task.id,
      'content': task.content,
      'time': task.time,
      'tags': JSON.stringify(task.tags) // 【核心技巧】：数组转字符串
    };

    try {
      let rowId = await this.rdbStore.insert(TABLE_NAME, valueBucket);
      console.info(`[DB] 成功插入任务，RowId: ${rowId}`);
      return true;
    } catch (err) {
      console.error('[DB] 插入任务失败:', err);
      return false;
    }
  }

  // 根据id删除任务
  public async deleteTask(taskId: string): Promise<boolean> {
    if (!this.rdbStore) return false;

    // 构造删除条件 (WHERE id = ?)
    let predicates = new relationalStore.RdbPredicates(TABLE_NAME);
    predicates.equalTo('id', taskId);

    try {
      let rows = await this.rdbStore.delete(predicates);
      console.info(`[DB] 成功删除任务，影响行数: ${rows}`);
      return true;
    } catch (err) {
      console.error('[DB] 删除任务失败:', err);
      return false;
    }
  }


  // 查：获取所有任务
  public async queryAllTasks(): Promise<TaskItem[]> {
    if (!this.rdbStore) return [];

    let tasks: TaskItem[] = [];
    let predicates = new relationalStore.RdbPredicates(TABLE_NAME);

    // 强制要求数据库按照id降序排列
    predicates.orderByDesc('id');

    try {
      // 执行查询，拿到结果集 (ResultSet)
      let resultSet = await this.rdbStore.query(predicates, ['id', 'content', 'time', 'tags']);

      // 遍历结果集游标，组装成对象数组
      while (resultSet.goToNextRow()) {
        let id = resultSet.getString(resultSet.getColumnIndex('id'));
        let content = resultSet.getString(resultSet.getColumnIndex('content'));
        let time = resultSet.getString(resultSet.getColumnIndex('time'));
        let tagsStr = resultSet.getString(resultSet.getColumnIndex('tags'));

        let tags: string[] = [];
        try {
          tags = JSON.parse(tagsStr); // 【核心技巧】：字符串转回数组
        } catch (e) {
          console.warn('[DB] Tags 解析失败，使用空数组');
        }

        tasks.push(new TaskItem(id, content, time, tags));
      }

      // 释放结果集内存 (极其重要！否则会导致内存泄漏)
      resultSet.close();
      return tasks;

    } catch (err) {
      console.error('[DB] 查询任务失败:', err);
      return [];
    }
  }
}

// 导出一个全局可用的实例
export const taskStore = TaskStore.getInstance();