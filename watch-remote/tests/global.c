#include "../Firmware/remote.h"
#include <assert.h>
#include <string.h>
#include <stdio.h>
int main(void){
 TGRGate g={0};TGRCommand c={.request=1,.client=99},d;uint8_t raw[32],pb[74],copy[32];
 tgr_encode(raw,&c);assert(tgr_decode(raw,32,&d)&&d.client==99);
 assert(tgr_carrier(pb,raw,false)==74&&tgr_uncarrier(pb,74,copy,false)&&!memcmp(copy,raw,32));
 assert(!tgr_uncarrier(pb,74,copy,true));
 assert(!tgr_decode(raw,31,&d));for(unsigned i=0;i<32;i++){raw[i]^=1;assert(!tgr_decode(raw,32,&d));raw[i]^=1;}
 assert(tgr_accept(&g,&c,100,7,false)==TGR_BLOCKED);
 assert(tgr_accept(&g,&c,100,7,true)==TGR_OK&&g.session==7);
 c.op=TGR_NEXT;c.session=7;c.sequence=1;c.tick=200;
 assert(tgr_accept(&g,&c,200,0,true)==TGR_OK);
 assert(tgr_accept(&g,&c,600,0,true)==TGR_EXPIRED);
 c.sequence=2;c.tick=300;assert(tgr_accept(&g,&c,300,0,true)==TGR_BUSY);
 assert(tgr_accept(&g,&c,900,0,true)==TGR_EXPIRED);
 c.sequence=3;c.tick=0;assert(tgr_accept(&g,&c,2000,0,true)==TGR_EXPIRED);
 c.sequence=4;c.tick=9999;assert(tgr_accept(&g,&c,2000,0,true)==TGR_EXPIRED);
 c.sequence=5;c.tick=2000;c.client=100;assert(tgr_accept(&g,&c,2000,0,true)==TGR_SESSION);
 c.client=99;assert(tgr_accept(&g,&c,2000,0,true)==TGR_OK);
 c.sequence=6;c.tick=18000;assert(tgr_accept(&g,&c,18000,0,true)==TGR_SESSION);
 c.op=TGR_HELLO;c.session=c.sequence=c.tick=0;assert(tgr_accept(&g,&c,18000,8,true)==TGR_OK&&g.session==8);
 assert(tgr_accept(&g,&c,18001,9,true)==TGR_OK&&g.session==8);
 c.op=TGR_CLOSE;c.session=8;c.sequence=1;c.tick=18002;assert(tgr_accept(&g,&c,18002,0,true)==TGR_OK&&!g.session);
 c.op=TGR_PRESS;assert(tgr_accept(&g,&c,18003,0,true)==TGR_SESSION);
 c.op=TGR_HELLO;c.session=c.sequence=c.tick=0;assert(tgr_accept(&g,&c,UINT32_MAX-100,9,true)==TGR_OK);
 c.op=TGR_BACK;c.session=9;c.sequence=1;c.tick=UINT32_MAX-50;assert(tgr_accept(&g,&c,30,0,true)==TGR_OK);
 assert(tgr_accept(&g,&c,31,0,false)==TGR_BLOCKED&&!g.session);
 tgr_reply(raw,&g,&c,TGR_BLOCKED,32);assert(!memcmp(raw,"TGA1",4)&&raw[5]==TGR_BLOCKED);
 tgr_carrier(pb,raw,true);assert(tgr_uncarrier(pb,74,copy,true)&&!memcmp(copy,raw,32));
 puts("PASS global protocol: fixed carrier, CRC, session, expiry, replay, rate, wraparound, close, blocked invalidation");
}
