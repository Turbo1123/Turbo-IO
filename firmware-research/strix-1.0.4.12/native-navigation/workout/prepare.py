"""Overlay TWK1 into an isolated, already prepared cue-card candidate only."""
from pathlib import Path
import argparse, shutil
p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);a=p.parse_args()
root=a.source.resolve();here=Path(__file__).resolve().parent
out=root/'workout-runtime-v1';out.mkdir()
for name in ('workout_wire.h','workout_glyphs.h','workout_view.inc','workout_menu_service.inc'):shutil.copyfile(here/name,out/name)
def edit(name,changes):
 path=root/'navigation-runtime-v1'/name;s=path.read_text()
 for old,new in changes:
  if s.count(old)!=1:raise SystemExit(f'Pinned source boundary count {s.count(old)}: {name}: {old[:100]}')
  s=s.replace(old,new,1)
 path.write_text(s)
edit('nav_runtime.h',[
 ('#include <stdbool.h>','#include "../workout-runtime-v1/workout_wire.h"\n#include <stdbool.h>'),
 (' uint32_t distance_m,remaining_m,remaining_s;',' bool workout; TWData workout_data;\n uint32_t distance_m,remaining_m,remaining_s;'),
 ('uint8_t mode; } TNReply;','uint8_t mode;bool workout; } TNReply;')])
edit('nav_runtime.c',[
 (' if(!s||s->icon>=TN_ICON_COUNT',' if(s&&s->workout)return tw_data_valid(&s->workout_data);\n if(!s||s->icon>=TN_ICON_COUNT'),
 ('bool tn_packet_valid(const uint8_t *p,size_t n){','bool tn_packet_valid(const uint8_t *p,size_t n){\n if(p&&n>=4&&!memcmp(p,"TWK1",4))return tw_packet_valid(p,n);'),
 ('r->stale,r->scene.mode};','r->stale,r->scene.mode,r->scene.workout};'),
 ('if(!r->stale&&(uint32_t)(now-r->last_update)>=TN_IDLE_MS)', 'if(!r->stale&&(uint32_t)(now-r->last_update)>=(r->scene.workout?15000u:TN_IDLE_MS))'),
 (' if(!api(u)||!p||n<32',' bool is_workout=p&&n>=4&&!memcmp(p,"TWK1",4);\n if(is_workout&&!tw_packet_valid(p,n))return reply(r,TN_BAD_PACKET);\n if(!api(u)||!p||n<32'),
 ('||memcmp(p,"TNV1",4)||p[4]!=1||p[6]||p[7]||u32(p+24)||u32(p+28)||u32(p+16)', '||(!is_workout&&memcmp(p,"TNV1",4))||p[4]!=(is_workout?TW_WIRE_VERSION:1)||p[6]||p[7]||(!is_workout&&u32(p+24))||u32(p+28)||u32(p+16)'),
 (' if(sid==r->sid&&seq==r->sequence',' if(r->active&&is_workout!=r->scene.workout)return reply(r,TN_BUSY);\n if(sid==r->sid&&seq==r->sequence'),
 ('if(!decode_scene(&next,p+32,n-32))return reply(r,TN_BAD_PACKET);','if(is_workout){memset(&next,0,sizeof next);next.workout=true;next.mode=TN_ALWAYS;if(!tw_decode_data(&next.workout_data,p+32,n-32))return reply(r,TN_BAD_PACKET);}\n  else if(!decode_scene(&next,p+32,n-32))return reply(r,TN_BAD_PACKET);'),
 ('&&!memcmp(p,"TNV1",4)){q.sid=', '&&(!memcmp(p,"TNV1",4)||!memcmp(p,"TWK1",4))){q.workout=!memcmp(p,"TWK1",4);q.sid='),
 ('memcpy(p,"TNA1",4);','memcpy(p,r.workout?"TWA1":"TNA1",4);')])
edit('nav_view.h',[
 (' _Alignas(64) uint8_t icon[TN_ICON_W*TN_ICON_H];\n _Alignas(64) uint8_t map[TN_MAP_W*TN_MAP_H];',' union { struct { _Alignas(64) uint8_t icon[TN_ICON_W*TN_ICON_H]; _Alignas(64) uint8_t map[TN_MAP_W*TN_MAP_H]; }; _Alignas(64) uint8_t workout[32768]; };\n char workout_text[8][48];'),
 ('*text[5];','*text[20];'),('bool open,retiring;','bool open,retiring,workout;')])
