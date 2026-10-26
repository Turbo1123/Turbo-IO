#include "trace.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
static TISample sample(uint64_t us,float x,float y,float z){TISample s={.us=us,.accel={0,0,9.80665f},.gyro={x,y,z}};return s;}
int main(void){
 TITrace t;ti_init(&t,0);uint64_t now=10000;
 for(unsigned i=0;i<180;i++,now+=10000){TISample s=sample(now,.01f,0,0);ti_sample(&t,&s,(uint32_t)(now/1000));}
 assert(t.calibrated&&t.hz==100&&t.bias[0]>.0099f&&t.bias[0]<.0101f);
 for(unsigned i=0;i<100;i++,now+=10000){TISample s=sample(now,.01f,0,.5f);ti_sample(&t,&s,(uint32_t)(now/1000));}
 TIPoint p=t.points[(t.head+TI_POINTS-1)%TI_POINTS];assert(p.x>300&&p.x<315&&p.y>=79&&p.y<=81);
 uint32_t before=t.gaps;now+=1000000;TISample s=sample(now,.01f,0,0);ti_sample(&t,&s,now/1000);assert(t.gaps==before+1&&!t.points[(t.head+TI_POINTS-1)%TI_POINTS].join);
 s.gyro[0]=NAN;assert(!ti_sample(&t,&s,now/1000));assert(t.invalid==1);
 s=sample(now,0,0,0);ti_sample(&t,&s,now/1000);assert(!ti_sample(&t,&s,now/1000));
 static uint8_t storage[TI_HEIGHT*(TI_WIDTH+4)+64];memset(storage,0xa5,sizeof storage);ti_draw(&t,storage+32,TI_WIDTH+4,now/1000);
 for(unsigned i=0;i<32;i++){assert(storage[i]==0xa5);assert(storage[sizeof storage-1-i]==0xa5);}
 ti_recenter(&t);assert(!t.calibrated&&!t.count&&t.q[0]==1);
 for(unsigned i=0;i<500;i++){s=sample(10000+i*10000,1,0,0);ti_sample(&t,&s,i*10);}assert(!t.calibrated);
 ti_init(&t,1);now=10000;for(unsigned i=0;i<180;i++,now+=10000){s=sample(now,0,0,0);ti_sample(&t,&s,now/1000);}
 for(unsigned i=0;i<100000;i++,now+=10000){s=sample(now,.02f,.03f,.01f);ti_sample(&t,&s,now/1000);assert(t.count<=TI_POINTS&&t.head<TI_POINTS);}
 float norm=0;for(unsigned i=0;i<4;i++)norm+=t.q[i]*t.q[i];assert(fabsf(norm-1)<.0001f);
 printf("trace core PASS: bias, 100Hz, turn projection, stale breaks, NaN, recenter, 100k bounded samples; state=%zu bytes\n",sizeof t);
}
