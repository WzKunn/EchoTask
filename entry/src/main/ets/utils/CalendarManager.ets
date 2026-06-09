import { calendarManager } from '@kit.CalendarKit';
import { common } from '@kit.AbilityKit';
import { TaskItem } from '../pages/HomeView';

export class CalendarManager {
  private static instance: CalendarManager;
  private calendarMgr: calendarManager.CalendarManager | null = null;
  private myCalendar: calendarManager.Calendar | null = null;

  // 日历账户配置
  private readonly CALENDAR_ACCOUNT: calendarManager.CalendarAccount = {
    name: 'EchoTask',
    type: calendarManager.CalendarType.LOCAL,
    displayName: 'EchoTask' // 用户在系统日历里看到的名称
  };

  public static getInstance(): CalendarManager {
    if (!CalendarManager.instance) {
      CalendarManager.instance = new CalendarManager();
    }
    return CalendarManager.instance;
  }

  // 初始化，确保账户存在
  public async init(context: common.UIAbilityContext) {
    this.calendarMgr = calendarManager.getCalendarManager(context);

    try {
      // 1. 尝试获取已有的灵犀日历
      this.myCalendar = await this.calendarMgr.getCalendar(this.CALENDAR_ACCOUNT);
    } catch (e) {
      // 2. 如果不存在，则创建一个新的
      this.myCalendar = await this.calendarMgr.createCalendar(this.CALENDAR_ACCOUNT);
      // 设置账户颜色为科技蓝
      await this.myCalendar.setConfig({ color: '#3b82f6' });
    }
    console.info('日历账户初始化成功');
  }

  // 解析时间
  private parseTaskTime(timeStr: string): number {
    // 1. 获取当前时间的基准点 (今天凌晨 00:00:00)
    let now = new Date();
    let targetDate = new Date(now.getFullYear(), now.getMonth(), now.getDate());

    // 2. 解析日期偏移 (今天、明天、后天)
    if (timeStr.includes('明天') || timeStr.includes('明早') || timeStr.includes('明晚')) {
      targetDate.setDate(targetDate.getDate() + 1);
    } else if (timeStr.includes('后天')) {
      targetDate.setDate(targetDate.getDate() + 2);
    }
    // 如果都没有，默认就是今天

    // 3. 解析具体时刻 (通过正则表达式抓取 HH:mm 格式)
    // 兼容中文冒号 "：" 和英文冒号 ":"
    const timeRegex = /(\d{1,2})[:：](\d{2})/;
    const match = timeStr.match(timeRegex);

    if (match) {
      let hours = parseInt(match[1], 10);
      let minutes = parseInt(match[2], 10);

      // 简单处理一下"下午"的逻辑 (比如用户说 "明天下午 2:00")
      if (timeStr.includes('下午') || timeStr.includes('晚上')) {
        if (hours < 12) hours += 12;
      }

      targetDate.setHours(hours, minutes, 0, 0);
    } else {
      // 兜底逻辑：如果没提取到具体时间（比如用户只说了"明天"）
      // 默认设置为上午 9 点
      targetDate.setHours(9, 0, 0, 0);
    }

    // 4. 返回计算好的时间戳
    return targetDate.getTime();
  }

  // 将TaskItem添加到系统日历
  public async addEvent(task: TaskItem): Promise<boolean> {
    if (!this.myCalendar) return false;

    // 直接使用任务的精准时间戳，不再重新解析文字
    let startTime = task.timestamp;
    if (startTime <= 0) {
      // 兜底：如果时间戳无效，使用当前时间
      startTime = Date.now();
    }
    let endTime = startTime + 60 * 60 * 1000;

    let event: calendarManager.Event = {
      title: '[EchoTask] ' + task.content,
      startTime: startTime,
      endTime: endTime,
      type: calendarManager.EventType.NORMAL,
      description: '来自EchoTask的智能提醒。标签: ' + task.tags.join(', '),
      // 设置提醒：日程开始前 10 分钟弹窗
      reminderTime: [10]
    };

    try {
      await this.myCalendar.addEvent(event);
      return true;
    } catch (err) {
      console.error('写入日历失败:', err);
      return false;
    }
  }
}

export const calendarMgr = CalendarManager.getInstance();