package com.turboio.addon;
import java.io.*;import java.util.*;

/** TdpSession (port of TDPPhoneSession/TDPDisplayReplyObserver) driving the unchanged TVP2 display runtime (C oracle). */
public final class TdpSessionTest {
    static int n;static void ok(boolean b,String why){n++;if(!b)throw new AssertionError("session "+n+" "+why);}
    static String oracle;
    /** One oracle process = one glasses page (tdp_open sid 7392 at 1000 ms). */
    static final class Glasses implements Closeable{
        final Process p;final DataOutputStream out;final DataInputStream in;long crc,revision;
        Glasses()throws IOException{p=new ProcessBuilder(oracle,"7392").start();out=new DataOutputStream(p.getOutputStream());in=new DataInputStream(p.getInputStream());}
        static void le(DataOutputStream o,long v)throws IOException{for(int i=0;i<4;i++)o.write((int)(v>>(8*i))&255);}
        long rle()throws IOException{long v=0;for(int i=0;i<4;i++)v|=(long)in.readUnsignedByte()<<(8*i);return v;}
        /** Feed one packet at the session clock; returns the glasses' carrier envelope (or null for a zero reply). */
        byte[] handle(byte[] packet,double now)throws IOException{le(out,(long)(now*1000));le(out,packet.length);out.write(packet);out.flush();byte[] raw=new byte[40];in.readFully(raw);crc=rle();revision=rle();Tdp.Reply r=Tdp.replyDecode(raw);return r==null?null:Tdp.carrierEncode(r);}
        public void close(){p.destroy();}
    }
    static final class Rig{
        double now=1;byte[] packet;int sends;boolean refuse;final ArrayDeque<Runnable> posted=new ArrayDeque<>();final TdpSession s;
        Rig(){s=new TdpSession("test",()->now,p->{if(refuse)return false;if(p.length>512||!Tdp.valid(p))throw new AssertionError("invalid packet sent");packet=p;sends++;return true;},posted::add);}
        void pump(){for(int i=0;i<4&&!posted.isEmpty();i++)posted.poll().run();}
        int reply(byte[] env){return s.reply("test",15,env);}
        /** Query + automatic renewal against the oracle. */
        void open(Glasses g)throws IOException{s.setForeground(true);ok(s.query(),"query");byte[] e=g.handle(packet,now);reply(e);s.fileDone(0);now+=0.16;s.tick();e=g.handle(packet,now);reply(e);s.fileDone(0);}
        /** Run the in-flight work to completion, alternating ACK order. Returns packets sent. */
        int drive(Glasses g,int limit,double step)throws IOException{int k=0;while(s.busy()&&k<limit){k++;byte[] e=g.handle(packet,now);int before=sends;
            if(k%2==1){reply(e);s.tick();pump();ok(sends==before,"reply alone never sends");s.fileDone(0);}else{s.fileDone(0);s.tick();pump();ok(sends==before,"file alone never sends");reply(e);}
            ok(sends==before,"no re-entry from the ACK callback");now+=step;pump();}return k;}
    }
    static Tdp.Reply copy(Tdp.Reply q){return Tdp.replyDecode(Tdp.replyEncode(q));}
    static byte[] frame(int mul){byte[] f=new byte[Tdp.PIXELS];for(int i=0;i<f.length;i++)f[i]=(byte)(i*mul);return f;}
    public static void main(String[] a)throws Exception{
        oracle=a[0];
        try(Glasses g=new Glasses()){Rig r=new Rig();TdpSession s=r.s;
            ok(!s.query(),"no query in background");s.setForeground(true);ok(s.query()&&!s.query()&&!s.ready(),"one query in flight");
            byte[] e=g.handle(r.packet,r.now);ok(s.reply("foreign",15,e)<0,"foreign peer ignored");ok(s.reply("test",11,e)<0,"wrong business ignored");
            ok(r.reply(e)==0&&!s.ready()&&s.busy(),"CAPS accepted, file pending");
            r.s.fileDone(0);ok(!s.ready()&&!s.busy(),"needs renewal");r.now+=0.16;s.tick();ok(s.busy(),"automatic initial renewal");
            e=g.handle(r.packet,r.now);s.fileDone(0);ok(s.busy()&&!s.ready(),"file alone not ready");ok(r.reply(e)==0&&s.ready()&&!s.busy()&&s.sessionID()==7392,"renewed, sid 7392");
            r.now+=0.16;ok(s.sendTestRect(),"test rect");e=g.handle(r.packet,r.now);r.reply(e);s.fileDone(0);ok(s.revision()==1&&g.revision==1,"rect revision 1");
            byte[] f=frame(1);ok(s.sendFrame(f),"frame");int k=r.drive(g,200,0.16);
            ok(k==141&&s.completedChunks()==139&&s.revision()==2&&s.ready()&&g.crc==Tdp.crc(f,0,f.length),"141 packets, 139 chunks, exact pixels ("+k+")");
            ok(s.hasPixelBaseline(),"baseline after COMMIT");
            // Delta: one tile changed → exactly one RECT; same image → zero packets; >32 tiles → refused.
            byte[] d=f.clone();d[600]^=0x40;int before=r.sends;ok(s.sendChangedPixels(d),"delta start");k=r.drive(g,10,0.05);
            ok(k==1&&r.sends==before+1&&g.crc==Tdp.crc(d,0,d.length)&&s.revision()==3&&s.hasPixelBaseline(),"one RECT, exact pixels");
            before=r.sends;ok(s.sendChangedPixels(d)&&r.sends==before&&!s.busy(),"same image is zero transfer");
            byte[] many=d.clone();for(int t=0;t<40;t++)many[((t*24)/512)*16*512+(t*24)%512]^=1;ok(!s.sendChangedPixels(many)&&r.sends==before&&s.state().startsWith("变化超过32个小区域"),"over 32 refused");
            ok(s.sendPartialPixels(many)&&s.deltaTotal()==8,"partial batch of 8");r.drive(g,20,0.05);ok(s.completedRects()==8&&s.hasPixelBaseline(),"partial applied");
            ok(s.closePage(),"close");e=g.handle(r.packet,r.now);r.reply(e);s.fileDone(0);ok(!s.ready()&&!s.busy(),"closed");
            // Timeout while the file is pending: busy, no retries until the file terminal.
            ok(s.query(),"query again");int count=r.sends;r.now+=6;s.tick();ok(!s.ready()&&s.busy()&&!s.query()&&r.sends==count,"uncertain file blocks retries");
            s.fileDone(2);ok(!s.busy()&&s.query(),"file terminal releases");s.setForeground(false);count=r.sends;r.now+=60;s.tick();ok(r.sends==count&&!s.ready(),"background stops");
            s.fileDone(0);
        }
        // Frame pacing modes: 1 slow → 25 s deadline; 2 foreground stop; 3 file failure; 4 late COMMIT.
        for(int mode=1;mode<=4;mode++)try(Glasses g=new Glasses()){Rig r=new Rig();TdpSession s=r.s;r.open(g);ok(s.ready(),"mode "+mode+" ready");
            byte[] f=frame(31);ok(s.sendFrame(f),"mode "+mode+" frame");double start=r.now;int k=0;
            while(s.frameActive()){k++;int before=r.sends;r.now+=mode==1?0.30:0.10;byte[] e=g.handle(r.packet,r.now);
                if(mode==4&&k==141){r.now=start+25;s.tick();ok(!s.frameActive()&&s.busy()&&!s.ready(),"late commit stops");r.reply(e);s.fileDone(0);r.pump();ok(!s.busy()&&r.sends==before,"late ACKs never resume");break;}
                if(mode==1&&r.now-start>=25){s.tick();ok(!s.frameActive()&&s.busy(),"25 s deadline");s.fileDone(0);r.reply(e);r.pump();ok(!s.busy()&&r.sends==before&&s.completedChunks()<139&&g.revision==0,"slow frame never shown");break;}
                if(mode==3&&k==5){s.fileDone(1);r.pump();ok(!s.busy()&&!s.ready()&&r.sends==before&&s.state().startsWith("文件通道返回失败"),"file failure stops");break;}
                r.reply(e);s.fileDone(0);
                if(mode==2&&k==5){s.setForeground(false);r.pump();ok(r.sends==before&&!s.frameActive()&&!s.ready(),"foreground stop");break;}
                r.pump();
            }
            int stopped=r.sends;s.setForeground(false);r.now+=60;r.pump();s.tick();ok(r.sends==stopped,"mode "+mode+" no sends after stop");
        }
        // Focus 1: stale request, mismatched sid, wrong revision and error results never advance; unsolicited CLOSED stops.
        try(Glasses g=new Glasses()){Rig r=new Rig();TdpSession s=r.s;r.open(g);ok(s.ready(),"focus rig");
            r.now+=0.2;ok(s.sendTestRect(),"rect for focus");byte[] good=g.handle(r.packet,r.now);Tdp.Reply q=Tdp.carrierDecode(15,good);
            Tdp.Reply stale=copy(q);stale.request=(q.request-1)&0xffffffffL;ok(r.reply(Tdp.carrierEncode(stale))<0&&s.busy(),"stale request ignored");
            Tdp.Reply sid=copy(q);sid.sid=q.sid+1;ok(r.reply(Tdp.carrierEncode(sid))<0&&s.busy(),"mismatched sid ignored");
            Tdp.Reply rev=copy(q);rev.revision=q.revision+1;ok(r.reply(Tdp.carrierEncode(rev))==1&&!s.ready()&&s.state().startsWith("眼镜拒绝"),"wrong revision refused and stops");
            s.fileDone(0);ok(!s.busy(),"file terminal after refusal");}
        for(int result:new int[]{Tdp.BUSY,Tdp.STALE,Tdp.BAD_PACKET})try(Glasses g=new Glasses()){Rig r=new Rig();TdpSession s=r.s;r.open(g);r.now+=0.2;s.sendTestRect();
            Tdp.Reply q=Tdp.carrierDecode(15,g.handle(r.packet,r.now));q.result=result;int before=r.sends;ok(r.reply(Tdp.carrierEncode(q))==1&&!s.ready()&&r.sends==before,"error result "+result+" stops");}
        try(Glasses g=new Glasses()){Rig r=new Rig();TdpSession s=r.s;r.open(g);r.now+=0.2;s.sendTestRect();
            Tdp.Reply q=Tdp.carrierDecode(15,g.handle(r.packet,r.now));q.result=Tdp.NO_SESSION;q.sid=0;ok(r.reply(Tdp.carrierEncode(q))==1&&s.state().startsWith("眼镜显示会话未打开"),"NO_SESSION sid 0 stops with the open-page hint");}
        try(Glasses g=new Glasses()){Rig r=new Rig();TdpSession s=r.s;r.open(g);Tdp.Reply c=new Tdp.Reply();c.result=Tdp.CLOSED;c.sid=7392;c.width=512;c.height=128;
            ok(r.reply(Tdp.carrierEncode(c))<0&&!s.ready()&&s.state().equals("眼镜实体退出，停止所有发送"),"unsolicited CLOSED stops");}
        // Focus 3: a ready session sends no renewal once in the background.
        try(Glasses g=new Glasses()){Rig r=new Rig();TdpSession s=r.s;r.open(g);ok(s.ready()&&!s.busy(),"ready idle");
            r.now+=29;s.tick();int before=r.sends;s.setForeground(false);r.now+=31;s.tick();r.pump();ok(r.sends==before&&!s.ready(),"background suppresses renewal");
        }
        // Refused submission is not sent: no file lock.
        try(Glasses g=new Glasses()){Rig r=new Rig();r.s.setForeground(true);r.refuse=true;ok(!r.s.query()&&!r.s.busy()&&r.s.state().equals("查询未提交"),"refused query");}
        System.out.println("TdpSessionTest: "+n+" checks; QUERY+renewal, dual ACK, 139-chunk exact frame, delta, CLOSE, timeouts, foreground, failures vs the TVP2 runtime");
    }
}
