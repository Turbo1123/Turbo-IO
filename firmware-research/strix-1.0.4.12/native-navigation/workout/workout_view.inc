#include "../workout-runtime-v1/workout_glyphs.h"
#include <stdarg.h>
static void tw_format(char *out,size_t cap,const char *fmt,...){
 va_list ap;va_start(ap,fmt);size_t pos=0;
 while(*fmt&&pos+1<cap){if(*fmt!='%'){out[pos++]=*fmt++;continue;}fmt++;unsigned width=0;if(fmt[0]=='0'&&fmt[1]=='2'){width=2;fmt+=2;}
  if(*fmt=='s'){const char *s=va_arg(ap,const char *);while(*s&&pos+1<cap)out[pos++]=*s++;}
  else if(*fmt=='u'){unsigned value=va_arg(ap,unsigned);char digits[12];unsigned n=0;do{digits[n++]=(char)('0'+value%10);value/=10;}while(value);while(n<width)digits[n++]='0';while(n&&pos+1<cap)out[pos++]=digits[--n];}
  if(*fmt)fmt++;
 }out[pos]=0;va_end(ap);
}
/* The 84-pixel glyphs reuse the existing 32 KiB frame buffer. No per-frame
 * widgets or allocations. Labels/values/units have independent fixed bounds. */
