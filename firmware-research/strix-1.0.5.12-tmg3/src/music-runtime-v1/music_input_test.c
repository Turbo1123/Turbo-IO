#include "music_input.h"
#include <assert.h>
#include <limits.h>
#include <stdio.h>
int main(void){TMInput s={0};
 for(unsigned i=0;i<1000;i++)assert(!tm_input_wheel(&s,i%2?2:-2,i));
 assert(!tm_input_wheel(&s,200,2000));assert(!tm_input_wheel(&s,200,2020));assert(tm_input_wheel(&s,200,2040)==1);
 for(unsigned i=0;i<10;i++)assert(!tm_input_wheel(&s,600,2050+i*60));
 assert(!tm_input_press(&s,2100));assert(tm_input_wheel(&s,-600,3000)==-1);
 assert(!tm_input_wheel(&s,300,4000));assert(!tm_input_wheel(&s,-300,4010));assert(tm_input_wheel(&s,-300,4020)==-1);
 s=(TMInput){0};assert(tm_input_wheel(&s,INT_MIN,UINT_MAX-100)==-1);assert(!tm_input_wheel(&s,INT_MAX,1));assert(tm_input_wheel(&s,INT_MAX,900)==1);
 s=(TMInput){0};assert(!tm_input_wheel(&s,200,1));assert(!tm_input_wheel(&s,400,400));assert(tm_input_press(&s,800));assert(!tm_input_press(&s,900));
 puts("music input: jitter, detents, one skip per gesture, reversal, overflow, click guard passed");
}
