/* 1.0.5.5 compatibility adapter. All entry points and timer run on launcher UI.
 * A2UI worker completion writes only atomic flags; it never calls LVGL, RNLink
 * or file operations. Stock owns its content store and all native widgets. */
#include "compat.h"
#include "../dashboard-editor-v1/editor.h"
#include "../dashboard-v1/card.h"
#include <string.h>
#include <stddef.h>
static const void *bounded_find(const void *raw,int byte,size_t n){const uint8_t *p=raw;for(size_t i=0;i<n;i++)if(p[i]==(uint8_t)byte)return p+i;return NULL;}
static int prefix(const char *a,const char *b,size_t n){for(size_t i=0;i<n;i++){if(a[i]!=b[i])return 1;if(!a[i])return 0;}return 0;}
#define memchr bounded_find
#define strncmp prefix
typedef struct J {struct J *next,*prev,*child;int type;char *value;int integer;double number;char *key;} J;
typedef struct {uint32_t v[3];} Str;
typedef struct {uint8_t kind,pad;uint16_t component;Str id,name;uint32_t revision;} Layout;
typedef struct {Layout *begin,*end,*cap;} Vector;
typedef struct {char id[64],name[64],description[128];} Descriptor;
typedef struct {void (*done)(void *,int);void (*destroy)(void *);void *ctx;} Result;
_Static_assert(sizeof(J)==40&&sizeof(Str)==12&&sizeof(Layout)==32&&sizeof(Descriptor)==256,"Pinned 32-bit ABI");
extern J *dcj_parse(const char *),*dcj_object(void),*dcj_array(void),*dcj_string(const char *),*dcj_duplicate(const J *,int),*dcj_get(const J *,const char *);
extern int dcj_add(J *,const char *,J *),dcj_append(J *,J *);extern void dcj_delete(J *),dcj_free(void *);extern char *dcj_print(J *);
extern J *tdc_stock_serialize(unsigned,int,void *);
extern bool tdc_stock_source(void *,void *);
extern void tdc_stock_message(void *,const Str *,unsigned,unsigned,unsigned,unsigned);
extern void tdc_send_raw(void *,const Str *,unsigned),tdc_notify(void *,unsigned,unsigned,unsigned);
extern int tdc_apps(Descriptor *,unsigned,unsigned *),tdc_install(const char *,const Result *),tdc_uninstall(const char *,const Result *);
extern int tdc_running(void);
extern void *stream_memalign(size_t,size_t),stream_free(void *),*stream_timer_next(void *),*stream_timer_create(void (*)(void *),uint32_t,void *);
extern uint32_t stream_tick(void);
extern void *nav_monitors(void),*nav_link(void *),*fm_system(void *);extern bool nav_bonded(void *);extern int nav_connection(unsigned);extern unsigned tgr_ota_status(void *);
extern void *tap_fs_fopen(const char *,const char *);extern size_t tap_fs_fread(void *,size_t,size_t,void *),tap_fs_fwrite(const void *,size_t,size_t,void *);
extern int tap_fs_ferror(void *),tap_fs_feof(void *),tap_fs_fflush(void *),tap_fs_fileno(void *),tap_fs_fsync(int),tap_fs_fclose(void *),*tap_fs_errno(void);
typedef struct {
 uint32_t magic;void *timer,*manager;TDCRegistry registry;
 TDCRow native[6],custom[26];unsigned nn,nc;Vector vector;Layout layout[32];
 uint32_t revision,last_probe,sequence,started;bool ready,pending,uninstall,expired,connected;
 int completion;unsigned done;char pending_id[64];
 uint8_t decoded[TCE_MAX_BYTES];TCEDocument document;
} Control;
static void tick(void *);
static Control *control(bool create);
static const char *const native_types[]={"","weather","todo","schedule","stock","mail","clock"};
static const char *const paths[]={"/mnt/nand_data/turbo_dashboard_0.cfg","/mnt/nand_data/turbo_dashboard_1.cfg"};
static bool paired(void){void *m=nav_monitors(),*l=m?nav_link(m):NULL;return l&&nav_bonded(l)&&nav_connection(0x80)!=0;}
static bool updating(void){void *m=nav_monitors(),*s=m?fm_system(m):NULL;return !s||tgr_ota_status(s)!=0;}
static const char *str(const Str *s){return s->v[0]&1?(const char *)(uintptr_t)s->v[2]:(const char *)s+1;}
static size_t strlength(const Str *s){return s->v[0]&1?s->v[1]:*(const uint8_t *)s>>1;}
/* Borrowed libc++ strings are never destroyed by stock. Source vector points
 * to stable Control storage and the stock planner makes its own owning copy. */
