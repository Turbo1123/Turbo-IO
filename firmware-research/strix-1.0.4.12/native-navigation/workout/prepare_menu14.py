"""Add workout menu only to a fresh, already prepared TWK1 candidate."""
import argparse
import re
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / 'cue-cards'))
from prepare_menu13 import replace_once, replace_all


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    root = parser.parse_args().source.resolve()
    def one(path, old, new): replace_once(root, Path(path), old, new)
    def many(path, old, new, count): replace_all(root, Path(path), old, new, count)
    nav = 'navigation-runtime-v1/nav_service.h'
    native = 'focus-v1/focus_menu_native.c'
    focus = 'focus-v1/focus_menu.c'
    music = 'music-runtime-v1/menu10.c'
    one(nav, ' void *cue_row,*cue_label,*cue_icon,*cue_dot;', ' void *cue_row,*cue_label,*cue_icon,*cue_dot;\n void *workout_row,*workout_label,*workout_icon,*workout_dot;')
    one(nav, '} TNNavSlot;', '} TNNavSlot;\nbool tw_slot_open(TNNavSlot *);')
    one(native, 'sizeof(TNNavSlot)==64', 'sizeof(TNNavSlot)==80')
    one(native, 'index>=13', 'index>=14')
    one(native, 's?s->cue_icon:NULL};', 's?s->cue_icon:NULL,s?s->workout_row:NULL,s?s->workout_icon:NULL};')
    one(focus, '"提词卡"};', '"提词卡","运动看板"};')
    one(focus, 'selected>=13', 'selected>=14')
    many(focus, 'index<13', 'index<14', 2)
    one(focus, ' case 12:box', ' case 13:line(p,32,53,9,30,g);line(p,9,30,9,19,g);line(p,9,19,17,11,g);line(p,17,11,25,11,g);line(p,25,11,32,19,g);line(p,32,19,39,11,g);line(p,39,11,47,11,g);line(p,47,11,55,19,g);line(p,55,19,55,30,g);line(p,55,30,32,53,g);line(p,15,31,24,31,g);line(p,24,31,28,24,g);line(p,28,24,34,39,g);line(p,34,39,39,31,g);line(p,39,31,48,31,g);break;\n case 12:box')

    one(music, '13+27*clamp(index,0,12)', '12+25*clamp(index,0,13)')
    one(music, 'clamp(frame/27,0,12)', 'clamp(frame/25,0,13)')
    one(music, 'if(value>12.0f)value=12.0f;', 'if(value>13.0f)value=13.0f;')
    one(music, 'value*27.0f+13.5f', 'value*25.0f+12.5f')
    one(music, 'return index==12?"TurboCueCards"', 'return index==13?"TurboWorkout":index==12?"TurboCueCards"')
    one(music, '  if(index==12){if(slot', '  if(index==13){if(slot(app)&&slot(app)->workout_label)native_label_text(slot(app)->workout_label,"运动看板");return;}\n  if(index==12){if(slot')
    one(music, 'slot(app)->cue_dot=NULL;stock_delete_dots(app);', 'slot(app)->cue_dot=NULL;if(slot(app))slot(app)->workout_dot=NULL;stock_delete_dots(app);')
    # Retain separate pointers; never grow or overwrite the stock app allocation.
    path = root / music
    text = path.read_text()
    for marker, following in [('  s->cue_row=', '\n}'), ('  if(s&&!s->cue_dot)', '\n}'), ('  s->cue_icon=', '\n}')]:
        begin = text.index(marker)
        end = text.index(following, begin)
        original = text[begin:end]
        added = original.replace('cue_', 'workout_').replace('提词卡', '运动看板')
        if 'cue_icon' in original:
            start = added.index('const int cards[][4]=')
            stop = added.index(';for(unsigned', start)
            added = added[:start] + 'const int cards[][4]={{15,4,9,12},{15,4,40,12},{4,20,7,16},{4,20,54,16},{9,4,24,17},{9,4,32,17},{8,5,11,35},{8,5,18,41},{8,5,25,47},{8,5,32,47},{8,5,39,41},{8,5,46,35}}' + added[stop:]
            added = added.replace('cards', 'heart')
        text = text[:end] + '\n' + added + text[end:]
    path.write_text(text)
    many(music, 'i<13;i++', 'i<14;i++', 2)
    one(music, 'void *row=i==12?', 'void *row=i==13?(slot(app)?slot(app)->workout_row:NULL):i==12?')
    one(music, 'void *dot=i==12?', 'void *dot=i==13?(slot(app)?slot(app)->workout_dot:NULL):i==12?')
    one(music, 'm8_impl_frame_start(12));', 'm8_impl_frame_start(13));')
    one(music, 'menu_translate(row,-55*d/30,0);', 'menu_translate(row,-55*d/25,0);')
    # Only this animation section uses 27 as the carousel step, not glyph coordinates.
    text = path.read_text(); begin = text.index('void m8_hook_label_frame'); end = text.index('\nvoid ', text.index('bool m8_hook_frame', begin))
    section = text[begin:end]
    assert len(re.findall(r'\b27\b', section)) == 33
    section = re.sub(r'\b27\b', '25', section).replace('8*weight+13', '8*weight+12').replace('128*weight+13', '128*weight+12')
    text = text[:begin] + section + text[end:];path.write_text(text)
    one(music, 'void *cue=slot(app)?slot(app)->cue_icon:NULL;if(cue){hidden(cue,cue_mix==0);menu_opa(cue,(uint8_t)(255*cue_mix/25),0);menu_translate(cue,55*(25-cue_mix)/25,0);}',
        'int workout_mix=clamp(frame-m8_impl_frame_start(12),0,25),cue_weight=cue_mix-workout_mix;void *cue=slot(app)?slot(app)->cue_icon:NULL;if(cue){hidden(cue,cue_weight==0);menu_opa(cue,(uint8_t)(255*cue_weight/25),0);menu_translate(cue,55*(25-cue_mix)/25,0);}\n  void *workout=slot(app)?slot(app)->workout_icon:NULL;if(workout){hidden(workout,workout_mix==0);menu_opa(workout,(uint8_t)(255*workout_mix/25),0);menu_translate(workout,55*(25-workout_mix)/25,0);}')
    one(music, 'if(index==12){trace(80,', 'if(index==13){trace(90,tw_slot_open(slot(app)));return true;}\n  if(index==12){trace(80,')
    profile = 'music-runtime-v1/menu10_profile.py'
    one(profile, "'f2ee087a','wheel target maximum 6.0 -> 12.0'", "'f2ee0a7a','wheel target maximum 6.0 -> 13.0'")
    many(profile, "struct.pack('<f',12.4666667)", "struct.pack('<f',13.4666667)", 2)
    one('build-image-rx-candidate.py', "menuProfile='native-thirteen-TFP1-CUE'", "menuProfile='native-fourteen-TFP1-CUE-TWK1'")

    print('Applied separate 14-item menu with heart icon and bounded wheel.')


if __name__ == '__main__': main()
