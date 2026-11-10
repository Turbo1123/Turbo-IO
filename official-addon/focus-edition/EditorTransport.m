#import "EditorTransport.h"
#import "EditorCodec.h"
#import "EditorModel.h"
#import "A2UIProbe.h"
#import "NavigationTransport.h"
#import "ProtocolContext.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>

// Read -> targeted mutation -> readback -> optional reorder -> readback. No retry.
// Main-thread only; mirrors the pinned A2UI business-15 contract used by the nav card.
static __weak id CardPlugin;
static NSDictionary *CardRoute;
static NSString *CardDevice,*CardStep,*CardNote=@"草稿只保存在手机";
static NSDictionary *CardBefore,*CardInstall;
static NSString *CardIdentifier;
static uint32_t CardSequence;
static NSTimeInterval CardLease,CardDeadline;
static BOOL CardBusyFlag,CardFirst,CardMutated,CardReadOnly;
static void(^CardCompletion)(NSDictionary *);
static NSString *CardPeer;
static void Change(NSString *s){CardNote=s;[NSNotificationCenter.defaultCenter postNotificationName:@"TCECardChanged" object:nil];}
// Publish-with-completion callers always terminate: success passes the final
// readback config, every failure path passes nil via Idle.
static void Complete(NSDictionary *receipt){if(!CardCompletion)return;void(^done)(NSDictionary *)=CardCompletion;CardCompletion=nil;done(receipt);}
static void Idle(NSString *s){Complete(nil);CardBusyFlag=NO;CardSequence=0;CardBefore=nil;CardInstall=nil;CardStep=nil;CardPeer=nil;Change(s);}
static NSTimeInterval Now(void){return NSProcessInfo.processInfo.systemUptime;}
static id Value(id o,NSString *k){@try{return [o valueForKey:k];}@catch(NSException *e){return nil;}}
static NSData *Bytes(id o){if([o isKindOfClass:NSData.class])return o;id d=Value(o,@"data");return [d isKindOfClass:NSData.class]?d:nil;}

void TCECardObserveCall(id plugin,NSString *method,NSDictionary *args){
 if(![method isEqual:@"rayneonet_sendMessage"]||![args[@"businessId"] isEqual:@15]||![args[@"deviceId"] isKindOfClass:NSString.class])return;
 TIOProtocolObserveCall(plugin,method,args);
 if(CardSequence)return;
 CardPlugin=plugin;CardLease=Now();
 NSMutableDictionary *r=[args mutableCopy];[r removeObjectForKey:@"payload"];CardRoute=r;
 if(![CardDevice isEqual:args[@"deviceId"]]){CardDevice=[args[@"deviceId"] copy];}
}

static BOOL CardSend(NSDictionary *json,NSString *step){
 if(!NSThread.isMainThread||CardSequence||!CardPlugin||!CardRoute||!CardDevice.length||![TIOProtocolDevice() isEqual:CardDevice]||!json)return NO;
 if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)return NO;
 if(Now()-CardLease>300)return NO;
 Class typed=NSClassFromString(@"FlutterStandardTypedData"),call=NSClassFromString(@"FlutterMethodCall");
 SEL td=NSSelectorFromString(@"typedDataWithBytes:"),mk=NSSelectorFromString(@"methodCallWithMethodName:arguments:"),handle=NSSelectorFromString(@"handleMethodCall:result:");
 if(![typed respondsToSelector:td]||![call respondsToSelector:mk]||![CardPlugin respondsToSelector:handle])return NO;
 uint32_t seq=arc4random_uniform(0x3fffffff)+0x40000000;
 NSData *packet=TIOA2UIPacket(18,seq,json);if(!packet)return NO;
 NSMutableDictionary *args=[CardRoute mutableCopy];args[@"payload"]=((id(*)(id,SEL,id))objc_msgSend)(typed,td,packet);args[@"businessId"]=@15;
 id c=((id(*)(id,SEL,id,id))objc_msgSend)(call,mk,@"rayneonet_sendMessage",args);
 CardSequence=seq;CardStep=[step copy];CardDeadline=Now()+20;
 if([@[@"install",@"remove",@"order"] containsObject:step])CardMutated=YES;
 Change([NSString stringWithFormat:@"仪表盘 · %@ · %lu 字节，等待回执",step,(unsigned long)packet.length]);
 uint32_t wait=seq;BOOL waitMutated=CardMutated;
 @try{((void(*)(id,SEL,id,id))objc_msgSend)(CardPlugin,handle,c,[^(id result){/* submission is not a lens ACK */} copy]);}
 @catch(NSException *e){CardSequence=0;Idle(@"通信调用失败，未继续修改");return NO;}
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,20*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(CardSequence==wait){CardSequence=0;Idle(waitMutated?@"20秒无回执，修改结果未知；请核对眼镜，未自动重发":@"读取超时，未修改卡片");}});
 return YES;
}

