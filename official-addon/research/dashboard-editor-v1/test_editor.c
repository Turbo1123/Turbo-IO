#include "editor.h"
#include <assert.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
static unsigned rng=42;
static unsigned random32(void){rng^=rng<<13;rng^=rng>>17;rng^=rng<<5;return rng;}
static void size(uint8_t *b,unsigned n){b[6]=n;b[7]=n>>8;}
int main(void){
 uint8_t bytes[2048]={ 'T','C','E','1',1,0,19,0,1,6,6,120,24,18,0,0,1,0,'A'};
 TCEDocument d;assert(tce_decode(bytes,19,&d)&&d.count==1&&d.pixels==0);
 for(unsigned n=0;n<19;n++)assert(!tce_decode(bytes,n,&d));
 for(unsigned i=0;i<19;i++){uint8_t old=bytes[i];bytes[i]=255;assert(!tce_decode(bytes,19,&d));bytes[i]=old;}
 uint8_t decoded[2048];assert(tce_unbase64("TQ==",4,decoded,sizeof decoded)==1&&decoded[0]=='M');assert(tce_unbase64("TWE=",4,decoded,sizeof decoded)==2);assert(tce_unbase64("TWFu",4,decoded,sizeof decoded)==3);
 const char *bad[]={"TR==","TWF=","TQ=A","=AAA","TQ==AAAA","TQ=","!!!!","AAAA\n"};for(unsigned i=0;i<sizeof bad/sizeof*bad;i++)assert(!tce_unbase64(bad[i],strlen(bad[i]),decoded,sizeof decoded));assert(!tce_unbase64("AAAA",4,decoded,2));
 bytes[8]=TCE_IMAGE;bytes[11]=bytes[12]=48;bytes[13]=0;bytes[16]=32;bytes[17]=1;memset(bytes+18,0x81,288);size(bytes,306);assert(tce_decode(bytes,306,&d)&&d.pixels==2304);
 uint8_t *pixels=malloc(65538);assert(pixels);memset(pixels,0xa5,65538);assert(tce_raster(&d.items[0],pixels+1,2304));assert(pixels[0]==0xa5&&pixels[2305]==0xa5&&pixels[1]==255&&pixels[2]==0&&pixels[8]==255);
 assert(!tce_raster(&d.items[0],pixels,2303));
 uint8_t vals[8]={0,10,100,33,66,1,99,50};
 for(int type=TCE_BAR;type<=TCE_LINE;type++)for(int w=64;w<245;w+=2)for(int h=32;h<183;h+=2){TCEItem q={.type=type,.w=w,.h=h,.length=8,.data=vals};memset(pixels,0xa5,65538);assert(tce_raster(&q,pixels+1,w*h));assert(pixels[0]==0xa5&&pixels[w*h+1]==0xa5);}
 for(unsigned i=0;i<200000;i++){unsigned n=random32()%2049;for(unsigned j=0;j<n;j++)bytes[j]=random32();if(i%2&&n>=8){memcpy(bytes,"TCE1",4);bytes[4]=1+random32()%12;bytes[5]=0;size(bytes,n);}memset(&d,0xa5,sizeof d);TCEDocument before=d;if(tce_decode(bytes,n,&d)){assert(d.count<=12&&d.pixels<=32768);for(unsigned j=0;j<d.count;j++)if(d.items[j].type==2||d.items[j].type==4||d.items[j].type==5)assert(tce_raster(&d.items[j],pixels,65536));}else assert(!memcmp(&d,&before,sizeof d));tce_unbase64((const char*)bytes,n,decoded,sizeof decoded);}
 free(pixels);puts("PASS TCE1 decoder, canonical base64, image orientation bits, all chart sizes, 200000 fuzz cases");return 0;
}
