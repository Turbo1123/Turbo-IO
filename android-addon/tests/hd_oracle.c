#include "player.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
/* Minimal emulation of TVP2 video-player-v1 native.inc over the unchanged vp_open/vp_hd (stride 544).
 * In: [now u32][len u32][bytes] (len 1 'P'/'R' pauses/resumes the player). Out: [n u32][reply n B][pixel crc][displayed]. */
static VPPlayer v;static bool page;static uint32_t csid,cseq;static int old_firmware;
static uint32_t rd(void){uint8_t b[4];if(fread(b,1,4,stdin)!=4)exit(0);return b[0]|((uint32_t)b[1]<<8)|((uint32_t)b[2]<<16)|((uint32_t)b[3]<<24);}
static void wr(uint32_t x){uint8_t b[4]={(uint8_t)x,(uint8_t)(x>>8),(uint8_t)(x>>16),(uint8_t)(x>>24)};fwrite(b,1,4,stdout);}
static void emit(const VPPacket *a){uint8_t raw[VP_HEADER];size_t n=vp_encode(raw,sizeof raw,a,true);wr((uint32_t)n);fwrite(raw,1,n,stdout);}
static void handle(const uint8_t *p,size_t n,uint32_t now){
 VPPacket q;if(!vp_decode(p,n,&q,false)){wr(0);return;}
 VPPacket a={.op=q.op,.sid=q.sid,.seq=q.seq,.result=VP_BUSY};
 if(q.op==VP_HELLO){if(!page){a.result=VP_OK;a.a=VP_W;a.b=VP_H|(q.a==VP_HD_CAP&&!old_firmware?(VP_HD_FLAG<<16):0);a.c=now;}emit(&a);return;}
 if(q.op==VP_OPEN){
  if(page&&csid==q.sid&&q.seq<=cseq){a.result=VP_STALE;emit(&a);return;}
  int32_t age=(int32_t)(now-q.a);if(age< -250||age>1500){a.result=VP_STALE;emit(&a);return;}
  if(q.b||q.c||(page&&csid!=q.sid)){emit(&a);return;}
  if(!v.open&&!vp_open(&v,q.sid,VP_STRIDE_MAX,now)){a.result=VP_RENDER;emit(&a);return;}
  page=true;csid=q.sid;cseq=q.seq;a.result=VP_OK;emit(&a);return;
 }
 if(!page||csid!=q.sid){a.result=VP_SESSION;emit(&a);return;}
 if(q.seq<=cseq){a.result=VP_STALE;emit(&a);return;}cseq=q.seq;
 if(q.op>=VP_HD_BEGIN&&q.op<=VP_HD_COMMIT){a.result=vp_hd(&v,&q,now,true);
  if(q.op==VP_HD_COMMIT){a.a=v.displayed;a.b=0;a.c=v.bytes;}else if(q.op==VP_HD_STRIP){a.a=v.hd_y;a.b=0;a.c=v.hd_bytes;}else{a.a=v.hd_frame;a.b=0;a.c=0;}}
 else if(q.op==VP_PING){v.seen=now;a.result=VP_OK;a.a=v.paused;a.b=v.displayed;a.c=v.bytes;}
 else if(q.op==VP_CLOSE){a.result=VP_OK;page=false;vp_close(&v);}
 else a.result=VP_INVALID;
 emit(&a);
}
int main(int argc,char **argv){
 static uint8_t p[VP_WIRE_MAX];old_firmware=argc>1&&!strcmp(argv[1],"old");
 for(;;){uint32_t now=rd(),n=rd();if(n>sizeof p)return 3;if(n&&fread(p,1,n,stdin)!=n)return 0;
  if(n==1&&(p[0]=='P'||p[0]=='R')){v.paused=p[0]=='P';wr(0);}else handle(p,n,now);
  wr(vp_pixels_crc(v.pixels[v.active],VP_STRIDE_MAX));wr(v.displayed);fflush(stdout);}
}
