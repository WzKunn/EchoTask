import { promptAction } from '@kit.ArkUI';
import { taskStore } from '../utils/TaskStore';

// 设置项数据结构
interface SettingItem {
  icon: string;
  label: string;
  showToggle: boolean;
}

@Component
export struct MineView {
  // 个人信息持久化
  @StorageLink('userNickname') userNickname: string = 'EchoTask 用户';
  @StorageLink('userSignature') userSignature: string = '用声音管理生活 ✨';

  // 云端模型配置
  @StorageLink('useCloudModel') useCloudModel: boolean = false;
  @StorageLink('cloudApiModel') cloudApiModel: string = '';
  @StorageLink('cloudApiKey') cloudApiKey: string = '';
  @StorageLink('cloudApiUrl') cloudApiUrl: string = '';

  // 统计数据
  @State totalTasks: number = 0;
  @State consecutiveDays: number = 0;

  // 编辑状态
  @State isEditingName: boolean = false;
  @State isEditingSign: boolean = false;
  @State editNameText: string = '';
  @State editSignText: string = '';

  // 云端配置展开状态
  @State isCloudExpanded: boolean = false;

  async aboutToAppear() {
    // 加载统计数据
    try {
      let tasks = await taskStore.queryAllTasks();
      this.totalTasks = tasks.length;
    } catch (err) {
      console.error('加载统计数据失败: ' + JSON.stringify(err));
    }

    // 计算连续使用天数
    this.calculateConsecutiveDays();
  }