edit('nav_view.c',[
 ('static int mag(int v)', '#include "../workout-runtime-v1/workout_view.inc"\nstatic int mag(int v)'),
 (' if(!tn_visual(s,false,&v->frames[0].visual))',' if(s&&s->workout)return tw_view_open(v,a,parent,s);\n if(!tn_visual(s,false,&v->frames[0].visual))'),
 ('v->retiring=false;return true;','v->retiring=false;v->workout=false;return true;'),
 (' unsigned next=v->active^1u;TNViewFrame *f=', ' if(!s||v->workout!=s->workout)return false;if(v->workout)return tw_view_update(v,s,stale);\n unsigned next=v->active^1u;TNViewFrame *f=')])
edit('nav_service.c',[
 (' bool waiting,retired,pending,sent;', ' bool waiting,retired,pending,sent,menu_open;\n uint32_t menu_nonce,menu_sequence,menu_last;'),
 ('} Control;', '} Control;\nstatic void tw_menu_close(Control *);\nstatic void tw_menu_tick(Control *,uint32_t);'),
 (' c->view->root=c->view->icon=c->view->map=NULL;', ' tw_menu_close(c);c->view->root=c->view->icon=c->view->map=NULL;'),
 ('static void leave(void *ctx){Control *c=ctx;c->waiting=false;', 'static void leave(void *ctx){Control *c=ctx;tw_menu_close(c);c->waiting=false;'),
 ('static void retire(Control *c){if(!c)return;TNUI', 'static void retire(Control *c){if(!c)return;tw_menu_close(c);TNUI'),
 (' if(c->runtime.active)tn_tick(&c->runtime,&u,now);', ' if(c->runtime.active)tn_tick(&c->runtime,&u,now);tw_menu_tick(c,now);'),
 ('static uint32_t u32(const uint8_t *p)', '#include "../workout-runtime-v1/workout_menu_service.inc"\nstatic uint32_t u32(const uint8_t *p)'),
 ('memcpy(out+sizeof head,prefix,sizeof prefix-1);','memcpy(out+sizeof head,prefix,sizeof prefix-1);\n if(reply.workout){static const char wp[]="{\\\"cmd\\\":\\\"turbo_wrk_v1\\\",\\\"payload\\\":{\\\"value\\\":0,\\\"mode\\\":0,\\\"data\\\":\\\"";memcpy(out+sizeof head,wp,sizeof wp-1);}'),
 ('&&!memcmp(p,"TNV1",4)&&p[4]==1','&&((!memcmp(p,"TNV1",4)&&p[4]==1)||(!memcmp(p,"TWK1",4)&&p[4]==TW_WIRE_VERSION))'),
 ('&&!u32(p+24)&&!u32(p+28)', '&&(!u32(p+24)||(!memcmp(p,"TWK1",4)&&p[5]==TN_START))&&!u32(p+28)'),
 (' TNUI u=api(c);c->reply=tn_receive', ' if(!memcmp(m->data,"TWK1",4)&&m->data[5]==TN_START&&u32(m->data+24)&&(!c->menu_open||!c->view||!c->view->open||!c->view->workout||u32(m->data+24)!=c->menu_nonce)){emit((TNReply){.result=TN_STALE,.sid=u32(m->data+8),.sequence=u32(m->data+12),.workout=true});return;}\n TNUI u=api(c);c->reply=tn_receive'),
 ('static const char name[]="turbo-navigation.tnv";if(!f||memcmp(f->filename,name,sizeof name))return TIO_FOREIGN;', 'static const char name[]="turbo-navigation.tnv",wn[]="turbo-workout.twk";if(!f)return TIO_FOREIGN;bool workout=!memcmp(f->filename,wn,sizeof wn);if(!workout&&memcmp(f->filename,name,sizeof name))return TIO_FOREIGN;\n if(!f->data||f->received<4||memcmp(f->data,workout?"TWK1":"TNV1",4))return TIO_BAD_SIZE;')])
print('Prepared separate TWK1 workout protocol and two-column native renderer')

# Existing font/color/alignment exports only; flags are private to the workout labels.
edit('nav_lvgl.c',[
 ('extern void nav_label_static(void *,const char *);','extern void nav_label_static(void *,const char *);\nextern void menu_text_align(void *,int,uint32_t);'),
 ('void *font=menu_font((int)size,0);','void *font=menu_font((int)(size&255u),0);'),
 ('native_text_color(o,0x00ff00,0);','native_text_color(o,(size&512u)?0x00aa00:0x00ff00,0);if(size&256u)menu_text_align(o,3,0);')])
