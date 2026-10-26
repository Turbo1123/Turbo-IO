#import "MusicBridge.h"
#import "MusicTransport.h"
#import "ProtocolContext.h"
#import "music.h"
#import "DisplayDiagnostics.h"
#import <objc/message.h>
static uint32_t Read(const uint8_t *p){return p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static void Put(uint8_t *p,uint32_t v){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(v>>(8*i));}
static BOOL Var(const uint8_t *p,NSUInteger n,NSUInteger *at,uint32_t *v){*v=0;for(unsigned i=0;i<5;i++){if(*at>=n)return NO;uint8_t b=p[(*at)++];if(i==4&&(b&240))return NO;*v|=(uint32_t)(b&127)<<(i*7);if(!(b&128))return YES;}return NO;}
BOOL TMMusicReply(NSDictionary *e,NSDictionary **out){if(![e isKindOfClass:NSDictionary.class]||![e[@"eventType"]isEqual:@"messageReceived"])return NO;id m=e[@"message"];if(![m isKindOfClass:NSDictionary.class]||![m[@"businessId"]isEqual:@15]||![m[@"payload"]isKindOfClass:NSData.class])return NO;NSData *d=m[@"payload"];if(d.length>512)return NO;
 const uint8_t *p=d.bytes;NSUInteger at=0;uint32_t version=0,type=0;NSData *json=nil;unsigned seen=0;
 while(at<d.length){uint32_t k,n;if(!Var(p,d.length,&at,&k)||k>>3==0||k>>3>6||(seen&(1u<<(k>>3))))return NO;seen|=1u<<(k>>3);if((k&7)==0){if(!Var(p,d.length,&at,&n))return NO;if(k>>3==1)version=n;if(k>>3==2)type=n;}else if((k&7)==2){if(!Var(p,d.length,&at,&n)||n>d.length-at)return NO;if(k>>3==3)json=[d subdataWithRange:NSMakeRange(at,n)];at+=n;}else return NO;}
 if(version!=1||type!=6||!json)return NO;id j=[NSJSONSerialization JSONObjectWithData:json options:0 error:nil];if(![j isKindOfClass:NSDictionary.class]||![j[@"cmd"]isEqual:@"turbo_music_v1"]||![j[@"payload"]isKindOfClass:NSDictionary.class])return NO;NSString *hex=j[@"payload"][@"data"];if(![hex isKindOfClass:NSString.class]||hex.length!=64)return NO;uint8_t raw[32];for(unsigned i=0;i<32;i++){unsigned v=0;for(unsigned k=0;k<2;k++){unichar c=[hex characterAtIndex:2*i+k];unsigned n=c>='0'&&c<='9'?c-'0':c>='a'&&c<='f'?c-'a'+10:16;if(n>15)return NO;v=v*16+n;}raw[i]=v;}
 if(memcmp(raw,"TMA1",4)||raw[4]!=1||raw[5]>TM_VIEW_CLOSED||raw[6]>TM_NO_SESSION||(raw[7]&~3)||Read(raw+28)!=tm_crc(raw,28))return NO;
 if(out)*out=@{@"event":@(raw[5]),@"result":@(raw[6]),@"active":@((raw[7]&1)!=0),@"awake":@((raw[7]&2)!=0),@"sid":@(Read(raw+8)),@"generation":@(Read(raw+12)),@"sequence":@(Read(raw+16)),@"request":@(Read(raw+20)),@"position":@(Read(raw+24))};return YES;
}
static NSData *Clip(NSString *s,NSUInteger max){if(![s isKindOfClass:NSString.class])s=@"";s=[[s componentsSeparatedByCharactersInSet:NSCharacterSet.controlCharacterSet]componentsJoinedByString:@" "];NSMutableData *d=[NSMutableData new];[s enumerateSubstringsInRange:NSMakeRange(0,s.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *a,NSRange r,NSRange all,BOOL *stop){NSData *b=[a dataUsingEncoding:NSUTF8StringEncoding];if(d.length+b.length>max){*stop=YES;return;}[d appendData:b];}];return d;}
@implementation TMMusicBridge{
 TMTransport *_transport;NSString *_peer,*_task,*_nativeTask,*_note;NSData *_packet,*_cover,*_lyrics;NSArray *_rows;NSMutableArray *_early;
 uint32_t _sid,_gen,_seq,_sendingGen;NSUInteger _coverAt,_lyricsAt,_chunk;unsigned _op;BOOL _ack,_fileDone,_submitted,_active,_needOpen,_needClose,_failed;
 NSTimeInterval _deadline,_lastClock,_next;NSUInteger _count;NSMutableOrderedSet *_commands;
}
- (instancetype)init{if((self=[super init])){TDPDiagConfigure([NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/display-phone-diagnostics.json"]]);TDPDiagRecord(@"state",@{@"code":@2302});}return self;}
- (BOOL)busy{return _packet!=nil;}
- (BOOL)active{return _active;}
- (void)reopen{if(!_gen||_failed)return;_needOpen=_active=YES;_needClose=NO;[self pump];}
- (void)changed{_lastClock=0;[self pump];}
- (NSString *)note{return _note?:@"尚未同步 · 需要 TMU1 新固件";}
- (BOOL)setup{NSString *peer=TIOProtocolDevice();if(!peer.length){_note=@"眼镜未连接";return NO;}if(_transport&&[_peer isEqual:peer])return !_failed;if(self.busy)return NO;
 _peer=[peer copy];_failed=NO;_commands=[NSMutableOrderedSet new];uint64_t last=[[NSUserDefaults.standardUserDefaults objectForKey:@"TurboMusicSIDV1"]unsignedLongLongValue];uint64_t sid=MAX(last+1,(uint64_t)NSDate.date.timeIntervalSince1970);if(sid>UINT32_MAX)return NO;_sid=(uint32_t)sid;_seq=0;[NSUserDefaults.standardUserDefaults setObject:@(sid) forKey:@"TurboMusicSIDV1"];
 NSString *pinned=_peer;NSURL *root=[NSURL fileURLWithPath:[NSHomeDirectory()stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/MusicTMU1"]];
 _transport=[[TMTransport alloc]initWithRoot:root device:_peer currentDevice:^{return TIOProtocolDevice();} call:^BOOL(NSString *method,NSDictionary *args,void(^done)(id)){
  if(![pinned isEqual:TIOProtocolDevice()])return NO;id plugin=TIOProtocolPlugin();Class cls=NSClassFromString(@"FlutterMethodCall");SEL make=NSSelectorFromString(@"methodCallWithMethodName:arguments:"),handle=NSSelectorFromString(@"handleMethodCall:result:");if(!plugin||![cls respondsToSelector:make]||![plugin respondsToSelector:handle])return NO;
  @try{id c=((id(*)(id,SEL,id,id))objc_msgSend)(cls,make,method,args);((void(*)(id,SEL,id,id))objc_msgSend)(plugin,handle,c,[done copy]);return YES;}@catch(NSException *e){return NO;}
 }];return YES;
}
- (void)assetsCover:(NSData *)cover lyrics:(NSArray *)rows{if(cover.length==TM_COVER_BYTES&&!_cover)_cover=[cover copy];if(rows.count&&!_lyrics){NSMutableData *d=[NSMutableData new];for(NSDictionary *r in rows){NSData *s=Clip(r[@"text"],240);if(!s.length)continue;if(d.length+6+s.length>TM_LYRIC_BYTES)break;uint8_t h[6];Put(h,[r[@"ms"]unsignedIntValue]);h[4]=s.length&255;h[5]=s.length>>8;[d appendBytes:h length:6];[d appendData:s];}_lyrics=d;}}
- (void)openWithCover:(NSData *)cover lyrics:(NSArray *)lyrics{if(![self setup])return;if(++_gen==0){_failed=YES;_note=@"会话计数耗尽，请重启";return;}_cover=_lyrics=nil;_coverAt=_lyricsAt=0;_needOpen=_active=YES;_needClose=NO;[self assetsCover:cover lyrics:lyrics];_note=@"请求打开眼镜音乐页";[self pump];}
- (NSData *)state{NSDictionary *s=self.snapshot?self.snapshot():@{};uint8_t b[TM_STATE_BYTES]={0};Put(b,MIN(86400000,[s[@"position"]unsignedIntValue]));Put(b+4,MIN(86400000,[s[@"duration"]unsignedIntValue]));b[8]=[s[@"playing"]boolValue];b[9]=MIN(2,[s[@"mode"]unsignedIntValue]);Put(b+12,[s[@"request"]unsignedIntValue]);NSData *title=Clip(s[@"title"],95),*artist=Clip(s[@"artist"],79);memcpy(b+16,title.bytes,title.length);memcpy(b+112,artist.bytes,artist.length);return [NSData dataWithBytes:b length:sizeof b];}
- (void)fail:(NSString *)reason{_failed=YES;_active=NO;_note=reason;TDPDiagRecord(@"state",@{@"code":@4,@"op":@(_op),@"sid":@(_sid),@"revision":@(_sendingGen),@"packet":@(_seq)});/* Do not delete uncertain in-flight native file. */}
- (void)finish{if(!_packet||!_ack||!_fileDone||!_submitted)return;[_transport cleanup:_task];if(_sendingGen==_gen){if(_op==TM_OPEN)_needOpen=NO;if(_op==TM_COVER)_coverAt+=_chunk;if(_op==TM_LYRICS)_lyricsAt+=_chunk;if(_op==TM_CLOSE)_active=_needClose=NO;}
 TDPDiagRecord(@"packet_complete",@{@"op":@(_op),@"sid":@(_sid),@"revision":@(_sendingGen),@"packet":@(_seq)});_packet=nil;_task=_nativeTask=nil;_early=nil;_count++;_next=NSProcessInfo.processInfo.systemUptime+.12;_note=[NSString stringWithFormat:@"眼镜已确认 %lu 包 · %@",(unsigned long)_count,_active?@"正在同步":@"已关闭画面"];
}
- (void)send:(unsigned)op data:(NSData *)data offset:(NSUInteger)offset final:(BOOL)final{if(_seq==UINT32_MAX){[self fail:@"序号耗尽"];return;}uint8_t b[TM_PACKET_MAX];size_t n=tm_encode(b,sizeof b,op,final,_sid,_gen,++_seq,(uint32_t)offset,data.bytes,data.length);if(!n){[self fail:@"音乐包编码失败"];return;}
 _packet=[NSData dataWithBytes:b length:n];_task=NSUUID.UUID.UUIDString;_nativeTask=nil;_early=[NSMutableArray new];_ack=_fileDone=_submitted=NO;_sendingGen=_gen;_op=op;_chunk=data.length;_deadline=NSProcessInfo.processInfo.systemUptime+15;NSString *task=_task;__weak typeof(self) weak=self;
 TDPDiagRecord(@"send",@{@"op":@(op),@"sid":@(_sid),@"revision":@(_gen),@"packet":@(_seq),@"bytes":@(n)});
 [_transport send:_packet task:task submitted:^(BOOL ok,NSString *native){TMMusicBridge *s=weak;if(!s||![task isEqual:s->_task])return;if(!ok){[s fail:@"提交失败，未继续发送。请重连后重试。"];return;}s->_submitted=YES;s->_nativeTask=native;NSArray *early=s->_early;s->_early=nil;for(NSDictionary *e in early)[s consume:e];[s finish];}];
}
- (void)close{_needClose=YES;[self pump];}
- (void)pump{NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;if(_peer&&![_peer isEqual:TIOProtocolDevice()]){[self fail:@"眼镜连接已变化，音乐仍可在手机播放"];return;}if(_failed)return;if(_packet){if(now>=_deadline)[self fail:@"眼镜未回执：确认 TMU1 固件和蓝牙。传输已停止。"];return;}if(!_active||now<_next)return;
 if(_needClose){[self send:TM_CLOSE data:nil offset:0 final:NO];return;}
 if(_needOpen){_lastClock=now;[self send:TM_OPEN data:[self state] offset:0 final:NO];return;}
 if(now-_lastClock>=3){_lastClock=now;[self send:TM_CLOCK data:[self state] offset:0 final:NO];return;}
 if(_lyricsAt<_lyrics.length){NSUInteger n=MIN(TM_PACKET_MAX-32,_lyrics.length-_lyricsAt);[self send:TM_LYRICS data:[_lyrics subdataWithRange:NSMakeRange(_lyricsAt,n)] offset:_lyricsAt final:_lyricsAt+n==_lyrics.length];return;}
 if(_coverAt<_cover.length){NSUInteger n=MIN(TM_PACKET_MAX-32,_cover.length-_coverAt);[self send:TM_COVER data:[_cover subdataWithRange:NSMakeRange(_coverAt,n)] offset:_coverAt final:_coverAt+n==_cover.length];}
}
- (BOOL)consume:(NSDictionary *)e{NSString *type=e[@"eventType"];if([@[@"fileShareSuccess",@"fileShareFailed"]containsObject:type]){if(![e[@"device"]isKindOfClass:NSDictionary.class]||![e[@"device"][@"id"]isEqual:_peer]||![e[@"role"]isEqual:@"sender"])return NO;if(!_nativeTask&&_packet){if(_early.count<8)[_early addObject:e];return NO;}if(![e[@"taskId"]isEqual:_nativeTask])return NO;if([type isEqual:@"fileShareFailed"]){[self fail:@"音乐传输失败"];return YES;}if(![e[@"fileName"]isEqual:@"turbo-music.tmu"])return NO;_fileDone=YES;[self finish];return YES;}
 NSDictionary *q;if(!TMMusicReply(e,&q))return NO;BOOL peerMatch=[e[@"message"][@"deviceId"]isEqual:TIOProtocolDevice()];TDPDiagRecord(@"reply_match",@{@"deviceMatch":@(peerMatch),@"eventCode":q[@"event"],@"result":q[@"result"],@"ready":q[@"active"],@"foreground":q[@"awake"],@"sid":q[@"sid"],@"revision":q[@"generation"],@"packet":q[@"sequence"],@"request":q[@"request"]});if(!peerMatch)return YES;
 unsigned event=[q[@"event"]unsignedIntValue];if(event){if(![self setup])return YES;if(event!=TM_RESUME&&([q[@"sid"]unsignedIntValue]!=_sid||[q[@"generation"]unsignedIntValue]!=_gen))return YES;NSNumber *key=q[@"request"];if(![_commands containsObject:key]){[_commands addObject:key];if(_commands.count>128)[_commands removeObjectAtIndex:0];if(event==TM_VIEW_CLOSED){_active=NO;_needOpen=NO;}if(self.command)self.command(q);}return YES;}
 if(!_packet||[q[@"sid"]unsignedIntValue]!=_sid||[q[@"generation"]unsignedIntValue]!=_sendingGen||[q[@"sequence"]unsignedIntValue]!=_seq)return YES;
 if([q[@"result"]unsignedIntValue]!=TM_OK){[self fail:[NSString stringWithFormat:@"眼镜拒绝音乐包（%@）",q[@"result"]]];return YES;}_ack=YES;[self finish];return YES;
}
@end
