#import "TDPhoneReply.h"
#import "diagnostics.h"
NSData *TDPhoneReply(NSDictionary *e){
 if(![e isKindOfClass:NSDictionary.class]||![e[@"eventType"]isEqual:@"messageReceived"])return nil;
 id m=e[@"message"];if(![m isKindOfClass:NSDictionary.class]||![m[@"businessId"]isEqual:@15]||![m[@"payload"]isKindOfClass:NSData.class])return nil;
 NSData *d=m[@"payload"];if(d.length<7||d.length>384)return nil;const uint8_t *p=d.bytes;
 if(memcmp(p,(uint8_t[]){8,1,16,6,26},5))return nil;
 unsigned len=p[5]&127,offset=6;if(p[5]&128){if(p[6]&128)return nil;len|=(unsigned)p[6]<<7;offset++;if(len<128)return nil;}
 if(len!=d.length-offset)return nil;
 id j=[NSJSONSerialization JSONObjectWithData:[d subdataWithRange:NSMakeRange(offset,len)] options:0 error:nil];
 if(![j isKindOfClass:NSDictionary.class]||![j[@"cmd"]isEqual:@"turbo_diagnostics_v1"]||![j[@"payload"]isKindOfClass:NSDictionary.class])return nil;
 id hex=j[@"payload"][@"data"];if(![hex isKindOfClass:NSString.class]||[hex length]!=256)return nil;
 uint8_t raw[128];for(unsigned i=0;i<128;i++){unsigned v=0;for(unsigned k=0;k<2;k++){unichar c=[hex characterAtIndex:2*i+k];unsigned n=c>='0'&&c<='9'?c-'0':c>='a'&&c<='f'?c-'a'+10:16;if(n>15)return nil;v=v*16+n;}raw[i]=v;}
 TDSample sample;if(!td_decode(raw,128,&sample))return nil;return [NSData dataWithBytes:raw length:128];
}
