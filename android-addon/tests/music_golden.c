#include "music.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
static void put(unsigned char *b,unsigned n){for(int i=0;i<4;i++)b[i]=(unsigned char)(n>>(8*i));}
int main(int argc,char **argv){if(argc!=2)return 1;unsigned char state[208]={0},lyrics[12]={0},cover[96]={0},packet[4096];put(state,12345);put(state+4,230000);state[8]=1;state[9]=2;put(state+12,17);memcpy(state+16,"Turbo Song",10);memcpy(state+112,"Turbo Artist",12);put(lyrics,1000);lyrics[4]=6;memcpy(lyrics+6,"hello!",6);memset(cover,127,96);
 for(int op=1;op<=6;op++){const void *data=NULL;size_t n=0;int final=0;if(op<=2){data=state;n=208;}if(op==3){data=cover;n=96;}if(op==4){data=lyrics;n=12;final=1;}size_t length=tm_encode(packet,sizeof packet,op,final,7392,3,8642,0,data,n);if(!length)return 2;char path[4096];snprintf(path,sizeof path,"%s/op%d.bin",argv[1],op);FILE *f=fopen(path,"wb");if(!f)return 3;fwrite(packet,1,length,f);fclose(f);}
 // Independently accept the Android-produced variable-size state/lyric payloads.
 return 0;}
