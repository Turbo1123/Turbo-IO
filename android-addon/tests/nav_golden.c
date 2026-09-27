#include "nav_runtime.h"
#include <stdio.h>
#include <assert.h>
#include <string.h>
int main(int argc,char **argv){assert(argc==2);char path[1024];uint8_t b[512];TNScene s={.icon=3,.mode=1,.heading=90,.distance_m=80,.remaining_m=2048,.remaining_s=420,.position={512,800},.point_count=3,.points={{512,800},{700,200},{1023,0}}};strcpy(s.road,"模拟 · 测试道路");strcpy(s.turn,"前方右转");
 for(unsigned op=1;op<=6;op++){size_t n=tn_encode(b,sizeof b,op,123,42,&s);assert(n&&tn_packet_valid(b,n));snprintf(path,sizeof path,"%s/command-%u.bin",argv[1],op);FILE *f=fopen(path,"wb");assert(f);assert(fwrite(b,1,n,f)==n);fclose(f);}
 TNReply r={.result=TN_OK,.sid=123,.sequence=42,.active=true,.awake=true,.mode=1};assert(tn_reply_encode(b,sizeof b,r)==32);snprintf(path,sizeof path,"%s/reply.bin",argv[1]);FILE *f=fopen(path,"wb");assert(f);assert(fwrite(b,1,32,f)==32);fclose(f);return 0;}
