import { promptAction } from '@kit.ArkUI';
import { TaskItem } from './HomeView';
import { NLPUtils, SearchIntent } from '../utils/NLPUtils';
import { taskStore } from '../utils/TaskStore';
import { TimeUtils } from '../utils/TimeUtils';
import { window } from '@kit.ArkUI';

@Builder
export function SearchPageBuilder() {
  SearchPage()
}

@Component
struct SearchPage {
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  @State searchText: string = '';
  @State searchResults: TaskItem[] = [];
  @State isSearching: boolean = false;
  @State hasSearched: boolean = false;

  build() {
    NavDestination() {
      Column() {

        // --- 1. 搜索栏 ---
        Row() {
          TextInput({ placeholder: '搜索日程，如"上周关于代码的事"', text: this.searchText })
            .layoutWeight(1)
            .height(44)
            .backgroundColor($r('app.color.search_input_bg'))
            .borderRadius(16)
            .padding({ left: 16, right: 16 })
            .onChange((value: string) => {
              this.searchText = value;
            })
            .onSubmit(() => {
              this.executeSearch();
            })

          Button() {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(20)
              .fontColor([Color.White])
          }
          .type(ButtonType.Circle)
          .width(44)
          .height(44)
          .backgroundColor($r('app.color.brand_primary'))
          .margin({ left: 10 })
          .onClick(() => {
            this.executeSearch();
          })
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 10, bottom: 15 })

        // --- 2. 搜索状态 ---
        if (this.isSearching) {
          Column() {
            LoadingProgress()
              .width(40)
              .height(40)
              .color($r('app.color.brand_primary'))
            Text('AI 正在理解你的搜索意图...')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 12 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)

        } else if (this.hasSearched && this.searchResults.length === 0) {
          // --- 3. 空状态 ---
          Column() {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(50)
              .fontColor([$r('app.color.text_tertiary')])

            Text('没有找到匹配的日程')
              .fontSize(16)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 16 })

            Text('试试换个说法？如"本周""关于学习的"')
              .fontSize(13)
              .fontColor($r('app.color.text_tertiary'))
              .margin({ top: 8 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)

        } else if (this.searchResults.length > 0) {
          // --- 4. 搜索结果列表 ---
          Column() {
            Text('找到 ' + this.searchResults.length + ' 条结果')
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .margin({ left: 24, bottom: 10 })
              .width('100%')

            List({ space: 12 }) {
              ForEach(this.searchResults, (item: TaskItem) => {
                ListItem() {
                  this.SearchResultCard(item)
                }
              }, (item: TaskItem) => item.id)
            }
            .width('100%')
            .height('100%')
            .layoutWeight(1)
            .scrollBar(BarState.Off)
            .padding({ left: 20, right: 20 })
          }
          .layoutWeight(1)

        } else {
          // --- 5. 初始状态引导 ---
          Column() {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(50)
              .fontColor([$r('app.color.text_tertiary')])

            Text('输入自然语言搜索你的日程')
              .fontSize(16)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 16 })

            // 快捷搜索标签
            Row({ space: 8 }) {
              this.QuickTag('今天的任务')
              this.QuickTag('本周的日程')
              this.QuickTag('关于学习的')
            }
            .margin({ top: 20 })

            Row({ space: 8 }) {
              this.QuickTag('上周的事')
              this.QuickTag('紧急任务')
            }
            .margin({ top: 8 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        }
      }
      .width('100%')
      .height('100%')
    }
    .linearGradient({
      direction: GradientDirection.LeftTop,
      colors: [
        [$r('app.color.page_gradient_start'), 0.0],
        [$r('app.color.page_gradient_start'), 0.4],
        [$r('app.color.page_gradient_end'), 0.9]
      ]
    })
    .title('搜索回溯')
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
  }

  // 快捷搜索标签
  @Builder QuickTag(text: string) {
    Text(text)
      .fontSize(13)
      .fontColor($r('app.color.brand_primary'))
      .backgroundColor($r('app.color.brand_primary_bg'))
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .borderRadius(20)
      .onClick(() => {
        this.searchText = text;
        this.executeSearch();
      })
  }

  // 搜索结果卡片
  @Builder SearchResultCard(item: TaskItem) {
    Column() {
      Row() {
        Text(item.content)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
      }
      .width('100%')

      Row() {
        Text(TimeUtils.formatTimestamp(item.timestamp))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))

        Blank()

        ForEach(item.tags, (tag: string) => {
          Text(tag)
            .fontSize(10)
            .fontColor($r('app.color.brand_primary'))
            .backgroundColor($r('app.color.brand_primary_bg'))
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .borderRadius(4)
            .margin({ left: 4 })
        })
      }
      .width('100%')
      .margin({ top: 10 })
    }
    .padding(18)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(16)
    .shadow({ radius: 8, color: 'rgba(0,0,0,0.05)', offsetY: 4 })
  }

  // 执行搜索
  async executeSearch(): Promise<void> {
    if (!this.searchText || this.searchText.trim().length === 0) {
      promptAction.showToast({ message: '请输入搜索内容' });
      return;
    }

    this.isSearching = true;
    this.hasSearched = false;
    this.searchResults = [];

    try {
      // 1. 解析搜索意图（云端优先，本地降级）
      let intent: SearchIntent = await NLPUtils.parseSearchIntent(this.searchText);

      // 2. 用结构化条件查询数据库
      let results = await taskStore.searchTasks(
        intent.keywords,
        intent.startTime > 0 ? intent.startTime : undefined,
        intent.endTime > 0 ? intent.endTime : undefined,
        intent.tags.length > 0 ? intent.tags : undefined
      );

      this.searchResults = results;
      this.hasSearched = true;

      if (results.length > 0) {
        console.info('搜索完成，找到 ' + results.length + ' 条结果');
      } else {
        console.info('搜索完成，无匹配结果');
      }

    } catch (err) {
      console.error('搜索过程出错: ' + JSON.stringify(err));
      promptAction.showToast({ message: '搜索失败，请重试' });
      this.hasSearched = true;
    } finally {
      this.isSearching = false;
    }
  }
}
