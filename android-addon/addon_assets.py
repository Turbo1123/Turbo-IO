"""Explicit public asset allowlist, shared with packager and derivative auditor.

No directory walks: private bootstrap/config files can never be bundled here.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'android-addon/assets/art'
HOME = ROOT / 'android-addon/assets/art'
GALLERY = ROOT / 'app-gallery'

def assets():
    result = {}
    result['assets/turboio/reader/demo-7392.txt'] = ROOT / 'android-addon/assets/reader-demo-7392.txt'
    result['assets/turboio/licenses/music-mit.txt'] = ROOT / 'android-addon/THIRD_PARTY_MUSIC_LICENSE.txt'
    for name in ('hero-glass-v5','hero-sequence-v5','music','reading','navigation',
                 'focus','focus-tomato-v2','news','settings'):
        result[f'assets/turboio/art/{name}.png'] = ART / f'{name}.png'
    for name in ('dashboard-editor','app-gallery'):
        result[f'assets/turboio/art/{name}.png'] = HOME / f'{name}.png'
    result['assets/turboio/gallery/catalog.json'] = GALLERY / 'catalog.json'
    result['assets/turboio/card.schema.json'] = ROOT / 'android-addon/assets/card.schema.json'
    catalog = json.loads((GALLERY / 'catalog.json').read_text())
    import hashlib
    if len(catalog['entries']) != 20:
        raise ValueError('Expected reviewed 20-template catalog')
    for item in catalog['entries']:
        name = item['resource']
        import re
        if not re.fullmatch(r'Gallery_[a-z_]+', name):
            raise ValueError('Unsafe resource path')
        path = GALLERY / (name + '.zip')
        if hashlib.sha256(path.read_bytes()).hexdigest() != item['sha256']:
            raise ValueError('Catalog/package digest mismatch')
        result[f'assets/turboio/gallery/{name}.zip'] = path
    if sum(p.stat().st_size for p in result.values()) > 24 * 1024 * 1024:
        raise ValueError('Asset budget exceeded')
    return result
