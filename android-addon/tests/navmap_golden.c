#include "nav_map.h"
#include "nav_runtime.h"
#include <stdio.h>
#include <string.h>
#include <assert.h>
/* TNR3 wire, label placement and validator verdicts from the iOS/firmware nav_map.c. */
static void w16(uint8_t *p,unsigned v){p[0]=(uint8_t)v;p[1]=(uint8_t)(v>>8);}
static void w32(uint8_t *p,uint32_t v){w16(p,v&0xffff);w16(p+2,v>>16);}
static void put(const char *dir,const char *name,const uint8_t *p,size_t n){char path[1024];snprintf(path,sizeof path,"%s/%s",dir,name);FILE *f=fopen(path,"wb");assert(f);assert(fwrite(p,1,n,f)==n);fclose(f);}
static void hex(FILE *f,const uint8_t *p,size_t n){for(size_t i=0;i<n;i++)fprintf(f,"%02x",p[i]);}
int main(int argc,char **argv){assert(argc==2);const char *d=argv[1];
 /* SCENE: 3 paths (5+3+2 points), styles 1/4/6, flags 1/2/0, layers -2/0/8, range 320. */
 static uint8_t scene[16+8*3+4*10];w32(scene,77);w16(scene+4,320);w16(scene+6,3);w16(scene+8,10);
 unsigned counts[]={5,3,2},style[]={1,4,6},flags[]={1,2,0};int layer[]={-2,0,8};
 for(int i=0;i<3;i++){uint8_t *q=scene+16+8*i;w16(q,counts[i]);q[2]=style[i];q[3]=flags[i];q[4]=(uint8_t)(int8_t)layer[i];}
 int pts[10][2]={{-400,0},{-200,40},{0,80},{200,40},{400,0},{0,-600},{0,0},{0,600},{-80,-80},{80,80}};
 for(int i=0;i<10;i++){w16(scene+16+24+4*i,(uint16_t)(int16_t)pts[i][0]);w16(scene+16+24+4*i+2,(uint16_t)(int16_t)pts[i][1]);}
 assert(tnr_body_valid(TNR_SCENE,scene,sizeof scene));
 /* SCENE2: same paths + 2 labels + pose. */
 static uint8_t scene2[sizeof scene+40*2+12];memcpy(scene2,scene,sizeof scene);w16(scene2+10,2);
 uint8_t *l=scene2+sizeof scene;w16(l,(uint16_t)(int16_t)-300);w16(l+2,200);const char *a="Main St";l[4]=(uint8_t)strlen(a);memcpy(l+8,a,strlen(a));
 l+=40;w16(l,250);w16(l+2,(uint16_t)(int16_t)-150);const char *b="深南大道";l[4]=(uint8_t)strlen(b);memcpy(l+8,b,strlen(b));
 uint8_t *pp=scene2+sizeof scene+80;w32(pp,77);w16(pp+4,0);w16(pp+6,0);w16(pp+8,0);w16(pp+10,0);
 assert(tnr_body_valid(TNR_SCENE2,scene2,sizeof scene2));
 uint8_t pose[12];w32(pose,77);w16(pose+4,(uint16_t)(int16_t)-40);w16(pose+6,120);w16(pose+8,215);w16(pose+10,350);assert(tnr_body_valid(TNR_POSE,pose,12));
 static uint8_t wire[TNR_MAX_BYTES];size_t n;
 n=tnr_wrap(wire,sizeof wire,TNR_SCENE,0x01020304u,5,scene,sizeof scene);assert(n);put(d,"scene.bin",wire,n);
 n=tnr_wrap(wire,sizeof wire,TNR_SCENE2,0x01020304u,6,scene2,sizeof scene2);assert(n);put(d,"scene2.bin",wire,n);
 n=tnr_wrap(wire,sizeof wire,TNR_POSE,0x01020304u,7,pose,12);assert(n);put(d,"pose.bin",wire,n);
 n=tnr_wrap(wire,sizeof wire,TNR_CLEAR,0x01020304u,8,NULL,0);assert(n);put(d,"clear.bin",wire,n);
 put(d,"scene2-body.bin",scene2,sizeof scene2);
 /* Labels visible at three poses (fresh receive, so no blending). */
 char path[1024];snprintf(path,sizeof path,"%s/labels.txt",d);FILE *f=fopen(path,"w");assert(f);
 int poses[3][3]={{0,0,0},{-40,120,90},{100,-60,215}};
 for(int k=0;k<3;k++){static TNRState s;memset(&s,0,sizeof s);uint8_t v[sizeof scene2];memcpy(v,scene2,sizeof v);uint8_t *tp=v+sizeof v-12;w16(tp+4,(uint16_t)(int16_t)poses[k][0]);w16(tp+6,(uint16_t)(int16_t)poses[k][1]);w16(tp+8,(unsigned)poses[k][2]);
  assert(tnr_receive(&s,TNR_SCENE2,v,sizeof v,0));TNRLabelView out[TNR_MAX_LABELS];unsigned c=tnr_labels(&s,200,out);
  fprintf(f,"%d %d %d %u",poses[k][0],poses[k][1],poses[k][2],c);for(unsigned i=0;i<c;i++)fprintf(f," %d,%d,%u",out[i].x,out[i].y,out[i].width);fprintf(f,"\n");}
 fclose(f);
 /* Validator verdicts: every byte of each valid body set to 0x00 and 0xff, and each bit-flipped. */
 snprintf(path,sizeof path,"%s/validity.txt",d);f=fopen(path,"w");assert(f);
 struct {unsigned op;uint8_t *p;size_t n;} bodies[]={{TNR_SCENE,scene,sizeof scene},{TNR_SCENE2,scene2,sizeof scene2},{TNR_POSE,pose,12}};
 for(unsigned k=0;k<3;k++)for(size_t i=0;i<bodies[k].n;i++)for(unsigned m=0;m<3;m++){uint8_t v[sizeof scene2];memcpy(v,bodies[k].p,bodies[k].n);v[i]=m==0?0:m==1?0xff:(uint8_t)(v[i]^1);
  fprintf(f,"%u %d ",bodies[k].op,tnr_body_valid(bodies[k].op,v,bodies[k].n)?1:0);hex(f,v,bodies[k].n);fprintf(f,"\n");}
 fprintf(f,"%u %d \n",TNR_CLEAR,tnr_body_valid(TNR_CLEAR,NULL,0)?1:0);
 fclose(f);return 0;
}
