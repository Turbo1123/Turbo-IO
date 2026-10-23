"""Offline derivative audit; never reads account state or prints asset contents."""
import hashlib
import json
import sys
import zipfile

source, output = sys.argv[1:3]
extra = {}
if sys.argv[3:] == ['--public-assets']:
    from addon_assets import assets
    from background_manifest import patch as patch_manifest
    extra = assets()
elif sys.argv[3:]:
    raise SystemExit('Unknown asset profile')
with zipfile.ZipFile(source) as original, zipfile.ZipFile(output) as derivative:
    before = {f.filename for f in original.infolist() if not f.is_dir()}
    after = {f.filename for f in derivative.infolist() if not f.is_dir()}
    for archive in (original, derivative):
        names = [f.filename for f in archive.infolist()]
        if len(names) != len(set(names)):
            raise SystemExit('Duplicate ZIP entries')
        if archive.testzip() is not None:
            raise SystemExit('ZIP integrity failed')
    index = 2
    while f'classes{index}.dex' in before:
        index += 1
    # Added DEX must continue the vendor sequence: optional hook DEX, then the addon.
    new_dex = sorted((n for n in after - before if n.startswith('classes') and n.endswith('.dex')), key=lambda n: int(n[7:-4] or 1))
    addon_dex = new_dex if len(new_dex) in (1, 2) and set(new_dex) == {f'classes{i}.dex' for i in range(index, index + len(new_dex))} else []
    removed = sorted(before - after)
    added = sorted(after - before)
    changed = sorted(name for name in before & after
                     if hashlib.sha256(original.read(name)).digest()
                     != hashlib.sha256(derivative.read(name)).digest())
    unexpected = [name for name in removed if not name.startswith('META-INF/')]
    unexpected += [name for name in added if name not in addon_dex and name not in extra and not name.startswith('META-INF/')]
    unexpected += [name for name, path in extra.items() if name not in after or derivative.read(name) != path.read_bytes()]
    expected_manifest = bool(extra) and derivative.read('AndroidManifest.xml') == patch_manifest(original.read('AndroidManifest.xml'))
    unexpected += [name for name in changed if name != 'classes2.dex' and not (name == 'AndroidManifest.xml' and expected_manifest)
                   and not name.startswith('META-INF/')]
    print(json.dumps({'added': added, 'changed': changed, 'removed_signature_entries': len(removed),
                     'resources_native_libraries_preserved': not unexpected,
                     'manifest_only_tts_and_background_added': expected_manifest,
                     'unexpected_paths': unexpected}, ensure_ascii=False))
    raise SystemExit(bool(unexpected))
