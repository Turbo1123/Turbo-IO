#import "EditorTransport.h"
#import "EditorCodec.h"
#import "DashboardCard.h"
#import "ProtocolContext.h"
#import "A2UIProbe.h"
#import "ExperimentalOTAFlash.h"
#import <objc/message.h>
static NSString *Message=@"草稿只在手机。需 TCE1 固件，发送后仍需镜片确认。",*Peer,*Step,*Owned;
static NSDictionary *Before,*PendingInstall;static uint32_t Seq;static NSUInteger Generation;static BOOL First;
static BOOL MutationSent;
static void(^RemoteComplete)(NSDictionary *);
BOOL TCEBusy(void){return Seq!=0;}
NSString *TCEStatus(void){return Message;}
static void Changed(NSString *s){Message=s;
 NSString *base=NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,NSUserDomainMask,YES).firstObject;NSString *dir=[base stringByAppendingPathComponent:@"TurboIO/DashboardEditor"];
 [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} error:nil];
 NSDictionary *record=@{@"protocol":@"TCE1",@"status":s?:@"",@"pending":@(Seq!=0),@"sequence":@(Seq),@"time":@([NSDate date].timeIntervalSince1970),@"physicalVerified":@NO};
 [[NSJSONSerialization dataWithJSONObject:record options:NSJSONWritingPrettyPrinted error:nil]writeToFile:[dir stringByAppendingPathComponent:@"status.json"] options:NSDataWritingAtomic error:nil];
 [NSNotificationCenter.defaultCenter postNotificationName:@"TCEChanged" object:nil];}
