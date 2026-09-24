#include "reader_input.h"
#include <assert.h>
#include <limits.h>
#include <stdio.h>
int main(void){WRInput s={0};for(unsigned i=0;i<200;i++)assert(!wr_input_wheel(&s,i&1?1:-1,i));
 assert(!wr_input_wheel(&s,200,500));assert(!wr_input_wheel(&s,200,520));assert(wr_input_wheel(&s,200,540)==1);
 assert(!wr_input_press(&s,600));assert(wr_input_press(&s,900));assert(!wr_input_press(&s,1100));
 assert(!wr_input_wheel(&s,INT_MAX,950));assert(wr_input_wheel(&s,INT_MIN,1400)==-1);assert(!wr_input_wheel(&s,INT_MAX,1401));
 s.confirmed=true;assert(!wr_input_press(&s,2000));assert(!wr_input_wheel(&s,600,2000));s.confirmed=false;
 assert(wr_input_press(&s,2200));s=(WRInput){0};assert(wr_input_wheel(&s,600,UINT_MAX-150)==1);assert(!wr_input_wheel(&s,600,1));assert(wr_input_wheel(&s,600,300)==1);
 puts("rotary filter tests passed: jitter, accumulation, press guards, burst, overflow, wrap");return 0;}
