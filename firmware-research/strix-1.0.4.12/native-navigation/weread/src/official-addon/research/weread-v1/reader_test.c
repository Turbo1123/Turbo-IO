#include "reader.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static WRReader r;
static uint32_t seq;
static uint8_t shelf[64+4*WR_CARD_BYTES],book[256+8*WR_LINE_BYTES];
static enum WRResult send(unsigned op,uint32_t rev,uint32_t off,const void *p,size_t n){
 uint8_t wire[WR_PACKET_MAX];WRPacket q;size_t bytes=wr_encode(wire,sizeof wire,op,7392,++seq,rev,off,p,n);assert(bytes&&wr_decode(wire,bytes,&q));return wr_receive(&r,&q,1000);
}
static void start(void){memset(&r,0,sizeof r);seq=0;assert(send(WR_OPEN,0,0,NULL,0)==WR_OK);}
static void transfer(const void *v,size_t n,unsigned rev){
 const uint8_t *p=v;uint8_t begin[8];wr_put(begin,(uint32_t)n);wr_put(begin+4,wr_crc(v,n));assert(send(WR_BEGIN,rev,0,begin,8)==WR_OK);
 for(size_t pos=0;pos<n;){size_t count=n-pos<480?n-pos:480;assert(send(WR_CHUNK,rev,(uint32_t)pos,p+pos,count)==WR_OK);pos+=count;}
 assert(send(WR_COMMIT,rev,0,NULL,0)==WR_OK);assert(r.pending);assert(!memcmp(wr_present(&r),v,n));wr_publish(&r);assert(r.valid&&!r.pending);
 for(unsigned i=0;i<WR_BANK_BYTES;i++)assert(r.bank[r.front^1u][i]==0);
}
int main(void){
 wr_put(shelf,1);wr_put(shelf+8,12);wr_put(shelf+12,4);
 for(unsigned i=0;i<4;i++){uint8_t *p=shelf+64+i*WR_CARD_BYTES;memcpy(p,"示例书",sizeof "示例书");memcpy(p+96,"作者",sizeof "作者");wr_put(p+160,i+1);memset(p+192,(int)i+1,WR_COVER_BYTES);}
 wr_put(book,2);wr_put(book+8,20);wr_put(book+12,8);wr_put(book+20,480);wr_put(book+24,1);wr_put(book+28,1);memcpy(book+64,"本地书籍",sizeof "本地书籍");memcpy(book+160,"第一章",sizeof "第一章");
 for(unsigned i=0;i<8;i++)memcpy(book+256+i*128,"一二三四",sizeof "一二三四");
 assert(wr_validate(shelf,sizeof shelf)&&wr_validate(book,sizeof book));
 start();transfer(shelf,sizeof shelf,1);wr_press(&r,1000);assert(r.event==WR_BOOK&&r.event_value==1);
 for(unsigned i=0;i<4;i++)wr_wheel(&r,1,1000);assert(r.selected==3&&r.event==WR_SHELF&&r.event_value==4);
 transfer(book,sizeof book,2);assert(r.automatic);r.last_tick=1000;wr_tick(&r,1500);assert(r.row==1); /* 4 characters at 480/min = 500 ms */
 assert(r.bank[r.front][256]==0);wr_wheel(&r,-1,1501);assert(r.event==WR_WINDOW&&r.event_value==0&&r.row==1&&!r.automatic);
 uint32_t previous=r.row;wr_tick(&r,2501);assert(r.row==previous);
 uint8_t settings[8];wr_put(settings,481);wr_put(settings+4,1);assert(send(WR_SETTINGS,0,0,settings,8)==WR_BAD);
 wr_put(settings,30);assert(send(WR_SETTINGS,0,0,settings,8)==WR_OK);
 /* Pending data cannot overwrite an old bank still held by the renderer. */
 uint8_t begin[8];wr_put(begin,sizeof shelf);wr_put(begin+4,wr_crc(shelf,sizeof shelf));assert(send(WR_BEGIN,3,0,begin,8)==WR_OK);assert(send(WR_BEGIN,4,0,begin,8)==WR_BUSY);
 assert(send(WR_CHUNK,3,1,shelf,10)==WR_BAD);assert(send(WR_CLOSE,0,0,NULL,0)==WR_OK);wr_clear(&r);for(unsigned i=0;i<sizeof r.bank;i++)assert(((uint8_t *)r.bank)[i]==0);
 assert(send(WR_OPEN,0,0,NULL,0)==WR_STALE); /* retired SID cannot reopen */
 for(unsigned i=0;i<1000;i++){start();transfer(shelf,sizeof shelf,1);transfer(book,sizeof book,2);assert(send(WR_CLOSE,0,0,NULL,0)==WR_OK);wr_clear(&r);}
 uint8_t wire[WR_PACKET_MAX];WRPacket q;size_t n=wr_encode(wire,sizeof wire,WR_QUERY,1,1,0,0,NULL,0);for(size_t i=0;i<n;i++){wire[i]^=1;assert(!wr_decode(wire,n,&q));wire[i]^=1;}
 book[256]=0xc0;book[257]=0x80;assert(!wr_validate(book,sizeof book));
 printf("PASS reader bounded two banks=%u bytes; shelf paging, selection, 480 chars/min, discard/refetch, backpressure, retired SID, CRC, UTF8, 1000 cycles\n",(unsigned)sizeof r.bank);
}
