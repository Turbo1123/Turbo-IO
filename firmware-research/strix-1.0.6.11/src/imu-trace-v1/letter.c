/* Original vector guide for simplified 粪: 米 (six strokes), 共 (six).
 * Read-only geometry; bounded state. Approximate ordered tracing, not a
 * handwriting/medical metric. No sample allocation or persistent history. */
#include "trace.h"
#include <string.h>
static const TIStroke glyph[TI_STROKES]={
 {2,{{211,12},{224,25}}}, {2,{{269,12},{256,25}}},
 {2,{{181,36},{299,36}}}, {2,{{240,8},{240,83}}},
 {3,{{237,42},{215,62},{180,79}}}, {3,{{243,42},{265,62},{300,79}}},
 {2,{{186,103},{294,103}}}, {2,{{216,91},{216,125}}},
 {2,{{264,91},{264,125}}}, {2,{{178,126},{302,126}}},
 {3,{{222,136},{210,146},{195,154}}}, {2,{{258,136},{278,154}}}
};
const TIStroke *ti_stroke(unsigned n){return n<TI_STROKES?&glyph[n]:NULL;}
static unsigned magnitude(int x){return (unsigned)(x<0?-x:x);}
/* Checkpoints <= 6 pixels apart; the caller must visit them in order. */
static unsigned segment_steps(TIGlyphPoint a,TIGlyphPoint b){unsigned x=magnitude(b.x-a.x),y=magnitude(b.y-a.y);return ((x>y?x:y)+5)/6;}
static unsigned steps(const TIStroke *s){unsigned n=0;for(unsigned i=1;i<s->count;i++)n+=segment_steps(s->p[i-1],s->p[i]);return n;}
static TIGlyphPoint checkpoint(const TIStroke *s,unsigned step){
 for(unsigned i=1;i<s->count;i++){TIGlyphPoint a=s->p[i-1],b=s->p[i];unsigned n=segment_steps(a,b);
  if(step<=n)return (TIGlyphPoint){a.x+(b.x-a.x)*(int)step/(int)n,a.y+(b.y-a.y)*(int)step/(int)n};step-=n;
 }return s->p[s->count-1];
}
static bool near(int x,int y,TIGlyphPoint p,int radius){int dx=x-p.x,dy=y-p.y;return dx*dx+dy*dy<=radius*radius;}
void ti_letter_reset(TILetter *l){memset(l,0,sizeof *l);}
void ti_letter_gap(TILetter *l){if(!l)return;l->valid=false;l->waiting=false;l->step=0;if(l->phase!=TI_FINISHED&&l->phase!=TI_REST)l->phase=TI_SEEK;}
const char *ti_letter_note(const TILetter *l){return l->phase==TI_FINISHED?"完成，放松一下":l->phase==TI_REST?"放松，准备下一笔":l->phase==TI_INK?"沿亮线慢慢描":"移向亮点，稍停";}
void ti_letter_feed(TILetter *l,int x,int y,uint32_t ms){
 if(!l||l->phase==TI_FINISHED)return;
 if(x<0||x>=TI_WIDTH||y<0||y>=TI_HEIGHT){ti_letter_gap(l);return;}
 if(l->valid){uint32_t dt=ms-l->last_ms;int dx=x-l->x,dy=y-l->y;
  if(!dt)return;
  if(dt>150||dx*dx+dy*dy>144)ti_letter_gap(l);
 }
 l->x=x;l->y=y;l->last_ms=ms;l->valid=true;
 if(l->phase==TI_REST){if((uint32_t)(ms-l->rest_at)<700)return;l->phase=TI_SEEK;l->waiting=false;}
 const TIStroke *s=ti_stroke(l->stroke);if(!s)return;
 if(l->phase==TI_SEEK){
  if(!near(x,y,s->p[0],7)){l->waiting=false;return;}
  if(!l->waiting){l->dwell=ms;l->waiting=true;return;}
  if((uint32_t)(ms-l->dwell)<300)return;
  l->phase=TI_INK;l->step=0;l->waiting=false;return;
 }
 unsigned total=steps(s);TIGlyphPoint target=checkpoint(s,l->step+1);
 /* At most two small checkpoints per valid sample. A jump never fills ink. */
 for(unsigned i=0;i<2&&l->step<total&&near(x,y,target,7);i++){
  l->step++;target=checkpoint(s,l->step+1);
 }
 if(l->step==total&&near(x,y,s->p[s->count-1],5)){
  l->stroke++;l->step=0;l->waiting=false;l->rest_at=ms;
  l->phase=l->stroke==TI_STROKES?TI_FINISHED:TI_REST;
 }
}
/* Shared guide geometry for rendering; no extra canvas or unbounded trails. */
unsigned ti_letter_steps(unsigned stroke){const TIStroke *s=ti_stroke(stroke);return s?steps(s):0;}
TIGlyphPoint ti_letter_point(unsigned stroke,unsigned step){const TIStroke *s=ti_stroke(stroke);return s?checkpoint(s,step):(TIGlyphPoint){0,0};}
