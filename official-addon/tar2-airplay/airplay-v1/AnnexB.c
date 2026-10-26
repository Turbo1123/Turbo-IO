#include "AnnexB.h"
static size_t marker(const uint8_t *p,size_t n,size_t i){
 if(i+3<=n&&p[i]==0&&p[i+1]==0){if(p[i+2]==1)return 3;if(i+4<=n&&p[i+2]==0&&p[i+3]==1)return 4;}return 0;
}
int tar_nals(const uint8_t *p,size_t n,TARNAL *out,size_t cap){
 if(!p||!out||n<4||n>2*1024*1024||!cap)return -1;
 size_t at=0,count=0;
 while(at<n){size_t lead=marker(p,n,at);if(!lead)return -1;size_t begin=at+lead,end=begin;
  while(end<n&&!marker(p,n,end))end++;
  if(end==begin||count==cap)return -1;
  out[count++]=(TARNAL){p+begin,end-begin};at=end;
 }return (int)count;
}
