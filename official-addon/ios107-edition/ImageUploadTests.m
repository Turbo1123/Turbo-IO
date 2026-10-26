#import "ImageUpload.h"
#include <assert.h>
static void Pump(void){[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];}
static uint32_t LE(const uint8_t *p){return p[0]|((uint32_t)p[1]<<8)|((uint32_t)p[2]<<16)|((uint32_t)p[3]<<24);}
int main(int argc,char **argv){@autoreleasepool{
 NSMutableData *pixels=[NSMutableData dataWithLength:TIO_PIXELS];memset(pixels.mutableBytes,73,TIO_PIXELS);
 __block NSData *packet;__block NSString *task;__block void(^accepted)(BOOL);
 TIOImageUpload *c=[[TIOImageUpload alloc]initWithSender:^(NSData *p,NSString *d,NSString *t,void(^cb)(BOOL)){assert([d isEqual:@"mock-peer"]);packet=p;task=t;accepted=cb;}];
 assert(![c sendLuminance:pixels at:0]);assert(!TIOImageUploadPacket([NSData data],1,1));
 assert([c authorizeDevice:@"mock-peer" session:7392 at:0]);assert([c sendLuminance:pixels at:0]);
 assert(packet.length==TIO_WIRE);const uint8_t *b=packet.bytes;uint32_t crc=LE(b+28);
 assert(LE(b+24)==7392&&LE(b+20)==1);assert(![c sendLuminance:pixels at:1]);
 [c receiverEvent:@"UI_SUBMITTED" device:@"wrong" session:7392 frame:1 crc:crc];assert([c.state isEqual:@"submitting"]);
 [c receiverEvent:@"UI_SUBMITTED" device:@"mock-peer" session:7392 frame:1 crc:crc];assert([c.state isEqual:@"render_submitted_waiting_file_result"]);
 accepted(YES);Pump();assert([c.state isEqual:@"render_submitted_waiting_file_result"]);
 [c fileResultForDevice:@"mock-peer" task:@"wrong" success:YES];assert(![c.state isEqual:@"render_submitted"]);
 [c fileResultForDevice:@"mock-peer" task:task success:YES];assert([c.state isEqual:@"render_submitted"]);
 if(argc==2){assert([packet writeToFile:[NSString stringWithUTF8String:argv[1]] options:NSDataWritingWithoutOverwriting error:nil]);}
 assert(![c sendLuminance:pixels at:0.5]);assert([c sendLuminance:pixels at:1]);
 accepted(YES);Pump();assert([c.state isEqual:@"transferring"]);
 [c fileResultForDevice:@"mock-peer" task:task success:YES];assert([c.state isEqual:@"file_received_waiting_renderer"]);
 [c receiverEvent:@"UI_SUBMITTED" device:@"mock-peer" session:7392 frame:1 crc:crc];assert([c.state isEqual:@"file_received_waiting_renderer"]);
 [c tick:16];assert([c.state isEqual:@"timeout_result_unknown"]);assert(![c sendLuminance:pixels at:17]);
 [c receiverEvent:@"UI_SUBMITTED" device:@"mock-peer" session:7392 frame:2 crc:crc];assert([c.state isEqual:@"timeout_result_unknown"]);
 [c disconnect];assert([c.state isEqual:@"disconnected_result_unknown"]);
 assert(![c authorizeDevice:@"mock-peer" session:8642 at:20]);
 puts("PASS phone encoder, ACK ordering/correlation, single flight, rate and timeout lockout");
}return 0;}
