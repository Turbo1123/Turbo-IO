#include "card.h"
#include <stdio.h>
#include <string.h>
#include <assert.h>
/* Verdicts of the iOS/firmware TDC1 parser; the Java validator must agree on every case. */
static const char *cases[]={
 "TDC1;99;90;85;375;1280;1400;2000;0;1;2","TDC1;25;50;75;640;1280;1000;2000;0;1;2","TDC1;0;0;0;0;1;0;1;0;0;0",
 "TDC1;100;100;100;99999;99999;99999;99999;2;2;2","TDC1;101;90;85;375;1280;1400;2000;0;1;2","TDC1;99;90;85;375;1280;1400;2000;0;1",
 "TDC1;99;90;85;375;1280;1400;2000;0;1;2;0","TDC1;1000000;90;85;375;1280;1400;2000;0;1;2","TDC1;99;90;85;1281;1280;1400;2000;0;1;2",
 "TDC1;99;90;85;375;1280;1400;2000;0;1;3","TDC2;99;90;85;375;1280;1400;2000;0;1;2","TDC1;99;90;85;375;0;0;2000;0;1;2",
 "TDC1;99;90;85;375;1280;1400;100000;0;1;2","TDC1;99;90;85;375;1280;1400;2000;0;1;2;","TDC1;;90;85;375;1280;1400;2000;0;1;2",
 "TDC1;99;90;85;375;1280;1400;2000;0;1;+2","TDC1;099;90;85;375;1280;1400;2000;0;1;2","tdc1;99;90;85;375;1280;1400;2000;0;1;2",
 "TDC1;99;90;85;375;1280;2001;2000;0;1;2","TDC1;","TDC1;99;90;85;375;1280;1400;2000;0;1; 2",
};
int main(int argc,char **argv){assert(argc==2);char path[1024];snprintf(path,sizeof path,"%s/cases.txt",argv[1]);FILE *f=fopen(path,"w");assert(f);
 for(size_t i=0;i<sizeof cases/sizeof*cases;i++){DCValues v;fprintf(f,"%d\t%s\n",dc_parse(cases[i],strlen(cases[i]),&v)?1:0,cases[i]);}
 fclose(f);return 0;}
