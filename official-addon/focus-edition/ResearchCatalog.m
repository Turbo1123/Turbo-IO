#import "ResearchCatalog.h"
static NSDictionary *Row(NSString *key,NSString *title,NSString *icon,NSInteger section,NSInteger row){return @{@"key":key,@"title":title,@"icon":icon,@"section":@(section),@"row":@(row)};}
NSArray<NSDictionary *> *LegacySections(NSString *page){
    if([page isEqual:@"model"])return @[
        @{@"title":@"实时字幕与翻译 · 本机验收",@"rows":@[Row(@"localTranslation",@"Apple / Hy-MT2 本地翻译",@"character.bubble",-2,22)]},
        @{@"title":@"自定义 Agents 控制",@"rows":@[Row(@"agent",@"执行 Agent",@"cpu",-2,0),Row(@"knowledge",@"知识库与来源",@"books.vertical",-2,1)]},
        @{@"title":@"回答方式",@"rows":@[Row(@"mode",@"当前回答方式",@"square.stack.3d.up",0,0)]},
        @{@"title":@"自有模型",@"rows":@[Row(@"api",@"接口与密钥",@"cube",0,1),Row(@"thinking",@"关闭深度思考",@"bolt",0,3)]},
        @{@"title":@"眼镜语音播报 · 实验",@"rows":@[Row(@"tts",@"回答同步朗读",@"waveform.circle",-2,13),Row(@"ttsEngine",@"朗读引擎",@"slider.horizontal.3",-2,16),Row(@"ttsKey",@"阿里 Flash TTS 配置",@"key",-2,14),Row(@"ttsTest",@"播放测试语音",@"play.circle",-2,15)]},
        @{@"title":@"联网与工具",@"rows":@[Row(@"search",@"允许联网搜索",@"globe",0,7),Row(@"searchKey",@"搜索服务配置",@"key",0,8),Row(@"tools",@"模型可用工具",@"wrench.and.screwdriver",0,11)]},
        @{@"title":@"语音与上下文",@"rows":@[Row(@"exit",@"语音退出",@"waveform",0,6),Row(@"prompt",@"系统提示词",@"text.bubble",0,5),Row(@"history",@"本次对话上下文",@"clock.arrow.circlepath",0,4)]}];
    if([page isEqual:@"library"])return @[
#if TIO_DISPLAY_PHONE
        @{@"title":@"随身应用",@"rows":@[Row(@"cuecards",@"提词卡",@"rectangle.stack",-2,23),Row(@"heartRate",@"运动看板 · Apple Watch",@"heart",-2,24)]},
#endif
        @{@"title":@"阅读空间",@"rows":@[Row(@"weread",@"微信读书 · 第十一项菜单",@"books.vertical",-2,21)]},
        @{@"title":@"音乐随行",@"rows":@[Row(@"music",@"网易云音乐 · 第十项菜单",@"music.note",-2,20)]},
        @{@"title":@"录音与整理",@"rows":@[Row(@"recordings",@"录音与文件分享",@"waveform",-1,0),Row(@"summary",@"转写文字整理",@"text.badge.star",-1,1)]},
        @{@"title":@"全天智记",@"rows":@[Row(@"lifelogText",@"已保存文字",@"doc.text",-1,2),Row(@"lifelogAudio",@"音频保存与分享",@"waveform.circle",-1,3),Row(@"capture",@"保存之后的最终文字",@"square.and.arrow.down",1,0),Row(@"archive",@"导出文字归档",@"square.and.arrow.up",1,1)]},
        @{@"title":@"出行",@"rows":@[Row(@"navigation",@"步行 / 骑行 / 驾车导航",@"location.north.line",-2,4)]}];
    if([page isEqual:@"diagnostics"])return @[
        @{@"title":@"开发者诊断",@"rows":@[Row(@"diagnosticsRuntime",@"眼镜运行状态 · TDG1",@"gauge.with.dots.needle.67percent",-2,21)]},
        @{@"title":@"导航显示实验",@"rows":@[Row(@"subtitleHUD",@"字幕导航 · 常亮与换文",@"text.bubble",-2,5)]},
        @{@"title":@"运行状态",@"rows":@[Row(@"status",@"适配与回调",@"checkmark.shield",2,0),Row(@"glassesLog",@"眼镜日志 · 仅本机",@"doc.text.magnifyingglass",-2,3)]},
        @{@"title":@"手动测试",@"rows":@[Row(@"a2ui",@"自定义 UI 真机验收",@"rectangle.3.group",-2,2),Row(@"apiTest",@"测试模型接口",@"bubble.left.and.bubble.right",0,2),Row(@"searchTest",@"测试联网搜索",@"globe",0,9),Row(@"todoTest",@"待办协议验收",@"checklist",0,10)]},
        @{@"title":@"固件研究",@"rows":@[
#if TIO_IMAGE_RX_LAB
#if TIO_DISPLAY_PHONE
        Row(@"displayPhone",@"灵活显示 · PHONE 06",@"rectangle.connected.to.line.below",-2,8),
#endif
        Row(@"imageRXLab",@"N8W 单张传图 · FIX 01",@"photo",-2,7),
#endif
#if TIO_DISPLAY_FLASH
        Row(@"experimentalOTA",@"TFP1 番茄时钟固件 · 默认锁定",@"shippingbox",-2,6)]}];
#else
        Row(@"experimentalOTA",@"实验固件 · 仅校验",@"shippingbox",-2,6)]}];