static void EndResult(NSString *s,NSString *state,NSString *code){void(^done)(NSDictionary *)=RemoteComplete;RemoteComplete=nil;Seq=0;Generation++;Step=nil;Before=nil;PendingInstall=nil;Changed(s);if(done)dispatch_async(dispatch_get_main_queue(),^{done(@{@"state":state,@"code":code,@"physicalVerified":@NO});});}
static void End(NSString *s){EndResult(s,MutationSent?@"outcome_unknown":@"failed",MutationSent?@"needs_readback":@"preflight_or_read_failed");}
static void Send(NSDictionary *json,NSString *step){
 if(Seq||!json||![Peer isEqual:TIOProtocolDevice()]||UIApplication.sharedApplication.applicationState!=UIApplicationStateActive||[TIOOTAFlashStatus()[@"stage"]integerValue]!=0){End(@"未发送：请保持连接、App 前台，并先结束升级会话（刷完后重开 App）。");return;}
 id plugin=TIOProtocolPlugin();Class td=NSClassFromString(@"FlutterStandardTypedData"),mc=NSClassFromString(@"FlutterMethodCall");SEL wrap=NSSelectorFromString(@"typedDataWithBytes:"),make=NSSelectorFromString(@"methodCallWithMethodName:arguments:"),handle=NSSelectorFromString(@"handleMethodCall:result:");
 if(!plugin||![plugin respondsToSelector:handle]||![td respondsToSelector:wrap]||![mc respondsToSelector:make]){End(@"等待官方首页建立眼镜通信。");return;}
 uint32_t seq=0x40000000+arc4random_uniform(0x3fffffff);NSData *data=TDCRequest(seq,json);if(!data){End(@"数据包超出限制，未发送。");return;}
 NSMutableDictionary *args=[TIOProtocolRoute(15)mutableCopy];args[@"payload"]=((id(*)(id,SEL,id))objc_msgSend)(td,wrap,data);id call=((id(*)(id,SEL,id,id))objc_msgSend)(mc,make,@"rayneonet_sendMessage",args);Seq=seq;Step=step;NSUInteger g=++Generation;Changed([NSString stringWithFormat:@"%@ · %lu 字节，等待眼镜回执",step,(unsigned long)data.length]);
 if([step isEqual:@"提交卡片"]||[step isEqual:@"置顶卡片"]||[step isEqual:@"移除卡片"])MutationSent=YES;
 @try{((void(*)(id,SEL,id,id))objc_msgSend)(plugin,handle,call,[^(id r){} copy]);}@catch(NSException *e){End(@"发送异常，结果未知。未自动重试。");return;}
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,20*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(Seq==seq&&Generation==g)End(@"20 秒未回执，结果未知；没有自动重发。请先看眼镜，勿连续点击。");});
}
static void Query(NSString *step){Send(@{@"cmd":@"dashboard_config",@"payload":@{@"version":@1,@"value":@0}},step);}
void TCEPublish(NSDictionary *draft,BOOL first){if(Seq){Changed(@"本轮尚在等待回执。");return;}MutationSent=NO;NSString *why=nil;NSDictionary *p=TCEInstall(draft,&why);if(!p){End(why?:@"草稿校验失败");return;}Peer=TIOProtocolDevice();if(!Peer.length){End(@"请先连接眼镜。");return;}Owned=[draft[@"id"]copy];PendingInstall=p;First=first;Query(@"读取原顺序");}
BOOL TCEPublishWithCompletion(NSDictionary *draft,NSString *expectedPeer,void(^complete)(NSDictionary *)){if(!NSThread.isMainThread||Seq||RemoteComplete||!complete||!expectedPeer.length||![expectedPeer isEqual:TIOProtocolDevice()])return NO;RemoteComplete=[complete copy];TCEPublish(draft,NO);return YES;}
void TCERemove(NSString *ident){if(Seq)return;if(![ident hasPrefix:@"turbo_ui_card_"]||ident.length>48)return;MutationSent=NO;Peer=TIOProtocolDevice();Owned=ident;if(!Peer.length){End(@"请先连接眼镜。");return;}PendingInstall=nil;Query(@"读取删除前状态");}
static NSData *Bytes(id x){if([x isKindOfClass:NSData.class])return x;@try{id d=[x valueForKey:@"data"];return [d isKindOfClass:NSData.class]?d:nil;}@catch(NSException *e){return nil;}}
static BOOL Others(NSDictionary *a,NSDictionary *b){NSDictionary *p=TCEReorder(b,Owned);NSString *s=p[@"payload"][@"data"];NSDictionary *sorted=s?[NSJSONSerialization JSONObjectWithData:[s dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil]:nil;return sorted&&TCEVerifyOrder(a,sorted,Owned);}
void TCEObserveEvent(NSDictionary *e){
 if(!Seq)return;if(![Peer isEqual:TIOProtocolDevice()]){End(@"连接设备变化，操作已停止。");return;}if(![e[@"eventType"]isEqual:@"messageReceived"])return;id m=e[@"message"];if(![m isKindOfClass:NSDictionary.class]||![m[@"deviceId"]isEqual:Peer]||![m[@"businessId"]isEqual:@15])return;
 NSDictionary *p=TIOA2UIDecode(Bytes(m[@"payload"]));if(![p[@"type"]isEqual:@19]||[p[@"sequence"]unsignedIntValue]!=Seq||![p[@"mode"]isEqual:@2])return;NSDictionary *j=p[@"json"];NSString *step=Step;
 if([step hasPrefix:@"读取"]){
  if(![j[@"cmd"]isEqual:@"dashboard_config"])return;id s=[j[@"payload"]isKindOfClass:NSDictionary.class]?j[@"payload"][@"data"]:nil;if([s isKindOfClass:NSString.class])s=[NSJSONSerialization JSONObjectWithData:[s dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];if(!TCESnapshot(s)){End(@"眼镜配置无法校验，停止修改。");return;}Seq=0;
  if([step isEqual:@"读取原顺序"]||[step isEqual:@"读取删除前状态"]){Before=s;for(NSDictionary *r in s[@"widgets_v2"])if([r[@"id"]isEqual:Owned]&&![r[@"type"]isEqual:@"a2ui"]){End(@"卡片 ID 与非自有类型冲突，拒绝修改。");return;}Send(PendingInstall?:TIOA2UIUninstall(Owned),PendingInstall?@"提交卡片":@"移除卡片");return;}
  if([step isEqual:@"读取安装结果"]){if(!Others(Before,s)){End(@"其他卡片发生变化，停止排序。请核对眼镜。");return;}if(First)Send(TCEReorder(s,Owned),@"置顶卡片");else EndResult(@"眼镜已接收，其他卡片保留。请确认实际显示；当前为手动配置数据。",@"device_accepted",@"config_readback");return;}
  if([step isEqual:@"读取最终顺序"]){End(TCEVerifyOrder(Before,s,Owned)?@"已接收并置顶，其他卡片保留。请确认镜片文字、图标与图表。":@"最终排序不符，停止操作，未自动重试。");return;}
  if([step isEqual:@"读取删除结果"]){NSMutableArray *before=[NSMutableArray new];for(NSDictionary *r in Before[@"widgets_v2"])if(![r[@"id"]isEqual:Owned])[before addObject:r];NSMutableDictionary *expected=[Before mutableCopy];expected[@"widgets_v2"]=before;End([expected isEqual:s]?@"本卡已移除，其他卡片及原顺序保留。":@"移除回读有差异，请核对；未继续修改。");return;}
  End(@"配置已读取。");return;
 }
 BOOL ok=NO;if([step isEqual:@"置顶卡片"]){if(![j[@"cmd"]isEqual:@"dashboard_update"])return;id v=[j[@"payload"]isKindOfClass:NSDictionary.class]?j[@"payload"][@"value"]:nil;ok=[v isKindOfClass:NSNumber.class]&&CFGetTypeID((__bridge CFTypeRef)v)!=CFBooleanGetTypeID()&&[v isEqual:@0];}
 else{ id v=j[@"code"];if(![v isKindOfClass:NSNumber.class]||CFGetTypeID((__bridge CFTypeRef)v)==CFBooleanGetTypeID())return;ok=[v isEqual:@0];}
 Seq=0;if(!ok){End(@"眼镜拒绝本步，停止修改；不自动重发。");return;}Query([step isEqual:@"提交卡片"]?@"读取安装结果":[step isEqual:@"置顶卡片"]?@"读取最终顺序":@"读取删除结果");
}
