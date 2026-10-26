#include "focus_view.h"
#include <string.h>
static void copy(char *d,const char *s){size_t n=0;while(n<111&&s[n])n++;memcpy(d,s,n);d[n]=0;}
static void clock_text(char *s,uint32_t seconds){unsigned m=seconds/60,n=seconds%60;unsigned at=0;if(m>=100)s[at++]='0'+m/100;s[at++]='0'+m/10%10;s[at++]='0'+m%10;s[at++]=':';s[at++]='0'+n/10;s[at++]='0'+n%10;s[at]=0;}
static int absolute(int n){return n<0?-n:n;}
static void stroke(uint8_t *p,const int8_t (*points)[2],unsigned count,unsigned gray){
 for(unsigned i=1;i<count;i++){int x=points[i-1][0],y=points[i-1][1],tx=points[i][0],ty=points[i][1];int dx=absolute(tx-x),dy=-absolute(ty-y),sx=x<tx?1:-1,sy=y<ty?1:-1,error=dx+dy;
  for(unsigned k=0;k<192;k++){for(int yy=-2;yy<=2;yy++)for(int xx=-2;xx<=2;xx++){int d=xx*xx+yy*yy,px=x+xx,py=y+yy;if(d<=5&&px>=0&&px<96&&py>=0&&py<96){unsigned v=d<=2?gray:gray/3;if(p[py*96+px]<v)p[py*96+px]=(uint8_t)v;}}if(x==tx&&y==ty)break;int e=2*error;if(e>=dy){error+=dy;x+=sx;}if(e<=dx){error+=dx;y+=sy;}}
 }
}
static void glyph(uint8_t *p,const TFocus *s){(void)s;memset(p,0,96*96);
 /* Hand-authored integer contours from the ImageGen tomato reference.
  * No clock hands, bitmap assets, floats, decoding or allocation. */
 static const int8_t body[][2]={{32,28},{25,30},{19,34},{14,41},{11,49},{11,60},{14,70},{20,79},{28,85},{38,88},{48,86},{58,88},{68,85},{76,79},{82,70},{85,60},{85,49},{82,41},{77,34},{70,30},{63,28}};
 static const int8_t leaves[][2]={{47,27},{38,20},{28,19},{35,29},{25,32},{36,34},{31,42},{44,37},{48,48},{53,37},{65,42},{60,33},{72,31},{61,28},{69,19},{57,21},{48,29}};
 static const int8_t stem[][2]={{48,27},{48,20},{51,13},{56,8}};
 static const int8_t shine[][2]={{26,42},{22,46},{20,52}};
 stroke(p,body,sizeof body/sizeof *body,210);stroke(p,leaves,sizeof leaves/sizeof *leaves,255);stroke(p,stem,sizeof stem/sizeof *stem,255);stroke(p,shine,sizeof shine/sizeof *shine,150);
}
bool tf_view_open(TFView *v,const TNWidgets *api,void *surface,void *parent){if(!v||!api||!api->idle(api->ctx))return false;memset(v,0,sizeof *v);v->api=*api;v->api.ctx=surface;
 v->root=api->root(surface,parent);if(!v->root)return false;api->place(surface,v->root,0,0,540,180);
 const unsigned fonts[]={22,48,20,18};const int rects[][4]={{156,8,368,28},{156,43,368,67},{156,116,368,26},{16,150,508,24}};
 for(unsigned i=0;i<4;i++){v->labels[i]=api->label(surface,v->root,fonts[i]);if(!v->labels[i]){api->destroy(surface,v->root);memset(v,0,sizeof *v);return false;}api->place(surface,v->labels[i],rects[i][0],rects[i][1],rects[i][2],rects[i][3]);}
 v->icon=api->canvas(surface,v->root);if(!v->icon){api->destroy(surface,v->root);memset(v,0,sizeof *v);return false;}api->place(surface,v->icon,24,38,96,96);v->open=true;return true;
}
bool tf_view_draw(TFView *v,const TFocus *s,bool compact){if(!v||!v->open||!v->root||!v->api.idle(v->api.ctx))return false;unsigned b=v->bank^1;memset(v->text[b],0,sizeof v->text[b]);
 const char *phase=s->phase==0?"番茄时钟 · 专注":s->phase==1?"番茄时钟 · 短休息":"番茄时钟 · 长休息";
 copy(v->text[b][0],compact?"● 专注计时中":phase);
 clock_text(v->text[b][1],(s->remaining_ms+999)/1000);
 copy(v->text[b][2],s->status==TF_DONE?"时间到，休息一下。":s->status==TF_PAUSED?"已暂停":s->status==TF_RUNNING?"安静计时 · 息屏后继续":"准备好，专注一件事");
 copy(v->text[b][3],s->status==TF_RUNNING?"短按暂停 · 长按停止 · 息屏继续计时":s->status==TF_PAUSED?"短按继续 · 长按停止并退出":s->status==TF_DONE?"短按开始下一阶段 · 长按退出":"滚动选时长 · 短按开始 · 长按退出");
 for(unsigned i=0;i<4;i++){v->api.text_static(v->api.ctx,v->labels[i],v->text[b][i]);v->api.visible(v->api.ctx,v->labels[i],!compact||i==0);}
 glyph(v->pixels[b],s);v->api.buffer(v->api.ctx,v->icon,v->pixels[b],96,96);v->api.visible(v->api.ctx,v->icon,!compact);v->api.visible(v->api.ctx,v->root,true);v->bank=b;return true;
}
bool tf_view_close(TFView *v){if(!v||!v->root)return true;if(!v->api.idle(v->api.ctx))return false;v->open=false;void *root=v->root;v->root=NULL;v->api.destroy(v->api.ctx,root);memset(v->labels,0,sizeof v->labels);return true;}
