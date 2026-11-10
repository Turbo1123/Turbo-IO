/* Included after camera helpers; distinct TVP1 namespace and full-screen owner. */
static bool vp_native_message(const TIONativeMessage *m){
 if(!m||m->id!=1||!m->data||m->bytes>VP_WIRE_MAX||m->mode>1||m->context||m->reserved||m->padding[0]||m->padding[1]||m->padding[2]||!paired())return false;
 VPPacket q;if(!vp_decode(m->data,m->bytes,&q,false))return false;
 VPPacket a={.op=q.op,.sid=q.sid,.seq=q.seq,.result=VP_BUSY};uint32_t now=stream_tick();
 void *vm=manager(),*app=ptr(vm,0x10);if(!app&&q.op==VP_HELLO&&home())app=nav_ensure_menu(vm);
 TCSlot *s=slot(app);TCControl *c=s?s->control:NULL;
 if(q.op==VP_HELLO){if(s&&home()&&!other(app)&&(!c||!c->root)){a.result=VP_OK;a.a=VP_W;a.b=VP_H|(q.a==VP_HD_CAP?(VP_HD_FLAG<<16):0);a.c=now;}vp_emit(&a);return true;}
 if(q.op==VP_OPEN){
  if(c&&c->sid==q.sid&&q.seq<=c->seq){a.result=VP_STALE;vp_emit(&a);return true;}
  int32_t age=(int32_t)(now-q.a);
  if(age< -250||age>1500){a.result=VP_STALE;vp_emit(&a);return true;}
  if(q.b||q.c||(c&&c->sid&&c->sid!=q.sid)||!s||!open_mode(s,false,VP_MODE)){vp_emit(&a);return true;}c=s->control;
  if(!c->video->open){if(!vp_open(c->video,q.sid,c->video->stride,now)){close_page(c);a.result=VP_RENDER;vp_emit(&a);return true;}TNWidgets w=tn_lvgl_widgets();w.buffer(NULL,c->canvas,c->video->pixels[0],VP_W,VP_H);}
  c->sid=q.sid;c->seen=now;c->seq=q.seq;c->phase=TC_LIVE;if(!c->hold)c->hold=nav_always_on("turbo_camera_v1");a.result=VP_OK;vp_emit(&a);return true;
 }
 if(!c||!c->video||!c->root||c->closing||!owns(c)||c->sid!=q.sid){a.result=VP_SESSION;vp_emit(&a);return true;}
 if(q.seq<=c->seq){a.result=VP_STALE;vp_emit(&a);return true;}c->seq=q.seq;c->seen=now;
 if(q.op==VP_FRAME){
  uint32_t before=stream_tick();TNWidgets w=tn_lvgl_widgets();a.result=vp_frame(c->video,&q,now,w.idle(NULL));
  uint32_t elapsed=stream_tick()-before;c->video->decode_ms+=elapsed;
  if(a.result==VP_OK)w.buffer(NULL,c->canvas,c->video->pixels[c->video->active],VP_W,VP_H);
  a.a=c->video->displayed;a.b=elapsed;a.c=c->video->bytes;
 }else if(q.op>=VP_HD_BEGIN&&q.op<=VP_HD_COMMIT){
  uint32_t before=stream_tick();TNWidgets w=tn_lvgl_widgets();a.result=vp_hd(c->video,&q,now,w.idle(NULL));
  uint32_t elapsed=stream_tick()-before;c->video->decode_ms+=elapsed;
  if(q.op==VP_HD_COMMIT){if(a.result==VP_OK)w.buffer(NULL,c->canvas,c->video->pixels[c->video->active],VP_W,VP_H);a.a=c->video->displayed;a.b=elapsed;a.c=c->video->bytes;}
  else if(q.op==VP_HD_STRIP){a.a=c->video->hd_y;a.b=elapsed;a.c=c->video->hd_bytes;}
  else{a.a=c->video->hd_frame;a.b=0;a.c=0;}
 }else if(q.op==VP_PING){c->video->seen=now;a.result=VP_OK;a.a=c->video->paused;a.b=c->video->displayed;a.c=c->video->bytes;}
 else if(q.op==VP_CLOSE){a.result=VP_OK;close_page(c);fm_sync(app);}
 else a.result=VP_INVALID;
 vp_emit(&a);return true;
}
