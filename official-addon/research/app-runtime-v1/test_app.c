#include "app.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int argc,char **argv){
 assert(argc==2);FILE *f=fopen(argv[1],"rb");assert(f);uint8_t wire[TAP_MAX_BYTES+1];size_t n=fread(wire,1,sizeof wire,f);assert(feof(f));fclose(f);
 TAPDocument d;assert(tap_parse(wire,n,&d));assert(d.pages==2);TAPState s;
 for(unsigned round=0;round<10000;round++){
  assert(tap_start(&s,&d));assert(tap_event(&s,TAP_TOUCH,100).type==0);assert(s.page==0);
  assert(tap_event(&s,TAP_PRESS,100).type==TAP_PAGE_CHANGED);assert(s.page==1);
  assert(tap_event(&s,TAP_LONG_PRESS,200).type==TAP_EXIT);assert(!s.active&&!s.document);
 }
 for(size_t cut=0;cut<n;cut++){TAPDocument bad;memset(&bad,0xaa,sizeof bad);assert(!tap_parse(wire,cut,&bad));assert(bad.count==0);}
 unsigned seed=7392;uint8_t fuzz[TAP_MAX_BYTES+1];
 for(unsigned i=0;i<100000;i++){memcpy(fuzz,wire,n);seed=seed*1664525u+1013904223u;unsigned at=seed%n;fuzz[at]^=(uint8_t)(1+(seed>>24));TAPDocument candidate;
  if(tap_parse(fuzz,n,&candidate)){assert(tap_start(&s,&candidate));for(unsigned k=0;k<20;k++)tap_event(&s,k%5,k*200);tap_stop(&s);}
 }
 printf("TAP1 draft: parser/truncation/100000 mutations/10000 lifecycle cycles passed; host only. document=%zu state=%zu\n",sizeof d,sizeof s);
 return 0;
}
