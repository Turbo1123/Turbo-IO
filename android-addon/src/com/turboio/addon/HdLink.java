package com.turboio.addon;
import java.security.SecureRandom;

/** TVP2 native HD window link (port of tar2-display TVPHDLink): HELLO with the HD capability, OPEN, then per frame
 * BEGIN + four STRIPs + COMMIT, PING while idle, glasses PAUSE/EXIT events, CLOSE. One packet in flight with a 3 s
 * deadline; every reply is checked against cumulative rows/bytes/frames; a late reply never resumes. Main thread. */
final class HdLink {
    interface Sender{boolean send(byte[] wire);}
    interface Clock{double now();}
    private final String peer;private final Sender sender;private final Clock clock;
    private String note="尚未开始";private boolean active,ready,paused,closing,closedCleanly;
    private long sid,seq,lastEvent,eventAtSend,frameID;private int pendingOp,pendingLength;private long pendingSeq,pendingA;
    private byte[] packet;private HdEncoder.Frame frame;private int strip;
    private long stagedBytes,frames,verifiedBytes,receivedBytes,submittedBytes,rejectedFrames,decodeMS;
    private double deadline,sentAt,frameAt,lastFrameSeconds;

    HdLink(String peer,Sender sender,Clock clock){
        if(peer==null||peer.isEmpty()||sender==null||clock==null)throw new IllegalArgumentException();
        this.peer=peer;this.sender=sender;this.clock=clock;SecureRandom r=new SecureRandom();do sid=r.nextInt()&0xffffffffL;while(sid==0);
    }
    boolean active(){return active;}boolean ready(){return ready;}boolean paused(){return paused;}boolean busy(){return packet!=null||frame!=null;}boolean closedCleanly(){return closedCleanly;}
    String note(){return note;}long sid(){return sid;}String peer(){return peer;}
    long frames(){return frames;}long verifiedBytes(){return verifiedBytes;}long receivedBytes(){return receivedBytes;}long submittedBytes(){return submittedBytes;}long rejectedFrames(){return rejectedFrames;}long decodeMS(){return decodeMS;}double lastFrameSeconds(){return lastFrameSeconds;}

