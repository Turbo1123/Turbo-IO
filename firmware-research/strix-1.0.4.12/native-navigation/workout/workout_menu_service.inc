/* Included in nav_service.c: shares its single page owner and UI executor.
 * A local menu generation binds automatic START to the still-open page.
 * The phone cannot reopen a page after Back with a delayed menu request. */
static void tw_menu_emit(Control *c,bool open){
 if(!c->menu_nonce||!paired()||c->menu_sequence==UINT32_MAX)return;
 uint8_t raw[20],out[160];memset(raw,0,sizeof raw);memcpy(raw,"TWM1",4);raw[4]=1;raw[5]=open?1:0;
 tw_p32(raw+8,c->menu_nonce);tw_p32(raw+12,++c->menu_sequence);tw_p32(raw+16,tw_crc(raw,16,false));
 static const char prefix[]="{\"cmd\":\"turbo_wrk_menu\",\"payload\":{\"data\":\"",suffix[]="\"}}",hex[]="0123456789abcdef";
 enum{len=sizeof prefix-1+40+sizeof suffix-1};_Static_assert(len<128,"menu PB width");
 const uint8_t head[]={8,1,16,6,26,len};memcpy(out,head,sizeof head);memcpy(out+sizeof head,prefix,sizeof prefix-1);
 unsigned pos=sizeof head+sizeof prefix-1;for(unsigned i=0;i<20;i++){out[pos++]=hex[raw[i]>>4];out[pos++]=hex[raw[i]&15];}
 memcpy(out+pos,suffix,sizeof suffix-1);(void)tdp_rnlink_send(15,out,pos+sizeof suffix-1,NULL);c->menu_last=stream_tick();
}
static void tw_menu_close(Control *c){if(!c||!c->menu_open)return;c->menu_open=false;tw_menu_emit(c,false);}
static void tw_menu_tick(Control *c,uint32_t now){
 if(c->menu_open&&c->waiting&&c->view&&c->view->open&&owns(c)&&(uint32_t)(now-c->menu_last)>=2000)tw_menu_emit(c,true);
}
bool tw_slot_open(TNNavSlot *s){
 Control *c=control(s);if(!c||!safe_home()||c->runtime.active||c->view||!s||((M8NativeTail *)((uint8_t *)c->app+0xdc))->page)return false;
#if TIO_MUSIC_RUNTIME
 if(tm_slot_visible(s->music)||wr_slot_visible(s->reader)||tf_slot_visible(s->focus))return false;
#endif
 TNScene empty;memset(&empty,0,sizeof empty);empty.workout=true;empty.mode=TN_ALWAYS;
 empty.workout_data.heart=empty.workout_data.pace=empty.workout_data.cadence=empty.workout_data.stride_cm=TW_MISSING16;
 empty.workout_data.distance_cm=empty.workout_data.energy_tenth_kcal=TW_MISSING32;
 if(!enter(c,&empty))return false;
 /* No fabricated zero metrics or running timer while waiting for HealthKit. */
 if(!tn_view_update(c->view,&empty,true)){retire(c);return false;}
 c->view->api.text_static(c->view->api.ctx,c->view->text[1],"运动看板");
 c->view->api.text_static(c->view->api.ctx,c->view->text[2],"请在手表开始跑步");
 c->waiting=true;c->waiting_since=stream_tick();
 if(!power(c,TN_POWER_WAKE_HOLD)){retire(c);return false;}
 uint32_t next=stream_tick();if(!next||next<=c->menu_nonce)next=c->menu_nonce+1;
 if(!next){retire(c);return false;}c->menu_nonce=next;c->menu_sequence=0;c->menu_open=true;tw_menu_emit(c,true);return true;
}
