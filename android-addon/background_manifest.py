"""Narrow additive AXML patch: own non-exported foreground service + media permission.
No original XML nodes, resource IDs or string indices are rewritten.
"""
import struct
from tts_manifest import patch as tts_patch, NS, U
SERVICE='com.turboio.addon.BackgroundWork'
OTA_SERVICE='com.turboio.addon.OtaService'
PERMISSION='android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK'
def patch(data):
    data=tts_patch(data)
    u16=lambda b,p:struct.unpack_from('<H',b,p)[0]
    u32=lambda b,p:struct.unpack_from('<I',b,p)[0]
    chunks=[];at=8
    while at<len(data):
        n=u32(data,at+4)
        if n<8 or at+n>len(data):raise ValueError('chunk')
        chunks.append(data[at:at+n]);at+=n
    pi=next(i for i,c in enumerate(chunks) if u16(c,0)==1);p=chunks[pi]
    count,styles,flags,start,style_start=struct.unpack_from('<IIIII',p,8)
    if styles or style_start:raise ValueError('style')
    utf=bool(flags&256)
    def length(pos):
        n=p[pos] if utf else u16(p,pos);pos+=1 if utf else 2
        high=128 if utf else 32768
        if n&high:n=((n&(high-1))<<(8 if utf else 16))|(p[pos] if utf else u16(p,pos));pos+=1 if utf else 2
        return n,pos
    ss=[]
    for i in range(count):
        pos=start+u32(p,28+i*4);n,pos=length(pos)
        if utf:n,pos=length(pos)
        ss.append(p[pos:pos+n*(1 if utf else 2)].decode('utf-8' if utf else 'utf-16le'))
    if SERVICE in ss:
        if OTA_SERVICE not in ss:raise ValueError('partial old patch; rebuild from original APK')
        return data
    required=['manifest','application','service','uses-permission','name','exported','foregroundServiceType',NS]
    if any(x not in ss for x in required):raise ValueError('missing host vocabulary')
    idx={s:ss.index(s) for s in required};raw=p[start:];offsets=[]
    for s in [SERVICE,PERMISSION,OTA_SERVICE]:
        idx[s]=len(ss);ss.append(s);offsets.append(len(raw))
        raw+=(bytes([len(s),len(s)])+s.encode()+b'\0') if utf else struct.pack('<H',len(s))+s.encode('utf-16le')+b'\0\0'
    raw+=b'\0'*(-len(raw)%4);new_start=start+12
    chunks[pi]=struct.pack('<HHIIIIII',1,28,new_start+len(raw),count+3,0,flags&~1,new_start,0)+p[28:start]+struct.pack('<III',*offsets)+raw
    rm=next(c for c in chunks if u16(c,0)==0x180)
    def rid(n):
        at=8+4*idx[n]
        if at+4>len(rm):raise ValueError('attribute resource mapping')
        return u32(rm,at)
    if rid('name')!=0x01010003 or rid('exported')!=0x01010010:raise ValueError('attribute mapping')
    def begin(name,attrs):
        a=b''
        for n,t,v in sorted(attrs,key=lambda x:rid(x[0])):
            a+=struct.pack('<IIIHBBI',idx[NS],idx[n],v if t==3 else U,8,0,t,v)
        return struct.pack('<HHIII',0x102,16,36+len(a),0,U)+struct.pack('<IIHHHHHH',U,idx[name],20,20,len(attrs),0,0,0)+a
    def end(name):return struct.pack('<HHIIIII',0x103,16,24,0,U,U,idx[name])
    out=[];added_permission=False;added_service=False
    for c in chunks:
        if u16(c,0)==0x102 and u32(c,20)==idx['application']:
            if added_permission:raise ValueError('multiple application')
            out += [begin('uses-permission',[('name',3,idx[PERMISSION])]),end('uses-permission')];added_permission=True
        if u16(c,0)==0x103 and u32(c,20)==idx['application']:
            out += [begin('service',[('name',3,idx[SERVICE]),('exported',18,0),('foregroundServiceType',17,154)]),end('service')];added_service=True
            out += [begin('service',[('name',3,idx[OTA_SERVICE]),('exported',18,0),('foregroundServiceType',17,16)]),end('service')]
        out.append(c)
    if not added_permission or not added_service:raise ValueError('missing application')
    b=b''.join(out);return struct.pack('<HHI',3,8,len(b)+8)+b
