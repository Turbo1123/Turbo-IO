#include "ui_scene.h"
#include "image_test.h"
#include <string.h>
static uint16_t u16(const uint8_t *p){return p[0]|((uint16_t)p[1]<<8);}
static uint32_t u32(const uint8_t *p){return p[0]|((uint32_t)p[1]<<8)|((uint32_t)p[2]<<16)|((uint32_t)p[3]<<24);}
static bool utf8(const uint8_t *p,unsigned n){
 for(unsigned i=0;i<n;){
  uint32_t cp=p[i++];unsigned extra;uint32_t min;
  if(cp<128){if(cp<32&&cp!=10)return false;if(cp==127)return false;continue;}
  if(cp>=0xc2&&cp<=0xdf){extra=1;min=0x80;cp&=31;}
  else if(cp>=0xe0&&cp<=0xef){extra=2;min=0x800;cp&=15;}
  else if(cp>=0xf0&&cp<=0xf4){extra=3;min=0x10000;cp&=7;}
  else return false;
  if(extra>n-i)return false;
  while(extra--){uint8_t b=p[i++];if((b&0xc0)!=0x80)return false;cp=(cp<<6)|(b&63);}
  if(cp<min||cp>0x10ffff||(cp>=0xd800&&cp<=0xdfff)||(cp>=0x80&&cp<=0x9f))return false;
 }
 return true;
}
bool tui_init(TUIRuntime *r,uint32_t session,uint16_t w,uint16_t h){
 if(!r||!session||!w||!h||w>1024||h>1024)return false;
 memset(r,0,sizeof *r);r->session=session;r->width=w;r->height=h;r->enabled=true;return true;
}
static bool node(TUINode *n,const uint8_t *p,const TUIRuntime *r){
 memset(n,0,sizeof *n);n->id=u16(p);n->kind=p[2];n->x=u16(p+4);n->y=u16(p+6);
 n->w=u16(p+8);n->h=u16(p+10);n->action=u16(p+12);n->text_len=u16(p+14);
 n->asset=u32(p+16);n->value=u32(p+20);
 if(!n->id||p[3]||n->kind<TUI_LABEL||n->kind>TUI_LINE||!n->w||!n->h||
 (uint32_t)n->x+n->w>r->width||(uint32_t)n->y+n->h>r->height||n->text_len>TUI_TEXT_BYTES||n->action>4)return false;
 if(n->action&&n->kind!=TUI_ARROW)return false;
 for(unsigned i=n->text_len;i<TUI_TEXT_BYTES;i++)if(p[24+i])return false;
 if(n->kind==TUI_LABEL){if(!n->text_len||n->asset||n->value<8||n->value>48||!utf8(p+24,n->text_len))return false;}
 else {
  if(n->text_len)return false;
  if(n->kind==TUI_IMAGE){if(!n->asset||n->value)return false;}
  else if(n->asset||n->value>(n->kind==TUI_ARROW?3u:255u))return false;
 }
 memcpy(n->text,p+24,n->text_len);return true;
}
TUIResult tui_apply(TUIRuntime *r,const TUISceneUI *ui,const uint8_t *p,size_t len){
 if(!r||!r->enabled||!ui||!ui->asset_ready||!ui->quiescent||!ui->commit||!p||len<32||len>1056)return TUI_BAD_PACKET;
 unsigned count=p[5],mode=p[6];
 if(memcmp(p,"TUI1",4)||p[4]!=1||!count||count>TUI_MAX_NODES||mode>1||p[7]||len!=32+count*64u||u32(p+24)!=count*64u||tio_image_crc32(p+32,len-32)!=u32(p+28))return TUI_BAD_PACKET;
 uint32_t session=u32(p+8),scene=u32(p+12),base=u32(p+16),rev=u32(p+20);
 if(session!=r->session||!scene||base!=r->active.revision||base==UINT32_MAX||rev!=base+1||
 (mode&&scene!=r->active.scene))return TUI_STALE;
 if(mode)r->staging=r->active;else memset(&r->staging,0,sizeof r->staging);
 r->staging.session=session;r->staging.scene=scene;r->staging.revision=rev;
 for(unsigned i=0;i<count;i++){
  const uint8_t *q=p+32+i*64;
  for(unsigned j=0;j<i;j++)if(u16(q)==u16(p+32+j*64))return TUI_BAD_NODE;
  unsigned slot=i;
  if(mode){for(slot=0;slot<r->staging.count;slot++)if(r->staging.nodes[slot].id==u16(q))break;if(slot==r->staging.count)return TUI_BAD_NODE;}
  if(!node(&r->staging.nodes[slot],q,r))return TUI_BAD_NODE;
 }
 if(!mode)r->staging.count=count;
 for(unsigned i=0;i<r->staging.count;i++)if(r->staging.nodes[i].kind==TUI_IMAGE&&!ui->asset_ready(ui->ctx,r->staging.nodes[i].asset))return TUI_MISSING_ASSET;
 if(!ui->quiescent(ui->ctx))return TUI_BUSY;
 if(!ui->commit(ui->ctx,&r->staging))return TUI_RENDER_ERROR;
 r->active=r->staging;return TUI_OK;
}
uint16_t tui_action(const TUIRuntime *r,uint32_t scene,uint32_t revision,uint16_t node_id){
 if(!r||!r->enabled||scene!=r->active.scene||revision!=r->active.revision)return 0;
 for(unsigned i=0;i<r->active.count;i++)if(r->active.nodes[i].id==node_id)return r->active.nodes[i].action;
 return 0;
}
TUIResult tui_close(TUIRuntime *r,const TUISceneUI *ui){
 if(!r||!ui||!ui->quiescent||!ui->commit)return TUI_BAD_PACKET;
 r->enabled=false;
 if(!r->active.count)return TUI_OK;
 if(!ui->quiescent(ui->ctx))return TUI_BUSY;
 memset(&r->staging,0,sizeof r->staging);
 if(!ui->commit(ui->ctx,&r->staging))return TUI_RENDER_ERROR;
 r->active=r->staging;return TUI_OK;
}
