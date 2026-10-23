"""Preserve original ZIP payloads; replace only the reviewed hook DEX and add ours.

Never round-trip vendor resources through a case-insensitive filesystem: res/A.xml
and res/a.xml are different ZIP members even on macOS. Signing happens separately.
"""
import pathlib
import re
import sys
import zipfile

source, assembled, addon, destination = map(pathlib.Path, sys.argv[1:5])
extra = {}

def addon_dex_name(names):
    # 1.0.4/1.0.5 ship three DEX files; 1.0.6 already ships classes4.dex.
    index = 2
    while f'classes{index}.dex' in names:
        index += 1
    if index < 4:
        raise SystemExit('Unexpected host DEX layout')
    return f'classes{index}.dex'

if sys.argv[5:] == ['--public-assets']:
    from addon_assets import assets
    from background_manifest import patch as patch_manifest
    extra = assets()
elif sys.argv[5:]:
    raise SystemExit('Unknown asset profile')
if destination.resolve() in {source.resolve(), assembled.resolve(), addon.resolve()}:
    raise SystemExit('Output must not overwrite input')
temporary = destination.with_suffix('.assembling.apk')
if temporary.exists():
    raise SystemExit('Temporary output exists; inspect before retrying')
with zipfile.ZipFile(source) as original, zipfile.ZipFile(assembled) as modified:
    # Hook-only DEX files apktool emitted beyond the vendor set (1.0.6 64K split).
    hook_dex = sorted((n for n in modified.namelist() if re.fullmatch(r'classes\d+\.dex', n) and n not in original.namelist()),
                      key=lambda n: int(n[7:-4]))
    addon_name = addon_dex_name(original.namelist() + hook_dex)
    if len(original.namelist()) != len(set(original.namelist())):
        raise SystemExit('Duplicate original ZIP members')
    if set(extra) & set(original.namelist()):
        raise SystemExit('Addon asset collision')
    patched = modified.read('classes2.dex')
    if not patched.startswith(b'dex\n') or not addon.read_bytes().startswith(b'dex\n'):
        raise SystemExit('Invalid DEX input')
    with zipfile.ZipFile(temporary, 'x', allowZip64=True) as output:
        for info in original.infolist():
            if re.fullmatch(r'META-INF/(?:MANIFEST\.MF|[^/]+\.(?:SF|RSA|DSA|EC))', info.filename, re.I):
                continue
            content = patched if info.filename == 'classes2.dex' else original.read(info)
            if extra and info.filename == 'AndroidManifest.xml': content = patch_manifest(content)
            output.writestr(info, content)
        for name in hook_dex:
            data = modified.read(name)
            if not data.startswith(b'dex\n'):
                raise SystemExit('Invalid hook DEX')
            info = zipfile.ZipInfo(name, (2026, 9, 26, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            output.writestr(info, data)
        info = zipfile.ZipInfo(addon_name, (2026, 9, 26, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = 0o100644 << 16
        output.writestr(info, addon.read_bytes())
        for name, path in sorted(extra.items()):
            info = zipfile.ZipInfo(name, (2026, 9, 26, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            output.writestr(info, path.read_bytes())
temporary.replace(destination)
print('Original resource/native payloads retained; hook DEX, addon DEX/assets and scoped TTS/background manifest additions reviewed.')
