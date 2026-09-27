#include "nav_visual.h"
#include <string.h>
static char *decimal(char *p,uint32_t v){char tmp[10];unsigned n=0;do{tmp[n++]=(char)('0'+v%10);v/=10;}while(v);while(n)*p++=tmp[--n];*p=0;return p;}
static char *append(char *p,const char *s){while(*s)*p++=*s++;*p=0;return p;}
static char *distance(char *p,uint32_t m){
 if(m<1000){p=decimal(p,m);return append(p," m");}
 p=decimal(p,m/1000);*p++='.';*p++=(char)('0'+m%1000/100);return append(p," km");
}
/* Caller validates 2000..2100 plus <=7 days; 32-bit arithmetic avoids adding
 * a 64-bit division runtime to the freestanding AP payload. */
static char *clock_hm(char *p,int64_t epoch){unsigned min=((uint32_t)epoch%86400)/60;
 *p++=(char)('0'+min/60/10);*p++=(char)('0'+min/60%10);*p++=':';
 *p++=(char)('0'+min%60/10);*p++=(char)('0'+min%10);*p=0;return p;
}
void tn_clock_text(char out[64],int64_t now,int64_t eta,bool stale){
 memset(out,0,64);
 if(stale){append(out,"导航数据已过期 · 请查看手机");return;}
 if(now<946684800||now>4102444800LL){append(out,"当前 --:-- · 到达时间待更新");return;}
 char *p=append(out,"当前 ");p=clock_hm(p,now);p=append(p," · ");
 if(eta<now||eta-now>604800){append(p,"到达时间待更新");return;}
 unsigned days=(uint32_t)eta/86400-(uint32_t)now/86400;
 if(days==1)p=append(p,"明日 ");else if(days){p=decimal(p,days);p=append(p,"天后 ");}
 p=append(p,"预计 ");p=clock_hm(p,eta);append(p," 到达");
}
static const TNXY straight[]={{48,84},{48,12},{20,40},{48,12},{76,40}};
static const TNXY right[]={{18,84},{18,36},{76,36},{52,12},{76,36},{52,60}};
static const TNXY slight[]={{22,84},{22,55},{72,15},{36,15},{72,15},{72,50}};
static const TNXY sharp[]={{18,84},{18,16},{74,66},{38,66},{74,66},{74,30}};
static const TNXY uturn[]={{18,84},{18,30},{30,16},{58,16},{72,30},{72,78},{52,58},{72,78},{88,58}};
static const TNXY roundabout[]={{48,84},{48,65},{24,48},{24,30},{44,15},{64,30},{64,48},{48,65},{48,15},{32,30},{48,15},{64,30}};
static const TNXY arrive[]={{22,84},{22,12},{76,12},{76,50},{22,50}};
static const TNXY unknown[]={{28,25},{38,15},{58,15},{70,26},{70,38},{48,54},{48,66},{48,75},{48,82}};
static TNXY map(TNPoint p){return (TNXY){406+(int32_t)p.x*112/1023,10+(int32_t)p.y*112/1023};}
bool tn_visual(const TNScene *s,bool stale,TNVisual *v){
 if(!s||!v||s->icon>=TN_ICON_COUNT||s->point_count>TN_POINTS_MAX||s->heading>=360||s->position.x>1023||s->position.y>1023)return false;
 memset(v,0,sizeof *v);v->stale=stale;const TNXY *icon=unknown;size_t n=sizeof unknown/sizeof *unknown;bool flip=false;
 switch(s->icon){
 #define GLYPH(name) icon=name;n=sizeof name/sizeof *name;break
 case TN_STRAIGHT:GLYPH(straight);
 case TN_LEFT:flip=true; /* fall through */
 case TN_RIGHT:GLYPH(right);
 case TN_SLIGHT_LEFT:flip=true; /* fall through */
 case TN_SLIGHT_RIGHT:GLYPH(slight);
 case TN_SHARP_LEFT:flip=true; /* fall through */
 case TN_SHARP_RIGHT:GLYPH(sharp);
 case TN_UTURN:GLYPH(uturn);
 case TN_ROUNDABOUT:GLYPH(roundabout);
 case TN_ARRIVE:GLYPH(arrive);
 default:break;
 #undef GLYPH
 }
 v->icon_count=(unsigned)n;for(unsigned i=0;i<n;i++)v->icon[i]=(TNXY){8+(flip?96-icon[i].x:icon[i].x),12+icon[i].y};
 v->route_count=s->point_count;for(unsigned i=0;i<s->point_count;i++){if(s->points[i].x>1023||s->points[i].y>1023)return false;v->route[i]=map(s->points[i]);}
 TNXY pos=map(s->position);
 /* Eight-way position arrow; no libm or per-frame heap allocation. */
 static const int8_t dirs[8][2]={{0,-1},{1,-1},{1,0},{1,1},{0,1},{-1,1},{-1,0},{-1,-1}};
 unsigned dir=((s->heading+22u)/45u)%8u;int dx=dirs[dir][0],dy=dirs[dir][1];
 v->position[0]=(TNXY){pos.x+dx*6,pos.y+dy*6};v->position[1]=(TNXY){pos.x-dx*4-dy*4,pos.y-dy*4+dx*4};
 v->position[2]=(TNXY){pos.x-dx*4+dy*4,pos.y-dy*4-dx*4};v->position[3]=v->position[0];
 char *p=v->distance;if(s->distance_m<1000){p=decimal(p,s->distance_m);append(p," m");}
 else {p=decimal(p,s->distance_m/1000);*p++='.';*p++=(char)('0'+s->distance_m%1000/100);append(p," km");}
 memcpy(v->turn,s->turn,sizeof v->turn);memcpy(v->road,s->road,sizeof v->road);v->turn[TN_TURN_MAX]=0;v->road[TN_ROAD_MAX]=0;
 p=append(v->summary,"剩余 ");p=distance(p,s->remaining_m);p=append(p," / ");
 unsigned minutes=s->remaining_s/60+(s->remaining_s%60!=0);
 if(minutes>=60){p=decimal(p,minutes/60);p=append(p,"h ");minutes%=60;}
 p=decimal(p,minutes);append(p,"min");
 append(v->status,stale?"导航数据已过期 · 请查看手机":s->mode==TN_ALWAYS?"导航 · 常亮":"导航 · 60秒无更新息屏");return true;
}
