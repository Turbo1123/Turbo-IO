#import "ResearchCatalog.h"
static NSDictionary *Row(NSString *key,NSString *title,NSString *icon,NSInteger section,NSInteger row){return @{@"key":key,@"title":title,@"icon":icon,@"section":@(section),@"row":@(row)};}
NSArray<NSDictionary *> *TIOResearchSections(NSString *page){
    if([page isEqual:@"model"])return @[
        @{@"title":@"自定义 Agents 控制",@"rows":@[Row(@"agent",@"执行 Agent",@"cpu",-2,0),Row(@"knowledge",@"知识库与来源",@"books.vertical",-2,1)]},
        @{@"title":@"回答方式",@"rows":@[Row(@"mode",@"当前回答方式",@"square.stack.3d.up",0,0)]},
        @{@"title":@"自有模型",@"rows":@[Row(@"api",@"接口与密钥",@"cube",0,1),Row(@"thinking",@"关闭深度思考",@"bolt",0,3)]},
        @{@"title":@"联网与工具",@"rows":@[Row(@"search",@"允许联网搜索",@"globe",0,7),Row(@"searchKey",@"搜索服务配置",@"key",0,8),Row(@"tools",@"模型可用工具",@"wrench.and.screwdriver",0,11)]},
        @{@"title":@"语音与上下文",@"rows":@[Row(@"exit",@"语音退出",@"waveform",0,6),Row(@"prompt",@"个人资料与提示词",@"text.bubble",0,5),Row(@"history",@"本次对话上下文",@"clock.arrow.circlepath",0,4)]}];
    if([page isEqual:@"library"])return @[
        @{@"title":@"录音与整理",@"rows":@[Row(@"recordings",@"录音与文件分享",@"waveform",-1,0),Row(@"summary",@"转写文字整理",@"text.badge.star",-1,1)]},
        @{@"title":@"全天智记",@"rows":@[Row(@"lifelogText",@"已保存文字",@"doc.text",-1,2),Row(@"lifelogAudio",@"音频保存与分享",@"waveform.circle",-1,3),Row(@"capture",@"保存之后的最终文字",@"square.and.arrow.down",1,0),Row(@"archive",@"导出文字归档",@"square.and.arrow.up",1,1)]}];
    if([page isEqual:@"diagnostics"])return @[
        @{@"title":@"运行状态",@"rows":@[Row(@"status",@"适配与回调",@"checkmark.shield",2,0)]},
        @{@"title":@"手动测试",@"rows":@[Row(@"apiTest",@"测试模型接口",@"bubble.left.and.bubble.right",0,2),Row(@"searchTest",@"测试联网搜索",@"globe",0,9),Row(@"todoTest",@"待办协议验收",@"checklist",0,10)]}];
    return @[];
}