static Str borrowed(const char *p){size_t n=strlen(p);Str s={{0}};if(n<=10){*(uint8_t *)&s=(uint8_t)(n*2);memcpy((char *)&s+1,p,n+1);}else{s.v[0]=(uint32_t)((n+2)|1);s.v[1]=(uint32_t)n;s.v[2]=(uint32_t)(uintptr_t)p;}return s;}
static bool copy(char dest[64],const char *s){if(!s)return false;size_t n=0;while(n<64&&s[n])n++;if(n==64)return false;memset(dest,0,64);memcpy(dest,s,n);return true;}
static int file_read(void *ctx,unsigned bank,uint8_t *p,size_t cap){
 (void)ctx;if(bank>1||cap!=TDC_BANK+1)return -1;void *f=tap_fs_fopen(paths[bank],"rb");if(!f)return *tap_fs_errno()==2?0:-1;
 size_t used=0;bool ok=true;while(used<cap){size_t n=tap_fs_fread(p+used,1,cap-used,f);if(n>cap-used||tap_fs_ferror(f)){ok=false;break;}used+=n;if(tap_fs_feof(f))break;if(!n){ok=false;break;}}
 if(tap_fs_fclose(f))ok=false;return ok?(int)used:-1;
}
static bool file_write(void *ctx,unsigned bank,const uint8_t *p,size_t n){
 (void)ctx;if(bank>1||n!=TDC_BANK)return false;void *f=tap_fs_fopen(paths[bank],"wb");if(!f)return false;
 size_t used=0;bool ok=true;while(used<n){size_t k=tap_fs_fwrite(p+used,1,n-used,f);if(!k||k>n-used||tap_fs_ferror(f)){ok=false;break;}used+=k;}
 if(ok&&tap_fs_fflush(f))ok=false;if(ok){int fd=tap_fs_fileno(f);if(fd<0||tap_fs_fsync(fd))ok=false;}if(tap_fs_fclose(f))ok=false;return ok;
}
static const TDCIO io={NULL,file_read,file_write};
static bool natives(Control *c){
 if(!c->manager)return false;Vector *v=(Vector *)((uint8_t *)c->manager+0x18);
 uintptr_t lo=(uintptr_t)v->begin,hi=(uintptr_t)v->end;
 if(hi<lo||(hi-lo)%32||(hi-lo)/32>6||(!lo&&hi))return false;
 unsigned n=(unsigned)((hi-lo)/32);
 for(unsigned i=0;i<n;i++){
  Layout *r=v->begin+i;TDCRow *d=c->native+i;memset(d,0,sizeof *d);
  if(r->kind||r->component<1||r->component>6||strlength(&r->id)>63||strlength(&r->name)>63)return false;
  d->component=r->component;d->revision=r->revision;
  if(!copy(d->id,str(&r->id))||!copy(d->name,str(&r->name)))return false;
 }
 c->nn=n;return true;
}
static bool merge(Control *c){return natives(c)&&tdc_refresh(&c->registry,c->native,c->nn,c->custom,c->nc);}
static bool refresh(Control *c){
 if(!tdc_running())return false;
 Descriptor *d=stream_memalign(64,32*sizeof *d);if(!d)return false;memset(d,0,32*sizeof *d);
 unsigned count=0;int rc=tdc_apps(d,32,&count);bool ok=rc==0&&count<=32;unsigned nc=0;
 for(unsigned i=0;ok&&i<count;i++){
  if(!memchr(d[i].id,0,64)||!memchr(d[i].name,0,64)){ok=false;break;}
  if(!tdc_owned(d[i].id))continue;
  if(nc==26){ok=false;break;}nc++;
  for(unsigned j=0;j<i;j++)if(!strcmp(d[i].id,d[j].id))ok=false;
 }
 if(ok){nc=0;for(unsigned i=0;i<count;i++)if(tdc_owned(d[i].id)){
  int old=tdc_find(&c->registry,d[i].id);uint32_t revision=old>=0?c->registry.rows[old].revision:1;
  if(c->pending&&!c->uninstall&&__atomic_load_n(&c->done,__ATOMIC_ACQUIRE)&&!c->completion&&!strcmp(c->pending_id,d[i].id))revision++;
  TDCRow *r=c->custom+nc++;memset(r,0,sizeof *r);r->kind=1;r->component=1000;copy(r->id,d[i].id);copy(r->name,d[i].name);r->revision=revision;
 }
 c->nc=nc;ok=merge(c);}
 stream_free(d);if(ok)c->ready=true;return ok;
}
static Control *control(bool create){
 void *t=NULL;for(unsigned i=0;i<512;i++){t=stream_timer_next(t);if(!t)break;if(*(void (**)(void *))((uint8_t *)t+8)==tick){Control *c=*(Control **)((uint8_t *)t+12);return c&&c->magic==0x32434454&&c->timer==t?c:NULL;}if(i==511)return NULL;}
 if(!create)return NULL;Control *c=stream_memalign(64,sizeof *c);if(!c)return NULL;memset(c,0,sizeof *c);c->magic=0x32434454;
 if(!tdc_load(&c->registry,io)){stream_free(c);return NULL;}c->timer=stream_timer_create(tick,100,c);if(!c->timer){stream_free(c);return NULL;}return c;
}
bool tdc_hook_source(void *manager,void *output){
 bool result=tdc_stock_source(manager,output);if(!result||!output)return result;
 Control *c=control(!updating());if(!c)return result;c->manager=manager;
 if(!c->ready&&!updating())refresh(c);
 if(!c->ready||!merge(c)||!c->nc)return result;
 for(unsigned i=0;i<c->registry.count;i++){
  TDCRow *r=c->registry.rows+i;Layout *o=c->layout+i;memset(o,0,sizeof *o);
  o->kind=r->kind;o->component=r->component;o->id=borrowed(r->id);o->name=borrowed(r->name);o->revision=r->revision;
 }
 c->vector=(Vector){c->layout,c->layout+c->registry.count,c->layout+32};
 *(Vector **)((uint8_t *)output+4)=&c->vector;*(uint32_t *)((uint8_t *)output+8)+=c->revision;return result;
}
static bool is(const J *j,int type){return j&&(j->type&255)==type;}
static const char *value(const J *j){return is(j,16)?j->value:NULL;}
static bool eq(const char *a,const char *b){return a&&b&&!strcmp(a,b);}
static bool add(J *j,const char *key,J *v){if(!v)return false;if(dcj_add(j,key,v))return true;dcj_delete(v);return false;}
static bool text(J *j,const char *k,const char *v){return add(j,k,dcj_string(v));}
static J *rowjson(const TDCRow *r){J *j=dcj_object();if(!j)return NULL;if(text(j,"type",r->kind?"a2ui":native_types[r->component])&&text(j,"id",r->id)&&text(j,"name",r->name))return j;dcj_delete(j);return NULL;}
J *tdc_hook_serialize(unsigned version,int simple,void *native_vector){
 J *j=tdc_stock_serialize(version,simple,native_vector);if(!j||version!=1)return j;
 Control *c=control(false);if(!c||!c->manager||(!c->pending&&!refresh(c))||!c->ready||!merge(c))return j;
 J *a=dcj_array();if(!a){dcj_delete(j);return NULL;}
 for(unsigned i=0;i<c->registry.count;i++){J *r=rowjson(c->registry.rows+i);if(!r||!dcj_append(a,r)){dcj_delete(r);dcj_delete(a);dcj_delete(j);return NULL;}}
 if(!add(j,"widgets_v2",a)){dcj_delete(j);return NULL;}return j;
}
/* Reject deep/oversized JSON before stock's recursive parser allocates nodes.
 * Duplicate keys at every object level are rejected after parsing. */
