#import "ResearchCatalog.h"
static NSDictionary *Row(NSString *key,NSString *title,NSString *icon,NSInteger section,NSInteger row){return @{@"key":key,@"title":title,@"icon":icon,@"section":@(section),@"row":@(row)};}
NSArray<NSDictionary *> *TIOResearchSections(NSString *page){
    if([page isEqual:@"model"])return @[
        @{@"title":@"自定义 Agents 控制",@"rows":@[Row(@"agent",@"执行 Agent",@"cpu",-2,0),Row(@"knowledge",@"知识库与来源",@"books.vertical",-2,1)]},
        @{@"title":@"回答方式",@"rows":@[Row(@"mode",@"当前回答方式",@"square.stack.3d.up",0,0)]},
        @{@"title":@"自有模型",@"rows":@[Row(@"api",@"接口与密钥",@"cube",0,1),Row(@"thinking",@"关闭深度思考",@"bolt",0,3)]},
        @{@"title":@"联网与工具",@"rows":@[Row(@"search",@"允许联网搜索",@"globe",0,7),Row(@"searchKey",@"搜索服务配置",@"key",0,8),Row(@"tools",@"模型可用工具",@"wrench.and.screwdriver",0,11)]},
        @{@"title":@"语音与上下文",@"rows":@[Row(@"exit",@"语音退出",@"waveform",0,6),Row(@"prompt",@"个人资料与提示词",@"text.bubble",0,5),Row(@"history",@"本次对话上下文",@"clock.arrow.circlepath",0,4)]},
        @{@"title":@"眼镜语音播报 · 实验",@"rows":@[Row(@"tts",@"回答同步朗读",@"waveform.circle",-2,13),Row(@"ttsEngine",@"朗读引擎",@"slider.horizontal.3",-2,16),Row(@"ttsKey",@"阿里 Flash TTS 配置",@"key",-2,14),Row(@"ttsTest",@"播放测试语音",@"play.circle",-2,15)]}];
    if([page isEqual:@"library"])return @[
#if TIO_LOCAL_TRANSLATION
        @{@"title":@"离线字幕与翻译 · iOS 26+",@"rows":@[Row(@"localTranslation",@"Apple / Hy-MT2 本地翻译",@"character.bubble",-2,21)]},
#endif
#if TIO_MUSIC
        @{@"title":@"音乐随行",@"rows":@[Row(@"music",@"网易云音乐 · 第十项菜单",@"music.note",-2,20)]},
#endif
        @{@"title":@"地图与眼镜导航",@"rows":@[Row(@"navigation",@"步行 / 骑行 / 驾车导航",@"map",-3,0)]},
        @{@"title":@"录音与整理",@"rows":@[Row(@"recordings",@"录音与文件分享",@"waveform",-1,0),Row(@"summary",@"转写文字整理",@"text.badge.star",-1,1)]},
        @{@"title":@"全天智记",@"rows":@[Row(@"lifelogText",@"已保存文字",@"doc.text",-1,2),Row(@"lifelogAudio",@"音频保存与分享",@"waveform.circle",-1,3),Row(@"capture",@"保存之后的最终文字",@"square.and.arrow.down",1,0),Row(@"archive",@"导出文字归档",@"square.and.arrow.up",1,1)]}];
    if([page isEqual:@"diagnostics"])return @[
#if TIO_OTA_RESEARCH_ENABLED
#if TIO_MUSIC
        @{@"title":@"TMU1 研究固件 · 有变砖风险",@"rows":@[Row(@"experimentalOTA",@"TMU1 音乐固件 · 默认锁定",@"exclamationmark.shield",-4,0),Row(@"displayPhone",@"Turbo Display · 传图测试",@"rectangle.connected.to.line.below",-4,1)]},
#elif TIO_NATIVE_NAV
        @{@"title":@"TNV1 研究固件 · 有变砖风险",@"rows":@[Row(@"experimentalOTA",@"TNV1 导航固件 · 默认锁定",@"exclamationmark.shield",-4,0),Row(@"displayPhone",@"Turbo Display · 传图测试",@"rectangle.connected.to.line.below",-4,1)]},
#else
        @{@"title":@"高风险固件实验 · 非日常使用",@"rows":@[Row(@"experimentalOTA",@"R3 试验用品 · 先阅读风险",@"exclamationmark.shield",-4,0)]},
#endif
#endif
        @{@"title":@"运行状态",@"rows":@[Row(@"status",@"适配与回调",@"checkmark.shield",2,0)]},
        @{@"title":@"手动测试",@"rows":@[Row(@"apiTest",@"测试模型接口",@"bubble.left.and.bubble.right",0,2),Row(@"searchTest",@"测试联网搜索",@"globe",0,9),Row(@"todoTest",@"待办协议验收",@"checklist",0,10)]}];
    return @[];
}
