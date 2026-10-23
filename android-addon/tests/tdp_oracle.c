#include "display_runtime.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
/* The unchanged TVP2 display runtime as a stdin/stdout oracle for the Java session test.
 * In: [now_ms u32][len u32][len bytes]. Out: 40-byte TDR1 reply (zeros for len 0), CRC-32 of the shown pixels, revision. */
static bool idle(void *c){(void)c;return true;}
static bool submit(void *c,const uint8_t *p,unsigned w,unsigned h){(void)c;(void)p;(void)w;(void)h;return true;}
static uint32_t rd(void){uint8_t b[4];if(fread(b,1,4,stdin)!=4)exit(0);return b[0]|((uint32_t)b[1]<<8)|((uint32_t)b[2]<<16)|((uint32_t)b[3]<<24);}
static void wr(uint32_t v){uint8_t b[4]={(uint8_t)v,(uint8_t)(v>>8),(uint8_t)(v>>16),(uint8_t)(v>>24)};fwrite(b,1,4,stdout);}
int main(int argc,char **argv){
 static TDPRuntime r;static uint8_t p[TDP_MAX_PACKET];TDPUI ui={NULL,idle,submit};
 if(argc!=2||!tdp_open(&r,(uint32_t)strtoul(argv[1],NULL,10),1000))return 2;
 for(;;){uint32_t now=rd(),n=rd();uint8_t out[TDP_REPLY_BYTES]={0};
  if(n>sizeof p)return 3;if(n&&fread(p,1,n,stdin)!=n)return 0;
  if(n){TDPReply q=tdp_handle(&r,&ui,p,n,now);if(!tdp_reply_encode(&q,out,sizeof out))return 4;}
  fwrite(out,1,sizeof out,stdout);wr(tdp_crc(r.pixels[r.active],TDP_PIXELS));wr(r.revision);fflush(stdout);}
}
