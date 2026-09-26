"""TAP1 draft developer package: bounded declarative apps, NOT arbitrary JS/HTML.

This module is the host contract and packager, not a device installer. A private
TAX1 phone/AP candidate exists; real hardware acceptance is still pending.
"""
import base64
import binascii
import io
import json
import re
import stat
import zipfile
from .contracts import Fault, canonical, digest, exact, integer

MAX_UNPACKED = 20_480
MAX_ZIP = 24_576
MAX_PIXELS = 32_768


def name(value):
    if not isinstance(value, str) or not re.fullmatch(r'[a-z][a-z0-9_]{0,23}', value):
        raise Fault('app_id', 'IDs must be 1–24 lowercase ASCII identifier characters')


def text(value, limit):
    if not isinstance(value, str) or not value or len(value.encode()) > limit or any(ord(c) < 32 or 127 <= ord(c) <= 159 for c in value):
        raise Fault('app_text', 'Text must be nonempty, bounded UTF-8 without controls')


def _validate_app(doc):
    if len(canonical(doc)) > MAX_UNPACKED:
        raise Fault('app_size', 'App description exceeds 20 KiB')
    exact(doc, ['schema', 'id', 'name', 'version', 'entry', 'permissions', 'pages', 'assets'])
    if type(doc['schema']) is not int or doc['schema'] != 1:
        raise Fault('app_schema', 'Only TAP1 draft schema 1 supported')
    name(doc['id']); text(doc['name'], 48); name(doc['entry']); integer(doc['version'], 1, 65535)
    if not isinstance(doc['permissions'], list) or any(p not in ('backend.events',) for p in doc['permissions']) or len(set(doc['permissions'])) != len(doc['permissions']):
        raise Fault('app_permission', 'Unknown or duplicate permission')
    if not isinstance(doc['pages'], list) or not 1 <= len(doc['pages']) <= 4:
        raise Fault('app_pages', 'Expected 1–4 pages')
    if not isinstance(doc['assets'], dict) or len(doc['assets']) > 8:
        raise Fault('app_assets', 'Expected up to eight monochrome assets')
    for key, asset in doc['assets'].items():
        name(key); exact(asset, ['format', 'width', 'height', 'pixels'])
        integer(asset['width'], 8, 128); integer(asset['height'], 8, 128)
        if asset['format'] != 'mono1-msb' or asset['width'] % 8 or not isinstance(asset['pixels'], str):
            raise Fault('app_asset', 'Expected row-aligned mono1-msb image')
        try:
            raw = base64.b64decode(asset['pixels'], validate=True)
        except (ValueError, binascii.Error):
            raise Fault('app_asset', 'Invalid image encoding') from None
        if len(raw) != asset['width']*asset['height']//8 or base64.b64encode(raw).decode() != asset['pixels']:
            raise Fault('app_asset', 'Image dimensions/encoding mismatch')
    pages, links, count, peak = set(), [], 0, 0
    for page in doc['pages']:
        exact(page, ['id', 'components']); name(page['id'])
        if page['id'] in pages:
            raise Fault('app_page_id', 'Duplicate page ID')
        pages.add(page['id'])
        if not isinstance(page['components'], list) or not 1 <= len(page['components']) <= 12:
            raise Fault('app_components', 'Expected 1–12 components per page')
        ids, pixels = set(), 0
        for c in page['components']:
            if not isinstance(c, dict):
                raise Fault('app_component', 'Component must be an object')
            kind = c.get('kind')
            fields = {'text': ['text', 'font'], 'button': ['text', 'font', 'action'],
                      'progress': ['value'], 'image': ['asset'], 'frame': []}.get(kind)
            if fields is None:
                raise Fault('app_component', 'Unknown component kind')
            exact(c, ['id', 'kind', 'x', 'y', 'w', 'h']+fields); name(c['id'])
            if c['id'] in ids:
                raise Fault('app_component_id', 'Duplicate component ID')
            ids.add(c['id']); count += 1
            for axis, low, high in [('x', 0, 538), ('y', 0, 178), ('w', 2, 540), ('h', 2, 180)]:
                integer(c[axis], low, high)
            if c['x']+c['w'] > 540 or c['y']+c['h'] > 180:
                raise Fault('app_bounds', 'Component outside 540×180 canvas')
            if kind in ('text', 'button'):
                text(c['text'], 96); integer(c['font'], 14, 28)
                if c['font'] not in (14, 16, 18, 20, 24, 28) or c['h'] < c['font']+4:
                    raise Fault('app_font', 'Unsupported font or insufficient height')
            if kind == 'progress':
                integer(c['value'], 0, 100)
            if kind == 'image':
                name(c['asset']); asset = doc['assets'].get(c['asset'])
                if not asset or (c['w'], c['h']) != (asset['width'], asset['height']):
                    raise Fault('app_asset', 'Image requires an existing asset at native dimensions')
                pixels += c['w']*c['h']
            if kind == 'button':
                action = c['action']
                exact(action, ['type', 'target']); text(action['target'], 24)
                if action['type'] == 'page':
                    name(action['target']); links.append(action['target'])
                elif action['type'] == 'emit':
                    name(action['target'])
                    if 'backend.events' not in doc['permissions']:
                        raise Fault('app_permission', 'Backend events require explicit permission')
                elif action['type'] != 'exit' or action['target'] != 'system':
                    raise Fault('app_action', 'Only page, emit and exit actions supported')
        peak = max(peak, pixels)
    if doc['entry'] not in pages or any(link not in pages for link in links):
        raise Fault('app_page_target', 'Entry/action references missing page')
    if peak > MAX_PIXELS:
        raise Fault('app_pixels', 'Decoded image budget exceeds 32 KiB')
    return {'valid': True, 'schema': 'TAP1-draft', 'components': count, 'pages': len(pages),
            'peakImageBytes': peak, 'imageBudgetExcludesLVGLHeap': True,
            'runtimeAvailable': False, 'physicalVerified': False}


