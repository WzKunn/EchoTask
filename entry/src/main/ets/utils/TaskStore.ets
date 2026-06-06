import relationalStore from '@ohos.data.relationalStore';
import { common } from '@kit.AbilityKit';
import { TaskItem } from '../pages/HomeView';

// 2. 数据库常量与 SQL 语句
const STORE_CONFIG: relationalStore.StoreConfig = {
  name: 'EchoTask.db', // 数据库文件名
  securityLevel: relationalStore.SecurityLevel.S1 // 安全级别
};
const TABLE_NAME = 'TASK_TABLE';
// 创建表的 SQL 语句 (id 为主键，tags 存为 TEXT，新增 timestamp)
const SQL_CREATE_TABLE = 'CREATE TABLE IF NOT EXISTS ' + TABLE_NAME + ' (' +
  'id TEXT PRIMARY KEY, ' +
  'content TEXT, ' +
  'time TEXT, ' +
  'timestamp INTEGER DEFAULT 0, ' +
  'tags TEXT' +
')';
// 旧版迁移：尝试为已有表添加 timestamp 列
const SQL_ADD_TIMESTAMP_COLUMN = 'ALTER TABLE ' + TABLE_NAME + ' ADD COLUMN timestamp INTEGER DEFAULT 0';
// 迁移兜底：用 id（Date.now 字符串）填充旧数据的 timestamp
const SQL_BACKFILL_TIMESTAMP = 'UPDATE ' + TABLE_NAME + ' SET timestamp = CAST(id AS INTEGER) WHERE timestamp = 0 AND id != \'welcome_id\'';

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

      // 尝试迁移：为旧版本数据库添加 timestamp 列
      // 如果列已存在，ALTER TABLE 会抛异常，catch 后静默忽略即可
      try {
        await this.rdbStore.executeSql(SQL_ADD_TIMESTAMP_COLUMN);
        console.info('[DB] 迁移成功：已添加 timestamp 列');
        // 新列添加成功后，用 id 回填旧数据的 timestamp
        await this.rdbStore.executeSql(SQL_BACKFILL_TIMESTAMP);
        console.info('[DB] 旧数据 timestamp 回填完成');
      } catch (migrateErr) {
        // 列已存在，正常现象，静默忽略
        console.info('[DB] timestamp 列已存在，跳过迁移');
      }

    } catch (err) {
      console.error('[DB] 数据库初始化失败: ' + JSON.stringify(err));
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
      'timestamp': task.timestamp,
      'tags': JSON.stringify(task.tags) // 【核心技巧】：数组转字符串
    };

    try {
      let rowId = await this.rdbStore.insert(TABLE_NAME, valueBucket);
      console.info('[DB] 成功插入任务，RowId: ' + rowId);
      return true;
    } catch (err) {
      console.error('[DB] 插入任务失败: ' + JSON.stringify(err));
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
      console.info('[DB] 成功删除任务，影响行数: ' + rows);
      return true;
    } catch (err) {
      console.error('[DB] 删除任务失败: ' + JSON.stringify(err));
      return false;
    }
  }


  // 查：获取所有任务
  public async queryAllTasks(): Promise<TaskItem[]> {
    if (!this.rdbStore) return [];

    let tasks: TaskItem[] = [];
    let predicates = new relationalStore.RdbPredicates(TABLE_NAME);

    // 按 timestamp 降序排列（最新的任务在最前面）
    predicates.orderByDesc('timestamp');

    try {
      // 执行查询，拿到结果集 (ResultSet)
      let resultSet = await this.rdbStore.query(predicates, ['id', 'content', 'time', 'timestamp', 'tags']);

      // 遍历结果集游标，组装成对象数组
      while (resultSet.goToNextRow()) {
        let id = resultSet.getString(resultSet.getColumnIndex('id'));
        let content = resultSet.getString(resultSet.getColumnIndex('content'));
        let time = resultSet.getString(resultSet.getColumnIndex('time'));
        let timestamp = resultSet.getLong(resultSet.getColumnIndex('timestamp'));
        let tagsStr = resultSet.getString(resultSet.getColumnIndex('tags'));

        let tags: string[] = [];
        try {
          tags = JSON.parse(tagsStr); // 【核心技巧】：字符串转回数组
        } catch (e) {
          console.warn('[DB] Tags 解析失败，使用空数组');
        }

        tasks.push(new TaskItem(id, content, time, timestamp, tags));
      }

      // 释放结果集内存 (极其重要！否则会导致内存泄漏)
      resultSet.close();
      return tasks;

    } catch (err) {
      console.error('[DB] 查询任务失败: ' + JSON.stringify(err));
      return [];
    }
  }

  /**
   * 语义搜索：根据关键词、时间范围、标签过滤任务
   * @param keywords 关键词数组（模糊匹配 content）
   * @param startTime 时间范围起始（Unix 毫秒），可选
   * @param endTime 时间范围截止（Unix 毫秒），可选
   * @param tags 标签过滤（任意匹配），可选
   */
  public async searchTasks(keywords: string[], startTime?: number, endTime?: number, tags?: string[]): Promise<TaskItem[]> {
    if (!this.rdbStore) return [];

    let tasks: TaskItem[] = [];

    // 构建 SQL 查询条件
    let conditions: string[] = [];
    let args: string[] = [];

    // 关键词条件：content LIKE '%keyword%'
    if (keywords.length > 0) {
      let keywordConditions: string[] = [];
      for (let kw of keywords) {
        keywordConditions.push('content LIKE ?');
        args.push('%' + kw + '%');
      }
      conditions.push('(' + keywordConditions.join(' OR ') + ')');
    }

    // 时间范围条件
    if (startTime !== undefined && startTime > 0) {
      conditions.push('timestamp >= ?');
      args.push(startTime.toString());
    }
    if (endTime !== undefined && endTime > 0) {
      conditions.push('timestamp <= ?');
      args.push(endTime.toString());
    }

    // 标签条件：tags LIKE '%标签%'（因为 tags 存储为 JSON 字符串）
    if (tags && tags.length > 0) {
      let tagConditions: string[] = [];
      for (let tag of tags) {
        tagConditions.push('tags LIKE ?');
        args.push('%' + tag + '%');
      }
      conditions.push('(' + tagConditions.join(' OR ') + ')');
    }

    // 如果没有任何条件，返回空（避免查出全部）
    if (conditions.length === 0) {
      console.warn('[DB] 搜索条件为空，跳过查询');
      return [];
    }

    let whereClause = conditions.join(' AND ');
    let sql = 'SELECT id, content, time, timestamp, tags FROM ' + TABLE_NAME + ' WHERE ' + whereClause + ' ORDER BY timestamp DESC';

    try {
      let resultSet = await this.rdbStore.querySql(sql, args);

      while (resultSet.goToNextRow()) {
        let id = resultSet.getString(resultSet.getColumnIndex('id'));
        let content = resultSet.getString(resultSet.getColumnIndex('content'));
        let time = resultSet.getString(resultSet.getColumnIndex('time'));
        let timestamp = resultSet.getLong(resultSet.getColumnIndex('timestamp'));
        let tagsStr = resultSet.getString(resultSet.getColumnIndex('tags'));

        let parsedTags: string[] = [];
        try {
          parsedTags = JSON.parse(tagsStr);
        } catch (e) {
          console.warn('[DB] Tags 解析失败');
        }

        tasks.push(new TaskItem(id, content, time, timestamp, parsedTags));
      }

      resultSet.close();
      console.info('[DB] 搜索完成，找到 ' + tasks.length + ' 条结果');
      return tasks;

    } catch (err) {
      console.error('[DB] 搜索任务失败: ' + JSON.stringify(err));
      return [];
    }
  }
}

// 导出一个全局可用的实例
export const taskStore = TaskStore.getInstance();
