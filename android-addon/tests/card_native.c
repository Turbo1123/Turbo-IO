#include "editor.h"
#include <assert.h>
#include <stdio.h>
int main(int argc,char **argv){assert(argc==2);for(unsigned i=0;i<6;i++){char path[1024];int written=snprintf(path,sizeof path,"%s/template%u.tce",argv[1],i);assert(written>0&&(unsigned)written<sizeof path);FILE *f=fopen(path,"rb");assert(f);unsigned char bytes[2049];size_t n=fread(bytes,1,sizeof bytes,f);fclose(f);TCEDocument document;assert(tce_decode(bytes,n,&document));assert(document.count>0&&document.count<=12);assert(document.pixels<=32768);assert(!tce_decode(bytes,n-1,&document));}puts("Six Android-generated cards accepted by existing firmware C decoder");return 0;}
