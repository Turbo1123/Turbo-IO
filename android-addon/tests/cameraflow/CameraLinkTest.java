package com.turboio.addon;
import java.util.*;

/** TCM1 link: handshake, latest-only frames, chunked delivery, busy retry, budget abort,
 * stale shutter isolation, close, and no resend after a timeout. Port of CameraLinkTests.m. */
public final class CameraLinkTest {
    static int n;static void ok(boolean b,String why){n++;if(!b)throw new AssertionError("camera link "+n+" "+why);}
    static double now=1;static byte[] sent;static int submits;
    static CameraLink link(String peer){return new CameraLink(peer,w->{if(sent!=null)throw new AssertionError("two packets in flight");sent=w;submits++;return true;},()->now);}
    static byte[] raw(byte[] wire){return HexCarrier.unwrap(wire,"TCM:",32,CameraCodec.RAW_MAX);}
    static int op(byte[] wire){return raw(wire)[5]&255;}
    /** Glasses ack for a phone packet: same op/sid/seq/a, given result, no data. */
    static byte[] ack(byte[] wire,int result,long a,long b,long c){byte[] p=Arrays.copyOf(raw(wire),32);p[0]='T';p[1]='C';p[2]='A';p[3]='1';p[6]=(byte)result;
        if(a>=0)HexCarrier.w32(p,16,a);if(b>=0)HexCarrier.w32(p,20,b);if(c>=0)HexCarrier.w32(p,24,c);HexCarrier.w32(p,28,~HexCarrier.crc(p,0,28,0xffffffffL)&0xffffffffL);return HexCarrier.wrap("TCA:",p);}
    static byte[] event(long sid,int op,long seq,long arg,long tick){byte[] p=new byte[32];p[0]='T';p[1]='C';p[2]='A';p[3]='1';p[4]=1;p[5]=(byte)op;HexCarrier.w32(p,8,sid);HexCarrier.w32(p,12,seq);HexCarrier.w32(p,16,arg);HexCarrier.w32(p,20,tick);HexCarrier.w32(p,28,~HexCarrier.crc(p,0,28,0xffffffffL)&0xffffffffL);return HexCarrier.wrap("TCA:",p);}
    static byte[] take(){byte[] s=sent;sent=null;return s;}
    static CameraLink ready(String peer){CameraLink l=link(peer);l.start();byte[] h=take();ok(op(h)==CameraCodec.HELLO,"hello");l.consume(peer,ack(h,CameraCodec.OK,256,144,1));byte[] o=take();ok(o!=null&&op(o)==CameraCodec.OPEN,"open");l.consume(peer,ack(o,CameraCodec.OK,-1,-1,-1));ok(l.ready(),"ready");return l;}
    public static void main(String[] a){
        CameraLink l=link("test");l.start();ok(l.active()&&!l.ready(),"started");byte[] h=take();
        l.consume("wrong-peer",ack(h,CameraCodec.OK,256,144,1));ok(!l.ready()&&sent==null,"foreign hello ignored");
        l.consume("test",ack(h,CameraCodec.OK,256,144,1));byte[] o=take();ok(op(o)==CameraCodec.OPEN,"open sent");l.consume("test",ack(o,CameraCodec.OK,-1,-1,-1));ok(l.ready(),"ready");
        long sid=HexCarrier.u32(raw(o),8);int[] shutters={0};l.action=(op,arg)->{if(op==CameraCodec.SHUTTER)shutters[0]++;};
        l.consume("test",event(sid,CameraCodec.SHUTTER,1,0,0));l.consume("test",event(sid,CameraCodec.SHUTTER,1,0,0));ok(shutters[0]==1,"duplicate event once");
        l.consume("test",event(sid,CameraCodec.SHUTTER,2,0,0xffffffffL-3000));ok(shutters[0]==1,"stale shutter never fires");
        l.consume("test",event(sid^1,CameraCodec.SHUTTER,3,0,0));ok(shutters[0]==1,"other session ignored");
        // Latest-only: a backlog of offers keeps one frame and counts the rest as dropped.
        byte[] gray=new byte[128*72];for(int i=0;i<gray.length;i++)gray[i]=(byte)(i*47);byte[] frame=CameraCodec.compress(CameraCodec.quantize(gray,2));
        for(int i=0;i<1000;i++)l.offer(frame,128,72,2,false);ok(l.dropped()==999,"latest only");
        byte[] got=new byte[frame.length];int framePackets=0;boolean busyOnce=false;
        for(int step=0;step<2000&&l.frames()<1;step++){l.tick();if(sent==null){now+=.025;continue;}byte[] w=take();byte[] r=raw(w);int op=r[5]&255;
            if(op==CameraCodec.BEGIN||op==CameraCodec.CHUNK||op==CameraCodec.COMMIT)framePackets++;
            if(op==CameraCodec.CHUNK)System.arraycopy(r,32,got,(int)HexCarrier.u32(r,16),r.length-32);
            int result=CameraCodec.OK;if(op==CameraCodec.COMMIT&&!busyOnce){busyOnce=true;result=CameraCodec.BUSY;}
            now+=.025;l.consume("test",ack(w,result,-1,-1,-1));}
        ok(l.frames()==1&&Arrays.equals(got,frame),"frame delivered intact");
        ok(framePackets==(frame.length+CameraCodec.DATA_MAX-1)/CameraCodec.DATA_MAX+3,"begin+chunks+commit+one busy retry");
        // Budget: a frame that cannot finish within its window is aborted, not stacked.
        l.offer(frame,128,72,2,false);for(int i=0;i<20&&sent==null;i++){l.tick();if(sent==null)now+=.025;}byte[] b=take();ok(op(b)==CameraCodec.BEGIN,"begin");l.consume("test",ack(b,CameraCodec.OK,-1,-1,-1));
        now+=CameraCodec.budget(128,72,2)+.1;l.tick();byte[] ab=take();ok(ab!=null&&op(ab)==CameraCodec.ABORT,"abort after budget");int dropped=l.dropped();l.consume("test",ack(ab,CameraCodec.OK,-1,-1,-1));ok(l.dropped()==dropped+1,"abort counted");
        // Idle: a ping every 3 s keeps the session alive.
        now+=3.1;l.tick();byte[] p=take();ok(p!=null&&op(p)==CameraCodec.PING,"ping");l.consume("test",ack(p,CameraCodec.OK,-1,-1,-1));
        // Close sends exactly one CLOSE and releases on its ack.
        l.close();ok(sent!=null&&op(sent)==CameraCodec.CLOSE,"close");byte[] c=take();l.tick();ok(sent==null,"single close");l.consume("test",ack(c,CameraCodec.OK,-1,-1,-1));ok(!l.active()&&!l.ready()&&l.closedCleanly(),"closed");
        // A rejected packet stops the preview.
        CameraLink r=ready("test");r.offer(frame,128,72,2,false);for(int i=0;i<20&&sent==null;i++){r.tick();if(sent==null)now+=.025;}byte[] rb=take();r.consume("test",ack(rb,CameraCodec.RENDER,-1,-1,-1));ok(!r.active()&&r.note().contains("拒绝"),"rejected stops");
        // Timeout stops and never resends; a late ack does not revive it.
        CameraLink late=link("test");late.start();byte[] lh=take();int count=submits;now+=4;late.tick();late.tick();ok(!late.active()&&submits==count&&sent==null,"timeout no resend");late.consume("test",ack(lh,CameraCodec.OK,256,144,1));ok(!late.active(),"late ack ignored");
        // Handshake from a receiver with other geometry or a slow answer is refused.
        CameraLink geo=link("test");geo.start();byte[] gh=take();geo.consume("test",ack(gh,CameraCodec.OK,320,180,1));ok(!geo.active()&&sent==null,"geometry refused");
        CameraLink slow=link("test");slow.start();byte[] sh=take();now+=1.5;slow.consume("test",ack(sh,CameraCodec.OK,256,144,1));ok(!slow.active(),"slow hello refused");
        // Unsupported geometry or oversized frames are never offered.
        CameraLink g=ready("test");int before=g.dropped();g.offer(frame,320,180,2,false);g.offer(new byte[CameraCodec.COMP_MAX+1],128,72,2,false);g.offer(frame,128,72,8,false);g.tick();ok(sent==null||op(sent)==CameraCodec.STATE,"bad offers ignored");
        System.out.println("CameraLinkTest: "+n+" checks; handshake, latest-only, chunked frame, busy retry, budget abort, stale shutter, close, no resend");
    }
}