static void tw_pixel(uint8_t *p,int x,int y,uint8_t gray){if(x>=0&&x<224&&y>=0&&y<144)p[y*224+x]=gray;}
static void tw_box(uint8_t *p,int x,int y,int w,int h,uint8_t gray){for(int j=0;j<h;j++)for(int i=0;i<w;i++)tw_pixel(p,x+i,y+j,gray);}
static void tw_digit(uint8_t *p,unsigned digit,int x,int y,uint8_t gray){for(int j=0;j<106;j++)for(int i=0;i<54;i++){unsigned bit=j*54+i;if(tw_glyphs[digit][bit/8]&(1u<<(7-bit%8)))tw_pixel(p,x+i,y+j,gray);}}
static void tw_visual_frame(TNViewFrame *f,const TWData *data,bool stale){
 TWData d=*data;uint8_t *p=f->workout;memset(p,0,sizeof f->workout);memset(f->workout_text,0,sizeof f->workout_text);
 if(stale){d.heart=d.pace=d.cadence=d.stride_cm=TW_MISSING16;d.distance_cm=d.energy_tenth_kcal=TW_MISSING32;d.zone=d.zone_count=0;}
 for(int y=0;y<30;y++)for(int x=0;x<32;x++){
  int dx=x<16?x-9:x-23,dy=y-9;
  if((y<=12&&dx*dx+dy*dy<=64)||(y>=9&&y<29&&x>=y-9&&x<=41-y))tw_pixel(p,17+x,34+y,255);
 }
 if(d.heart==TW_MISSING16)tw_digit(p,10,104,0,255);
 else{unsigned n=d.heart,count=n>=100?3:2;int x=count==3?62:96;for(unsigned i=0;i<count;i++){unsigned div=count-i==3?100:count-i==2?10:1;tw_digit(p,(n/div)%10,x+(int)i*53,0,255);}}
 unsigned count=d.zone_count;
 if(count){unsigned w=(195-(count-1)*5)/count;for(unsigned i=0;i<count;i++){bool selected=d.zone==i+1;tw_box(p,19+i*(w+5),selected?119:125,w,selected?11:5,selected?255:51);}}
 tw_box(p,222,8,1,136,51);
 char (*t)[48]=f->workout_text;
 if(d.pace==TW_MISSING16)tw_format(t[0],48,"—");else tw_format(t[0],48,"%u′%02u″",d.pace/60,d.pace%60);
 if(d.cadence==TW_MISSING16)tw_format(t[1],48,"—");else tw_format(t[1],48,"%u",d.cadence);
 if(d.stride_cm==TW_MISSING16)tw_format(t[2],48,"—");else tw_format(t[2],48,"%u.%02u",d.stride_cm/100,d.stride_cm%100);
 if(d.distance_cm==TW_MISSING32)tw_format(t[3],48,"—");else tw_format(t[3],48,"%u.%02u",d.distance_cm/100000,(d.distance_cm/1000)%100);
 if(d.energy_tenth_kcal==TW_MISSING32)tw_format(t[4],48,"—");else tw_format(t[4],48,"%u",(d.energy_tenth_kcal+5)/10);
 if(stale)tw_format(t[5],48,"—");else if(d.elapsed_s>=3600)tw_format(t[5],48,"%u:%02u:%02u",d.elapsed_s/3600,(d.elapsed_s/60)%60,d.elapsed_s%60);else tw_format(t[5],48,"%02u:%02u",d.elapsed_s/60,d.elapsed_s%60);
 if(d.zone)tw_format(t[6],48,"Z%u / %u",d.zone,count);else tw_format(t[6],48,"%s",stale?"连接中":d.paused?"已暂停":"等待心率");
 tw_format(t[7],48,"%s",d.zone?d.zone_range:stale?"等待新数据":"");
 tw_format(f->visual.status,sizeof f->visual.status,"%s",d.paused?"已暂停":"用时");
}
/* size flags: 0x100 right alignment; 0x200 dim native green. */
typedef struct {int x,y,w,h;unsigned style;} TWLabel;
static const TWLabel tw_labels[20]={
 {136,99,78,20,14|0x300},{19,139,195,23,18},{19,161,195,19,14|0x300},
 {249,13,56,24,16|0x200},{310,1,169,39,32|0x100},{485,15,49,22,14|0x200},
 {249,51,36,24,16|0x200},{284,47,48,29,20|0x100},{335,54,43,21,14|0x200},
 {394,51,36,24,16|0x200},{430,47,72,29,20|0x100},{510,53,23,21,14|0x200},
 {249,84,70,24,16|0x200},{327,80,152,30,20|0x100},{488,86,46,23,14|0x200},
 {249,117,85,24,16|0x200},{342,113,133,30,20|0x100},{482,119,52,23,14|0x200},
 {249,150,75,24,16|0x200},{328,146,206,31,20|0x100}
};
static void tw_publish(TNView *v,TNViewFrame *f){
 TNWidgets *a=&v->api;a->buffer(a->ctx,v->icon,f->workout,224,144);char (*t)[48]=f->workout_text;
 const char *s[]={"次 / 分",t[6],t[7],"配速",t[0],"/km","步频",t[1],"/min","步幅",t[2],"m","距离",t[3],"km","活动热量",t[4],"kcal",f->visual.status,t[5]};
 for(unsigned i=0;i<20;i++)a->text_static(a->ctx,v->text[i],s[i]);
}
static bool tw_view_open(TNView *v,const TNWidgets *a,void *parent,const TNScene *s){
 if(!s||!tw_data_valid(&s->workout_data))return false;
 v->api=*a;v->active=0;v->workout=true;v->root=a->root(a->ctx,parent);if(!v->root){v->workout=false;return false;}
 a->visible(a->ctx,v->root,false);a->place(a->ctx,v->root,0,0,540,180);
 v->icon=a->canvas(a->ctx,v->root);if(!v->icon)goto fail;a->place(a->ctx,v->icon,0,0,224,144);
 for(unsigned i=0;i<20;i++){const TWLabel *l=&tw_labels[i];v->text[i]=a->label(a->ctx,v->root,l->style);if(!v->text[i])goto fail;a->place(a->ctx,v->text[i],l->x,l->y,l->w,l->h);}
 tw_visual_frame(&v->frames[0],&s->workout_data,false);tw_publish(v,&v->frames[0]);v->open=true;a->visible(a->ctx,v->root,true);return true;
 fail:a->destroy(a->ctx,v->root);v->root=v->icon=NULL;memset(v->text,0,sizeof v->text);v->workout=false;return false;
}
static bool tw_view_update(TNView *v,const TNScene *s,bool stale){if(!s||!tw_data_valid(&s->workout_data))return false;unsigned next=v->active^1u;tw_visual_frame(&v->frames[next],&s->workout_data,stale);tw_publish(v,&v->frames[next]);v->active=next;return true;}
