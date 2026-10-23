package com.turboio.addon;

/** TCM1 viewfinder session with the glasses. One packet in flight, 3 s reply window, latest frame
 * only, never resends a shutter. Glasses dial events older than 1.5 s are dropped so a BLE backlog
 * can never take a late photo. Port of iOS TCCameraLink; the caller owns the transport lease. */
final class CameraLink {
    interface Sender{boolean send(byte[] wire);}
    interface Clock{double now();}
    interface Action{void fire(int op,long arg);}
    Action action;
    private final String peer;private final Sender sender;private final Clock clock;
    private String note="尚未连接取景器";
    private boolean ready,active,closing,stateDirty,frameReview,latestReview,closedCleanly;
    private int phase=CameraCodec.LIVE,zoom=100,remaining,w,h,bits,lw,lh,lb,offset;
    private long sid,seq,frameID,lastEvent,eyeTick;private double eyeAt;
    private byte[] packet,latest,frame;private int pendingOp,pendingLength;private long pendingSeq,pendingA;
    private double deadline,lastSend,frameAt,latestAt,commitRetry,frameBudget,lastFrameSeconds;
    private int frames,dropped,framePackets,lastFrameBytes,lastFramePackets,lastFrameWidth,lastFrameHeight,lastFrameBits;long bytes;

