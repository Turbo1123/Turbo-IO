#import "NavigationTeleHUD.h"
#import "NewsTeleprompter.h"
#import "NavigationCore.h"
#include <math.h>
NSString *TIONavTeleKey(NSDictionary *f){
    if(![f isKindOfClass:NSDictionary.class]||![f[@"phase"] isEqual:@"navigating"]||![f[@"mode"] isEqual:@"模拟导航 · 非实际定位"])return nil;
    for(NSString *k in @[@"turn",@"road",@"distance"])if(![f[k] isKindOfClass:NSString.class]||[f[k] lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>240)return nil;
    id segment=f[@"segment"];if(![segment isKindOfClass:NSNumber.class]||CFGetTypeID((__bridge CFTypeRef)segment)==CFBooleanGetTypeID())return nil;
    double n=[segment doubleValue];if(!isfinite(n)||n<0||n>100000||n!=[segment integerValue])return nil;
    return [[NSString alloc]initWithData:[NSJSONSerialization dataWithJSONObject:@[segment,f[@"turn"],f[@"road"]] options:0 error:nil] encoding:NSUTF8StringEncoding];
}
NSString *TIONavTeleText(NSDictionary *f,NSUInteger sequence){
    if(!TIONavTeleKey(f)||!sequence||sequence>13)return nil;
    return [NSString stringWithFormat:@"高德模拟导航 %02lu\n%@\n%@\n更新时距转向：%@\n仅指令变化时更新，非实时距离\n请以手机地图为准",(unsigned long)sequence,TIONavClip(f[@"turn"],120),TIONavClip(f[@"road"],150),TIONavClip(f[@"distance"],60)];
}
@implementation TIONavTeleHUD {
    BOOL _enabled,_owns,_starting,_waiting;
    NSNumber *_session;
    NSDictionary *_latest;
    NSString *_committed,*_pendingKey,*_note;
    NSTimeInterval _latestAt,_lastSent,_startedAt;
    NSUInteger _frames;
}
- (instancetype)init{if((self=[super init]))_note=@"常亮指引未启用；先获取官方手动提词模板";return self;}
- (NSDictionary *)status{return @{@"version":@"nav-tele-v1",@"enabled":@(_enabled),@"owns":@(_owns),@"waiting":@(_waiting||_starting),@"frames":@(_frames),@"note":_note?:@""};}
- (BOOL)matches:(NSDictionary *)s{return _owns&&[s[@"navigation"] boolValue]&&[s[@"sessionEpoch"] isEqual:_session];}
- (BOOL)enable{
    NSDictionary *s=TIONewsTeleStatus();
    if(_enabled||_owns||[s[@"active"] boolValue]||![s[@"manualAvailable"] boolValue]){_note=@"不能开启：请先结束已有提词，并取得官方手动准备／开始／退出模板";return NO;}
    _enabled=YES;_latest=nil;_committed=_pendingKey=nil;_frames=0;_waiting=_starting=NO;_note=@"已启用，等待高德模拟路线指令";return YES;
}
- (void)stop:(NSString *)reason{
    NSDictionary *s=TIONewsTeleStatus();BOOL matched=[self matches:s];
    _enabled=NO;_owns=NO;_starting=_waiting=NO;_latest=nil;_session=nil;
    // Never stop another owner even if it is also a navigation/manual session.
    if(matched&&! [s[@"stopping"] boolValue])TIONewsTeleControl(6,120);
    _note=[NSString stringWithFormat:@"%@%@",reason?:@"常亮指引停止",matched?@"；已请求退出，镜片关闭需确认":@""];
}
- (void)offer:(NSDictionary *)f at:(NSTimeInterval)now{
    if(!_enabled||!isfinite(now))return;
    if(!TIONavTeleKey(f)){[self stop:@"路线暂不可用／非模拟路线，停止旧指引"];return;}
    _latest=[f copy];_latestAt=now;
}
- (void)pumpAt:(NSTimeInterval)now{
    if(!_enabled||!isfinite(now))return;
    NSDictionary *s=TIONewsTeleStatus();
    if(_owns&&(![self matches:s]||[s[@"stopping"] boolValue]||[s[@"manualBlocked"] boolValue])){[self stop:@"提词已退出、超时或异常，需手动重新启用"];return;}
    if(!_latest)return;
    if(now-_latestAt>15||now<_latestAt){[self stop:@"高德指令超过15秒未更新，停止旧指引"];return;}
    if(_owns&&now-_startedAt>=300){[self stop:@"5分钟模拟验收结束"];return;}
    NSString *key=TIONavTeleKey(_latest);
    if(!_owns){
        if(!TIOTeleNavigationPrepare(TIONavTeleText(_latest,1))){[self stop:@"导航稿准备失败；不抢占、不重试"];return;}
        s=TIONewsTeleStatus();_session=s[@"sessionEpoch"];_owns=YES;_starting=YES;_pendingKey=key;_lastSent=_startedAt=now;_frames=1;_note=@"首帧准备中；收稿成功后自动开始手动显示";return;
    }
    if(_starting){
        if(![s[@"ready"] boolValue])return;
        if(![s[@"started"] boolValue]){if(!TIONewsTeleControl(3,120))[self stop:@"导航提词启动失败"];return;}
        if(![s[@"playing"] boolValue]||[s[@"manualPending"] unsignedIntegerValue])return;
        _starting=NO;_committed=_pendingKey;_pendingKey=nil;_note=@"常亮指令已开始；换稿会出现传输loading";
    }
    if(_waiting){
        if([s[@"replacing"] boolValue]||![s[@"ready"] boolValue])return;
        _waiting=NO;_committed=_pendingKey;_pendingKey=nil;_note=@"新指令收稿确认；实际镜片效果待核对";
    }
    if(![s[@"playing"] boolValue]){[self stop:@"提词已暂停，停止导航显示更新"];return;}
    // One second slack relative to the transport's independent 15s guard.
    if([key isEqual:_committed]||now-_lastSent<16)return;
    if(_frames>=13){[self stop:@"本轮13帧验收上限已到，停止更新"];return;}
    if(!TIOTeleNavigationReplace(TIONavTeleText(_latest,_frames+1))){[self stop:@"导航换稿未提交，停止更新，不循环重试"];return;}
    _frames++;_lastSent=now;_pendingKey=key;_waiting=YES;_note=@"转向／路段改变，等待新稿回执；合并在途更新";
}
@end
