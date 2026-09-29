"""Create an OFFLINE full-tree derivative. Never install/flash. No extra hooks."""
from pathlib import Path
import argparse, shutil, hashlib, json
p=argparse.ArgumentParser();p.add_argument('--base',type=Path,required=True);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
assert not a.out.exists()
root=Path(__file__).resolve().parent
shutil.copytree(a.base,a.out,ignore=shutil.ignore_patterns('__pycache__'))
src=a.out/'official-addon/research';dst=src/'global-remote-v1';assert not dst.exists();shutil.copytree(root/'Firmware',dst)
def replace(path,old,new):
 text=path.read_text();assert text.count(old)==1,(str(path),old);path.write_text(text.replace(old,new))
replace(src/'music-runtime-v1/menu10.c','void m8_hook_message(void *handler,const TIONativeMessage *message){',
 'extern void tgr_native_message(const TIONativeMessage *);\nvoid m8_hook_message(void *handler,const TIONativeMessage *message){\n  tgr_native_message(message); /* borrowed bytes; stock handler still disposes */')
aliases={
 'tgr_indev_next':('lv_indev_get_next',0x10661da9),
 'tgr_indev_type':('lv_indev_get_type',0x10661e15),
 'tgr_indev_group':('lv_indev_get_group',0x10661e29),
 'tgr_indev_driver':('lv_indev_get_driver_data',0x10661e35),
 'tgr_intercept':('lv_intercept_input_data',0x10746a69),
 'tgr_group_send':('lv_group_send_data',0x106548d9),
 'tgr_raw_wheel':('lv_rayneo_input_notify_raw_wheel_data',0x10746d8d),
 'tgr_sim_wheel':('sim_wheel_event',0x10820bc1),
 'tgr_ota_status':('rayneo::service::launcher::SysStateMonitor::getOtaStatus',0x106dc675),
}
replace(src/'build-image-rx-candidate.py','ALIASES={','ALIASES={\n'+''.join(f' {k!r}: {v!r},\n' for k,v in aliases.items()))
replace(src/'build-image-rx-candidate.py','    animation_units=[]',"    units+=['global-remote-v1/remote','global-remote-v1/remote_native']\n    animation_units=[]")
def sha(f):return hashlib.sha256(f.read_bytes()).hexdigest()
changed=[str(f.relative_to(a.out)) for f in a.out.rglob('*') if f.is_file() and (a.base/f.relative_to(a.out)).is_file() and sha(f)!=sha(a.base/f.relative_to(a.out))]
assert sorted(changed)==['official-addon/research/build-image-rx-candidate.py','official-addon/research/music-runtime-v1/menu10.c']
record={'base':str(a.base.resolve()),'changed':changed,'aliases':aliases,'sources':{f.name:sha(f) for f in dst.iterdir()},'flashed':False,'extraBinaryHooks':0}
(a.out/'global-remote-stage.json').write_text(json.dumps(record,indent=2)+'\n');print(json.dumps(record))
