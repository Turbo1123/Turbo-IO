package com.turboio.addon;
import java.io.*;import java.util.*;

/** HdLink (port of tar2-display TVPHDLink) against the unchanged TVP2 vp_hd behind a native.inc emulation. */
public final class HdLinkTest {
    static int n;static void ok(boolean b,String why){n++;if(!b)throw new AssertionError("link "+n+" "+why);}
    static String oracle;
    static final class Glasses implements Closeable{
        final Process p;final DataOutputStream out;final DataInputStream in;long crc,displayed;
        Glasses(boolean old)throws IOException{p=(old?new ProcessBuilder(oracle,"old"):new ProcessBuilder(oracle)).start();out=new DataOutputStream(p.getOutputStream());in=new DataInputStream(p.getInputStream());}
        void le(long v)throws IOException{for(int i=0;i<4;i++)out.write((int)(v>>(8*i))&255);}
        long rle()throws IOException{long v=0;for(int i=0;i<4;i++)v|=(long)in.readUnsignedByte()<<(8*i);return v;}
        byte[] handle(byte[] packet,double now)throws IOException{le((long)(now*1000));le(packet.length);out.write(packet);out.flush();int k=(int)rle();byte[] r=new byte[k];in.readFully(r);crc=rle();displayed=rle();return k==0?null:r;}
        void pause(boolean on)throws IOException{handle(new byte[]{(byte)(on?'P':'R')},0);}
        public void close(){p.destroy();}
    }
    static final class Rig{double now=10;final List<byte[]> out=new ArrayList<>();final HdLink link=new HdLink("eye",w->{out.add(w);return true;},()->now);byte[] last(){return out.get(out.size()-1);}}
    static byte[] plane(int w,int h){byte[] b=new byte[w*h];for(int y=0;y<h;y++)for(int x=0;x<w;x++)b[y*w+x]=(byte)(x*17+y*31+(x%13)*19);return b;}
    static byte[] event(long sid,long seq,int op,long a){Vp.Packet q=new Vp.Packet();q.op=op;q.sid=sid;q.seq=seq;q.a=a;return Vp.encode(q,true);}
    /** Answer whatever the link sent last, until it stops sending. Returns packets answered. */
    static int pump(Rig r,Glasses g,int limit)throws IOException{int k=0;while(k<limit){int before=r.out.size();byte[] reply=g.handle(r.last(),r.now);k++;r.now+=.05;if(reply!=null)r.link.consume("eye",reply);if(r.out.size()==before)break;}return k;}
    public static void main(String[] a)throws Exception{
        oracle=a[0];
        HdEncoder.Frame crop=HdEncoder.encodeForLane(plane(400,1000),400,1000,400,false,8,false,2,.5,.5);ok(crop!=null,"frame");
        try(Glasses g=new Glasses(false)){Rig r=new Rig();HdLink l=r.link;
            l.start();Vp.Packet q=Vp.decode(r.last(),false);ok(q.op==Vp.HELLO&&q.a==Vp.HD_CAP,"hello with HD capability");
            byte[] hello=g.handle(r.last(),r.now);ok(!l.consume("other",hello)||!l.ready(),"foreign peer");ok(!l.ready()&&r.out.size()==1,"foreign peer ignored");
            l.consume("eye",hello);ok(Vp.decode(r.last(),false).op==Vp.OPEN,"open follows hello");l.consume("eye",g.handle(r.last(),r.now));ok(l.ready()&&!l.busy(),"ready");
            ok(l.offer(crop),"offer");int sent=r.out.size();int k=pump(r,g,20);
            ok(r.out.size()-sent==5&&l.frames()==1&&l.verifiedBytes()==crop.compressedBytes&&l.receivedBytes()==crop.compressedBytes&&!l.busy(),"6 packets for one frame ("+k+")");
            ok(g.displayed==1&&g.crc==Vp.pixelsCrc(pad(crop.gray),544),"glasses show exactly the encoded frame");
            // Foreign sid and stale replies are ignored.
            Vp.Packet bogus=new Vp.Packet();bogus.op=Vp.PING;bogus.sid=(l.sid()+1)&0xffffffffL;if(bogus.sid==0)bogus.sid=1;bogus.seq=99;ok(l.consume("eye",Vp.encode(bogus,true))&&l.active(),"foreign sid ignored");
            // PING after 2 s idle, answered by the glasses.
            r.now+=2.1;int before=r.out.size();l.tick();ok(r.out.size()==before+1&&Vp.decode(r.last(),false).op==Vp.PING,"ping when idle");l.consume("eye",g.handle(r.last(),r.now));ok(l.active()&&!l.busy(),"ping ok");
            // BUSY on a strip drops the frame and counts it.
            ok(l.offer(crop),"second frame");l.consume("eye",g.handle(r.last(),r.now));g.pause(true);l.consume("eye",g.handle(r.last(),r.now));
            ok(!l.busy()&&l.rejectedFrames()==1&&l.active()&&l.frames()==1,"busy strip drops frame");g.pause(false);
            l.close();ok(Vp.decode(r.last(),false).op==Vp.CLOSE,"close");l.consume("eye",g.handle(r.last(),r.now));ok(l.closedCleanly()&&!l.active(),"closed cleanly");
        }
        try(Glasses g=new Glasses(true)){Rig r=new Rig();r.link.start();r.link.consume("eye",g.handle(r.last(),r.now));ok(!r.link.active()&&r.link.closedCleanly()&&r.out.size()==1&&r.link.note().startsWith("需要先刷 TVP2"),"old firmware: no OPEN");}
        { Rig r=new Rig();r.link.start();r.now+=3.1;r.link.tick();ok(!r.link.active()&&r.out.size()==1&&!r.link.closedCleanly(),"3 s timeout"); }
        try(Glasses g=new Glasses(false)){Rig r=new Rig();HdLink l=r.link;l.start();l.consume("eye",g.handle(r.last(),r.now));l.consume("eye",g.handle(r.last(),r.now));ok(l.ready()&&l.offer(crop),"pause rig");
            byte[] beginReply=g.handle(r.last(),r.now);l.consume("eye",event(l.sid(),1,Vp.PAUSE,1));l.consume("eye",beginReply);
            ok(l.paused()&&!l.busy()&&l.frames()==0,"pause drops frame");int k=r.out.size();l.tick();ok(r.out.size()==k&&!l.offer(crop),"paused: nothing sent");
            l.consume("eye",event(l.sid(),1,Vp.PAUSE,0));ok(l.paused(),"stale event ignored");
            l.consume("eye",event(l.sid(),2,Vp.PAUSE,0));ok(!l.paused()&&l.offer(crop),"resume");
            byte[] reply=g.handle(r.last(),r.now);reply[16]^=1;HdLinkTest.resealReply(reply);l.consume("eye",reply);ok(!l.active()&&!l.closedCleanly(),"mismatched begin reply stops");
        }
        try(Glasses g=new Glasses(false)){Rig r=new Rig();HdLink l=r.link;l.start();l.consume("eye",g.handle(r.last(),r.now));l.consume("eye",g.handle(r.last(),r.now));ok(l.offer(crop),"late rig");
            byte[] reply=g.handle(r.last(),r.now);r.now+=3.1;l.consume("eye",reply);ok(!l.active(),"late reply never resumes");int k=r.out.size();l.tick();ok(r.out.size()==k,"nothing after late reply");
        }
        try(Glasses g=new Glasses(false)){Rig r=new Rig();HdLink l=r.link;l.start();l.consume("eye",g.handle(r.last(),r.now));l.consume("eye",g.handle(r.last(),r.now));
            l.consume("eye",event(l.sid(),1,Vp.EXIT,0));ok(!l.active()&&l.closedCleanly(),"glasses exit stops");
        }
        try(Glasses g=new Glasses(false)){HdEncoder.Frame huge=HdEncoder.encode(noise(),540,220,540,false,16,true,1,.5,.5);Rig q=new Rig();q.link.start();q.link.consume("eye",g.handle(q.last(),q.now));q.link.consume("eye",g.handle(q.last(),q.now));
            ok(q.link.ready()&&!q.link.offer(huge)&&!q.link.busy(),"over-lane frame refused while ready");}
        try(Glasses g=new Glasses(false)){Rig r=new Rig();HdLink l=r.link;l.start();l.consume("eye",g.handle(r.last(),r.now));l.consume("eye",g.handle(r.last(),r.now));ok(l.offer(crop),"strip rig");
            l.consume("eye",g.handle(r.last(),r.now));byte[] reply=g.handle(r.last(),r.now);reply[24]^=1;resealReply(reply);l.consume("eye",reply);ok(!l.active()&&l.note().startsWith("分块累计"),"strip byte count mismatch stops");}
        try(Glasses g=new Glasses(false)){Rig r=new Rig();r.link.start();byte[] hello=g.handle(r.last(),r.now);r.now+=1.5;r.link.consume("eye",hello);ok(!r.link.active()&&r.out.size()==1,"HELLO answered after 1 s never opens");}
        System.out.println("HdLinkTest: "+n+" checks; handshake, 6-packet frame shown pixel-exact by vp_hd, ping, busy drop, close, old firmware, timeouts, pause/exit, mismatches, lane");
    }
    static byte[] noise(){byte[] b=new byte[540*220];long s=1;for(int i=0;i<b.length;i++){s=s*6364136223846793005L+1442695040888963407L;b[i]=(byte)(s>>>56);}return b;}
    static byte[] pad(byte[] gray){byte[] p=new byte[544*220];for(int y=0;y<220;y++)System.arraycopy(gray,y*540,p,y*544,540);return p;}
    static void resealReply(byte[] p){int c=-1;for(int i=0;i<p.length;i++){if(i>=28&&i<32)continue;c^=p[i]&255;for(int k=0;k<8;k++)c=(c>>>1)^(0xedb88320&-(c&1));}long v=~c&0xffffffffL;for(int i=0;i<4;i++)p[28+i]=(byte)(v>>(8*i));}
}
