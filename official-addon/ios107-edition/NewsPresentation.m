#import "NewsPresentation.h"
unsigned TIONewsPlaybackCommand(NSDictionary *s){if(![s[@"ready"] boolValue]||[s[@"stopping"] boolValue])return 0;return [s[@"playing"] boolValue]?4:([s[@"started"] boolValue]?5:3);}
NSDictionary *TIONewsPresentation(NSDictionary *s,BOOL busy,NSUInteger characters){
    NSString *title,*detail;BOOL available=[s[@"available"] boolValue],active=[s[@"active"] boolValue];
    if([s[@"stopping"] boolValue]){title=@"正在退出眼镜阅读";detail=@"等待眼镜确认，请勿重复发送。";}
    else if(active){title=[s[@"playing"] boolValue]?@"眼镜正在阅读":([s[@"ready"] boolValue]?@"稿件已就绪":@"正在传送稿件");detail=s[@"state"]?:@"等待眼镜确认";}
    else if(!available){title=@"等待连接或首次提词配置";detail=@"先确认官方 App 已连接眼镜。已保存的配置会自动恢复，重启不必重做。\n\n首次升级尚无配置时：选一份短稿，用匀速模式准备、开始、退出一次；收到完整回执后保存。换设备或配置不兼容时才需重新学习。";}
    else if([s[@"automaticInitialization"] boolValue]){title=@"发送时自动准备提词器";detail=@"已载入内置匀速配置，无需先操作官方稿件。发送后等待文件及眼镜收稿确认，再开始阅读。";}
    else if([s[@"templateSaveError"] length]){title=@"本次可用，配置尚未保存";detail=[NSString stringWithFormat:@"%@。可以发送本批新闻，但重启恢复尚未就绪，请保留诊断信息。",s[@"templateSaveError"]];}
    else {title=@"提词器已准备好";detail=[s[@"templateSaved"] boolValue]?@"配置已保存，同设备、同版本重启后自动恢复。发送时仍会重新确认眼镜收稿。":@"可以发送本批新闻。初始化状态不代表实时蓝牙连接保证。";}
    return @{@"title":title,@"detail":detail,@"needsPreparation":@(!available&&!active),@"canFetch":@(!busy&&!active),@"canSend":@(available&&!active&&!busy&&characters>0),@"canPlay":@(!busy&&TIONewsPlaybackCommand(s)!=0),@"canStop":@(active&&!([s[@"stopping"] boolValue])),@"canTest":@(available&&!active&&!busy)};
}
