"""Add one package-visibility intent to binary AXML without rebuilding resources.

Preserve every original string index and XML node. No permissions/components are
added. Re-applying is idempotent; malformed input fails closed.
"""
import struct

ACTION = 'android.intent.action.TTS_SERVICE'
NS = 'http://schemas.android.com/apk/res/android'
U = 0xffffffff

def patch(data):
    def u16(b, p): return struct.unpack_from('<H', b, p)[0]
    def u32(b, p): return struct.unpack_from('<I', b, p)[0]
    if len(data) < 8 or u16(data, 0) != 3 or u16(data, 2) != 8 or u32(data, 4) != len(data):
        raise ValueError('Not binary manifest XML')
    chunks = []
    at = 8
    while at < len(data):
        size = u32(data, at + 4)
        if size < 8 or at + size > len(data): raise ValueError('Invalid XML chunk')
        chunks.append(data[at:at+size]); at += size
    pools = [i for i, c in enumerate(chunks) if u16(c, 0) == 1]
    if len(pools) != 1: raise ValueError('String pool count')
    pi = pools[0]; p = chunks[pi]
    if u16(p, 2) != 28: raise ValueError('String pool header')
    count, styles, flags, start, style_start = struct.unpack_from('<IIIII', p, 8)
    if styles or style_start: raise ValueError('Styled manifest pool unsupported')
    utf8 = bool(flags & 0x100)
    def length(pos):
        if utf8:
            n = p[pos]; pos += 1
            if n & 128: n = ((n & 127) << 8) | p[pos]; pos += 1
        else:
            n = u16(p, pos); pos += 2
            if n & 0x8000: n = ((n & 0x7fff) << 16) | u16(p, pos); pos += 2
        return n, pos
    strings = []
    for i in range(count):
        pos = start + u32(p, 28+4*i)
        n, pos = length(pos)
        if utf8: n, pos = length(pos)
        strings.append(p[pos:pos+n*(1 if utf8 else 2)].decode('utf-8' if utf8 else 'utf-16le'))
    if ACTION in strings: return data
    for s in ('queries', 'intent', 'action', 'name', NS):
        if s not in strings: raise ValueError('Expected existing manifest vocabulary missing')
    idx = {s: strings.index(s) for s in ('queries', 'intent', 'action', 'name', NS)}
    # The name resource ID must remain the original framework android:name.
    maps = [c for c in chunks if u16(c,0) == 0x180]
    if len(maps) != 1 or 8+4*idx['name']+4 > len(maps[0]) or u32(maps[0],8+4*idx['name']) != 0x01010003:
        raise ValueError('android:name resource mapping missing')
    raw = p[start:]
    enc = (bytes([len(ACTION),len(ACTION)])+ACTION.encode()+b'\0') if utf8 else (struct.pack('<H',len(ACTION))+ACTION.encode('utf-16le')+b'\0\0')
    new_raw = raw+enc
    new_raw += b'\0' * (-len(new_raw)%4)
    new_start = start+4
    size = new_start+len(new_raw)
    head = struct.pack('<HHIIIIII',1,28,size,count+1,0,flags & ~1,new_start,0)
    chunks[pi] = head+p[28:start]+struct.pack('<I',len(raw))+new_raw
    def begin(name, attr=False):
        attrs = struct.pack('<IIIHBBI',idx[NS],idx['name'],count,8,0,3,count) if attr else b''
        return struct.pack('<HHIII',0x102,16,36+len(attrs),0,U)+struct.pack('<IIHHHHHH',U,idx[name],20,20,int(attr),0,0,0)+attrs
    def end(name): return struct.pack('<HHIIIII',0x103,16,24,0,U,U,idx[name])
    stack=[]; insertion=None
    for i,c in enumerate(chunks):
        if u16(c,0)==0x102: stack.append(u32(c,20))
        elif u16(c,0)==0x103:
            n=u32(c,20)
            if not stack or stack.pop()!=n: raise ValueError('XML nesting mismatch')
            if n==idx['queries']:
                if insertion is not None: raise ValueError('Multiple queries nodes')
                insertion=i
    if stack or insertion is None: raise ValueError('Missing queries node')
    chunks[insertion:insertion] = [begin('intent'),begin('action',True),end('action'),end('intent')]
    body=b''.join(chunks)
    return struct.pack('<HHI',3,8,len(body)+8)+body
