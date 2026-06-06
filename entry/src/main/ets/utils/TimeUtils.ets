/**
 * 时间工具类
 * 负责将中文相对时间表达式（如"明天 14:00""后天 下午三点"）转换为 Unix 毫秒时间戳
 */
export class TimeUtils {

  /**
   * 将中文时间表达式转换为 Unix 毫秒时间戳
   * 如果无法解析，返回当前时间（兜底）
   */
  public static parseChineseTimeToTimestamp(timeStr: string): number {
    let now = new Date();
    let targetDate = new Date(now.getTime());

    // 1. 解析日期偏移（今天/明天/后天/大后天/下周X）
    if (timeStr.includes('大后天')) {
      targetDate.setDate(now.getDate() + 3);
    } else if (timeStr.includes('后天')) {
      targetDate.setDate(now.getDate() + 2);
    } else if (timeStr.includes('明天') || timeStr.includes('明日')) {
      targetDate.setDate(now.getDate() + 1);
    } else if (timeStr.includes('今天') || timeStr.includes('今日')) {
      // 不偏移
    } else if (timeStr.includes('下周') || timeStr.includes('下个星期') || timeStr.includes('下个周')) {
      let dayOffset = TimeUtils.parseWeekday(timeStr);
      if (dayOffset >= 0) {
        let currentDay = now.getDay();
        let daysUntilNextWeekday = (7 - currentDay) + dayOffset;
        if (dayOffset === 0) {
          daysUntilNextWeekday = 7;
        }
        targetDate.setDate(now.getDate() + daysUntilNextWeekday);
      }
    } else if (timeStr.includes('周') || timeStr.includes('星期')) {
      let dayOffset = TimeUtils.parseWeekday(timeStr);
      if (dayOffset >= 0) {
        let currentDay = now.getDay();
        let diff = dayOffset - currentDay;
        if (diff <= 0) {
          diff += 7;
        }
        targetDate.setDate(now.getDate() + diff);
      }
    }

    // 2. 解析具体时间（HH:MM 格式）
    let timeMatch = timeStr.match(/(\d{1,2}):(\d{2})/);
    if (timeMatch !== null) {
      let h = parseInt(timeMatch[1]);
      let m = parseInt(timeMatch[2]);
      targetDate.setHours(h, m, 0, 0);
    } else {
      // 3. 解析模糊时间（早上/上午/中午/下午/晚上）
      if (timeStr.includes('早上') || timeStr.includes('早晨') || timeStr.includes('清晨')) {
        targetDate.setHours(8, 0, 0, 0);
      } else if (timeStr.includes('上午')) {
        targetDate.setHours(10, 0, 0, 0);
      } else if (timeStr.includes('中午')) {
        targetDate.setHours(12, 0, 0, 0);
      } else if (timeStr.includes('下午')) {
        let chineseHour = TimeUtils.parseChineseHour(timeStr);
        if (chineseHour > 0) {
          let finalHour = chineseHour >= 12 ? chineseHour : chineseHour + 12;
          targetDate.setHours(finalHour, 0, 0, 0);
        } else {
          targetDate.setHours(14, 0, 0, 0);
        }
      } else if (timeStr.includes('晚上') || timeStr.includes('晚间') || timeStr.includes('今晚')) {
        targetDate.setHours(20, 0, 0, 0);
      } else if (timeStr.includes('稍后')) {
        return now.getTime();
      } else {
        targetDate.setHours(9, 0, 0, 0);
      }
    }

    return targetDate.getTime();
  }

  /**
   * 从时间字符串中解析星期几
   * 返回 0-6（周日-周六），未匹配返回 -1
   */
  private static parseWeekday(timeStr: string): number {
    if (timeStr.includes('周日') || timeStr.includes('星期日') || timeStr.includes('星期天')) {
      return 0;
    }
    if (timeStr.includes('周一') || timeStr.includes('星期一')) {
      return 1;
    }
    if (timeStr.includes('周二') || timeStr.includes('星期二')) {
      return 2;
    }
    if (timeStr.includes('周三') || timeStr.includes('星期三')) {
      return 3;
    }
    if (timeStr.includes('周四') || timeStr.includes('星期四')) {
      return 4;
    }
    if (timeStr.includes('周五') || timeStr.includes('星期五')) {
      return 5;
    }
    if (timeStr.includes('周六') || timeStr.includes('星期六')) {
      return 6;
    }
    return -1;
  }

  /**
   * 解析中文数字小时（如"三点""八点半"）
   * 返回小时数，未匹配返回 -1
   */
  private static parseChineseHour(timeStr: string): number {
    // 匹配中文数字 "X点" 模式
    if (timeStr.includes('一点')) return 1;
    if (timeStr.includes('二点')) return 2;
    if (timeStr.includes('三点')) return 3;
    if (timeStr.includes('四点')) return 4;
    if (timeStr.includes('五点')) return 5;
    if (timeStr.includes('六点')) return 6;
    if (timeStr.includes('七点')) return 7;
    if (timeStr.includes('八点')) return 8;
    if (timeStr.includes('九点')) return 9;
    if (timeStr.includes('十二点')) return 12;
    if (timeStr.includes('十一点')) return 11;
    if (timeStr.includes('十点')) return 10;

    // 匹配阿拉伯数字 "3点"
    let digitMatch = timeStr.match(/(\d{1,2})点/);
    if (digitMatch !== null) {
      return parseInt(digitMatch[1]);
    }

    return -1;
  }

  /**
   * 将时间戳格式化为友好的显示文案
   * 用于在搜索结果等场景下展示真实日期
   */
  public static formatTimestamp(timestamp: number): string {
    if (timestamp <= 0) return '未设定时间';

    let date = new Date(timestamp);
    let now = new Date();

    let month = date.getMonth() + 1;
    let day = date.getDate();
    let hours = String(date.getHours()).padStart(2, '0');
    let minutes = String(date.getMinutes()).padStart(2, '0');

    let todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
    let targetDayStart = new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
    let dayDiff = Math.round((targetDayStart - todayStart) / (1000 * 60 * 60 * 24));

    if (dayDiff === 0) return '今天 ' + hours + ':' + minutes;
    if (dayDiff === 1) return '明天 ' + hours + ':' + minutes;
    if (dayDiff === -1) return '昨天 ' + hours + ':' + minutes;

    return month + '月' + day + '日 ' + hours + ':' + minutes;
  }
}
