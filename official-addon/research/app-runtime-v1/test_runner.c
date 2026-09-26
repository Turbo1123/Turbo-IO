#include "app_runner.h"
#include "app_command.h"
#include "app_shelf.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef struct {uint8_t file[8][TAP_STORE_BYTES];size_t n[8];bool idle,fail,write_uncertain;unsigned objects;} Fixture;
static int read_file(void *ctx,unsigned bank,uint8_t *out,size_t cap,size_t *n){Fixture *f=ctx;assert(bank<8);if(!f->n[bank])return 0;assert(cap>=f->n[bank]);memcpy(out,f->file[bank],f->n[bank]);*n=f->n[bank];return 1;}
static bool write_file(void *ctx,unsigned bank,const uint8_t *p,size_t n){Fixture *f=ctx;assert(bank<8&&n<=sizeof f->file[bank]);memcpy(f->file[bank],p,n);f->n[bank]=n;return !f->write_uncertain;}
static bool space(void *ctx,size_t n){(void)ctx;(void)n;return true;}
static bool idle(void *ctx){return ((Fixture *)ctx)->idle;}
static void *make(void *ctx,void *parent){(void)parent;Fixture *f=ctx;if(f->fail)return NULL;return (void *)(uintptr_t)(++f->objects+100);}
static void *text(void *ctx,void *p,const char *t,unsigned s){assert(t&&s);return make(ctx,p);}
static void *rect(void *ctx,void *p,uint32_t c,bool outline){(void)c;(void)outline;return make(ctx,p);}
static void *image(void *ctx,void *p,const uint8_t *data,unsigned w,unsigned h){assert(data&&w&&h&&!((uintptr_t)data%64));return make(ctx,p);}
static void place(void *ctx,void *o,unsigned x,unsigned y,unsigned w,unsigned h){(void)ctx;assert(o&&x+w<=540&&y+h<=180);}
static void visible(void *ctx,void *o,bool yes){(void)ctx;(void)yes;assert(o);}
static void destroy(void *ctx,void *o){Fixture *f=ctx;assert(f->idle&&o);f->objects=0;}
int main(int argc,char **argv){
 assert(argc==2||argc==4);FILE *in=fopen(argv[1],"rb");assert(in);uint8_t wire[TAP_MAX_BYTES];size_t n=fread(wire,1,sizeof wire,in);fclose(in);
 Fixture *f=calloc(1,sizeof(*f));TAPStore *s=calloc(1,sizeof(*s));TAPRunner *r=calloc(1,sizeof(*r));assert(f&&s&&r);f->idle=true;s->io=(TAPStoreIO){f,read_file,write_file,space};TAPWidgets w={f,idle,make,text,rect,image,place,visible,destroy};tap_runner_init(r,s,&w,NULL);
 unsigned slot;assert(tap_runner_install(r,"fixture","测试",1,wire,n,&slot)==0&&slot==0);
 for(unsigned i=0;i<1000;i++){
  assert(tap_runner_start(r,0)==0);assert(tap_runner_start(r,0)==TAP_STORE_BUSY);
  assert(tap_runner_install(r,"fixture","新版",2,wire,n,&slot)==TAP_STORE_BUSY);
  assert(tap_runner_remove(r,0)==TAP_STORE_BUSY);
  assert(tap_runner_event(r,TAP_TOUCH,10).type==TAP_NO_EVENT&&r->state.page==0);
  assert(tap_runner_event(r,TAP_PRESS,20).type==TAP_PAGE_CHANGED&&r->state.page==1);
  f->idle=false;assert(tap_runner_event(r,TAP_LONG_PRESS,30).type==TAP_EXIT&&r->closing&&r->view.root&&r->wire[0]=='T');assert(!tap_runner_poll(r));assert(tap_runner_start(r,0)==TAP_STORE_BUSY);
  f->idle=true;assert(tap_runner_poll(r)&&r->slot==-1&&!r->view.root&&!r->wire[0]&&!f->objects);
 }
 assert(tap_runner_start(r,0)==0);f->fail=true;assert(tap_runner_event(r,TAP_PRESS,40).type==TAP_EXIT);assert(r->slot==-1&&!f->objects&&!r->state.active);f->fail=false;
 assert(tap_runner_start(r,0)==0);assert(tap_runner_event(r,TAP_PRESS,50).type==TAP_PAGE_CHANGED);assert(tap_runner_event(r,TAP_PRESS,60).type==TAP_EXIT&&r->slot==-1);
 assert(tap_runner_start(r,0)==0);f->objects=0;tap_view_detached(&r->view);f->idle=false;
 assert(!tap_runner_poll(r)&&r->closing&&r->slot==0&&r->wire[0]=='T'&&!r->state.active);
 assert(tap_runner_start(r,0)==TAP_STORE_BUSY);
 f->idle=true;assert(tap_runner_poll(r)&&r->slot==-1&&!r->view.retiring);
 assert(tap_runner_start(r,0)==0);f->objects=0;tap_view_detached(&r->view);
 assert(tap_runner_event(r,TAP_PRESS,70).type==TAP_EXIT&&r->slot==-1);
 assert(tap_shelf_open(r));assert(!tap_shelf_open(r)&&r->slot==-1);assert(tap_runner_event(r,TAP_PRESS,80).type==TAP_BACKEND_EVENT);
 assert(tap_runner_close(r)&&r->slot==-1);
 if(argc==4){
  memset(f->n,0,sizeof f->n);assert(tap_store_scan(s)==TAP_STORE_OK);
  FILE *commands=fopen(argv[2],"rb"),*replies=fopen(argv[3],"wb");assert(commands&&replies);
  TAPSession session={.nonce=7392};uint8_t packet[TAP_COMMAND_MAX],reply[TAP_REPLY_BYTES];unsigned seen=0;
  for(;;){uint8_t header[4];if(fread(header,1,4,commands)!=4){assert(feof(commands));break;}unsigned length=header[0]|header[1]<<8|header[2]<<16|header[3]<<24;assert(length<=sizeof packet&&fread(packet,1,length,commands)==length);TAPCommand c;assert(tap_command_decode(packet,length,&c));
   for(unsigned k=0;k<length;k++){TAPCommand bad;assert(!tap_command_decode(packet,k,&bad));}
   for(unsigned k=0;k<length;k++){packet[k]^=1;TAPCommand bad;assert(!tap_command_decode(packet,length,&bad));packet[k]^=1;}
   if(c.op!=TAP_QUERY){TAPCommand bad=c;bad.session++;assert(tap_command_apply(r,&session,&bad,true).result==TAP_SESSION);assert(tap_command_apply(r,&session,&c,false).result==TAP_DENIED);}
   TAPOutcome outcome=tap_command_apply(r,&session,&c,true);assert(outcome.result==TAP_STORE_OK&&!outcome.duplicate);
   assert(tap_command_reply(r,&session,&c,outcome,reply,sizeof reply));assert(fwrite(reply,1,sizeof reply,replies)==sizeof reply);
   TAPOutcome duplicate=tap_command_apply(r,&session,&c,true);assert(duplicate.result==TAP_STORE_OK&&duplicate.duplicate==(c.op!=TAP_QUERY));
   if(c.op!=TAP_QUERY){TAPCommand bad=c;bad.checksum^=1;assert(tap_command_apply(r,&session,&bad,true).result==TAP_REPLAY);}
   seen++;
  }
  assert(seen==5&&r->slot==-1&&s->slots[0].tombstone);fclose(commands);fclose(replies);puts("TAX1 commands: install, launch, stop, remove, replay and consent gates passed");
  assert(tap_shelf_open(r));assert(tap_runner_event(r,TAP_PRESS,90).type==TAP_NO_EVENT);assert(tap_runner_event(r,TAP_LONG_PRESS,100).type==TAP_EXIT);
  TAPCommand changed={.op=TAP_LAUNCH,.slot=0,.version=1,.request=6,.session=7392,.checksum=6};strcpy(changed.id,"not_this_app");
  assert(tap_command_apply(r,&session,&changed,true).result==TAP_STORE_VERSION&&r->slot==-1);
  changed.op=TAP_INSTALL;changed.slot=255;changed.version=2;changed.request=7;changed.checksum=7;changed.wire=wire;changed.length=(uint16_t)n;strcpy(changed.id,s->slots[0].id);strcpy(changed.name,"Updated");
  f->write_uncertain=true;assert(tap_command_apply(r,&session,&changed,true).result==TAP_STORE_UNKNOWN&&session.needs_query);f->write_uncertain=false;
  changed.op=TAP_LAUNCH;changed.slot=0;changed.request=8;changed.checksum=8;
  assert(tap_command_apply(r,&session,&changed,true).result==TAP_QUERY_REQUIRED);
  TAPCommand query={.op=TAP_QUERY,.slot=255,.request=9};assert(tap_command_apply(r,&session,&query,false).result==TAP_STORE_OK&&!session.needs_query);
  assert(s->slots[0].version==2&&!s->slots[0].tombstone); // query reports actual state, not fabricated failure/rollback
  assert(tap_command_apply(r,&session,&changed,true).result==TAP_STORE_OK);assert(tap_runner_close(r));
 }
 free(r);free(s);free(f);puts("runner: 1000 lifecycles, one owner, touch ignored, delayed close and page allocation failure passed");return 0;
}
