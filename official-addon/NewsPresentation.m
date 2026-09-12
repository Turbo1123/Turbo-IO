#import "NewsPresentation.h"
unsigned TIONewsPlaybackCommand(NSDictionary *s){if(![s[@"ready"] boolValue]||[s[@"stopping"] boolValue])return 0;return [s[@"playing"] boolValue]?4:([s[@"started"] boolValue]?5:3);}
NSDictionary *TIONewsPresentation(NSDictionary *s,BOOL busy,NSUInteger characters){
    NSString *title,*detail;BOOL available=[s[@"available"] boolValue],active=[s[@"active"] boolValue];
    if([s[@"stopping"] boolValue]){title=@"正在退出眼镜阅读";detail=@"等待眼镜确认，请勿重复发送。";}
    else if(active){title=[s[@"playing"] boolValue]?@"眼镜正在阅读":([s[@"ready"] boolValue]?@"稿件已就绪":@"正在传送稿件");detail=s[@"state"]?:@"等待眼镜确认";}
    else if(!available){title=@"先准备眼镜提词器";detail=@"1  回到官方 App，打开短稿，选择匀速滚动。\n2  准备并开始，确认眼镜滚动后退出提词。\n3  回到新闻页，再发送内容。\n\nApp 完全重启后需要重新准备；准备前仍可在手机阅读新闻。";}
    else {title=@"提词器已准备好";detail=@"可以发送本批新闻。初始化状态不代表实时蓝牙连接保证。";}
    return @{@"title":title,@"detail":detail,@"needsPreparation":@(!available&&!active),@"canFetch":@(!busy&&!active),@"canSend":@(available&&!active&&!busy&&characters>0),@"canPlay":@(!busy&&TIONewsPlaybackCommand(s)!=0),@"canStop":@(active&&!([s[@"stopping"] boolValue])),@"canTest":@(available&&!active&&!busy)};
}