static NSDictionary *Config(NSDictionary *j){
 if(![j isKindOfClass:NSDictionary.class]||![j[@"cmd"] isEqual:@"dashboard_config"])return nil;
 id payload=j[@"payload"],body=[payload isKindOfClass:NSDictionary.class]?payload[@"data"]:nil;
 if([body isKindOfClass:NSString.class])body=[NSJSONSerialization JSONObjectWithData:[body dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
 if(![body isKindOfClass:NSDictionary.class])return nil;
 id rows=body[@"widgets_v2"];
 if(![rows isKindOfClass:NSArray.class]||[rows count]>32)return nil;
 NSMutableSet *ids=[NSMutableSet new];
 for(id row in rows){
  if(![row isKindOfClass:NSDictionary.class])return nil;
  id identifier=row[@"id"],type=row[@"type"];
  if(![identifier isKindOfClass:NSString.class]||[identifier length]>128||![type isKindOfClass:NSString.class]||[type length]>128||[ids containsObject:identifier])return nil;[ids addObject:identifier];
 }
 return body;
}
static NSDictionary *FindRow(NSDictionary *config,NSString *identifier){
 for(id row in config[@"widgets_v2"])if([row isKindOfClass:NSDictionary.class]&&[row[@"id"] isEqual:identifier])return row;
 return nil;
}
static BOOL SameExtras(id a,id b){
 if(![a isKindOfClass:NSString.class]||![b isKindOfClass:NSString.class])return NO;
 id first=[NSJSONSerialization JSONObjectWithData:[a dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
 id second=[NSJSONSerialization JSONObjectWithData:[b dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
 return [first isEqual:second];
}
static BOOL Preserves(NSDictionary *before,NSDictionary *after,NSString *identifier){
 NSMutableArray *x=[NSMutableArray new],*y=[NSMutableArray new];
 for(id row in before[@"widgets_v2"])if(![row isKindOfClass:NSDictionary.class]||![row[@"id"] isEqual:identifier])[x addObject:row];
 for(id row in after[@"widgets_v2"])if(![row isKindOfClass:NSDictionary.class]||![row[@"id"] isEqual:identifier])[y addObject:row];
 NSMutableDictionary *a=[before mutableCopy],*b=[after mutableCopy];
 a[@"widgets_v2"]=@[];b[@"widgets_v2"]=@[];
 return [a isEqual:b]&&[x isEqual:y];
}
static NSDictionary *Reordered(NSDictionary *config,NSString *identifier){
 NSMutableArray *items=[NSMutableArray new];NSDictionary *own=nil;
 for(id row in config[@"widgets_v2"]){if([row isKindOfClass:NSDictionary.class]&&[row[@"id"] isEqual:identifier])own=row;else [items addObject:row];}
 if(!own||![own[@"type"] isEqual:@"a2ui"])return nil;
 [items insertObject:own atIndex:0];
 NSMutableDictionary *changed=[config mutableCopy];changed[@"widgets_v2"]=items;return changed;
}

static void Query(NSString *stage){
 if(!CardSend(@{@"cmd":@"dashboard_config",@"payload":@{@"version":@1,@"value":@0}},stage)){Idle(@"无法发送读取请求；请回官方首页确认眼镜连接，保持手机前台");}
}

static BOOL Begin(void){
 NSDictionary *nav=TIONavTransportStatus();
 if(nav[@"pending"]||[nav[@"enabled"] boolValue]){Idle(@"导航卡更新通道占用中；先停止导航/仪表盘导航卡，再操作卡片。");return NO;}
 if(!CardRoute||!CardDevice.length||![TIOProtocolDevice() isEqual:CardDevice]||UIApplication.sharedApplication.applicationState!=UIApplicationStateActive){Idle(@"未发送：请回官方首页确认眼镜连接，保持手机前台。");return NO;}
 if(![CardPeer isEqual:CardDevice]){Idle(@"目标眼镜与当前连接不一致，未发送。");return NO;}
 CardBusyFlag=YES;CardBefore=nil;CardMutated=NO;Query(@"before");return CardBusyFlag;
}

BOOL TCEBusy(void){return CardBusyFlag;}
NSString *TCEStatus(void){return CardNote;}

void TCEPublish(NSDictionary *draft,BOOL first){
 if(CardBusyFlag){Change(@"上一轮仍在确认");return;}
 NSString *reason=nil;NSDictionary *install=TCEInstall(draft,&reason);
 if(!install){Change(reason?:@"草稿校验失败，未发送");return;}
 CardReadOnly=NO;CardInstall=install;CardIdentifier=[draft[@"id"] copy];CardFirst=first;CardPeer=[CardDevice copy];Begin();
}

BOOL TCEPublishWithCompletion(NSDictionary *draft,NSString *expectedPeer,void(^complete)(NSDictionary *receipt)){
 if(!complete)return NO;
 if(CardBusyFlag||![expectedPeer isKindOfClass:NSString.class]||![expectedPeer isEqual:CardDevice]){complete(nil);return NO;}
 void(^saved)(NSDictionary *)=[complete copy];
 NSString *reason=nil;NSDictionary *install=TCEInstall(draft,&reason);
 if(!install){Change(reason?:@"草稿校验失败，未发送");complete(nil);return NO;}
 CardInstall=install;CardIdentifier=[draft[@"id"] copy];CardFirst=YES;CardPeer=[expectedPeer copy];CardReadOnly=NO;
 if(!Begin()){saved(nil);return NO;}
 CardCompletion=saved;return YES;
}

void TCERemove(NSString *identifier){
 if(CardBusyFlag)return;
 if(![identifier isKindOfClass:NSString.class]||[identifier length]<15||[identifier length]>48||![identifier hasPrefix:@"turbo_ui_card_"])return;
 static NSCharacterSet *allowed;
 if(!allowed)allowed=[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789_"];
 if([[identifier substringFromIndex:14] rangeOfCharacterFromSet:allowed.invertedSet].location!=NSNotFound||[identifier length]-14>34)return;
 CardReadOnly=NO;CardInstall=nil;CardIdentifier=[identifier copy];CardFirst=NO;CardPeer=[CardDevice copy];Begin();
}

// Read-only readback: reports the current dashboard rows, never mutates.
void TCEInspect(void){
 if(CardBusyFlag){Change(@"上一轮仍在确认");return;}
 NSDictionary *nav=TIONavTransportStatus();
 if(nav[@"pending"]||[nav[@"enabled"] boolValue]){Idle(@"导航卡更新通道占用中；先停止导航/仪表盘导航卡，再回查。");return;}
 if(!CardRoute||!CardDevice.length||![TIOProtocolDevice() isEqual:CardDevice]||UIApplication.sharedApplication.applicationState!=UIApplicationStateActive){Idle(@"未发送：请回官方首页确认眼镜连接，保持手机前台。");return;}
 CardBusyFlag=YES;CardReadOnly=YES;CardInstall=nil;CardIdentifier=nil;CardFirst=NO;CardPeer=[CardDevice copy];CardMutated=NO;Query(@"before");
}

void TCEObserveEvent(NSDictionary *event){
 if(![event isKindOfClass:NSDictionary.class]||![event[@"eventType"] isEqual:@"messageReceived"])return;
 NSDictionary *m=event[@"message"];
 if(![m isKindOfClass:NSDictionary.class]||![m[@"businessId"] isEqual:@15]||![m[@"deviceId"] isEqual:CardDevice])return;
 NSDictionary *e=TIOA2UIDecode(Bytes(m[@"payload"]));
 if(![e[@"type"] isEqual:@19]||!CardSequence)return;
 NSDictionary *j=e[@"json"];uint32_t seq=[e[@"sequence"] unsignedIntValue];
 if(seq!=CardSequence&&seq!=0)return;
 CardLease=Now();CardSequence=0;
 NSString *step=CardStep;CardStep=nil;
 if([step isEqual:@"before"]){
  CardBefore=Config(j);
  if(!CardBefore){Idle(@"仪表盘回读格式无法识别，已停止后续修改");return;}
  if(CardReadOnly){
   NSMutableString *report=[NSMutableString stringWithString:@"眼镜仪表盘 · 已回读（未修改）"];
   NSUInteger index=0;
   for(id row in CardBefore[@"widgets_v2"]){index++;[report appendFormat:@"\n%lu · %@ [%@]",(unsigned long)index,row[@"name"]?:row[@"id"],row[@"type"]];}
   Complete(CardBefore);
   Idle(report.copy);return;
  }
  NSDictionary *old=FindRow(CardBefore,CardIdentifier);
  if(old&&![old[@"type"] isEqual:@"a2ui"]){Idle(@"眼镜已有同名非本工具卡片，拒绝覆盖");return;}
  if(!CardInstall&&!old){Idle(@"眼镜没有这张卡片，未执行移除");return;}
  NSDictionary *command=CardInstall?:@{@"cmd":@"widget_uninstall",@"payload":@{@"data":@{@"id":CardIdentifier}}};
  if(!CardSend(command,CardInstall?@"install":@"remove")){Idle(CardInstall?@"安装请求未发送；未修改眼镜":@"移除请求未发送；未修改眼镜");return;}
  return;
 }
 if([step isEqual:@"install"]||[step isEqual:@"remove"]){
  id code=j[@"code"];
  if(![code isKindOfClass:NSNumber.class]||CFGetTypeID((__bridge CFTypeRef)code)==CFBooleanGetTypeID()||[code integerValue]!=0){Idle([NSString stringWithFormat:@"眼镜拒绝修改（code=%@），已停止",code]);return;}
  Query([step isEqual:@"install"]?@"verify-install":@"verify-remove");return;
 }
 if([step isEqual:@"verify-install"]){
  NSDictionary *after=Config(j);NSDictionary *own=after?FindRow(after,CardIdentifier):nil;
  if(!after||!own||![own[@"type"] isEqual:@"a2ui"]||!Preserves(CardBefore,after,CardIdentifier)){Idle(@"安装回查不符，已停止；请核对眼镜，不自动重试");return;}
  NSDictionary *expected=((CardInstall[@"payload"][@"data"]));
  if(![own[@"name"] isEqual:expected[@"name"]]||!SameExtras(own[@"extras"],expected[@"extras"])){Idle(@"回查内容与草稿不一致，已停止");return;}
  if(CardFirst){
   NSDictionary *ordered=Reordered(after,CardIdentifier);
   if(!ordered){Idle(@"无法生成置顶顺序，已停止；卡片已安装，其他卡片顺序不变");return;}
   NSData *canonical=[NSJSONSerialization dataWithJSONObject:ordered options:NSJSONWritingSortedKeys error:nil];
   if(!canonical){Idle(@"顺序数据编码失败，未修改顺序");return;}
   if(!CardSend(@{@"cmd":@"dashboard_update",@"payload":@{@"version":@1,@"value":@0,@"data":[[NSString alloc]initWithData:canonical encoding:NSUTF8StringEncoding]}},@"order")){Idle(@"置顶请求未发送；卡片已安装，顺序未变");return;}
   return;
  }
  Complete(after);
  Idle(@"眼镜已确认并回读卡片，其他卡片保留；请检查镜片显示");return;
 }
 if([step isEqual:@"order"]){
  id value=j[@"payload"];
  if([value isKindOfClass:NSDictionary.class])value=value[@"value"];
  if(![value isKindOfClass:NSNumber.class]||[value integerValue]!=0){Idle(@"眼镜拒绝置顶顺序，已停止");return;}
  Query(@"verify-order");return;
 }
 if([step isEqual:@"verify-order"]){
  NSDictionary *after=Config(j);
  NSArray *rows=after[@"widgets_v2"];
  if(!after||rows.count<1||![rows[0][@"id"] isEqual:CardIdentifier]||!Preserves(CardBefore,after,CardIdentifier)){Idle(@"置顶回查不符，已停止；请核对眼镜");return;}
  Complete(after);
  Idle(@"卡片已置顶并回读确认，其他卡片顺序保留；镜片效果待确认");return;
 }
 if([step isEqual:@"verify-remove"]){
  NSDictionary *after=Config(j);
  if(!after||FindRow(after,CardIdentifier)||!Preserves(CardBefore,after,CardIdentifier)){Idle(@"移除回查不符，已停止；请核对眼镜");return;}
  Idle(@"本卡已移除，其他卡片保留");return;
 }
}
