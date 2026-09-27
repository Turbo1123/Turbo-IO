#include "focus.h"
#include <stdio.h>
#include <assert.h>
int main(int argc,char **argv){assert(argc==2);unsigned char b[64];char name[1024];
 for(unsigned op=1;op<=7;op++){TFCommand c={.op=op,.sid=op==1?0:123,.seq=42,.revision=op==1?0:7,.seconds=op==2?1500:0};
  assert(tf_encode(b,sizeof b,&c)==64);snprintf(name,sizeof name,"%s/command-%u.bin",argv[1],op);FILE *f=fopen(name,"wb");assert(f);assert(fwrite(b,1,64,f)==64);fclose(f);}
 TFocus state;tf_init(&state,0);TFCommand c={.op=TF_START,.sid=123,.seq=42,.revision=0,.seconds=1500};assert(tf_apply(&state,&c,0)==TF_OK);
 assert(tf_reply(b,sizeof b,&state,TF_OK,&c)==64);snprintf(name,sizeof name,"%s/reply.bin",argv[1]);FILE *f=fopen(name,"wb");assert(f);assert(fwrite(b,1,64,f)==64);fclose(f);return 0;
}
