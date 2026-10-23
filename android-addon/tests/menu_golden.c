#include "menu_config.h"
#include <stdio.h>
#include <assert.h>
/* Wire bytes produced by the iOS/firmware TMG2 codec; the Java port must match byte for byte. */
static void put(const char *dir,const char *name,const uint8_t *p,size_t n){char path[1024];snprintf(path,sizeof path,"%s/%s",dir,name);FILE *f=fopen(path,"wb");assert(f);assert(fwrite(p,1,n,f)==n);fclose(f);}
int main(int argc,char **argv){assert(argc==2);uint8_t raw[32],wire[74];
 TMLCommand query={.op=TML_QUERY,.request=0x11223344u,.client=0x55667788u};
 tml_encode(raw,&query);assert(tml_carrier(wire,raw,false)==74);put(argv[1],"query.bin",wire,74);
 TMLCommand set={.op=TML_SET,.rows=3,.request=0x0a0b0c0du,.token=7,.generation=2,.client=0x55667788u};
 tml_encode(raw,&set);assert(tml_carrier(wire,raw,false)==74);put(argv[1],"set3.bin",wire,74);
 TMLState s={.token=9,.client=0x55667788u,.stored={.generation=5,.rows=2,.readable=true}};
 tml_reply(raw,&s,&query,TML_OK);assert(tml_carrier(wire,raw,true)==74);put(argv[1],"reply-ok.bin",wire,74);
 TMLState denied={.stored={.generation=5,.rows=3,.readable=true}};
 tml_reply(raw,&denied,&set,TML_SESSION);assert(tml_carrier(wire,raw,true)==74);put(argv[1],"reply-session.bin",wire,74);
 return 0;
}