#endif
    return @[];
}

NSArray<NSDictionary *> *TIOResearchSections(NSString *page){
 NSMutableDictionary *lookup=[NSMutableDictionary new];for(NSString *p in @[@"model",@"library",@"diagnostics"])for(NSDictionary *section in LegacySections(p))for(NSDictionary *r in section[@"rows"])lookup[r[@"key"]]=r;
 NSArray *groups=nil;
 if([page isEqual:@"model"])groups=@[@[@"日常对话",@"mode",@"tts",@"search"],@[@"模型与接口",@"api",@"thinking"],@[@"语音设置",@"ttsEngine",@"ttsTest",@"ttsKey",@"exit"],@[@"Agent 与工具",@"agent",@"knowledge",@"tools",@"searchKey"],@[@"提示词与记忆",@"prompt",@"history"]];
 if([page isEqual:@"library"])groups=@[@[@"随身应用",@"cuecards",@"heartRate",@"music",@"weread",@"navigation",@"localTranslation",@"recordings"],@[@"文字整理",@"summary"],@[@"全天智记",@"lifelogText",@"lifelogAudio",@"capture",@"archive"]];
 if([page isEqual:@"diagnostics"])groups=@[@[@"运行与日志",@"diagnosticsRuntime",@"glassesLog",@"status"],@[@"协议实验",@"subtitleHUD",@"a2ui",@"apiTest",@"searchTest",@"todoTest"],@[@"显示实验",@"displayPhone",@"imageRXLab"],@[@"实验固件 · 有风险",@"experimentalOTA"]];
 if(!groups)return @[];NSMutableArray *sections=[NSMutableArray new];NSDictionary *names=@{@"music":@"音乐",@"weread":@"微信读书",@"navigation":@"导航",@"localTranslation":@"本地翻译与字幕",@"recordings":@"录音与分享"};
 for(NSArray *group in groups){NSMutableArray *rows=[NSMutableArray new];for(NSUInteger i=1;i<group.count;i++){NSDictionary *r=lookup[group[i]];if(r){NSMutableDictionary *m=[r mutableCopy];if(names[group[i]])m[@"title"]=names[group[i]];[rows addObject:m];}}if(rows.count)[sections addObject:@{@"title":group[0],@"rows":rows}];}return sections;
}
