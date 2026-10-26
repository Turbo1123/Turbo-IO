#import "ReaderBridge.h"
#import "ReaderTransport.h"
#import "ReadingContent.h"
#import "reader.h"
#include <assert.h>
#include <stdio.h>
static TWReaderBridge *bridge;static WRReader state;static NSMutableArray *trace;static NSString *peer=@"SYNTHETIC-DEVICE";static NSUInteger cleanups;
id TIOProtocolPlugin(void){return nil;}
NSString *TIOProtocolDevice(void){return peer;}
static NSDictionary *Reply(unsigned event,unsigned result,uint32_t seq,uint32_t rev){uint8_t b[48]={0};memcpy(b,"WRA1",4);b[4]=1;b[5]=event;b[6]=result;b[7]=state.active;wr_put(b+8,state.sid);wr_put(b+12,seq);wr_put(b+16,rev);wr_put(b+20,state.event_id);wr_put(b+24,state.event_value);wr_put(b+44,wr_crc(b,44));NSMutableString *hex=[NSMutableString new];for(unsigned i=0;i<48;i++)[hex appendFormat:@"%02x",b[i]];NSData *json=[NSJSONSerialization dataWithJSONObject:@{@"cmd":@"turbo_read_v1",@"payload":@{@"data":hex}} options:0 error:nil];uint8_t prefix[7]={8,1,16,6,26,(json.length&127)|128,json.length>>7};NSMutableData *payload=[NSMutableData dataWithBytes:prefix length:7];[payload appendData:json];return @{@"eventType":@"messageReceived",@"message":@{@"businessId":@15,@"deviceId":peer,@"payload":payload}};}
@implementation TWTransport
- (instancetype)initWithRoot:(NSURL *)r device:(NSString *)d currentDevice:(NSString *(^)(void))c call:(BOOL(^)(NSString *,NSDictionary *,void(^)(id)))call{return [super init];}
- (void)send:(NSData *)packet task:(NSString *)task submitted:(TWSubmitted)done{WRPacket p;assert(wr_decode(packet.bytes,packet.length,&p));[trace addObject:[packet base64EncodedStringWithOptions:0]];unsigned result=wr_receive(&state,&p,1000);assert(result==WR_OK);if(state.pending)wr_publish(&state);
 NSDictionary *file=@{@"eventType":@"fileShareSuccess",@"device":@{@"id":peer},@"role":@"sender",@"fileName":@"turbo-reader.twr",@"taskId":task};
 // Intentionally deliver native terminal event BEFORE send completion.
 [bridge consume:file];[bridge consume:Reply(0,result,p.sequence,p.revision)];done(YES,task);
 if(p.op==WR_OPEN)[bridge consume:Reply(WR_SHELF,0,p.sequence,p.revision)];
}
- (void)cleanup:(NSString *)task{assert(task.length);cleanups++;}
@end
static void Pump(void){[NSThread sleepForTimeInterval:.13];[bridge pump];}
int main(int argc,const char **argv){@autoreleasepool{trace=[NSMutableArray new];bridge=[TWReaderBridge new];__block unsigned commands=0;bridge.command=^(NSDictionary *q){commands++;};[bridge open];for(int i=0;i<4;i++)Pump();assert(bridge.active&&commands==1);
 NSArray *lines=TWReadingLines(@"这是手机和固件的端到端合成验证。\n每次只传有限窗口，不是整本书。\n最后校验7392。");NSData *body=TWReaderWindow(lines,@"原创验证正文",1,0,480,YES);assert(body);[bridge sendBody:body];for(int i=0;i<30&&bridge.busy;i++)Pump();assert(!bridge.busy&&state.valid&&state.speed==480);
 [bridge settings:120 automatic:NO];for(int i=0;i<10&&bridge.busy;i++)Pump();assert(state.speed==120&&!state.automatic);[bridge close];for(int i=0;i<10&&bridge.busy;i++)Pump();assert(!bridge.active&&!state.active&&cleanups==trace.count);
 NSArray *replayPackets=[trace copy];
 // Physical exit retires this SID. Reopening must establish a NEW SID even
 // though the Bluetooth peer and the bridge object have not changed.
 wr_clear(&state); // Native service retires its render buffers after CLOSE.
 [bridge open];for(int i=0;i<4;i++)Pump();uint32_t retired=state.sid;assert(state.active);
 [bridge consume:Reply(WR_CLOSED,0,state.sequence,state.revision)];assert(!bridge.active);wr_clear(&state);
 [bridge open];for(int i=0;i<4;i++)Pump();assert(state.active&&state.sid!=retired);
 [bridge close];for(int i=0;i<10&&bridge.busy;i++)Pump();assert(!bridge.active&&!state.active);
 NSDictionary *q;assert(TWDecodeReply(Reply(0,0,state.sequence,0),&q));assert(!TWDecodeReply(@{@"eventType":@"wrong"},NULL));
 if(argc>1){NSData *d=[NSJSONSerialization dataWithJSONObject:@{@"syntheticOnly":@YES,@"packets":replayPackets} options:NSJSONWritingPrettyPrinted error:nil];assert([d writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:NO]);}
 puts("PASS phone bridge: serialized packets, early terminal, ACK + file completion, body/settings/close, no credentials");
}return 0;}
