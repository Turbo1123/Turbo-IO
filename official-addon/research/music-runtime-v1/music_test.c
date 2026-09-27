#include "music.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
static uint8_t packet[TM_PACKET_MAX],state[TM_STATE_BYTES];
static void put(uint8_t *p,uint32_t n){for(int i=0;i<4;i++)p[i]=(uint8_t)(n>>(8*i));}
static enum TMResult send(TMMusic *m,unsigned op,unsigned flags,uint32_t sid,uint32_t gen,uint32_t seq,uint32_t off,const void *p,size_t n,uint32_t tick){TMPacket q;size_t len=tm_encode(packet,sizeof packet,op,flags,sid,gen,seq,off,p,n);assert(len&&tm_decode(packet,len,&q));return tm_receive(m,&q,tick);}
int main(void){TMMusic *m=calloc(1,sizeof *m);assert(m);put(state+4,90000);state[8]=1;state[9]=1;memcpy(state+16,"音乐校验",sizeof "音乐校验");
 assert(send(m,TM_OPEN,0,1,1,1,0,state,sizeof state,100)==TM_OK);assert(m->active&&m->awake);assert(tm_position(m,5100)==5000);
 assert(send(m,TM_OPEN,0,1,1,1,0,state,sizeof state,300)==TM_OK);assert(m->wake_tick==100);
 assert(send(m,TM_CLOCK,0,1,1,2,0,state,sizeof state,29000)==TM_OK);assert(tm_expired(m,30100));assert(!tm_expired(m,30099));assert(m->wake_tick==100);
 state[8]=0;put(state,8000);assert(send(m,TM_CLOCK,0,1,1,3,0,state,sizeof state,30000)==TM_OK);assert(tm_position(m,35000)==8000);
 assert(send(m,TM_CLOCK,0,1,1,2,0,state,sizeof state,30001)==TM_STALE);assert(send(m,TM_CLOCK,0,1,2,4,0,state,sizeof state,30001)==TM_NO_SESSION);
 uint8_t cover[TM_COVER_BYTES];memset(cover,128,sizeof cover);uint32_t seq=4;for(unsigned at=0;at<sizeof cover;){unsigned n=sizeof cover-at;if(n>TM_PACKET_MAX-32)n=TM_PACKET_MAX-32;assert(send(m,TM_COVER,at+n==sizeof cover,1,1,seq++,at,cover+at,n,31000)==TM_OK);at+=n;}assert(m->cover_ready&&!memcmp(m->cover,cover,sizeof cover));
 uint8_t lyrics[]={0,0,0,0,3,0,'o','n','e',0x88,0x13,0,0,3,0,'t','w','o'};assert(send(m,TM_LYRICS,1,1,1,seq++,0,lyrics,sizeof lyrics,32000)==TM_OK);char text[4];tm_text(m,tm_line(m,32000),text,sizeof text);assert(!strcmp(text,"two"));
 assert(send(m,TM_LYRICS,1,1,1,seq++,0,lyrics,sizeof lyrics,32001)==TM_BAD);
 state[8]=1;state[9]=0;assert(send(m,TM_OPEN,0,1,2,seq++,0,state,sizeof state,33000)==TM_OK);assert(!m->cover_ready&&!m->lyrics_ready&&m->line_count==0);assert(!tm_expired(m,62000));assert(tm_expired(m,64000));
 assert(send(m,TM_COVER,0,1,1,seq++,0,cover,100,33001)==TM_STALE);
 assert(send(m,TM_CLOSE,0,1,2,seq++,0,NULL,0,33002)==TM_OK);assert(!m->active);assert(send(m,TM_CLOCK,0,1,2,seq++,0,state,sizeof state,33003)==TM_NO_SESSION);
 size_t n=tm_encode(packet,sizeof packet,TM_OPEN,0,2,1,seq++,0,state,sizeof state);assert(n);TMPacket q;for(size_t i=0;i<n;i++){packet[i]^=1;assert(!tm_decode(packet,n,&q));packet[i]^=1;}
 assert(!tm_decode(packet,31,&q)&&!tm_decode(packet,TM_PACKET_MAX+1,&q));state[16]=0xc0;assert(!tm_encode(packet,sizeof packet,TM_OPEN,0,2,1,seq,0,state,sizeof state));state[16]='T';
 uint8_t *out=malloc(TM_COVER_BYTES+16);assert(out);memset(out+TM_COVER_BYTES,0xAA,16);for(unsigned i=0;i<10000;i++)tm_rotate(cover,out,i);for(unsigned i=0;i<16;i++)assert(out[TM_COVER_BYTES+i]==0xAA);assert(out[0]==0&&out[72*144+72]==0);
 free(out);free(m);printf("PASS music core: CRC, bounds, replay, generation, UTF8, lyrics, timer, pause, 10000 rotations; state=%zu bytes\n",sizeof(TMMusic));return 0;}
