#include "command.h"
#include <stdio.h>
#include <string.h>
#include <assert.h>
/* TDQ1 commands and TDG1 samples from the iOS/firmware diagnostics codec. */
static void put(const char *dir,const char *name,const uint8_t *p,size_t n){char path[1024];snprintf(path,sizeof path,"%s/%s",dir,name);FILE *f=fopen(path,"wb");assert(f);assert(fwrite(p,1,n,f)==n);fclose(f);}
int main(int argc,char **argv){assert(argc==2);uint8_t c[TDQ_BYTES],s[TD_WIRE_BYTES];
 assert(td_command_encode((TDCommand){TDQ_START,0x12345678u,1,600000},c,sizeof c));put(argv[1],"start.bin",c,sizeof c);
 assert(td_command_encode((TDCommand){TDQ_STOP,0x12345678u,2,0},c,sizeof c));put(argv[1],"stop.bin",c,sizeof c);
 TDSample v;memset(&v,0,sizeof v);v.session=0x12345678u;v.sequence=5;v.tick_ms=123456;v.probe_ms=3;v.valid=0x7FFFFu;v.build=0x01000001u;
 for(unsigned i=0;i<TD_METRICS;i++)v.values[i]=i<TD_RESERVED?i*1000+7:0;v.event_count=3;v.events_lost=1;v.flags=0;
 assert(td_encode(&v,s,sizeof s));put(argv[1],"sample.bin",s,sizeof s);
 v.valid=0x5;v.sequence=6;v.flags=1;assert(td_encode(&v,s,sizeof s));put(argv[1],"sample-partial.bin",s,sizeof s);
 return 0;}
