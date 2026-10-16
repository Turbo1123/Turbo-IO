#include "editor.h"
#include <string.h>
static unsigned le16(const uint8_t *p){return p[0]|((unsigned)p[1]<<8);}
static bool utf8(const uint8_t *s,size_t n){
 for(size_t i=0;i<n;){unsigned c=s[i++],v,min,k;if(c<0x80){if(c<32||c==127)return false;continue;}
  if(c>=0xc2&&c<=0xdf){v=c&31;min=0x80;k=1;}else if(c>=0xe0&&c<=0xef){v=c&15;min=0x800;k=2;}else if(c>=0xf0&&c<=0xf4){v=c&7;min=0x10000;k=3;}else return false;
  if(k>n-i)return false;while(k--){c=s[i++];if((c&0xc0)!=0x80)return false;v=(v<<6)|(c&63);}if(v<min||v>0x10ffff||(v>=0xd800&&v<=0xdfff)||(v>=0x80&&v<=0x9f)||v==0x2028||v==0x2029)return false;
 }return true;
}
bool tce_decode(const uint8_t *p,size_t n,TCEDocument *out){
 if(!p||!out||n<8||n>TCE_MAX_BYTES||memcmp(p,"TCE1",4)||!p[4]||p[4]>12||p[5]||le16(p+6)!=n)return false;
 TCEDocument d;memset(&d,0,sizeof d);d.count=p[4];size_t at=8;unsigned images=0,charts=0;
 for(unsigned j=0;j<d.count;j++){
  if(n-at<10)return false;TCEItem *q=&d.items[j];q->type=p[at];q->x=p[at+1];q->y=p[at+2];q->w=p[at+3];q->h=p[at+4];q->a=p[at+5];q->b=p[at+6];q->length=le16(p+at+8);
  if(p[at+7]||q->x<6||q->y<6||q->w<2||q->h<2||((q->x|q->y|q->w|q->h)&1)||q->x+q->w>250||q->y+q->h>188)return false;
  at+=10;if(q->length>n-at)return false;q->data=p+at;at+=q->length;
  switch(q->type){
  case TCE_TEXT:
   if(!q->length||q->length>96||!utf8(q->data,q->length)||q->b>2||!(q->a==14||q->a==16||q->a==18||q->a==20||q->a==24||q->a==28)||q->h<q->a+4||q->w<16)return false;break;
  case TCE_IMAGE:
   if(q->a||q->b||++images>4||q->w!=q->h||!(q->w==16||q->w==24||q->w==32||q->w==48)||q->length!=(q->w/8)*q->h)return false;d.pixels+=q->w*q->h;break;
  case TCE_PROGRESS:if(q->a>100||q->b||q->length||q->w<16||q->h>12)return false;break;
  case TCE_BAR:case TCE_LINE:
   if(q->a||q->b||++charts>2||q->w<64||q->h<32||q->length<2||q->length>8)return false;
   for(unsigned i=0;i<q->length;i++)if(q->data[i]>100)return false;d.pixels+=((q->w+3)&~3u)*q->h;break;
  case TCE_DIVIDER:if(q->a||q->b||q->length||q->h!=2||q->w<8)return false;break;
  case TCE_FRAME:if(q->a||q->b||q->length||q->w<16||q->h<16)return false;break;
  default:return false;
  }
  if(d.pixels>TCE_PIXEL_BUDGET)return false;
 }
 if(at!=n)return false;memcpy(out,&d,sizeof d);return true;
}
static int digit(char c){if(c>='A'&&c<='Z')return c-'A';if(c>='a'&&c<='z')return c-'a'+26;if(c>='0'&&c<='9')return c-'0'+52;if(c=='+')return 62;if(c=='/')return 63;return -1;}
size_t tce_unbase64(const char *s,size_t n,uint8_t *out,size_t cap){
 if(!s||!out||!n||n%4||n>TCE_MAX_TEXT)return 0;size_t k=0;
 for(size_t i=0;i<n;i+=4){int a=digit(s[i]),b=digit(s[i+1]),c=digit(s[i+2]),d=digit(s[i+3]);bool pc=s[i+2]=='=',pd=s[i+3]=='=';unsigned bytes=pc?1:pd?2:3;
  if(a<0||b<0||(!pc&&c<0)||(!pd&&d<0)||(pc&&!pd)||((pc||pd)&&i+4!=n)||(pc&&(b&15))||(pd&&!pc&&(c&3))||bytes>cap-k)return 0;
  out[k++]=(a<<2)|(b>>4);if(!pc){out[k++]=(b<<4)|(c>>2);if(!pd)out[k++]=(c<<6)|d;}
 }return k;
}
static void dot(uint8_t *p,int w,int h,int x,int y,uint8_t v){if(x>=0&&y>=0&&x<w&&y<h)p[y*w+x]=v;}
static void line(uint8_t *p,int w,int h,int x,int y,int xx,int yy){int dx=xx>x?xx-x:x-xx,sx=x<xx?1:-1,dy=yy>y?y-yy:yy-y,sy=y<yy?1:-1,err=dx+dy;
 for(;;){dot(p,w,h,x,y,255);dot(p,w,h,x,y+1,255);if(x==xx&&y==yy)break;int e=2*err;if(e>=dy){err+=dy;x+=sx;}if(e<=dx){err+=dx;y+=sy;}}
}
bool tce_raster(const TCEItem *q,uint8_t *p,size_t cap){
 if(!q||!p||!q->data||cap<(size_t)q->w*q->h||!q->w||!q->h)return false;int w=q->w,h=q->h;
 if(q->type==TCE_IMAGE){if(w!=h||!(w==16||w==24||w==32||w==48)||q->length!=(w/8)*h)return false;for(int y=0;y<h;y++)for(int x=0;x<w;x++)p[y*w+x]=(q->data[y*(w/8)+x/8]&(0x80>>(x%8)))?255:0;return true;}
 if((q->type!=TCE_BAR&&q->type!=TCE_LINE)||q->length<2||q->length>8||w<64||h<32)return false;for(unsigned j=0;j<q->length;j++)if(q->data[j]>100)return false;
 memset(p,0,(size_t)w*h);for(int y=0;y<h;y++)dot(p,w,h,0,y,75);for(int x=0;x<w;x++)dot(p,w,h,x,h-1,75);
 for(int y=h/4;y<h-1;y+=h/4)for(int x=2;x<w;x+=4)dot(p,w,h,x,y,30);
 for(unsigned i=0;i<q->length;i++){
  int y=(h-3)*(100-q->data[i])/100+1;
  if(q->type==TCE_BAR){int left=2+i*(w-2)/q->length,right=2+(i+1)*(w-2)/q->length-2;for(int yy=y;yy<h-1;yy++)for(int x=left;x<right;x++)dot(p,w,h,x,yy,255);}
  else{int x=2+i*(w-4)/(q->length-1);if(i){int px=2+(i-1)*(w-4)/(q->length-1),py=(h-3)*(100-q->data[i-1])/100+1;line(p,w,h,px,py,x,y);}for(int dy=-1;dy<=1;dy++)for(int dx=-1;dx<=1;dx++)dot(p,w,h,x+dx,y+dy,255);}
 }return true;
}
