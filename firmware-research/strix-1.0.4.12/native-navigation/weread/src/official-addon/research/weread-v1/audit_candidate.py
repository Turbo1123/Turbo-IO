"""Independent legacy whitelist audit extended explicitly to menu 11/TWR1."""
from pathlib import Path
base=Path(__file__).resolve().parents[1]/'audit-image-rx-candidate.py'
s=base.read_text()
def change(a,b,n=1):
 global s
 assert s.count(a)==n,(a,s.count(a));s=s.replace(a,b)
change("ROOT=Path(__file__).resolve().parents[2]",f"ROOT=Path({str(Path(__file__).resolve().parents[3])!r})")
change("'TMU1-offline-experimental-candidate'","'TWR1-offline-experimental-candidate'",2)
change('native-ten-TDP1-TNV1-TMU1','native-eleven-TDP1-TNV1-TMU1-TWR1')
change('menu10-native-arm.json','menu11-native-arm.json')
change("len(menu['scenarios'])==44","len(menu['scenarios'])==94")
change("s['nativeWheelIndex9']","s['nativeWheelIndex9'] and s['nativeWheelIndex10'] and s['eleventhMenuDistinct']")
change("'f2ee027a'","'f2ee047a'");change('9.4666667','10.4666667',2)
change("assert len(new)<=0x9f0000", "reader=json.loads((folder/'reader-service-arm.json').read_text())\n assert reader['passed'] and reader['AP']==sha(new) and reader['noHeapLeaks'] and reader['parentDeleteNoDoubleFree']\n opening=json.loads((folder/'reader-open-lifecycle-arm.json').read_text())\n assert opening['passed'] and opening['AP']==sha(new) and opening['noHeapLeaks'] and opening['nestedRootsBeforeLayout'] and opening['busyBeforeCreate'] and opening['busyBeforePaint'] and opening['cancelWhileOpening'] and opening['retryAfterFailure']\n assert len(new)<=0x9f0000")
exec(compile(s,str(base),'exec'),{'__file__':str(base),'__name__':'__main__'})