  calculateConsecutiveDays() {
    // 从本地持久化中读取首次使用日期
    let firstUseDateStr: string = AppStorage.get<string>('firstUseDate') || '';
    let now = new Date();
    let todayStr = now.getFullYear() + '-'
      + String(now.getMonth() + 1).padStart(2, '0') + '-'
      + String(now.getDate()).padStart(2, '0');

    if (firstUseDateStr.length === 0) {
      // 首次使用，记录今天
      AppStorage.setOrCreate('firstUseDate', todayStr);
      this.consecutiveDays = 1;
    } else {
      // 计算天数差
      let firstDate = new Date(firstUseDateStr.replace(/-/g, '/'));
      let today = new Date(todayStr.replace(/-/g, '/'));
      let diffMs = today.getTime() - firstDate.getTime();
      this.consecutiveDays = Math.floor(diffMs / (24 * 60 * 60 * 1000)) + 1;
    }
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {

        // ==========================================
        // 1. 顶部个人信息卡片
        // ==========================================
        Column() {
          // 头像
          Stack() {
            // 外圈渐变光环
            Circle()
              .width(96)
              .height(96)
              .fill(Color.Transparent)
              .stroke('#dbeafe')
              .strokeWidth(3)

            // 头像背景圆
            Circle()
              .width(84)
              .height(84)
              .fill('#eff6ff')

            // 系统人物图标
            SymbolGlyph($r('sys.symbol.person_crop_circle_fill'))
              .fontSize(52)
              .fontColor(['#3b82f6'])
          }
          .width(96)
          .height(96)
          .margin({ top: 24 })

          // 昵称区域
          if (this.isEditingName) {
            Row({ space: 8 }) {
              TextInput({ text: this.editNameText, placeholder: '请输入昵称' })
                .fontSize(18)
                .layoutWeight(1)
                .height(40)
                .onChange((value: string) => {
                  this.editNameText = value;
                })

              Button('完成')
                .fontSize(13)
                .height(36)
                .backgroundColor('#3b82f6')
                .onClick(() => {
                  if (this.editNameText.trim().length > 0) {
                    this.userNickname = this.editNameText.trim();
                  }
                  this.isEditingName = false;
                })
            }
            .width('80%')
            .margin({ top: 14 })
          } else {
            Text(this.userNickname)
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor('#1e293b')
              .margin({ top: 14 })
              .onClick(() => {
                this.editNameText = this.userNickname;
                this.isEditingName = true;
              })
          }

          // 个性签名
          if (this.isEditingSign) {
            Row({ space: 8 }) {
              TextInput({ text: this.editSignText, placeholder: '请输入签名' })
                .fontSize(14)
                .layoutWeight(1)
                .height(36)
                .onChange((value: string) => {
                  this.editSignText = value;
                })

              Button('完成')
                .fontSize(13)
                .height(32)
                .backgroundColor('#3b82f6')
                .onClick(() => {
                  if (this.editSignText.trim().length > 0) {
                    this.userSignature = this.editSignText.trim();
                  }
                  this.isEditingSign = false;
                })
            }
            .width('80%')
            .margin({ top: 6 })
          } else {
            Text(this.userSignature)
              .fontSize(14)
              .fontColor('#94a3b8')
              .margin({ top: 6 })
              .onClick(() => {
                this.editSignText = this.userSignature;
                this.isEditingSign = true;
              })
          }

          // 提示文字
          Text('点击昵称或签名可编辑')
            .fontSize(11)
            .fontColor('#cbd5e1')
            .margin({ top: 4, bottom: 20 })
        }
        .width('100%')
        .backgroundColor(Color.White)
        .borderRadius(20)
        .shadow({ radius: 12, color: 'rgba(0,0,0,0.04)', offsetY: 4 })
        .alignItems(HorizontalAlign.Center)

        // ==========================================
        // 2. 数据统计栏
        // ==========================================
        Row() {
          // 总任务数
          Column() {
            Text(this.totalTasks.toString())
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor('#3b82f6')

            Text('总任务数')
              .fontSize(12)
              .fontColor('#94a3b8')
              .margin({ top: 4 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)

          // 分隔线
          Divider()
            .vertical(true)
            .height(40)
            .color('#e2e8f0')

          // 连续使用天数
          Column() {
            Text(this.consecutiveDays.toString())
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor('#8b5cf6')

            Text('连续使用(天)')
              .fontSize(12)
              .fontColor('#94a3b8')
              .margin({ top: 4 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
        .padding({ top: 20, bottom: 20 })
        .backgroundColor(Color.White)
        .borderRadius(20)
        .shadow({ radius: 12, color: 'rgba(0,0,0,0.04)', offsetY: 4 })

        // ==========================================
        // 3. 智能引擎配置卡片
        // ==========================================
        Column({ space: 0 }) {
          // 标题
          Row() {
            SymbolGlyph($r('sys.symbol.gearshape'))
              .fontSize(18)
              .fontColor(['#f59e0b'])

            Text('智能引擎')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor('#1e293b')
              .margin({ left: 8 })
          }
          .width('100%')
          .padding({ left: 16, top: 16, bottom: 12 })

          // 云端模型开关
          Row() {
            SymbolGlyph($r('sys.symbol.cloud'))
              .fontSize(18)
              .fontColor(['#3b82f6'])

            Text('启用云端大模型解析')
              .fontSize(15)
              .fontColor('#334155')
              .margin({ left: 10 })

            Blank()

            Toggle({ type: ToggleType.Switch, isOn: this.useCloudModel })
              .onChange((isOn: boolean) => {
                this.useCloudModel = isOn;
                this.isCloudExpanded = isOn;
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 10, bottom: 10 })

          // 云端配置展开区
          if (this.useCloudModel) {
            Column({ space: 12 }) {
              Divider().color('#f1f5f9').margin({ bottom: 4 })

              TextInput({ text: this.cloudApiModel, placeholder: '模型名称 (如 glm-4-flash)' })
                .onChange((value: string) => { this.cloudApiModel = value; })
                .height(44)
                .borderRadius(10)

              TextInput({ text: this.cloudApiUrl, placeholder: 'Base URL (如 https://open.bigmodel.cn/api/paas/v4)' })
                .onChange((value: string) => { this.cloudApiUrl = value; })
                .height(44)
                .borderRadius(10)

              TextInput({ text: this.cloudApiKey, placeholder: 'API Key' })
                .type(InputType.Password)
                .onChange((value: string) => { this.cloudApiKey = value; })
                .height(44)
                .borderRadius(10)

              Button('保存配置')
                .width('100%')
                .height(42)
                .backgroundColor('#3b82f6')
                .borderRadius(10)
                .fontColor(Color.White)
                .onClick(() => {
                  if (!this.cloudApiKey || !this.cloudApiModel || !this.cloudApiUrl) {
                    promptAction.showToast({ message: '请填写全部信息' });
                    return;
                  }
                  promptAction.showToast({ message: '✅ 配置已保存' });
                })
            }
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 16 })
          }
        }
        .width('100%')
        .backgroundColor(Color.White)
        .borderRadius(20)
        .shadow({ radius: 12, color: 'rgba(0,0,0,0.04)', offsetY: 4 })

        // ==========================================
        // 4. 通用设置卡片
        // ==========================================
        Column({ space: 0 }) {
          // 标题
          Row() {
            SymbolGlyph($r('sys.symbol.gearshape'))
              .fontSize(18)
              .fontColor(['#6366f1'])

            Text('通用设置')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor('#1e293b')
              .margin({ left: 8 })
          }
          .width('100%')
          .padding({ left: 16, top: 16, bottom: 8 })

          // 主题切换
          this.SettingRow('sys.symbol.circle_lefthalf_filled', '深色模式', '#f59e0b', true)

          Divider().color('#f1f5f9').margin({ left: 52, right: 16 })

          // 通知提醒
          this.SettingRow('sys.symbol.bell', '通知提醒', '#10b981', true)

          Divider().color('#f1f5f9').margin({ left: 52, right: 16 })

          // 清除缓存
          Row() {
            SymbolGlyph($r('sys.symbol.trash'))
              .fontSize(18)
              .fontColor(['#ef4444'])

            Text('清除缓存')
              .fontSize(15)
              .fontColor('#334155')
              .margin({ left: 10 })

            Blank()

            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(14)
              .fontColor(['#cbd5e1'])
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })
          .onClick(() => {
            promptAction.showToast({ message: '功能开发中，敬请期待' });
          })
        }
        .width('100%')
        .backgroundColor(Color.White)
        .borderRadius(20)
        .shadow({ radius: 12, color: 'rgba(0,0,0,0.04)', offsetY: 4 })

        // ==========================================
        // 5. 关于
        // ==========================================
        Column() {
          Row() {
            SymbolGlyph($r('sys.symbol.info_circle'))
              .fontSize(18)
              .fontColor(['#64748b'])

            Text('关于')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor('#1e293b')
              .margin({ left: 8 })
          }
          .width('100%')
          .padding({ left: 16, top: 16, bottom: 8 })

          Row() {
            Text('版本号')
              .fontSize(15)
              .fontColor('#334155')

            Blank()

            Text('v1.0.0')
              .fontSize(14)
              .fontColor('#94a3b8')
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 16 })
        }
        .width('100%')
        .backgroundColor(Color.White)
        .borderRadius(20)
        .shadow({ radius: 12, color: 'rgba(0,0,0,0.04)', offsetY: 4 })

        // 底部间距，防止被导航栏遮挡
        Row().height(20)
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 10 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }

  // 通用设置行（带 Toggle）
  @Builder SettingRow(icon: string, label: string, iconColor: string, showToggle: boolean) {
    Row() {
      SymbolGlyph($r(icon))
        .fontSize(18)
        .fontColor([iconColor])

      Text(label)
        .fontSize(15)
        .fontColor('#334155')
        .margin({ left: 10 })

      Blank()

      if (showToggle) {
        Toggle({ type: ToggleType.Switch, isOn: false })
          .onChange(() => {
            promptAction.showToast({ message: '功能开发中，敬请期待' });
          })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
  }
}