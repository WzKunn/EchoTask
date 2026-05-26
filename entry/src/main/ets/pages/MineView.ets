import router from '@ohos.router';
import { promptAction } from '@kit.ArkUI';

@Component
export struct MineView {
  // 双向绑定硬盘里的数据 UI 上的任何修改，都会自动存入硬盘
  @StorageLink('useCloudModel') useCloudModel: boolean = false;
  @StorageLink('cloudApiModel') cloudApiModel: string = '';
  @StorageLink('cloudApiKey') cloudApiKey: string = '';
  @StorageLink('cloudApiUrl') cloudApiUrl: string = '';

  build() {
    Column() {
      // 1. 模式切换开关
      Row() {
        Text('启用云端大模型解析').fontSize(18)
        Blank() // 撑开空间
        Toggle({ type: ToggleType.Switch, isOn: this.useCloudModel })
          .onChange((isOn: boolean) => {
            this.useCloudModel = isOn; // 赋值的瞬间，就已经自动存入本地硬盘了！
          })
      }
      .width('90%')
      .padding(15)
      .backgroundColor('#f1f5f9')
      .borderRadius(12)

      // 2. 如果开启了云端模式，才显示输入框 (条件渲染)
      if (this.useCloudModel) {
        Column({ space: 15 }) {
          TextInput({ text: this.cloudApiModel, placeholder: '请输入模型名称 (如 glm-4)' })
            .onChange((value: string) => { this.cloudApiModel = value; })

          TextInput({ text: this.cloudApiUrl, placeholder: '请输入 Base URL (如 https://open.bigmodel.cn/api/paas/v4)' })
            .onChange((value: string) => {
              this.cloudApiUrl = value;
            })

          TextInput({ text: this.cloudApiKey, placeholder: '请输入 API Key' })
            .type(InputType.Password) // 密码模式，保护 Key 不被偷看
            .onChange((value: string) => {
              this.cloudApiKey = value;
            })

          Button('保存配置')
            .width('100%')
            .onClick(() => {
              if (!this.cloudApiKey || !this.cloudApiModel || !this.cloudApiUrl) {
                promptAction.showToast({ message: '请填写全部信息' });
                return;
              }
              promptAction.showToast({ message: '配置已保存' });
            })
        }
        .width('90%')
        .padding(15)
        .backgroundColor('#f8fafc')
        .borderRadius(12)
      }
    }
    .width('100%')
    .height('100%')
  }
}