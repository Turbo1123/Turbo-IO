"""Adapt the existing real ARM carousel regression to eleven slots.
LVGL objects and feature pages are mocks; native wheel/index code is executed.
"""
from pathlib import Path
source=Path(__file__).resolve().parents[1]/'music-runtime-v1/test_menu10_arm.py'
s=source.read_text()
def change(a,b,n=1):
 global s
 assert s.count(a)==n,(a,s.count(a));s=s.replace(a,b)
change('menu10-native-arm.json','menu11-native-arm.json')
change('native-ten-TDP1-TNV1-TMU1','native-eleven-TDP1-TNV1-TMU1-TWR1')
change('music=[False];SLOT','music=[False];reader=[False];SLOT')
change('MUSIC=SLOT+128','MUSIC=SLOT+128;READER=SLOT+256')
change("for name in ['stock_ctor'", "for name in ['wr_slot_create','wr_slot_destroy','wr_slot_hidden','wr_slot_visible','wr_slot_open','wr_slot_wheel']:calls[syms[name]&~1]=name\n for name in ['stock_ctor'")
change('u.mem_write(SLOT,bytes(28))','u.mem_write(SLOT,bytes(40))')
change("elif name=='tm_slot_create':", "elif name=='wr_slot_create':u.mem_write(READER,bytes(28));ret(READER)\n  elif name=='wr_slot_visible':ret(reader[0])\n  elif name=='wr_slot_open':reader[0]=fail_at!='readerpage';ret(reader[0])\n  elif name in ['wr_slot_destroy','wr_slot_hidden']:reader[0]=False;ret()\n  elif name=='wr_slot_wheel':assert reader[0];ret()\n  elif name=='tm_slot_create':")
change('min(9,n)','min(10,n)');change('min(299,n)','min(329,n)')
change('==10\n','==11\n');change('range(300)','range(330)');change('range(299,-1,-1)','range(329,-1,-1)')
change('for start in range(10):',"selected(9);call(0x1079a310,APP,600);assert word(APP+0x88)==10\n selected(10);call(0x1079a310,APP,-600);assert word(APP+0x88)==9\n for start in range(11):")
change('word(APP+0x88)<=9','word(APP+0x88)<=10')
change('9.46<readfp(APP+0xa8)<9.47','10.46<readfp(APP+0xa8)<10.47')
change("call(0x10799896,APP);assert word(APP+0xe8)==0", "call(0x1079a784,APP);selected(10);call(0x1079a890,APP,0);assert reader[0]==(fail_at!='readerpage')\n if reader[0]:call(0x1079a310,APP,-600);assert word(APP+0x88)==10\n call(0x1079a7b8,APP);assert not reader[0]\n call(0x10799896,APP);assert word(APP+0xe8)==0")
change("if frame==285:","if frame==315:\n    assert objects[word(READER)]['opa']==255 and not objects[word(READER)]['hidden']\n    assert objects[word(READER+8)]['opa']==255 and not objects[word(READER+8)]['hidden']\n    assert objects[word(MUSIC+8)]['hidden']\n    assert objects[word(READER+12)]['size']==(12,4)\n   if frame==285:")
change("'frameSweep':600", "'frameSweep':660,'nativeWheelIndex10':True,'eleventhMenuDistinct':True")
change("Native ten-index ARM offline test","Native eleven-index ARM offline test")
change('range(1,41)','range(1,90)')
change("scenario('musicpage')]","scenario('musicpage'),scenario('readerpage')]")
exec(compile(s,str(source),'exec'),{'__file__':str(source),'__name__':'__main__'})
