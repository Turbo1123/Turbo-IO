#include "camera.h"
#include <stdio.h>
#include <string.h>
#include <assert.h>
/* Wire bytes, quantized planes and PackBits output from the iOS/firmware TCM1 codec. */
static void put(const char *dir,const char *name,const uint8_t *p,size_t n){char path[1024];snprintf(path,sizeof path,"%s/%s",dir,name);FILE *f=fopen(path,"wb");assert(f);assert(fwrite(p,1,n,f)==n);fclose(f);}
static void packet(const char *dir,const char *name,const TCPacket *q,bool reply){uint8_t raw[TC_RAW_MAX],wire[TC_WIRE_MAX];size_t n=tc_packet(raw,sizeof raw,q,reply);assert(n);size_t w=tc_wrap(wire,sizeof wire,raw,n,reply);assert(w);put(dir,name,wire,w);}
int main(int argc,char **argv){assert(argc==2);const char *d=argv[1];
 TCPacket hello={.op=TC_HELLO,.sid=0xa1b2c3d4u,.seq=1};packet(d,"hello.bin",&hello,false);
 TCPacket begin={.op=TC_BEGIN,.sid=0xa1b2c3d4u,.seq=7,.a=256u|(144u<<16),.b=1234u|(4u<<24),.c=0xdeadbeefu};packet(d,"begin.bin",&begin,false);
 uint8_t data[TC_DATA_MAX];for(unsigned i=0;i<TC_DATA_MAX;i++)data[i]=(uint8_t)(i*37+5);
 TCPacket chunk={.op=TC_CHUNK,.sid=0xa1b2c3d4u,.seq=7,.a=416,.data=data,.length=TC_DATA_MAX};packet(d,"chunk.bin",&chunk,false);
 TCPacket shutter={.op=TC_SHUTTER,.sid=0xa1b2c3d4u,.seq=9,.a=0,.b=123456u};packet(d,"shutter-reply.bin",&shutter,true);
 TCPacket hello_ok={.op=TC_HELLO,.sid=0xa1b2c3d4u,.seq=1,.a=256,.b=144,.c=5000};packet(d,"hello-reply.bin",&hello_ok,true);
 static uint8_t gray[TC_PIXELS],q2[TC_PIXELS/4],q4[TC_PIXELS/2];for(unsigned i=0;i<TC_PIXELS;i++)gray[i]=(uint8_t)((i%256)^(i/256));
 assert(tc_quantize(gray,TC_PIXELS,2,q2,sizeof q2));put(d,"gray.bin",gray,TC_PIXELS);put(d,"quant2.bin",q2,sizeof q2);
 assert(tc_quantize(gray,TC_PIXELS,4,q4,sizeof q4));put(d,"quant4.bin",q4,sizeof q4);
 static uint8_t mixed[1000],packed[TC_COMP_MAX];size_t k=0;
 for(unsigned i=0;i<300;i++)mixed[k++]=7;                 /* long run, split at 128 */
 for(unsigned i=0;i<200;i++)mixed[k++]=(uint8_t)(i*13);   /* literals, split at 128 */
 mixed[k++]=1;mixed[k++]=1;mixed[k++]=2;mixed[k++]=2;mixed[k++]=2;  /* short pair then run of 3 */
 while(k<1000){mixed[k]=(uint8_t)(k%3==0?9:k);k++;}
 size_t n=tc_compress(mixed,sizeof mixed,packed,sizeof packed);assert(n);put(d,"mixed.bin",mixed,sizeof mixed);put(d,"packbits.bin",packed,n);
 size_t m=tc_compress(q4,sizeof q4,packed,sizeof packed);assert(m);put(d,"quant4-packbits.bin",packed,m);
 return 0;
}
