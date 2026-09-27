#include "render_idle.h"
static bool ram(uint32_t p,uint32_t extent){
 return !(p&3)&&p>=0x18000000&&p<=0x1b600000-extent;
}
bool tio_render_graph_idle(TIOReadWord read,TIONextDisplay next){
 uint32_t unit=0;unsigned count=0;
 if(!read||!next||!read(0x18617b8c+0x124,&unit)||!unit)return false;
 while(unit){
  uint32_t dispatch=0,active=0,n=0;
  if(++count>8||!ram(unit,32)||!read(unit+12,&dispatch)||
     (dispatch!=0x1057dff1&&dispatch!=0x1065d43b)||
     !read(unit+24,&active)||active||!read(unit,&n))return false;
  unit=n;
 }
 uint32_t display=next(0);count=0;
 if(!display)return false;
 while(display){
  uint32_t layer=0;unsigned layers=0;
  if(++count>4||!ram(display,0x2a4)||!read(display+0x2a0,&layer))return false;
  while(layer){
   uint32_t tasks=0,n=0;
   if(++layers>32||!ram(layer,0x44)||!read(layer+0x38,&tasks)||tasks||
      !read(layer+0x40,&n))return false;
   layer=n;
  }
  display=next(display);
 }
 return true;
}