    CameraLink(String peer,Sender sender,Clock clock){
        if(peer==null||peer.isEmpty()||sender==null||clock==null)throw new IllegalArgumentException("camera link");
        this.peer=peer;this.sender=sender;this.clock=clock;java.security.SecureRandom r=new java.security.SecureRandom();do{sid=r.nextInt()&0xffffffffL;}while(sid==0);
    }
    boolean ready(){return ready;}boolean active(){return active;}boolean closedCleanly(){return closedCleanly;}String note(){return note;}String peer(){return peer;}
    int frames(){return frames;}int dropped(){return dropped;}long bytes(){return bytes;}double lastFrameSeconds(){return lastFrameSeconds;}
    int lastFrameBytes(){return lastFrameBytes;}int lastFramePackets(){return lastFramePackets;}
    int lastFrameWidth(){return lastFrameWidth;}int lastFrameHeight(){return lastFrameHeight;}int lastFrameBits(){return lastFrameBits;}
    boolean reviewBusy(){return (latest!=null&&latestReview)||(frame!=null&&frameReview);}
    void invalidate(String why){active=ready=false;packet=frame=latest=null;note=why;}
    private boolean send(int op,long s,long a,long b,long c,byte[] data){
        if(packet!=null||!active)return false;byte[] wire;
        try{wire=CameraCodec.packet(op,sid,s,a,b,c,data);}catch(IllegalArgumentException e){return false;}
        packet=wire;pendingOp=op;pendingSeq=s;pendingA=a;pendingLength=data==null?0:data.length;lastSend=clock.now();deadline=lastSend+3;
        if(!sender.send(wire)){invalidate("通信提交被保护门禁拒绝，已停止；没有重试快门");return false;}
        bytes+=wire.length;if(op==CameraCodec.BEGIN||op==CameraCodec.CHUNK||op==CameraCodec.COMMIT||op==CameraCodec.ABORT)framePackets++;return true;
    }
    private long next(){if(seq==0xffffffffL){invalidate("会话编号耗尽，请重新开启");return 0;}return ++seq;}
    void start(){if(active||seq!=0)return;active=true;note="正在核对 TCM1 取景能力…";send(CameraCodec.HELLO,next(),0,0,0,null);}
    void close(){if(!active)return;closing=true;latest=null;note="正在关闭取景器…";tick();}
    void state(int newPhase,int newZoom,int newRemaining){
        if(newPhase<0||newPhase>CameraCodec.ERROR||newZoom<100||newZoom>10000||newRemaining<0||newRemaining>10000)return;
        if(phase!=newPhase||zoom!=newZoom||remaining!=newRemaining){phase=newPhase;zoom=newZoom;remaining=newRemaining;stateDirty=true;}
    }
    void offer(byte[] compressed,int width,int height,int depth,boolean review){
        if(!ready||closing||compressed==null||compressed.length==0||compressed.length>CameraCodec.COMP_MAX||CameraCodec.budget(width,height,depth)==0)return;
        if(latestReview&&!review){dropped++;return;}if(latest!=null)dropped++;
        latest=compressed.clone();lw=width;lh=height;lb=depth;latestReview=review;latestAt=clock.now();
    }
    void tick(){
        if(!active)return;double now=clock.now();
        if(packet!=null){if(now>=deadline)invalidate("眼镜回执超时，已停止预览；不补发快门，请重新连接");return;}
        if(closing){send(CameraCodec.CLOSE,next(),0,0,0,null);return;}
        if(!ready)return;
        if(stateDirty){stateDirty=false;send(CameraCodec.STATE,next(),phase,zoom,remaining,null);return;}
        if(frame!=null){
            if(!frameReview&&now-frameAt>frameBudget){send(CameraCodec.ABORT,frameID,0,0,0,null);return;}
            if(offset<frame.length){int n=Math.min(CameraCodec.DATA_MAX,frame.length-offset);byte[] d=new byte[n];System.arraycopy(frame,offset,d,0,n);send(CameraCodec.CHUNK,frameID,offset,0,0,d);return;}
            if(now>=commitRetry)send(CameraCodec.COMMIT,frameID,0,0,0,null);return;
        }
        if(latest!=null){
            if(!latestReview&&now-latestAt>.75){latest=null;dropped++;return;}
            frame=latest;latest=null;frameReview=latestReview;latestReview=false;w=lw;h=lh;bits=lb;offset=0;frameID=next();frameAt=now;framePackets=0;frameBudget=CameraCodec.budget(w,h,bits);
            send(CameraCodec.BEGIN,frameID,w|((long)h<<16),frame.length|((long)bits<<24),HexCarrier.crc(frame,frame.length),null);return;
        }
        if(now-lastSend>=3)send(CameraCodec.PING,next(),0,0,0,null);
    }
    /** Returns true when the bytes were a TCA1 camera packet (consumed even if ignored). */
    boolean consume(String device,byte[] wire){
        CameraCodec.Packet q=CameraCodec.reply(wire);if(q==null)return false;
        if(!active||!peer.equals(device)||q.sid!=sid)return true;
        if(q.op>=CameraCodec.SHUTTER){
            if(q.seq<=lastEvent||q.result!=CameraCodec.OK)return true;lastEvent=q.seq;
            int age=(int)((eyeTick+(long)((clock.now()-eyeAt)*1000)-q.b)&0xffffffffL);
            if(age<-1000||age>1500)return true; // stale clicks never trigger a late photo
            stateDirty=true;if(action!=null)action.fire(q.op,q.a);return true;
        }
        if(packet==null||q.op!=pendingOp||q.seq!=pendingSeq||(q.op==CameraCodec.CHUNK&&q.a!=pendingA))return true;
        if(clock.now()>=deadline){invalidate("迟到回执未恢复预览，请重新连接");return true;}
        int op=q.op;packet=null;
        if(q.result!=CameraCodec.OK){
            if(q.result==CameraCodec.BUSY&&op==CameraCodec.COMMIT&&clock.now()-frameAt<8){commitRetry=clock.now()+.1;return true;}
            invalidate("眼镜拒绝取景包（"+q.result+"），已停止；请退出其他页面后重试");return true;
        }
        if(op==CameraCodec.HELLO){if(q.a!=256||q.b!=144||clock.now()-lastSend>1){invalidate("取景能力不匹配或握手延迟过高，请确认已刷 TVP2");return true;}eyeTick=q.c;eyeAt=clock.now();send(CameraCodec.OPEN,next(),q.c,0,0,null);return true;}
        if(op==CameraCodec.OPEN){ready=true;stateDirty=true;note="眼镜取景器已连接 · 低帧率压缩预览";}
        if(op==CameraCodec.CHUNK)offset+=pendingLength;
        if(op==CameraCodec.COMMIT){frames++;lastFrameSeconds=Math.max(0,clock.now()-frameAt);lastFrameBytes=frame.length;lastFramePackets=framePackets;lastFrameWidth=w;lastFrameHeight=h;lastFrameBits=bits;frame=null;commitRetry=0;note=frameReview?"拍后缩略图已提交到眼镜":"取景帧已提交 · 以镜片为准";}
        if(op==CameraCodec.ABORT){frame=null;dropped++;note="旧帧传输超时已丢弃；可选择较低分辨率，未堆积图片";}
        if(op==CameraCodec.CLOSE){closedCleanly=true;invalidate("取景器已关闭，控制权已释放");}
        return true;
    }
}
