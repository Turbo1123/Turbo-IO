#import "SubtitleHUDCore.h"
#include <assert.h>
int main(void){@autoreleasepool{
    NSDictionary *preview=@{@"sid":@"official",@"scope":@"temporary",@"force":@NO,@"config":@{@"is_display":@YES}},*stop=@{@"sid":@"official",@"reason_code":@10};
    NSMutableArray *sent=[NSMutableArray new];TIOSubtitleTrial *t=[TIOSubtitleTrial new];
    NSDictionary *differentStop=@{@"sid":@"different-official-id",@"reason_code":@10,@"text":@""};
    NSDictionary *derived=TIOSubtitleStopContract(differentStop,@"official");assert([derived[@"sid"] isEqual:@"official"]);assert([differentStop[@"sid"] isEqual:@"different-official-id"]);
    assert(!TIOSubtitleStopContract(@{@"sid":@"x",@"reason_code":@11,@"text":@""},@"official"));
    assert(!TIOSubtitleStopContract(@{@"sid":@"x",@"reason_code":@10,@"text":@"private"},@"official"));
    assert(!TIOSubtitleStopContract(@{@"sid":@"x",@"reason_code":@10,@"text":@"",@"force":@YES},@"official"));
    t.send=^BOOL(NSUInteger type,NSDictionary *j){[sent addObject:@{@"type":@(type),@"json":j}];assert(([@[@3,@5,@7] containsObject:@(type)]));return YES;};
    assert(![t nextAt:1]);assert(![t startWithPreview:@{} stop:stop now:1]);assert(![t startWithPreview:preview stop:@{@"sid":@"wrong"} now:1]);
    assert([t startWithPreview:preview stop:stop now:10]);assert(![t.sid isEqual:@"official"]);assert(![t startWithPreview:preview stop:stop now:11]);assert(![t nextAt:11]);
    [t receive:@{@"type":@8,@"json":@{@"sid":@"wrong",@"code":@1}} now:11];assert([t.phase isEqual:@"starting"]);
    [t receive:@{@"type":@8,@"json":@{@"sid":t.sid,@"code":@1}} now:12];assert([t.phase isEqual:@"ready"]);
    assert([t nextAt:13]);assert(![t nextAt:14]);assert([t nextAt:16]);assert([t nextAt:19]);assert(![t nextAt:25]);assert(sent.count==4);
    for(NSDictionary *e in sent){NSData *p=TIOSubtitlePacket([e[@"type"] unsignedIntegerValue],e[@"json"]);NSDictionary *decoded=TIOSubtitleEnvelope(p);assert([decoded[@"json"] isEqual:e[@"json"]]);}
    assert([sent[1][@"json"][@"mode"] isEqual:@3]);assert([sent[1][@"json"][@"status"] isEqual:@0]);
    [t tick:249];assert([t.phase isEqual:@"ready"]);[t tick:250];assert([t.phase isEqual:@"stopping"]);assert([sent.lastObject[@"type"] isEqual:@3]);assert([sent.lastObject[@"json"][@"reason_code"] isEqual:@10]);
    [t tick:258];assert([t.phase isEqual:@"uncertain"]);assert(![t startWithPreview:preview stop:stop now:259]);
    // Audio type4 with binary payload and no JSON must not be silently ignored.
    uint8_t audio[]={8,1,16,4,34,3,0xff,0,0x80};NSDictionary *ae=TIOSubtitleEnvelope([NSData dataWithBytes:audio length:sizeof(audio)]);assert([ae[@"type"] isEqual:@4]&&[ae[@"binaryBytes"] isEqual:@3]);
    t.phase=@"idle";assert([t startWithPreview:preview stop:stop now:300]);[t receive:ae now:301];assert(t.audioPackets==1&&[t.phase isEqual:@"stopping"]);NSUInteger count=sent.count;[t receive:ae now:302];assert(sent.count==count&&t.audioPackets==2);
    uint8_t malformed[]={8,1,16,4,34,127};assert(!TIOSubtitleEnvelope([NSData dataWithBytes:malformed length:sizeof(malformed)]));assert(!TIOSubtitlePacket(1,@{}));
    t.phase=@"idle";assert([t startWithPreview:preview stop:stop now:400]);[t tick:410];assert([t.phase isEqual:@"stopping"]);
    // New caption mode must not relax navigation limits, steal a SID or permit oversized text.
    t.phase=@"idle";assert([t startLiveCaptionWithPreview:preview stop:stop now:500]);assert(t.liveCaption);
    assert(![t sendNavigationText:@"before ack" now:501]);
    [t receive:@{@"type":@8,@"json":@{@"sid":t.sid,@"code":@1}} now:501];
    assert([t sendNavigationText:@"hello" now:502]);assert(![t sendNavigationText:@"too fast" now:502.1]);
    assert([t sendNavigationText:@"world" now:502.5]);
    assert(![t sendNavigationText:[@"中" stringByPaddingToLength:129 withString:@"中" startingAtIndex:0] now:503]);
    [t tick:800];assert([t.phase isEqual:@"ready"]);
    [t tick:1700];assert([t.phase isEqual:@"stopping"]);
    t.phase=@"idle";assert([t startNavigationWithPreview:preview stop:stop now:1800]);assert(!t.liveCaption);
    [t receive:@{@"type":@8,@"json":@{@"sid":t.sid,@"code":@1}} now:1801];
    assert([t sendNavigationText:@"nav" now:1802]);assert(![t sendNavigationText:@"nav2" now:1802.5]);
    [t tick:2040];assert([t.phase isEqual:@"stopping"]);
    NSLog(@"PASS subtitle HUD: original guards plus isolated live caption 0.5s/384bytes/20min; mock only.");
}return 0;}
