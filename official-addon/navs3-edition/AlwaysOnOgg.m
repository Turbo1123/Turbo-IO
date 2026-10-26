#import "AlwaysOnOgg.h"
static uint32_t LE32(const uint8_t *p){return p[0]|((uint32_t)p[1]<<8)|((uint32_t)p[2]<<16)|((uint32_t)p[3]<<24);}
static uint64_t LE64(const uint8_t *p){return LE32(p)|((uint64_t)LE32(p+4)<<32);}
static uint32_t CRC(const uint8_t *p,NSUInteger n){uint32_t c=0;for(NSUInteger i=0;i<n;i++){c^=(uint32_t)((i>=22&&i<26)?0:p[i])<<24;for(int b=0;b<8;b++)c=(c<<1)^((c&0x80000000)?0x04c11db7:0);}return c;}
static int Samples(const uint8_t *p,NSUInteger n){if(!n)return 0;int t=p[0],spf=(t&128)?(48000<<((t>>3)&3))/400:((t&96)==96?((t&8)?960:480):(((t>>3)&3)==3?2880:(48000<<((t>>3)&3))/100));int frames=(t&3)==0?1:(t&3)==3?(n>1?p[1]&63:0):2;return frames>0&&spf*frames<=5760?spf*frames:0;}
static BOOL Scan(NSURL *url,BOOL write,BOOL *needsRepair){
    NSFileHandle *f=write?[NSFileHandle fileHandleForUpdatingURL:url error:nil]:[NSFileHandle fileHandleForReadingFromURL:url error:nil];if(!f)return NO;
    BOOL ok=NO,eos=NO,legacy=YES,correct=YES;uint32_t serial=0,seq=0;uint64_t total=0,count=0;NSUInteger packets=0;uint16_t skip=0;NSMutableData *packet=[NSMutableData new];
    @try{for(NSUInteger pageIndex=0;pageIndex<100000;pageIndex++){
        unsigned long long offset=f.offsetInFile;NSData *header=[f readDataOfLength:27];if(!header.length){ok=eos&&packets>2&&packet.length==0&&(legacy||correct);break;}
        if(eos||header.length!=27)break;const uint8_t *h=header.bytes;if(memcmp(h,"OggS",4)||h[4]||(h[5]&~7)||((h[5]&1)!=0)!=(packet.length>0))break;
        if(pageIndex==0){if(!(h[5]&2)||LE32(h+18)!=0)break;serial=LE32(h+14);}else if(h[5]&2)break;
        if(LE32(h+14)!=serial||LE32(h+18)!=seq++)break;
        NSUInteger n=h[26];NSData *laces=[f readDataOfLength:n];if(laces.length!=n)break;const uint8_t *ls=laces.bytes;NSUInteger size=0;for(NSUInteger i=0;i<n;i++)size+=ls[i];NSData *body=[f readDataOfLength:size];if(body.length!=size)break;
        NSMutableData *page=[header mutableCopy];[page appendData:laces];[page appendData:body];if(CRC(page.bytes,page.length)!=LE32(h+22))break;
        NSUInteger at=0,completed=0;BOOL valid=YES;
        for(NSUInteger i=0;i<n;i++){[packet appendBytes:(const uint8_t *)body.bytes+at length:ls[i]];at+=ls[i];if(packet.length>65536){valid=NO;break;}if(ls[i]==255)continue;
            const uint8_t *p=packet.bytes;NSUInteger len=packet.length;
            if(packets==0){if(len!=19||memcmp(p,"OpusHead",8)||p[8]!=1||p[18]!=0||!(p[9]==1||p[9]==2)){valid=NO;break;}skip=p[10]|(p[11]<<8);}
            else if(packets==1){if(len<8||memcmp(p,"OpusTags",8)){valid=NO;break;}}
            else{int samples=Samples(p,len);if(!samples){valid=NO;break;}total+=samples;count++;completed++;}
            packets++;[packet setLength:0];
        }
        if(!valid)break;uint64_t gp=LE64(h+6);eos=!!(h[5]&4);
        if(eos&&(!count||packet.length))break;
        if(completed){legacy=legacy&&gp==count*960+skip;correct=correct&&gp==total;
            if(write){uint8_t *out=page.mutableBytes;for(int i=0;i<8;i++)out[6+i]=(total>>(8*i))&255;uint32_t crc=CRC(out,page.length);for(int i=0;i<4;i++)out[22+i]=(crc>>(8*i))&255;[f seekToFileOffset:offset];[f writeData:page];}
        }else if(gp!=(packet.length?UINT64_MAX:0))break;
    }if(write&&ok)[f synchronizeFile];}@catch(NSException *e){ok=NO;}@finally{[f closeFile];}
    if(needsRepair)*needsRepair=ok&&legacy&&!correct;return ok;
}
BOOL TIOFinalizeAlwaysOnOgg(NSURL *copy){BOOL repair=NO;if(!Scan(copy,NO,&repair))return NO;return !repair||Scan(copy,YES,NULL);}