    private void fail(String s){active=ready=false;packet=null;frame=null;note=s;}
    private boolean send(int op,long a,long b,long c,byte[] data){
        if(!active||packet!=null)return false;if(seq==Vp.U32){fail("会话序号耗尽");return false;}
        Vp.Packet q=new Vp.Packet();q.op=op;q.sid=sid;q.seq=seq+1;q.a=a;q.b=b;q.c=c;q.data=data;byte[] wire=Vp.encode(q,false);
        if(wire==null){fail("本机高清分块无效");return false;}
        seq++;pendingOp=op;pendingSeq=seq;pendingA=a;pendingLength=q.length();packet=wire;sentAt=clock.now();deadline=sentAt+3;eventAtSend=lastEvent;
        boolean ok;try{ok=sender.send(packet);}catch(RuntimeException e){ok=false;}
        if(!ok){fail("通信门禁拒绝提交，已停止");return false;}submittedBytes+=wire.length;return true;
    }
    void start(){if(active||seq!=0)return;active=true;note="核对 TVP2 原生高清能力…";send(Vp.HELLO,Vp.HD_CAP,0,0,null);}
    void close(){if(!active)return;closing=true;frame=null;note="正在释放眼镜…";tick();}
    void tick(){
        if(!active)return;
        if(packet!=null){if(clock.now()>=deadline)fail("高清回执超时，已停发；眼镜最迟15秒退出");return;}
        if(closing){send(Vp.CLOSE,0,0,0,null);return;}
        if(frame!=null&&!paused){
            if(strip<frame.strips.length){int y=strip*Vp.HD_ROWS,h=Math.min(Vp.HD_ROWS,Vp.H-y);byte[] d=frame.strips[strip];send(Vp.HD_STRIP,y|((long)h<<16),frame.bits,Vp.crc(d,0,d.length),d);}
            else send(Vp.HD_COMMIT,frameID,0,frame.pixelCrc,null);
            return;
        }
        if(ready&&clock.now()-sentAt>=2)send(Vp.PING,0,0,0,null);
    }
    /** Offer the latest frame; refused while not ready, paused, busy or if any strip exceeds the Android lane. */
    boolean offer(HdEncoder.Frame f){
        if(!ready||closing||paused||busy()||f==null||f.strips==null||f.strips.length!=(Vp.H+Vp.HD_ROWS-1)/Vp.HD_ROWS||(f.bits!=2&&f.bits!=4)||f.gray==null||f.gray.length!=Vp.W*Vp.H)return false;
        for(byte[] d:f.strips)if(d==null||d.length==0||d.length>Vp.COMP_MAX||d.length+Vp.HEADER>Vp.LANE)return false;
        if(frameID==Vp.U32){close();return false;}
        frame=f;strip=0;stagedBytes=0;frameAt=clock.now();frameID++;
        return send(Vp.HD_BEGIN,frameID,f.bits,f.pixelCrc,null);
    }
    /** A business-15 message. true when it is a VPA1 reply (consumed, possibly ignored as foreign/stale). */
    boolean consume(String from,byte[] payload){
        if(payload==null||payload.length!=Vp.HEADER)return false;Vp.Packet q=Vp.decode(payload,true);if(q==null)return false;
        if(!active||!peer.equals(from)||q.sid!=sid)return true;
        if(q.op==Vp.PAUSE||q.op==Vp.EXIT){
            if(q.result!=Vp.OK||q.seq<=lastEvent)return true;lastEvent=q.seq;
            if(q.op==Vp.EXIT){closedCleanly=true;fail("眼镜已退出，接收停止");}else if(q.a<=1){paused=q.a!=0;if(paused)frame=null;}
            return true;
        }
        if(packet==null||q.op!=pendingOp||q.seq!=pendingSeq)return true;
        if(clock.now()>=deadline){fail("迟到回执未恢复传输");return true;}packet=null;
        if(q.result==Vp.BUSY&&q.op>=Vp.HD_BEGIN&&q.op<=Vp.HD_COMMIT){frame=null;rejectedFrames++;note="眼镜暂忙，丢弃本帧，等待新画面";return true;}
        if(q.result!=Vp.OK){fail("眼镜拒绝高清指令："+q.result+"，已停发");return true;}
        if(q.op==Vp.HELLO){
            if(q.a!=Vp.W||q.b!=(Vp.H|((long)Vp.HD_FLAG<<16))||clock.now()-sentAt>1){closedCleanly=true;fail("需要先刷 TVP2 清晰投屏固件；未打开眼镜页面");return true;}
            if(closing){closedCleanly=true;fail("未打开眼镜页面");return true;}
            send(Vp.OPEN,q.c,0,0,null);
        }else if(q.op==Vp.OPEN){ready=true;note="已连接 540×220 点对点窗口";}
        else if(q.op==Vp.HD_BEGIN){if(q.a!=frameID||q.b!=0||q.c!=0){fail("高清起帧回执不一致");return true;}}
        else if(q.op==Vp.HD_STRIP){long y=(pendingA&65535)+(pendingA>>>16),expected=stagedBytes+pendingLength;
            if(q.a!=y||q.c!=expected){fail("分块累计行数/字节不一致");return true;}stagedBytes=expected;receivedBytes+=pendingLength;decodeMS+=q.b;strip++;}
        else if(q.op==Vp.HD_COMMIT){if(q.a!=frames+1||q.c!=verifiedBytes+stagedBytes){fail("完整画面累计字节/帧数不一致");return true;}
            frames=q.a;verifiedBytes=q.c;decodeMS+=q.b;lastFrameSeconds=clock.now()-frameAt;frame=null;note="原生高清显示 · 短按暂停 · 长按退出";}
        else if(q.op==Vp.PING){if(q.a>1||q.b!=frames||q.c!=verifiedBytes){fail("高清状态校验失败");return true;}if(eventAtSend==lastEvent)paused=q.a!=0;}
        else if(q.op==Vp.CLOSE){closedCleanly=true;fail("接收已结束，眼镜已释放");return true;}
        tick();return true;
    }
}