def validate_app(doc):
    try:
        return _validate_app(doc)
    except (TypeError, KeyError, UnicodeError, RecursionError, OverflowError):
        raise Fault('app_schema', 'App does not match TAP1 draft schema') from None


def manifest(doc):
    return dict(format='TAP1-draft', id=doc['id'], version=doc['version'],
                entry='app.json', sha256=digest(doc), runtime='TAP1-draft', permissions=doc['permissions'])


def build_package(doc):
    validate_app(doc)
    files = {'app.json': canonical(doc), 'manifest.json': canonical(manifest(doc))}
    if sum(map(len, files.values())) > MAX_UNPACKED:
        raise Fault('app_size', 'Manifest plus app exceeds 20 KiB')
    output = io.BytesIO()
    with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_STORED) as archive:
        for key, data in sorted(files.items()):
            info = zipfile.ZipInfo(key, date_time=(2026, 1, 1, 0, 0, 0))
            info.external_attr = (stat.S_IFREG | 0o600) << 16
            archive.writestr(info, data)
    result = output.getvalue()
    if len(result) > MAX_ZIP:
        raise Fault('zip_limit', 'ZIP exceeds transfer limit')
    return result


def read_package(data):
    if len(data) > MAX_ZIP:
        raise Fault('zip_limit', 'ZIP exceeds transfer limit')
    try:
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            infos = archive.infolist()
            if len(infos) != 2 or {i.filename for i in infos} != {'app.json', 'manifest.json'}:
                raise Fault('zip_members', 'ZIP must contain exactly app.json and manifest.json')
            if sum(i.file_size for i in infos) > MAX_UNPACKED:
                raise Fault('app_size', 'Uncompressed package exceeds 20 KiB')
            files = {}
            for info in infos:
                mode = info.external_attr >> 16
                if info.flag_bits & 1 or stat.S_ISLNK(mode) or (stat.S_IFMT(mode) not in (0, stat.S_IFREG)) or info.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED):
                    raise Fault('zip_type', 'Encrypted, special or unsupported member')
                with archive.open(info) as stream:
                    raw = stream.read(MAX_UNPACKED+1)
                if len(raw) != info.file_size or len(raw) > MAX_UNPACKED:
                    raise Fault('zip_size', 'ZIP member size mismatch')
                value = json.loads(raw)
                if canonical(value) != raw:
                    raise Fault('zip_json', 'Use canonical compiler output; duplicate/noncanonical JSON rejected')
                files[info.filename] = value
        doc = files['app.json']
        budget = validate_app(doc)
        if files['manifest.json'] != manifest(doc):
            raise Fault('manifest', 'Manifest/hash mismatch')
        return {'document': doc, 'manifest': files['manifest.json'], 'budget': budget,
                'unpackedBytes': sum(i.file_size for i in infos), 'zipBytes': len(data)}
    except (ValueError, KeyError, TypeError, UnicodeError, RecursionError, zipfile.BadZipFile, RuntimeError, NotImplementedError, EOFError):
        raise Fault('invalid_package', 'Invalid or corrupt app package') from None


class Simulator:
    """Host-only state model: four slots, one active app. No persistence/firmware claim."""
    def __init__(self):
        self.slots, self.active, self.page, self.focus = {}, None, None, 0

    def install(self, data):
        checked = read_package(data)  # validate before touching existing state
        doc = checked['document']; ident = doc['id']
        if ident not in self.slots and len(self.slots) == 4:
            raise Fault('slots_full', 'At most four apps installed', 409)
        old = self.slots.get(ident)
        if old and doc['version'] <= old['version']:
            raise Fault('version', 'Update must increment app version', 409)
        if self.active == ident:
            self.exit()
        self.slots[ident] = doc

    def start(self, ident):
        if ident not in self.slots:
            raise Fault('not_found', 'App not installed', 404)
        self.active, self.page, self.focus = ident, self.slots[ident]['entry'], 0

    def exit(self):
        self.active, self.page, self.focus = None, None, 0

    def remove(self, ident):
        if self.active == ident:
            self.exit()
        self.slots.pop(ident, None)

    def components(self):
        if self.active is None:
            return []
        return next(p['components'] for p in self.slots[self.active]['pages'] if p['id'] == self.page)

    def event(self, kind):
        if kind == 'long_press':
            self.exit(); return {'type': 'exit'}
        buttons = [c for c in self.components() if c['kind'] == 'button']
        if not buttons:
            return None
        if kind in ('wheel_next', 'wheel_previous'):
            self.focus = (self.focus + (1 if kind == 'wheel_next' else -1)) % len(buttons)
        elif kind == 'short_press':
            action = buttons[self.focus]['action']
            if action['type'] == 'exit':
                self.exit()
            elif action['type'] == 'page':
                self.page, self.focus = action['target'], 0
            return dict(action)
        return None