static bool preflight(const char *s,size_t n){
 if(!s||!n||n>7500||s[n]||memchr(s,0,n))return false;
 unsigned depth=0,tokens=0;bool quote=false,escape=false;
 for(size_t i=0;i<n;i++){unsigned char ch=(unsigned char)s[i];if(quote){if(escape){escape=false;if(ch=='u'&&i+4<n&&!memcmp(s+i+1,"0000",4))return false;}else if(ch=='\\')escape=true;else if(ch=='"')quote=false;else if(ch<32)return false;continue;}
  if(ch=='"'){quote=true;if(++tokens>256)return false;}else if(ch=='{'||ch=='['){if(++depth>16)return false;}else if(ch=='}'||ch==']'){if(!depth)return false;depth--;}}
 return !quote&&!escape&&!depth;
}
static bool unique(J *j,unsigned depth){
 if(!j||depth>16)return false;if(!is(j,64)&&!is(j,32))return true;unsigned n=0;
 for(J *p=j->child;p;p=p->next){if(++n>128)return false;if(is(j,64)){if(!p->key)return false;for(J *q=j->child;q!=p;q=q->next)if(eq(q->key,p->key))return false;}if(!unique(p,depth+1))return false;}return true;
}
static J *parse(const char *s,size_t n){if(!preflight(s,n))return NULL;J *j=dcj_parse(s);if(j&&!unique(j,0)){dcj_delete(j);return NULL;}return j;}
static void response(Control *c,unsigned seq,bool reorder,int code){
 if(!seq||!c||!c->manager||!paired())return;
 const char *msg=reorder?(code?"{\"cmd\":\"dashboard_update\",\"payload\":{\"value\":1}}":"{\"cmd\":\"dashboard_update\",\"payload\":{\"value\":0}}"):(code?"{\"code\":1,\"msg\":\"dashboard compatibility rejected; query before retry\"}":"{\"code\":0}");
 Str s=borrowed(msg);tdc_send_raw((uint8_t *)c->manager+0x260,&s,seq);
}
static void complete(void *ctx,int code){Control *c=ctx;c->completion=code;__atomic_store_n(&c->done,1,__ATOMIC_RELEASE);}
static void changed(Control *c){c->revision++;tdc_notify(c->manager,0,0,0);}
static void tick(void *timer){
 Control *c=*(Control **)((uint8_t *)timer+12);if(!c||c->magic!=0x32434454)return;
 bool connected=paired();if(!connected)c->connected=false;
 if(updating())return;
 if(!c->ready&&c->manager&&(uint32_t)(stream_tick()-c->last_probe)>=2000){c->last_probe=stream_tick();if(refresh(c)){changed(c);}}
 if(!c->pending)return;
 if(__atomic_load_n(&c->done,__ATOMIC_ACQUIRE)){
  int code=c->completion;c->revision++;bool read=refresh(c);if(!read)code=-1;
  int found=tdc_find(&c->registry,c->pending_id);if(read&&((c->uninstall&&found>=0)||(!c->uninstall&&found<0)))code=-1;
  if(read&&!tdc_save(&c->registry,io))code=-1;
  c->pending=false;if(read)tdc_notify(c->manager,0,0,0);
  if(!c->expired&&c->connected)response(c,c->sequence,false,code);c->sequence=0;return;
 }
 if(!c->expired&&(uint32_t)(stream_tick()-c->started)>15000){c->expired=true;if(c->connected)response(c,c->sequence,false,1);c->sequence=0;}
 /* A timed-out worker retains its slot until completion; never resubmit it. */
}
static bool numeric(const J *j,int n){
 /* Only the small stock enum values 0..6 are accepted. Compare exact IEEE
  * bits, not cJSON's truncated valueint (which would accept 1.5 as 1). */
 static const uint32_t hi[]={0,0x3ff00000,0x40000000,0x40080000,0x40100000,0x40140000,0x40180000};
 uint32_t bits[2];if(!is(j,8)||n<0||n>6)return false;memcpy(bits,&j->number,8);return !bits[0]&&bits[1]==hi[n];
}
static bool reorder(Control *c,J *body){
 J *v=dcj_get(body,"widgets_v2"),*native=dcj_get(body,"widgets"),*simple=dcj_get(body,"simple_mode");
 if(!is(body,64)||!is(v,32)||!is(native,32)||!numeric(simple,*(int *)((uint8_t *)c->manager+8)))return false;
 J *p=native->child;for(unsigned i=0;i<c->nn;i++){if(!numeric(p,c->native[i].component))return false;p=p->next;}if(p)return false;
 char ids[32][64]={{0}};unsigned count=0;
 for(J *r=v->child;r;r=r->next){if(count==32||!is(r,64))return false;const char *id=value(dcj_get(r,"id"));int at=tdc_find(&c->registry,id);if(at<0)return false;const TDCRow *known=c->registry.rows+at;
  if(!eq(value(dcj_get(r,"type")),known->kind?"a2ui":native_types[known->component])||!eq(value(dcj_get(r,"name")),known->name)||!copy(ids[count++],id))return false;
 }
 if(!tdc_reorder(&c->registry,ids,count,io))return false;changed(c);return true;
}
static char *package(Control *c,J *row){
 const char *id=value(dcj_get(row,"id")),*name=value(dcj_get(row,"name")),*extra=value(dcj_get(row,"extras"));
 if(!tdc_owned(id)||!name||!name[0]||strlen(name)>63||!eq(value(dcj_get(row,"type")),"a2ui")||!extra)return NULL;
 J *e=parse(extra,strlen(extra));if(!is(e,64)||!eq(value(dcj_get(e,"widgetId")),id)||!eq(value(dcj_get(e,"name")),name)){dcj_delete(e);return NULL;}
 J *ui=dcj_get(e,"uiContent"),*create=dcj_get(ui,"createSurface"),*update=dcj_get(ui,"updateComponents"),*components=dcj_get(update,"components"),*root=components?components->child:NULL;
 bool valid=is(ui,64)&&is(create,64)&&is(update,64)&&eq(value(dcj_get(create,"surfaceId")),id)&&eq(value(dcj_get(update,"surfaceId")),id)&&eq(value(dcj_get(create,"catalogId")),"https://rayneo.com/a2ui/catalogs/glasses-base/v1/catalog.json")&&is(components,32)&&root&&!root->next&&eq(value(dcj_get(root,"id")),"root")&&eq(value(dcj_get(root,"component")),"Text");
 const char *content=root?value(dcj_get(root,"text")):NULL;
 if(valid&&content&&!strncmp(id,"turbo_ui_card_",14)&&!strncmp(content,"TCE1:",5)){
  size_t size=tce_unbase64(content+5,strlen(content+5),c->decoded,sizeof c->decoded);valid=size&&tce_decode(c->decoded,size,&c->document);
 }else if(valid&&content&&!strcmp(id,DC_SURFACE)){DCValues values;valid=dc_parse(content,strlen(content),&values);}else valid=false;
 if(!valid){dcj_delete(e);return NULL;}
 J *j=dcj_object(),*messages=dcj_array(),*a=dcj_object(),*b=dcj_object();bool ok=j&&messages&&a&&b;
 if(ok)ok=text(j,"widgetId",id)&&text(j,"name",name)&&text(a,"version","v0.9")&&text(b,"version","v0.9")&&add(a,"createSurface",dcj_duplicate(create,1))&&add(b,"updateComponents",dcj_duplicate(update,1));
 if(ok){ok=dcj_append(messages,a)!=0;if(ok)a=NULL;}if(ok){ok=dcj_append(messages,b)!=0;if(ok)b=NULL;}
 if(ok){ok=add(j,"messages",messages);messages=NULL;}
 char *out=ok?dcj_print(j):NULL;if(out&&strlen(out)>7500){dcj_free(out);out=NULL;}
 dcj_delete(a);dcj_delete(b);dcj_delete(messages);dcj_delete(j);dcj_delete(e);return out;
}
void tdc_hook_message(void *manager,const Str *raw,unsigned seq,unsigned mode,unsigned arg4,unsigned arg5){
 const char *s=raw?str(raw):NULL;size_t n=raw?strlength(raw):0;J *j=parse(s,n);
 const char *cmd=value(dcj_get(j,"cmd"));J *payload=dcj_get(j,"payload"),*data=dcj_get(payload,"data");
 /* sendConfigResponse constructs its own source and does not call the view's
  * getDashboardSource. Establish the owner on a query as well as on rendering. */
 if(eq(cmd,"dashboard_config")&&!updating()){Control *owner=control(true);if(owner)owner->manager=manager;}
 bool install=eq(cmd,"widget_install"),remove=eq(cmd,"widget_uninstall"),update=eq(cmd,"dashboard_update");
 J *body=NULL;if(update&&value(data))body=parse(value(data),strlen(value(data)));
 bool v2=body&&dcj_get(body,"widgets_v2");
 if(!install&&!remove&&!v2){dcj_delete(body);dcj_delete(j);tdc_stock_message(manager,raw,seq,mode,arg4,arg5);return;}
 Control *c=control(true);if(c)c->manager=manager;
 bool allowed=c&&seq&&mode==1&&paired()&&!updating()&&!c->pending&&c->registry.writable&&refresh(c);
 if(!allowed){if(c&&mode==1)response(c,seq,v2,1);goto end;}
 if(v2){bool ok=numeric(dcj_get(payload,"version"),1)&&numeric(dcj_get(payload,"value"),0)&&reorder(c,body);response(c,seq,true,ok?0:1);goto end;}
 const char *id=value(dcj_get(data,"id"));if(!tdc_owned(id)){response(c,seq,false,1);goto end;}
 int at=tdc_find(&c->registry,id);
 if(remove&&at<0){response(c,seq,false,1);goto end;}
 if(install&&at<0&&(c->registry.count>=32||c->nc>=26)){response(c,seq,false,1);goto end;}
 char *textdata=install?package(c,data):NULL;if(install&&!textdata){response(c,seq,false,1);goto end;}
 c->pending=true;c->uninstall=remove;c->expired=false;c->connected=true;c->sequence=seq;c->started=stream_tick();copy(c->pending_id,id);__atomic_store_n(&c->done,0,__ATOMIC_RELEASE);
 Result result={complete,NULL,c};int rc=remove?tdc_uninstall(id,&result):tdc_install(textdata,&result);dcj_free(textdata);
 if(rc){c->pending=false;c->sequence=0;response(c,seq,false,1);}
 end:dcj_delete(body);dcj_delete(j);
}
size_t tdc_control_bytes(void){return sizeof(Control);}
