import { abilityAccessCtrl, AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { taskStore } from '../utils/TaskStore';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  async onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Promise<void> {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    try {
      // 【核心代码】：调用初始化，并把大门的通行证 this.context 传进去
      await taskStore.initDB(this.context);
      console.info('EntryAbility 数据库初始化成功');
    } catch (err) {
      console.error('EntryAbility 数据库初始化失败:', err);
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    let windowClass: window.Window = windowStage.getMainWindowSync();
    windowClass.setWindowLayoutFullScreen(true);

    let atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    atManager.requestPermissionsFromUser(this.context, ['ohos.permission.MICROPHONE']).then((data) => {
      hilog.info(0x0000, 'testTag', 'data:' + JSON.stringify(data));
      hilog.info(0x0000, 'testTag', 'data permissions:' + data.permissions);
      hilog.info(0x0000, 'testTag', 'data authResults:' + data.authResults);
    }).catch((err: BusinessError) => {
      hilog.error(0x0000, 'testTag', 'errCode: ' + err.code + 'errMessage: ' + err.message);
    });

    atManager.requestPermissionsFromUser(this.context, ['ohos.permission.READ_CALENDAR']).then((data) => {
      hilog.info(0x0000, 'testTag', 'data:' + JSON.stringify(data));
      hilog.info(0x0000, 'testTag', 'data permissions:' + data.permissions);
      hilog.info(0x0000, 'testTag', 'data authResults:' + data.authResults);
    }).catch((err: BusinessError) => {
      hilog.error(0x0000, 'testTag', 'errCode: ' + err.code + 'errMessage: ' + err.message);
    });

    atManager.requestPermissionsFromUser(this.context, ['ohos.permission.WRITE_CALENDAR']).then((data) => {
      hilog.info(0x0000, 'testTag', 'data:' + JSON.stringify(data));
      hilog.info(0x0000, 'testTag', 'data permissions:' + data.permissions);
      hilog.info(0x0000, 'testTag', 'data authResults:' + data.authResults);
    }).catch((err: BusinessError) => {
      hilog.error(0x0000, 'testTag', 'errCode: ' + err.code + 'errMessage: ' + err.message);
    });

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }

      // 在 loadContent 回调内注册持久化属性（此时 Ace 容器已就绪，PersistentStorage 才能正常工作）
      try {
        PersistentStorage.persistProp('useCloudModel', false);
        PersistentStorage.persistProp('cloudApiModel', '');
        PersistentStorage.persistProp('cloudApiKey', '');
        PersistentStorage.persistProp('cloudApiUrl', '');
        PersistentStorage.persistProp('userNickname', 'EchoTask 用户');
        PersistentStorage.persistProp('userSignature', '用声音管理生活 ✨');
        PersistentStorage.persistProp('userAvatarUri', '');
        PersistentStorage.persistProp('firstUseDate', '');
        PersistentStorage.persistProp('isDarkMode', false);
        hilog.info(DOMAIN, 'testTag', 'PersistentStorage initialized successfully.');
      } catch (storageErr) {
        hilog.error(DOMAIN, 'testTag', 'Failed to initialize PersistentStorage: %{public}s', JSON.stringify(storageErr));
      }

      // 持久化注册完成后，根据保存的深色模式状态设置系统颜色模式
      try {
        let isDarkMode = AppStorage.get<boolean>('isDarkMode');
        hilog.info(DOMAIN, 'testTag', 'Restored isDarkMode = %{public}s', String(isDarkMode));
        if (isDarkMode) {
          this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
        }
      } catch (colorErr) {
        hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode: %{public}s', JSON.stringify(colorErr));
      }

      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}