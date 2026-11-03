#include "nav_map.h"
#include "nav_runtime.h"
#include <string.h>
static unsigned nm_u16(const uint8_t *p){return p[0]|(unsigned)p[1]<<8;}
static uint32_t nm_u32(const uint8_t *p){return p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static void nm_p32(uint8_t *p,uint32_t v){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(v>>(8*i));}
static int ab(int v){return v<0?-v:v;}
static bool point_ok(const uint8_t *p){return ab((int16_t)nm_u16(p))<=8192&&ab((int16_t)nm_u16(p+2))<=8192;}
/* Strict UTF-8, BMP printable names only; no control/bidi/surrogate text.
 * Width is conservative at the stock 16 px font. No allocation or shaping. */
static unsigned text_width(const uint8_t *p,unsigned n){
 unsigned w=0;
 for(unsigned i=0;i<n;){unsigned a=p[i++],c=a;
  if(a<0x80){if(a<32||a==127)return 0;w+=9;continue;}
  unsigned more=a>=0xc2&&a<=0xdf?1:a>=0xe0&&a<=0xef?2:0;if(!more||i+more>n)return 0;c=a&((1u<<(6-more))-1);
  for(unsigned k=0;k<more;k++){unsigned b=p[i++];if((b&0xc0)!=0x80)return 0;c=(c<<6)|(b&63);}
  if(c<(more==1?0x80u:0x800u)||(c>=0xd800&&c<=0xdfff)||(c>=0x7f&&c<=0x9f)||(c>=0x200b&&c<=0x202e)||(c>=0x2060&&c<=0x206f)||c>=0xfff0)return 0;w+=16;
 }return w<=104?w:0;
}
bool tnr_body_valid(unsigned op,const uint8_t *p,size_t n){
 if(op==TNR_CLEAR)return n==0;
 if(!p)return false;
 if(op==TNR_POSE)return n==12&&nm_u32(p)&&point_ok(p+4)&&nm_u16(p+8)<360&&nm_u16(p+10)<=4000;
 if((op!=TNR_SCENE&&op!=TNR_SCENE2)||n<16||n>TNR_MAX_BYTES-32||!nm_u32(p)||nm_u16(p+4)<180||nm_u16(p+4)>700||nm_u32(p+12))return false;
 unsigned paths=nm_u16(p+6),points=nm_u16(p+8),labels=nm_u16(p+10),sum=0;
 if(!paths||paths>TNR_MAX_PATHS||points>TNR_MAX_POINTS||labels>TNR_MAX_LABELS||(op==TNR_SCENE&&labels)||n!=16+8*paths+4*points+(op==TNR_SCENE2?40*labels+12:0))return false;
 for(unsigned i=0;i<paths;i++){const uint8_t *q=p+16+8*i;unsigned count=nm_u16(q);if(count<2||count>points-sum||q[2]>6||(q[3]&~3)||((int8_t)q[4])< -8||((int8_t)q[4])>8||q[5]||nm_u16(q+6))return false;sum+=count;}
 if(sum!=points)return false;for(unsigned i=0;i<points;i++)if(!point_ok(p+16+8*paths+4*i))return false;
 if(op==TNR_SCENE2){
  for(unsigned i=0;i<labels;i++){const uint8_t *q=p+16+8*paths+4*points+40*i;unsigned len=q[4];if(!point_ok(q)||!len||len>=TNR_LABEL_BYTES||q[5]||nm_u16(q+6)||!text_width(q+8,len))return false;for(unsigned j=len;j<TNR_LABEL_BYTES;j++)if(q[8+j])return false;}
  if(!tnr_body_valid(TNR_POSE,p+n-12,12)||nm_u32(p+n-12)!=nm_u32(p))return false;
 }return true;
}
static int angle(int a,int b){int d=(b-a+540)%360-180;return d;}
bool tnr_stale(const TNRState *s,uint32_t now){if(!s||!s->located)return true;uint32_t elapsed=now-s->pose_at;return elapsed>=TNR_STALE_MS||s->target.age>=TNR_STALE_MS-elapsed;}
bool tnr_position(const TNRState *s,uint32_t now,TNRPose *p){
 if(!s||!p||!s->valid||!s->located)return false;uint32_t t=now-s->pose_at;if(t>TNR_BLEND_MS)t=TNR_BLEND_MS;*p=s->target;
 p->p.x=(int16_t)(s->from.p.x+(s->target.p.x-s->from.p.x)*(int)t/(int)TNR_BLEND_MS);p->p.y=(int16_t)(s->from.p.y+(s->target.p.y-s->from.p.y)*(int)t/(int)TNR_BLEND_MS);
 p->heading=(uint16_t)((s->from.heading+angle(s->from.heading,s->target.heading)*(int)t/(int)TNR_BLEND_MS+360)%360);return true;
}
bool tnr_receive(TNRState *s,unsigned op,const uint8_t *p,size_t n,uint32_t now){
 if(!s||!tnr_body_valid(op,p,n))return false;
 if(op==TNR_CLEAR){memset(s,0,sizeof *s);s->dirty=true;return true;}
 if(op==TNR_SCENE||op==TNR_SCENE2){
  if((s->valid&&nm_u32(p)<=s->scenes[s->bank].generation)||(s->pending&&nm_u32(p)<=s->scenes[s->bank^1u].generation))return false;
  unsigned bank=s->bank^1u;TNRScene *d=&s->scenes[bank];memset(d,0,sizeof *d);d->generation=nm_u32(p);d->range=(uint16_t)nm_u16(p+4);d->path_count=(uint16_t)nm_u16(p+6);d->point_count=(uint16_t)nm_u16(p+8);unsigned first=0;
  for(unsigned i=0;i<d->path_count;i++){const uint8_t *q=p+16+8*i;d->paths[i]=(TNRPath){(uint16_t)first,(uint16_t)nm_u16(q),q[2],q[3],(int8_t)q[4],0};first+=nm_u16(q);}
  for(unsigned i=0;i<d->point_count;i++){const uint8_t *q=p+16+8*d->path_count+4*i;d->points[i]=(TNRPoint){(int16_t)nm_u16(q),(int16_t)nm_u16(q+2)};}
  d->label_count=(uint16_t)nm_u16(p+10);
  for(unsigned i=0;i<d->label_count;i++){const uint8_t *q=p+16+8*d->path_count+4*d->point_count+40*i;d->labels[i].p=(TNRPoint){(int16_t)nm_u16(q),(int16_t)nm_u16(q+2)};memcpy(d->labels[i].text,q+8,q[4]);d->labels[i].width=(uint16_t)text_width(q+8,q[4]);}
  /* Keep the old scene visible until a matching origin-relative pose arrives. */
  s->pending=true;if(op==TNR_SCENE)return true;p+=n-12; /* op10 commits atomically */
 }
 if(s->pending){if(nm_u32(p)!=s->scenes[s->bank^1u].generation)return false;s->bank^=1u;s->valid=true;s->located=false;s->pending=false;}
 if(!s->valid||nm_u32(p)!=s->scenes[s->bank].generation)return false;
 TNRPose q={.generation=nm_u32(p),.p={(int16_t)nm_u16(p+4),(int16_t)nm_u16(p+6)},.heading=(uint16_t)nm_u16(p+8),.age=(uint16_t)nm_u16(p+10)};
 if(s->located&&!tnr_stale(s,now))tnr_position(s,now,&s->from);else s->from=q;
 /* Never interpolate long discontinuities across a junction or a relocalization. */
 if(ab(q.p.x-s->from.p.x)+ab(q.p.y-s->from.p.y)>400)s->from=q;
 s->target=q;s->pose_at=now;s->located=true;s->dirty=true;return true;
}
bool tnr_needs_draw(const TNRState *s,uint32_t now){return s&&(s->dirty||s->was_stale!=tnr_stale(s,now)||(s->valid&&s->located&&(uint32_t)(now-s->pose_at)<TNR_BLEND_MS+40&&(uint32_t)(now-s->last_draw)>=33));}
void tnr_presented(TNRState *s,uint32_t now){if(s){s->dirty=false;s->last_draw=now;s->was_stale=tnr_stale(s,now);}}
/* Q14 sine table; no libm, heap allocation or FP ABI assumptions in renderer. */
static const int16_t sin5[]={0,1428,2845,4240,5604,6924,8192,9397,10531,11585,12551,13421,14189,14849,15396,15826,16135,16322,16384};
static int sine(unsigned a){a%=360;int sign=a>=180?-1:1;a%=180;if(a>90)a=180-a;unsigned i=a/5,r=a%5;return sign*(sin5[i]+(i<18?(sin5[i+1]-sin5[i])*(int)r/5:0));}
static TNRPoint screen(TNRPoint p,const TNRPose *pose,unsigned range){int x=p.x-pose->p.x,y=p.y-pose->p.y,s=sine(pose->heading),c=sine(pose->heading+90);int dx=(x*c-y*s)/16384,dy=(x*s+y*c)/16384;return (TNRPoint){(int16_t)(96+dx*192/(int)(range*4)),(int16_t)(101-dy*192/(int)(range*4))};}
unsigned tnr_labels(const TNRState *s,uint32_t now,TNRLabelView out[TNR_MAX_LABELS]){
 memset(out,0,sizeof(TNRLabelView)*TNR_MAX_LABELS);TNRPose p;if(!tnr_position(s,now,&p)||tnr_stale(s,now))return 0;
 const TNRScene *d=&s->scenes[s->bank];unsigned count=0;
 for(unsigned i=0;i<d->label_count;i++){const TNRLabel *l=&d->labels[i];TNRPoint q=screen(l->p,&p,d->range);int w=l->width,x=q.x-w/2,y=q.y-10;
  if(x<3||x+w>189||y<3||y+20>141||(x<111&&x+w>81&&y<114&&y+20>83)||(x<70&&x+w>2&&y<143&&y+20>116))continue;
  bool overlap=false;for(unsigned j=0;j<count;j++)if(x<out[j].x+out[j].width+4&&x+w+4>out[j].x&&y<out[j].y+24&&y+24>out[j].y)overlap=true;
  if(overlap)continue;out[count].x=(int16_t)x;out[count].y=(int16_t)y;out[count].width=(uint16_t)w;memcpy(out[count++].text,l->text,TNR_LABEL_BYTES);
 }return count;
}
static unsigned code(int x,int y){return (x<0?1u:x>191?2u:0u)|(y<0?4u:y>143?8u:0u);}
static bool clip(int *x,int *y,int *xx,int *yy){for(unsigned i=0;i<10;i++){unsigned a=code(*x,*y),b=code(*xx,*yy);if(!(a|b))return true;if(a&b)return false;unsigned c=a?a:b;int nx=0,ny=0;if(c&12){ny=c&4?0:143;if(*yy==*y)return false;nx=*x+(*xx-*x)*(ny-*y)/(*yy-*y);}else{nx=c&1?0:191;if(*xx==*x)return false;ny=*y+(*yy-*y)*(nx-*x)/(*xx-*x);}if(c==a){*x=nx;*y=ny;}else{*xx=nx;*yy=ny;}}return false;}
static void dot(uint8_t *out,int x,int y,unsigned gray,unsigned alpha,bool erase){if(x<0||x>=192||y<0||y>=144)return;unsigned i=(unsigned)y*192+(unsigned)x,v=gray*alpha/255;if(erase)out[i]=0;else if(v>out[i])out[i]=(uint8_t)v;}
static void line(uint8_t *out,TNRPoint a,TNRPoint b,unsigned gray,unsigned width,bool dash,bool erase,unsigned *budget){
 int x=a.x,y=a.y,xx=b.x,yy=b.y;if(!clip(&x,&y,&xx,&yy))return;int dx=xx-x,dy=yy-y,n=ab(dx)>ab(dy)?ab(dx):ab(dy);if(!n)n=1;
 if((unsigned)n+1>*budget)return;*budget-=(unsigned)n+1;
 for(int i=0;i<=n;i++){if(dash&&(i/4)%2)continue;int fx=x*256+dx*256*i/n,fy=y*256+dy*256*i/n,px=fx/256,py=fy/256;unsigned alpha=(unsigned)(ab(dx)>=ab(dy)?fy%256:fx%256);
  for(unsigned w=0;w<width;w++){dot(out,px,py+(int)w,gray,255-alpha,erase);if(ab(dx)>=ab(dy))dot(out,px,py+1+(int)w,gray,alpha,erase);else dot(out,px+1,py+(int)w,gray,alpha,erase);}
 }
}
bool tnr_scale(unsigned range,unsigned *metres,unsigned *pixels){
 if(!metres||!pixels||range<180||range>700)return false;
 static const unsigned values[]={10,20,50,100,200};unsigned m=10;
 for(unsigned i=0;i<sizeof values/sizeof values[0];i++)if(values[i]*TNR_W<=60*range)m=values[i];
 *metres=m;*pixels=(m*TNR_W+range/2)/range;return true;
}
static void scale_draw(uint8_t *out,unsigned range,unsigned gray){
 unsigned metres,pixels;if(!tnr_scale(range,&metres,&pixels))return;
 /* Small fixed digit atlas, not heap/LVGL objects; same projection as roads.
  * Reserve bottom-left 68x27 px, outside the vehicle marker and road labels. */
 static const uint8_t glyph[11][7]={
  {14,17,19,21,25,17,14},{4,12,4,4,4,4,14},{14,17,1,2,4,8,31},
  {30,1,1,14,1,1,30},{2,6,10,18,31,2,2},{31,16,16,30,1,1,30},
  {14,16,16,30,17,17,14},{31,1,2,4,8,8,8},{14,17,17,14,17,17,14},
  {14,17,17,15,1,1,14},{0,0,26,21,21,21,21}};
 for(unsigned y=117;y<143;y++)memset(out+y*TNR_W+3,0,66);
 unsigned digits[4],count=0;if(metres>=100)digits[count++]=metres/100;
 digits[count++]=(metres/10)%10;digits[count++]=metres%10;digits[count++]=10;
 for(unsigned i=0;i<count;i++)for(unsigned y=0;y<7;y++)for(unsigned x=0;x<5;x++)
  if(glyph[digits[i]][y]&(1u<<(4-x)))for(unsigned yy=0;yy<2;yy++)for(unsigned xx=0;xx<2;xx++)out[(119+y*2+yy)*TNR_W+5+i*12+x*2+xx]=(uint8_t)gray;
 for(unsigned x=5;x<=5+pixels;x++){out[137*TNR_W+x]=(uint8_t)gray;out[138*TNR_W+x]=(uint8_t)gray;}
 for(unsigned y=134;y<=140;y++){out[y*TNR_W+5]=(uint8_t)gray;out[y*TNR_W+5+pixels]=(uint8_t)gray;}
}
void tnr_draw(const TNRState *s,uint32_t now,uint8_t out[TNR_W*TNR_H]){
 memset(out,0,TNR_W*TNR_H);TNRPose p;if(!tnr_position(s,now,&p))return;const TNRScene *d=&s->scenes[s->bank];bool stale=tnr_stale(s,now);static const uint8_t gray[]={140,128,112,94,76,56,255};
 /* Phone sorts bridges/layers; highlighted route is always the final layer. */
 /* Hard raster work caps even for a syntactically valid pathological scene.
  * Keep a separate route allowance so background roads cannot starve it. */
 for(unsigned pass=0;pass<2;pass++){unsigned budget=pass?4000:8000;
  for(unsigned i=0;i<d->path_count;i++){const TNRPath *r=&d->paths[i];if((r->style==6)!=!!pass)continue;unsigned g=stale?gray[r->style]/3:gray[r->style],w=r->style==6?3:r->style<2?2:1;
   for(unsigned j=1;j<r->count;j++){TNRPoint a=screen(d->points[r->first+j-1],&p,d->range),b=screen(d->points[r->first+j],&p,d->range);if(r->flags&1||r->style==6)line(out,a,b,0,w+2,false,true,&budget);line(out,a,b,g,w,!!(r->flags&2),false,&budget);}
  }
 }
 TNRLabelView labels[TNR_MAX_LABELS];unsigned names=tnr_labels(s,now,labels);
 for(unsigned i=0;i<names;i++)for(int y=labels[i].y-1;y<labels[i].y+21;y++)memset(out+y*TNR_W+labels[i].x-1,0,labels[i].width+2);
 unsigned marker_budget=512;TNRPoint tip={96,90},left={90,107},right={102,107};line(out,tip,left,stale?85:255,2,false,false,&marker_budget);line(out,left,right,stale?85:255,2,false,false,&marker_budget);line(out,right,tip,stale?85:255,2,false,false,&marker_budget);
 scale_draw(out,d->range,stale?85:230);
 if(stale)line(out,(TNRPoint){0,142},(TNRPoint){191,142},75,1,true,false,&marker_budget);
}
size_t tnr_wrap(uint8_t *out,size_t cap,unsigned op,uint32_t sid,uint32_t seq,const uint8_t *body,size_t n){
 if(!out||!sid||!seq||cap<n+32||n+32>TNR_MAX_BYTES||!tnr_body_valid(op,body,n))return 0;memset(out,0,n+32);memcpy(out,"TNV1",4);out[4]=1;out[5]=(uint8_t)op;nm_p32(out+8,sid);nm_p32(out+12,seq);nm_p32(out+16,(uint32_t)n);if(n)memcpy(out+32,body,n);nm_p32(out+20,tn_crc(out,n+32));return n+32;
}
