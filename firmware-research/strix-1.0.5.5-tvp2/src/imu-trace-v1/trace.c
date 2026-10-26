/* Relative gyro attitude only: no position integration, magnetometer, or claim
 * of world-locked yaw. Recentring starts a fresh stationary bias calibration. */
#include "trace.h"
#include <string.h>
static float absolute(float x){return x<0?-x:x;}
static bool finite_number(float x){return x==x&&x<1e20f&&x> -1e20f;}
static float root(float x){float v=x>1?x:1;for(unsigned i=0;i<12;i++)v=.5f*(v+x/v);return v;}
static float angle(float y,float x){
 /* Bounded atan2 approximation. Projection is diagnostic, not navigation. */
 float ay=absolute(y)+1e-10f,r,a;
 if(x>=0){r=(x-ay)/(x+ay);a=.785398163f;}else{r=(x+ay)/(ay-x);a=2.35619449f;}
 a+=(.1963f*r*r-.9817f)*r;return y<0?-a:a;
}
void ti_init(TITrace *t,unsigned profile){memset(t,0,sizeof *t);t->tracing=(profile&TI_TRACE_FLAG)!=0;profile&=3;t->profile=profile<3?profile:0;t->gain=1;t->q[0]=1;t->break_line=true;}
void ti_recenter(TITrace *t){unsigned p=t->profile|(t->tracing?TI_TRACE_FLAG:0),g=t->gain;TILetter l=t->letter;ti_init(t,p);t->gain=g;t->letter=l;ti_letter_gap(&t->letter);}
void ti_gap(TITrace *t){t->previous=0;t->break_line=true;t->gaps++;ti_letter_gap(&t->letter);if(!t->calibrated){t->cal_begin=0;t->cal_samples=0;memset(t->sum,0,sizeof t->sum);}}
bool ti_sample(TITrace *t,const TISample *s,uint32_t ms){
 if(!t||!s)return false;
 bool good=s->us!=0;for(unsigned i=0;i<3;i++)good=good&&finite_number(s->gyro[i])&&absolute(s->gyro[i])<=40&&finite_number(s->accel[i])&&absolute(s->accel[i])<=200;
 if(!good){t->invalid++;ti_gap(t);return false;}
 if(t->previous&&s->us<=t->previous){t->invalid++;ti_gap(t);return false;}
 uint64_t delta=t->previous?s->us-t->previous:0;t->previous=s->us;t->samples++;t->last_ms=ms;
 if(!t->rate_begin)t->rate_begin=s->us;t->rate_samples++;
 if(s->us>t->rate_begin&&s->us-t->rate_begin>=1000000){uint64_t elapsed=s->us-t->rate_begin;t->hz=elapsed>5000000?0:(uint32_t)((float)(t->rate_samples-1)*1000000.f/(uint32_t)elapsed);t->rate_begin=s->us;t->rate_samples=1;}
 if(!t->calibrated){
  float norm=0,motion=0;for(unsigned i=0;i<3;i++){norm+=s->accel[i]*s->accel[i];motion+=s->gyro[i]*s->gyro[i];}
  /* SI acceleration m/s2, angular velocity rad/s. Reject motion during bias capture. */
  if(norm<64||norm>144||motion>.01f||(delta>100000)){
   t->cal_begin=0;t->cal_samples=0;memset(t->sum,0,sizeof t->sum);return false;
  }
  if(!t->cal_begin)t->cal_begin=s->us;t->cal_samples++;
  for(unsigned i=0;i<3;i++)t->sum[i]+=s->gyro[i];
  if(s->us-t->cal_begin<1500000||t->cal_samples<30)return false;
  for(unsigned i=0;i<3;i++)t->bias[i]=t->sum[i]/t->cal_samples;
  t->calibrated=true;t->break_line=true;delta=0;
 }
 if(delta>100000){t->gaps++;t->break_line=true;ti_letter_gap(&t->letter);delta=0;}
 if(delta){
  float d=(float)(uint32_t)delta*.0000005f,x=(s->gyro[0]-t->bias[0])*d,y=(s->gyro[1]-t->bias[1])*d,z=(s->gyro[2]-t->bias[2])*d;
  float a=t->q[0],b=t->q[1],c=t->q[2],e=t->q[3];
  t->q[0]=a-b*x-c*y-e*z;t->q[1]=b+a*x+c*z-e*y;t->q[2]=c+a*y+e*x-b*z;t->q[3]=e+a*z+b*y-c*x;
  float n=0;for(unsigned i=0;i<4;i++)n+=t->q[i]*t->q[i];n=root(n);for(unsigned i=0;i<4;i++)t->q[i]/=n;
 }
 if(t->count&&(uint32_t)(ms-t->last_point)<33)return true;
 /* Rotation-vector projection keeps all three gyro axes observable. */
 float v[3];for(unsigned i=0;i<3;i++)v[i]=2*angle(t->q[i+1],t->q[0]);
 static const unsigned pairs[3][2]={{2,0},{2,1},{1,0}};
 float scale=t->tracing?(t->gain==0?400:t->gain==2?800:600):(t->gain==0?80:t->gain==2?240:140);
 int x=TI_WIDTH/2+(int)(v[pairs[t->profile][0]]*scale),y=TI_HEIGHT/2-(int)(v[pairs[t->profile][1]]*scale);
 bool inside=x>=2&&x<TI_WIDTH-2&&y>=2&&y<TI_HEIGHT-2;
 if(x<2)x=2;if(x>TI_WIDTH-3)x=TI_WIDTH-3;if(y<2)y=2;if(y>TI_HEIGHT-3)y=TI_HEIGHT-3;
 TIPoint p={(int16_t)x,(int16_t)y,ms,!t->break_line&&inside};t->points[t->head]=p;t->head=(t->head+1)%TI_POINTS;if(t->count<TI_POINTS)t->count++;
 if(t->tracing){if(!inside||t->break_line)ti_letter_gap(&t->letter);ti_letter_feed(&t->letter,x,y,ms);}
 t->last_point=ms;t->break_line=!inside;return true;
}
static void pixel(uint8_t *b,unsigned stride,int x,int y,uint8_t c){if(x>=0&&x<TI_WIDTH&&y>=0&&y<TI_HEIGHT)b[y*stride+x]=c;}
static void line(uint8_t *b,unsigned stride,int x,int y,int a,int z,uint8_t c){
 int dx=a>x?a-x:x-a,sx=x<a?1:-1,dy=z>y?y-z:z-y,sy=y<z?1:-1,err=dx+dy;
 for(unsigned n=0;n<TI_WIDTH+TI_HEIGHT;n++){pixel(b,stride,x,y,c);if(x==a&&y==z)break;int twice=2*err;if(twice>=dy){err+=dy;x+=sx;}if(twice<=dx){err+=dx;y+=sy;}}
}
void ti_draw(const TITrace *t,uint8_t *b,unsigned stride,uint32_t now){
 if(!t||!b||stride<TI_WIDTH||stride>TI_WIDTH+4)return;memset(b,0,stride*TI_HEIGHT);
 if(t->tracing){
  for(unsigned s=0;s<TI_STROKES;s++){
   unsigned n=ti_letter_steps(s);TIGlyphPoint a=ti_letter_point(s,0);
   for(unsigned j=1;j<=n;j++){TIGlyphPoint z=ti_letter_point(s,j);uint8_t c=s<t->letter.stroke?210:s==t->letter.stroke?(j<=t->letter.step?230:110):36;
    for(int dy=-1;dy<=1;dy++)for(int dx=-1;dx<=1;dx++)line(b,stride,a.x+dx,a.y+dy,z.x+dx,z.y+dy,c);a=z;
   }
   for(int dy=0;dy<4;dy++)line(b,stride,338,22+(int)s*10+dy,346,22+(int)s*10+dy,s<t->letter.stroke?210:30);
  }
  if(t->letter.stroke<TI_STROKES){TIGlyphPoint p=ti_letter_point(t->letter.stroke,t->letter.phase==TI_INK?t->letter.step+1:0);
   for(int y=-4;y<=4;y++)for(int x=-4;x<=4;x++)if(x*x+y*y>=10&&x*x+y*y<=20)pixel(b,stride,p.x+x,p.y+y,250);
  }
 }else{
 for(int x=0;x<TI_WIDTH;x+=40)line(b,stride,x,0,x,TI_HEIGHT-1,20);
 for(int y=0;y<TI_HEIGHT;y+=40)line(b,stride,0,y,TI_WIDTH-1,y,20);
 line(b,stride,TI_WIDTH/2-7,TI_HEIGHT/2,TI_WIDTH/2+7,TI_HEIGHT/2,100);line(b,stride,TI_WIDTH/2,TI_HEIGHT/2-7,TI_WIDTH/2,TI_HEIGHT/2+7,100);
 }
 const TIPoint *prev=NULL;
 for(unsigned k=0;k<t->count;k++){const TIPoint *p=&t->points[(t->head+TI_POINTS-t->count+k)%TI_POINTS];uint32_t age=now-p->ms;
  uint32_t life=t->tracing?500:3000;if(age>life){prev=NULL;continue;}if(prev&&p->join)line(b,stride,prev->x,prev->y,p->x,p->y,(uint8_t)(50+(life-age)*100/life));prev=p;
 }
 if(prev&&(uint32_t)(now-t->last_ms)<500)for(int y=-3;y<=3;y++)for(int x=-3;x<=3;x++)if(x*x+y*y<=9)pixel(b,stride,prev->x+x,prev->y+y,255);
}
