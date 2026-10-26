#include "ride.h"
#include <stdio.h>
#include <string.h>
#include <assert.h>
/* Golden vectors for the Android TDR1/DRA1 port, from the unchanged TVP2 didi-v1 ride.c. */
static const char *dir;
static void put(const char *name,const void *p,size_t n){char path[512];snprintf(path,sizeof path,"%s/%s",dir,name);FILE *f=fopen(path,"wb");assert(f);fwrite(p,1,n,f);fclose(f);}
static DRScene scene(void){DRScene s;memset(&s,0,sizeof s);s.phase=DR_QUOTE;s.flags=DR_SHOW|DR_CONFIRM;s.ttl=60;s.nonce=0xA1B2C3D4u;strcpy(s.metric,"32元");strcpy(s.title,"快车 · 预估");strcpy(s.line1,"起：测试上车点");strcpy(s.line2,"终：测试目的地");strcpy(s.footer,"旋钮选确认，再短按提交");return s;}
int main(int argc,char **argv){
    assert(argc==2);dir=argv[1];uint8_t p[DR_PACKET];DRCommand c;memset(&c,0,sizeof c);
    c.op=DR_SNAPSHOT;c.sid=1792990000u;c.seq=7;c.scene=scene();assert(dr_encode(p,sizeof p,&c)==DR_PACKET);put("snapshot.bin",p,DR_PACKET);
    DRCommand close={0};close.op=DR_CLOSE;close.sid=1792990000u;close.seq=8;assert(dr_encode(p,sizeof p,&close)==DR_PACKET);put("close.bin",p,DR_PACKET);
    DRCommand q={0};q.op=DR_QUERY;q.sid=1792990000u;q.seq=9;assert(dr_encode(p,sizeof p,&q)==DR_PACKET);put("query.bin",p,DR_PACKET);
    DRState st;memset(&st,0,sizeof st);DRCommand d;assert(dr_encode(p,sizeof p,&c)&&dr_decode(p,DR_PACKET,&d));assert(dr_apply(&st,&d,1000)==DR_OK);st.selected=true;assert(dr_confirm(&st,2000));
    uint8_t r[32];dr_reply(r,&st,DR_OK,DR_CONFIRMED);put("reply.bin",r,32);
    /* Scene rule table: valid? flag per case. */
    FILE *f;char path[512];snprintf(path,sizeof path,"%s/scenes.txt",dir);f=fopen(path,"wb");assert(f);
    for(unsigned k=0;k<8;k++){DRCommand x=c;switch(k){case 0:break;case 1:x.scene.ttl=14;break;case 2:x.scene.ttl=121;break;case 3:x.scene.nonce=0;break;case 4:x.scene.phase=DR_TRIP;break;case 5:x.scene.flags=4;break;case 6:x.scene.title[0]=0x01;break;case 7:x.scene.flags=DR_SHOW;x.scene.phase=DR_TRIP;x.scene.nonce=0;break;}
        fprintf(f,"%u %d\n",k,dr_encode(p,sizeof p,&x)?1:0);}
    fclose(f);return 0;
}
