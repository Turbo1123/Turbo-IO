"""Apply the cue-card home-menu overlay only to a fresh FOCUS candidate copy."""
import argparse
from pathlib import Path


def replace_once(root, relative, old, new):
    path = root / relative
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"Expected one patch point in {relative}, found {count}: {old[:72]!r}")
    path.write_text(text.replace(old, new))


def replace_all(root, relative, old, new, expected):
    path = root / relative
    text = path.read_text()
    count = text.count(old)
    if count != expected:
        raise SystemExit(f"Expected {expected} patch points in {relative}, found {count}: {old[:72]!r}")
    path.write_text(text.replace(old, new))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    root = parser.parse_args().source.resolve()
    nav = Path("navigation-runtime-v1/nav_service.h")
    music = Path("music-runtime-v1/menu10.c")
    focus = Path("focus-v1/focus_menu.c")
    native = Path("focus-v1/focus_menu_native.c")
    replace_once(root, nav, " void *quad;\n} TNNavSlot;", " void *quad;\n void *cue_row,*cue_label,*cue_icon,*cue_dot;\n} TNNavSlot;")
    replace_once(root, native, "_Static_assert(sizeof(TNNavSlot)==48,\"quad extends only separately allocated slot\");", "_Static_assert(sizeof(TNNavSlot)==64,\"candidate cue-menu pointers extend only separately allocated slot\");")
    replace_once(root, native, "index>=12)return;uint32_t now=stream_tick();", "index>=13)return;uint32_t now=stream_tick();")
    replace_once(root, native, "reader?reader->icon:NULL,focus?focus->row:NULL,focus?focus->icon:NULL};", "reader?reader->icon:NULL,focus?focus->row:NULL,focus?focus->icon:NULL,s?s->cue_row:NULL,s?s->cue_icon:NULL};")

    replace_once(root, focus, '"番茄时钟"};', '"番茄时钟","提词卡"};')
    replace_once(root, focus, 'selected>=12||!v->api.idle', 'selected>=13||!v->api.idle')
    replace_once(root, focus,
                 "v->pages[b][0]='1'+selected/4;v->pages[b][1]='/';v->pages[b][2]='3';v->pages[b][3]=0;",
                 "v->pages[b][0]='1'+selected/4;v->pages[b][1]='/';v->pages[b][2]='4';v->pages[b][3]=0;")
    replace_once(root, focus,
                 "for(unsigned i=0;i<4;i++){unsigned index=(unsigned)selected/4*4+i;icon(v->pixels[b][i],index,index==(unsigned)selected?255:150);v->api.buffer(v->api.ctx,v->icons[i],v->pixels[b][i],64,64);v->api.text_static(v->api.ctx,v->labels[i],names[index]);}",
                 "for(unsigned i=0;i<4;i++){unsigned index=(unsigned)selected/4*4+i;if(index<13)icon(v->pixels[b][i],index,index==(unsigned)selected?255:150);else memset(v->pixels[b][i],0,64*64);v->api.buffer(v->api.ctx,v->icons[i],v->pixels[b][i],64,64);v->api.text_static(v->api.ctx,v->labels[i],index<13?names[index]:\"\");}")
    replace_once(root, focus, " case 11:ring(p,31,35,21,g);line(p,31,17,32,6,g);line(p,31,17,22,11,g);line(p,31,17,43,10,g);line(p,20,28,17,36,g);break;\n }", " case 11:ring(p,31,35,21,g);line(p,31,17,32,6,g);line(p,31,17,22,11,g);line(p,31,17,43,10,g);line(p,20,28,17,36,g);break;\n case 12:box(p,8,10,42,32,g);box(p,14,16,42,32,g);line(p,23,27,29,32,g);line(p,29,32,39,22,g);break;\n }")

    replace_once(root, music, "int m8_impl_frame_start(int index){return 15+30*clamp(index,0,11);}", "int m8_impl_frame_start(int index){return 13+27*clamp(index,0,12);}")
    replace_once(root, music, "int m8_impl_frame_index(int frame){return clamp(frame,0,359)/30;}", "int m8_impl_frame_index(int frame){return clamp(frame/27,0,12);}")
    replace_once(root, music, "if(value>12.0f)value=12.0f;\n int frame=(int)(value*30.0f+15.5f);", "if(value>12.0f)value=12.0f;\n int frame=(int)(value*27.0f+13.5f);")
    replace_once(root, music,
                 'return index==11?"TurboFocus":index==10?"TurboWeRead":index==9?"TurboMusic":index==8?"TurboNavigation":index==7?"TurboDisplay":stock_app_id(index);',
                 'return index==12?"TurboCueCards":index==11?"TurboFocus":index==10?"TurboWeRead":index==9?"TurboMusic":index==8?"TurboNavigation":index==7?"TurboDisplay":stock_app_id(index);')
    replace_once(root, music,
                 "if(index==11){if(focus(app)&&focus(app)->label)native_label_text(focus(app)->label,\"番茄时钟\");return;}",
                 "if(index==12){if(slot(app)&&slot(app)->cue_label)native_label_text(slot(app)->cue_label,\"提词卡\");return;}\n  if(index==11){if(focus(app)&&focus(app)->label)native_label_text(focus(app)->label,\"番茄时钟\");return;}")
    replace_once(root, music, "if(focus(app))focus(app)->dot=NULL;stock_delete_dots(app);", "if(focus(app))focus(app)->dot=NULL;if(slot(app))slot(app)->cue_dot=NULL;stock_delete_dots(app);")
    replace_once(root, music,
                 "  TFSlot *f=focus(app);if(!f)return;f->row=tio_lv_obj_create_ex(ptr(app,4),0);if(!f->row)return;\n  clean_style(f->row);tio_lv_obj_set_size(f->row,260,26);native_align(f->row,5,0,-60);hidden(f->row,true);\n  f->label=native_label_create(f->row);if(!f->label)return;clean_style(f->label);native_label_text(f->label,\"番茄时钟\");\n  if(font)menu_text_font(f->label,font,0);native_text_color(f->label,0x00ff00,0);menu_text_align(f->label,2,0);tio_lv_obj_set_size(f->label,260,26);native_align(f->label,9,0,0);",
                 "  TFSlot *f=focus(app);if(!f)return;f->row=tio_lv_obj_create_ex(ptr(app,4),0);if(!f->row)return;\n  clean_style(f->row);tio_lv_obj_set_size(f->row,260,26);native_align(f->row,5,0,-60);hidden(f->row,true);\n  f->label=native_label_create(f->row);if(!f->label)return;clean_style(f->label);native_label_text(f->label,\"番茄时钟\");\n  if(font)menu_text_font(f->label,font,0);native_text_color(f->label,0x00ff00,0);menu_text_align(f->label,2,0);tio_lv_obj_set_size(f->label,260,26);native_align(f->label,9,0,0);\n  TNNavSlot *s=slot(app);if(!s)return;s->cue_row=tio_lv_obj_create_ex(ptr(app,4),0);if(!s->cue_row)return;clean_style(s->cue_row);tio_lv_obj_set_size(s->cue_row,260,26);native_align(s->cue_row,5,0,-60);hidden(s->cue_row,true);s->cue_label=native_label_create(s->cue_row);if(!s->cue_label)return;clean_style(s->cue_label);native_label_text(s->cue_label,\"提词卡\");if(font)menu_text_font(s->cue_label,font,0);native_text_color(s->cue_label,0x00ff00,0);menu_text_align(s->cue_label,2,0);tio_lv_obj_set_size(s->cue_label,260,26);native_align(s->cue_label,9,0,0);")
    replace_once(root, music,
                 "  TFSlot *f=focus(app);if(f&&!f->dot){f->dot=block(parent,4,4,0,0);if(f->dot){native_align(f->dot,0,0,0);tio_lv_obj_set_style_bg_opa(f->dot,127,0);}}",
                 "  TFSlot *f=focus(app);if(f&&!f->dot){f->dot=block(parent,4,4,0,0);if(f->dot){native_align(f->dot,0,0,0);tio_lv_obj_set_style_bg_opa(f->dot,127,0);}}\n  if(s&&!s->cue_dot){s->cue_dot=block(parent,4,4,0,0);if(s->cue_dot){native_align(s->cue_dot,0,0,0);tio_lv_obj_set_style_bg_opa(s->cue_dot,127,0);}}")
    replace_once(root, music,
                 "  const int tomato[][4]={{34,3,15,15},{44,3,10,20},{3,28,8,23},{3,28,54,23},{44,3,10,51},{34,3,15,56},{3,18,31,25},{14,3,31,40},{4,10,30,5},{13,3,22,10},{13,3,32,8}};\n  for(unsigned i=0;i<sizeof tomato/sizeof *tomato;i++)if(!block(f->icon,tomato[i][0],tomato[i][1],tomato[i][2],tomato[i][3])){tio_lv_obj_delete(f->icon);f->icon=NULL;break;}",
                 "  const int tomato[][4]={{34,3,15,15},{44,3,10,20},{3,28,8,23},{3,28,54,23},{44,3,10,51},{34,3,15,56},{3,18,31,25},{14,3,31,40},{4,10,30,5},{13,3,22,10},{13,3,32,8}};\n  for(unsigned i=0;i<sizeof tomato/sizeof *tomato;i++)if(!block(f->icon,tomato[i][0],tomato[i][1],tomato[i][2],tomato[i][3])){tio_lv_obj_delete(f->icon);f->icon=NULL;break;}\n  TNNavSlot *s=slot(app);if(!s)return;s->cue_icon=tio_lv_obj_create_ex(ptr(app,4),0);if(!s->cue_icon)return;clean_style(s->cue_icon);tio_lv_obj_set_size(s->cue_icon,65,65);native_align(s->cue_icon,2,0,52);hidden(s->cue_icon,true);const int cards[][4]={{48,3,8,11},{48,3,8,20},{40,3,17,17},{3,23,16,27},{3,23,22,36},{3,23,28,45}};for(unsigned i=0;i<sizeof cards/sizeof *cards;i++)if(!block(s->cue_icon,cards[i][0],cards[i][1],cards[i][2],cards[i][3])){tio_lv_obj_delete(s->cue_icon);s->cue_icon=NULL;break;}")
    replace_once(root, music, "for(unsigned i=0;i<12;i++){\n    void *row=i==11?", "for(unsigned i=0;i<13;i++){\n    void *row=i==12?(slot(app)?slot(app)->cue_row:NULL):i==11?")
    replace_once(root, music, "if(distance>=30){hidden(row,true);continue;}\n    hidden(row,false);menu_opa(row,(uint8_t)(255*(30-distance)/30),0);", "if(distance>=27){hidden(row,true);continue;}\n    hidden(row,false);menu_opa(row,(uint8_t)(255*(27-distance)/27),0);")
    replace_once(root, music, "for(unsigned i=0;i<12;i++){\n    void *dot=i==11?", "for(unsigned i=0;i<13;i++){\n    void *dot=i==12?(slot(app)?slot(app)->cue_dot:NULL):i==11?")
    replace_once(root, music, "frame=clamp(frame,15,345);", "frame=clamp(frame,m8_impl_frame_start(0),m8_impl_frame_start(12));")
    replace_once(root, music, "int weight=30-clamp(d,0,30);\n    tio_lv_obj_set_size(dot,4+(8*weight+15)/30,4);\n    tio_lv_obj_set_style_bg_opa(dot,(uint8_t)(127+(128*weight+15)/30),0);", "int weight=27-clamp(d,0,27);\n    tio_lv_obj_set_size(dot,4+(8*weight+13)/27,4);\n    tio_lv_obj_set_style_bg_opa(dot,(uint8_t)(127+(128*weight+13)/27),0);")

    replace_once(root, music,
                 "int mix=clamp(frame-195,0,30);\n  menu_lottie_frame(lottie,frame<=195?frame:195);\n  menu_opa(lottie,(uint8_t)(255*(30-mix)/30),0);",
                 "int display_start=m8_impl_frame_start(6);int mix=clamp(frame-display_start,0,27);\n  menu_lottie_frame(lottie,frame<=display_start?frame:display_start);\n  menu_opa(lottie,(uint8_t)(255*(27-mix)/27),0);")
    replace_once(root, music, "int navmix=clamp(frame-225,0,30),picture=mix-navmix;", "int navmix=clamp(frame-m8_impl_frame_start(7),0,27),picture=mix-navmix;")
    replace_once(root, music, "menu_opa(icon,(uint8_t)(255*picture/30),0);menu_translate(icon,55*(30-mix)/30,0);", "menu_opa(icon,(uint8_t)(255*picture/27),0);menu_translate(icon,55*(27-mix)/27,0);")
    replace_once(root, music, "int musicmix=clamp(frame-255,0,30),navweight=navmix-musicmix;", "int musicmix=clamp(frame-m8_impl_frame_start(8),0,27),navweight=navmix-musicmix;")
    replace_once(root, music, "menu_opa(nav,(uint8_t)(255*navweight/30),0);menu_translate(nav,55*(30-navmix)/30,0);", "menu_opa(nav,(uint8_t)(255*navweight/27),0);menu_translate(nav,55*(27-navmix)/27,0);")
    replace_once(root, music, "int readmix=clamp(frame-285,0,30),noteweight=musicmix-readmix;", "int readmix=clamp(frame-m8_impl_frame_start(9),0,27),noteweight=musicmix-readmix;")
    replace_once(root, music, "menu_opa(note,(uint8_t)(255*noteweight/30),0);menu_translate(note,55*(30-musicmix)/30,0);", "menu_opa(note,(uint8_t)(255*noteweight/27),0);menu_translate(note,55*(27-musicmix)/27,0);")
    replace_once(root, music, "int focusmix=clamp(frame-315,0,30),bookweight=readmix-focusmix;", "int focusmix=clamp(frame-m8_impl_frame_start(10),0,27),bookweight=readmix-focusmix;")
    replace_once(root, music, "menu_opa(book,(uint8_t)(255*bookweight/30),0);menu_translate(book,55*(30-readmix)/30,0);", "menu_opa(book,(uint8_t)(255*bookweight/27),0);menu_translate(book,55*(27-readmix)/27,0);")
    replace_once(root, music, "void *tomato=focus(app)?focus(app)->icon:NULL;if(tomato){hidden(tomato,focusmix==0);menu_opa(tomato,(uint8_t)(255*focusmix/30),0);menu_translate(tomato,55*(30-focusmix)/30,0);}", "int cue_mix=clamp(frame-m8_impl_frame_start(11),0,27),tomato_weight=focusmix-cue_mix;void *tomato=focus(app)?focus(app)->icon:NULL;if(tomato){hidden(tomato,tomato_weight==0);menu_opa(tomato,(uint8_t)(255*tomato_weight/27),0);menu_translate(tomato,55*(27-focusmix)/27,0);}\n  void *cue=slot(app)?slot(app)->cue_icon:NULL;if(cue){hidden(cue,cue_mix==0);menu_opa(cue,(uint8_t)(255*cue_mix/27),0);menu_translate(cue,55*(27-cue_mix)/27,0);}")
    replace_once(root, music, "if(index==11){trace(70,tf_slot_open(focus(app)));return true;}", "if(index==12){trace(80,wr_slot_open_cue(reader(app)));return true;}\n  if(index==11){trace(70,tf_slot_open(focus(app)));return true;}")

    replace_once(root, Path("weread-v1/reader.h"), "uint8_t front;bool active,valid,receiving,pending,automatic,dirty,returning;", "uint8_t front;bool active,valid,receiving,pending,automatic,dirty,returning,cue_home;")
    replace_once(root, Path("weread-v1/reader.h"), "void wr_tick(WRReader *,uint32_t);", "bool wr_should_close_for_idle(bool,uint32_t);\nvoid wr_tick(WRReader *,uint32_t);")
    replace_once(root, Path("weread-v1/reader_service.h"), "bool wr_slot_visible(WRSlot *),wr_slot_open(WRSlot *),wr_handle_event(void *);", "bool wr_slot_visible(WRSlot *),wr_slot_open(WRSlot *),wr_slot_open_cue(WRSlot *),wr_handle_event(void *);")

    profile = Path("music-runtime-v1/menu10_profile.py")
    replace_once(root, profile, "(0x1079a2b8,'f1ee087a','f2ee067a','wheel target maximum 6.0 -> 11.0'),", "(0x1079a2b8,'f1ee087a','f2ee087a','wheel target maximum 6.0 -> 12.0'),")
    replace_all(root, profile, "struct.pack('<f',11.4666667)", "struct.pack('<f',12.4666667)", 2)
    replace_once(root, Path("build-image-rx-candidate.py"), "report.update(kind='TFP1-focus-interaction-experimental-candidate',menuProfile='native-twelve-TFP1')", "report.update(kind='TFP1-focus-interaction-experimental-candidate',menuProfile='native-thirteen-TFP1-CUE')\n    report['cueCardsProfile']={'menuIndex':12,'contentKind':3,'waitScreen':True,'deviceVerified':False}")

    replace_once(root, music, "  TNNavSlot *s=slot(app);if(!s)return;s->cue_row=", "  s->cue_row=")
    replace_once(root, music, "  TNNavSlot *s=slot(app);if(!s)return;s->cue_icon=", "  s->cue_icon=")

    print("Applied 13-item cue-card home-menu overlay to candidate source.")


if __name__ == "__main__":
    main()
