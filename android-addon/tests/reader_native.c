#include "reader.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
static size_t read_file(const char *dir,const char *name,unsigned char *b,size_t cap){char p[1024];snprintf(p,sizeof p,"%s/%s",dir,name);FILE *f=fopen(p,"rb");assert(f);size_t n=fread(b,1,cap,f);assert(feof(f));fclose(f);return n;}
int main(int argc,char **argv){assert(argc==2);unsigned char b[24577],out[512];size_t n=read_file(argv[1],"shelf.bin",b,sizeof b);assert(wr_validate(b,n));n=read_file(argv[1],"window.bin",b,sizeof b);assert(wr_validate(b,n));for(int op=1;op<=7;op++){char name[32];snprintf(name,sizeof name,"op%d.bin",op);n=read_file(argv[1],name,b,sizeof b);WRPacket p;assert(wr_decode(b,n,&p));size_t k=wr_encode(out,sizeof out,p.op,p.sid,p.sequence,p.revision,p.offset,p.data,p.length);assert(k==n&&!memcmp(out,b,n));}puts("TWR1 native decoder: 2 pages and 7 byte-exact operation vectors passed");}
