"""Stage the public focus-edition with Watch sources; never install or enable OTA.
Run from a full public repository; the input must be official-addon/focus-edition.
This source derivative is NOT the previously installed private build.
"""
from pathlib import Path
import argparse, hashlib, json, shutil

p=argparse.ArgumentParser()
p.add_argument('--base',type=Path,required=True)
p.add_argument('--out',type=Path,required=True)
a=p.parse_args()
root=Path(__file__).resolve().parent
assert not a.out.exists(), 'Use a new staging directory'
shutil.copytree(a.base,a.out,ignore=shutil.ignore_patterns('build','*-verification','__pycache__'))
def replace(name,old,new):
    path=a.out/name
    text=path.read_text()
    assert text.count(old)==1,(name,old)
    path.write_text(text.replace(old,new))
for f in (root/'Addon').iterdir():
    if f.suffix in ('.m','.h'):shutil.copy2(f,a.out/f.name)
for name in ['remote.c','remote.h']:shutil.copy2(root/'Firmware'/name,a.out/name)
replace('build.sh','LocalTranslationEntry.m ExperimentalOTA.m',
        '-framework WatchConnectivity WatchRemoteGate.m WatchGlobalBridge.m remote.c WatchRemoteAddon.m LocalTranslationEntry.m ExperimentalOTA.m')
replace('DisplayPhoneUI.m','#import "DisplayPhoneUI.h"','#import "DisplayPhoneUI.h"\n#import "WatchGlobalBridge.h"')
replace('DisplayPhoneUI.m',' if(TDDiagnosticsConsume(e))return YES;',' if(TIOWatchGlobalConsume(e))return YES;\n if(TDDiagnosticsConsume(e))return YES;')
replace('DisplayPhoneUI.m','if(!TFDecodeReply(event)&&','if(!TIOWatchGlobalIsReply(event)&&!TFDecodeReply(event)&&')
replace('EditorialShell.inc','#include "HeroSequence.inc"',
        '#include "HeroSequence.inc"\n#import "WatchRemoteAddon.h"')
replace('EditorialShell.inc','@[@"研究与诊断",',
        '@[@"手表遥控",@[@"Apple Watch 遥控",@"watchRemote",@"applewatch"]],@[@"研究与诊断",')
replace('EditorialShell.inc','NSDictionary *indexes=@',
        'if([key isEqual:@"watchRemote"]){[self.navigationController pushViewController:TIOWatchRemoteController() animated:YES];return;}NSDictionary *indexes=@')
replace('MusicPlayer.m','- (BOOL)otaIdle{',
        '- (BOOL)watchRemoteAvailable{return _glasses&&_song&&_bridge.active&&!_bridge.busy;}\n- (BOOL)otaIdle{')
def sha(f):return hashlib.sha256(f.read_bytes()).hexdigest()
changed={f.name for f in a.base.iterdir() if f.suffix in ('.m','.h','.inc','.sh','.c') and f.is_file() and sha(f)!=sha(a.out/f.name)}
assert changed=={'build.sh','EditorialShell.inc','MusicPlayer.m','DisplayPhoneUI.m'},changed
record={'base':str(a.base.resolve()),'changed':sorted(changed),
        'sources':{f.name:sha(f) for f in a.out.iterdir() if f.is_file() and f.suffix in ('.m','.h','.inc','.sh','.c')},
        'firmwareChanged':False,'installed':False}
(a.out/'watch-stage.json').write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps({'stage':str(a.out),'changed':record['changed'],'firmwareChanged':False}))
