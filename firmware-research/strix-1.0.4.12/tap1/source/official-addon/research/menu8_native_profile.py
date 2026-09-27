"""1.0.4.12 AP-only native eight-slot profile. Every patch is version/hash pinned.

The old seven-pointer arrays stay untouched; eighth objects live in the owner
tail. Whole UI methods replace unsafe indexed accesses, rather than writing an
eighth element over the next stock field. No resource-pack/BT/recovery changes.
"""
WRAPPERS=[('names',0x10799dec,4),('dots',0x107998b8,4),
 ('delete_dots',0x10799896,4),('lottie',0x10799c58,4),
 ('app_id',0x10799838,4),('refresh_label',0x10799c1a,4)]
REPLACEMENTS=[('frame_start',0x1079911a,4),('frame_index',0x10799130,4),
 ('label_frame',0x1079a01c,4),('label_index',0x1079a484,4),
 ('indicator',0x10799a44,4),('frame',0x10799d38,4)]
ALIASES={'native_snap':'rayneo::app::launcher::AppListView::snapRawWheelToNearestFrame',
 'menu_remove_styles':'lv_obj_remove_style_all','menu_opa':'lv_obj_set_style_opa',
 'menu_translate':'lv_obj_set_style_translate_x','menu_lottie_frame':'lv_lottie_set_frame',
 'menu_font':('ResourcePool::GetFont',0x107de545),'menu_text_font':'lv_obj_set_style_text_font',
 'menu_text_align':'lv_obj_set_style_text_align'}
# Native spring remains native, with its upper end extended by one whole item.
# Frame render clamp 209 -> 239; resting frame for item 7 is 225.
PATCHES=[
 (0x1079a2b8,'f1ee087a','f1ee0c7a','wheel target maximum 6.0 -> 7.0'),
 (0x107992f0,'efeece40','efeeee40','follow target upper bound 6.4667 -> 7.4667'),
 (0x10799328,'efeece40','efeeee40','spring position upper bound 6.4667 -> 7.4667'),
 (0x10799d90,'d129','ef29','render frame comparison 209 -> 239'),
 (0x10799d94,'d121','ef21','render frame clamp 209 -> 239')]
