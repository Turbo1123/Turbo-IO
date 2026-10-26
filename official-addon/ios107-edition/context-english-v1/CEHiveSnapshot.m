#import "CEHiveSnapshot.h"
#include <zlib.h>
#include <math.h>

typedef struct {const uint8_t *b; NSUInteger p,n,nodes; BOOL bad;} CEReader;
static BOOL Need(CEReader *r,NSUInteger n){if(r->bad||n>r->n-r->p){r->bad=YES;return NO;}return YES;}
static uint8_t CEByte(CEReader *r){return Need(r,1)?r->b[r->p++]:0;}
static uint32_t Word(CEReader *r){if(!Need(r,4))return 0;const uint8_t *b=r->b+r->p;r->p+=4;return (uint32_t)b[0]|(uint32_t)b[1]<<8|(uint32_t)b[2]<<16|(uint32_t)b[3]<<24;}
static NSString *String(CEReader *r,NSUInteger n){if(n>4*1024*1024||!Need(r,n)){r->bad=YES;return nil;}NSString *s=[[NSString alloc]initWithBytes:r->b+r->p length:n encoding:NSUTF8StringEncoding];r->p+=n;if(!s)r->bad=YES;return s;}
static id Value(CEReader *r,NSUInteger depth){
    if(depth>24||++r->nodes>200000){r->bad=YES;return nil;}
    unsigned type=CEByte(r);if(r->bad)return nil;
    if(type==0)return NSNull.null;
    if(type==1||type==2){if(!Need(r,8))return nil;uint64_t bits=0;for(int i=0;i<8;i++)bits|=(uint64_t)r->b[r->p++]<<(i*8);double d;memcpy(&d,&bits,8);if(!isfinite(d)){r->bad=YES;return nil;}return @(d);}
    if(type==3)return @(CEByte(r)!=0);
    if(type==4){NSUInteger n=Word(r);return String(r,n);}
    if(type==5){NSUInteger n=Word(r);if(!Need(r,n))return nil;NSData *d=[NSData dataWithBytes:r->b+r->p length:n];r->p+=n;return d;}
    if(type==10||type==11||type==9){NSUInteger count=Word(r);if(count>20000){r->bad=YES;return nil;}
        NSMutableArray *list=[NSMutableArray new];NSMutableDictionary *map=[NSMutableDictionary new];
        for(NSUInteger i=0;i<count&&!r->bad;i++){
            if(type==11){id key=Value(r,depth+1);id v=Value(r,depth+1);if((![key isKindOfClass:NSString.class]&&![key isKindOfClass:NSNumber.class])||!v){r->bad=YES;break;}map[key]=v;}
            else {id v;if(type==9){NSUInteger n=Word(r);v=String(r,n);}else v=Value(r,depth+1);if(!v){r->bad=YES;break;}[list addObject:v];}
        }
        return r->bad?nil:type==11?map:list;
    }
    r->bad=YES;return nil;
}
NSDictionary *CEReadHiveSnapshot(NSData *data,NSError **error){
    NSMutableDictionary *out=[NSMutableDictionary new];CEReader r={data.bytes,0,data.length,0,NO};NSUInteger frames=0;
    if(data.length>32*1024*1024)r.bad=YES;
    while(!r.bad&&r.p<r.n){
        NSUInteger start=r.p,length=Word(&r);if(r.bad||length<9||length>r.n-start||++frames>100000){r.bad=YES;break;}
        NSUInteger end=start+length-4;CEReader crcReader={r.b,end,r.n,0,NO};uint32_t expected=Word(&crcReader);
        if((uint32_t)crc32(0,r.b+start,(uInt)(length-4))!=expected){r.bad=YES;break;}
        CEReader body={r.b,r.p,end,0,NO};unsigned kt=CEByte(&body);id key=nil;
        if(kt==0)key=@(Word(&body));else if(kt==1){NSUInteger n=CEByte(&body);key=String(&body,n);}else body.bad=YES;
        if(!key||body.bad){r.bad=YES;break;}
        if(body.p==body.n)[out removeObjectForKey:key];
        else {id v=Value(&body,0);if(body.bad||body.p!=body.n||!v){r.bad=YES;break;}out[key]=v;}
        r.nodes+=body.nodes;if(r.nodes>200000){r.bad=YES;break;}
        r.p=start+length;
    }
    if(r.bad){if(error)*error=[NSError errorWithDomain:@"TurboEnglishHive" code:1 userInfo:@{NSLocalizedDescriptionKey:@"官方缓存正在变化、格式不兼容或校验失败；未修改原文件，请稍后重试。"}];return nil;}
    return out;
}
