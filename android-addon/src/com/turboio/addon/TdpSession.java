package com.turboio.addon;
import java.security.SecureRandom;
import java.util.Locale;
import java.util.function.Consumer;

/** Main-thread-only TDP1 coordinator (port of iOS TDPPhoneSession + TDPDisplayReplyObserver). Exactly one file AND
 * one glasses reply in flight; both are required before the next packet. Failures stop, never retry. Times in s. */
final class TdpSession {
    interface Clock{double now();}
    /** Submits one turbo-display.tdp packet. false = refused before submission (nothing was sent). */
    interface Sender{boolean send(byte[] packet);}
    static final int FILE_OK=0,FILE_FAILED=1,FILE_UNKNOWN=2;
    private static final long U32=Tdp.U32;
    private final String device;private final Clock clock;private final Sender sender;private final Consumer<Runnable> post;
    Runnable changed;
    private String state="等待查询 TDP1；以真实回执判断固件能力";
    private byte[] packet,frame,knownPixels,deltaTarget;
    private double deadline,nextSend,renewAt,frameDeadline,frameStarted,frameEnded,deltaStarted,deltaEnded,deltaDeadline;
    private long counter,tx,base,baselineSID,baselineRevision;private int offset,chunkLength,completedChunks,files,deltaIndex;
    private boolean fileBusy,apAck,foreground,needsRenew,pumpQueued,hasFrameTiming,hasDeltaTiming;
    private final Tdp.Delta delta=new Tdp.Delta();
    // Reply observer.
    private long oSid,oRev,oMaxPx,oPending,oCounter;private double oExpires,oPendingDeadline;private boolean oQuery;

    TdpSession(String device,Clock clock,Sender sender,Consumer<Runnable> post){
        if(device==null||device.isEmpty()||clock==null||sender==null||post==null)throw new IllegalArgumentException();
        this.device=device;this.clock=clock;this.sender=sender;this.post=post;SecureRandom r=new SecureRandom();
        counter=(r.nextInt()&0x3fffffffL)+1;tx=counter;oCounter=(r.nextInt()&0x7ffffffeL)+1;
    }
    private double now(){return clock.now();}
    String device(){return device;}
    String state(){return state;}
    private boolean oReady(){return oSid!=0&&now()<oExpires&&(oPending==0||now()<oPendingDeadline);}
    boolean ready(){return oReady()&&!needsRenew;}
    boolean busy(){return packet!=null||fileBusy||frame!=null||deltaTarget!=null;}
    long sessionID(){return oReady()?oSid:0;}
    long revision(){return oReady()?oRev:0;}
    private long maxPixels(){return oReady()?oMaxPx:0;}
    int completedChunks(){return completedChunks;}
    boolean frameActive(){return frame!=null;}
    double frameElapsed(){return hasFrameTiming?Math.max(0,(frame!=null?now():frameEnded)-frameStarted):0;}
    boolean deltaActive(){return deltaTarget!=null;}
    boolean hasPixelBaseline(){return ready()&&knownPixels!=null&&baselineSID==sessionID()&&baselineRevision==revision();}
    int deltaTotal(){return delta.count;}
    int completedRects(){return deltaIndex;}
    double deltaElapsed(){return hasDeltaTiming?Math.max(0,(deltaTarget!=null?now():deltaEnded)-deltaStarted):0;}
    /** The packet awaiting its two acknowledgements (for the carrier's self-ack), or null. */
    byte[] inflight(){return packet;}

    private void oDisconnected(){oSid=oRev=oPending=oMaxPx=0;oExpires=oPendingDeadline=0;oQuery=false;}
    private byte[] oMakeQuery(){
        if(oPending!=0&&now()>=oPendingDeadline)oDisconnected();
        if(oPending!=0||oCounter==U32)return null;oPending=++oCounter;oQuery=true;oPendingDeadline=now()+5;return Tdp.query(oPending);
    }
    private boolean oExpect(long request,long sid){
        if(request==0||oPending!=0||!oReady()||sid!=oSid)return false;oPending=request;oQuery=false;oPendingDeadline=now()+5;return true;
    }
    private void oConsume(Tdp.Reply r){
        if(oPending!=0&&now()>=oPendingDeadline){oDisconnected();return;}
        if(r.request==0){if(r.result==Tdp.CLOSED&&r.sid==oSid)oDisconnected();return;}
        if(r.request!=oPending)return;
        if(oQuery){
            if(r.result==Tdp.CAPS&&r.sid!=0&&r.width==512&&r.height==128&&r.maxRect>0&&r.maxRect<=16384&&r.lease==120000){oSid=r.sid;oRev=r.revision;oMaxPx=Math.min(r.maxRect,Tdp.NATIVE_PIXELS);oExpires=now()+110;}
            else oDisconnected();
            oPending=0;oQuery=false;return;
        }
        if((r.result==Tdp.CLOSED||r.result==Tdp.NO_SESSION)&&r.sid==0){oDisconnected();return;}
        if(r.sid!=oSid)return;
        oPending=0;
        if(r.result==Tdp.UI_SUBMITTED||r.result==Tdp.ALIVE){if(r.revision<oRev)return;oRev=r.revision;oExpires=now()+110;}
    }

    private void publish(String s){state=s;if(changed!=null)changed.run();}
    private long request(){if(counter==U32)return 0;return ++counter;}
    private void fail(String s){
        if(frame!=null)frameEnded=now();if(deltaTarget!=null)deltaEnded=now();
        packet=null;frame=null;deltaTarget=null;knownPixels=null;needsRenew=false;oDisconnected();publish(s);
    }
    /** At most one queued wake; never re-enter the sender from an acknowledgement callback. */
    private void queuePump(){
        if(pumpQueued||(frame==null&&deltaTarget==null)||!foreground)return;pumpQueued=true;
        post.accept(()->{pumpQueued=false;tick();});
    }
    void disconnect(){foreground=false;fail("连接已失效；等待重新查询。未确认结束的文件不会重发");}
    private boolean send(byte[] p,boolean query){
        if(p==null||packet!=null||fileBusy||files>=512||!foreground)return false;
        if(!query&&!oExpect(Tdp.u32(p,12),Tdp.u32(p,8)))return false;
        packet=p;files++;fileBusy=true;apAck=false;deadline=now()+5;
        publish(frame!=null?String.format(Locale.ROOT,"整帧 %d / 139 块 · %.1f秒；等待当前块双回执",completedChunks,frameElapsed()):"手机提交中；等待文件终态和眼镜协议回执");
        boolean ok;try{ok=sender.send(p);}catch(RuntimeException e){ok=false;}
        // A refused submission never reached the file lane: no file lock to keep.
        if(!ok){packet=null;fileBusy=false;oPending=0;return false;}
        return true;
    }
    boolean query(){
        if(busy()||!foreground||files>=512)return false;
        knownPixels=null;oDisconnected();needsRenew=true;
        if(!send(oMakeQuery(),true)){fail("查询未提交");return false;}return true;
    }
    private boolean control(int op){return send(Tdp.control(op,sessionID(),request(),revision()),false);}
    boolean closePage(){if(busy()||!ready())return false;return control(Tdp.CLOSE);}
    boolean sendTestRect(){
        if(busy()||!ready()||now()<nextSend)return false;
        byte[] px=new byte[400];for(int y=0;y<20;y++)for(int x=0;x<20;x++)px[y*20+x]=(byte)((x==y||x+y==19)?255:60);
        return send(Tdp.rect(sessionID(),request(),revision(),4,4,20,20,px),false);
    }
    boolean sendFrame(byte[] gray){
        if(busy()||!ready()||!foreground||gray==null||gray.length!=Tdp.PIXELS||tx==U32||files>368)return false;
        frame=gray.clone();base=revision();tx++;offset=0;completedChunks=0;frameStarted=now();frameEnded=0;hasFrameTiming=true;frameDeadline=frameStarted+25;
        if(!send(Tdp.begin(sessionID(),request(),base,tx,Tdp.crc(frame,0,frame.length)),false)){fail("整帧未提交，已停止；重新查询后再试");return false;}return true;
    }
    boolean sendChangedPixels(byte[] gray){return sendPixels(gray,false);}
    /** At most 8 rectangles from the latest target; the next call replans against acknowledged pixels. */
    boolean sendPartialPixels(byte[] gray){return sendPixels(gray,true);}
    private boolean sendPixels(byte[] gray,boolean partial){
        if(busy()||!foreground)return false;
        if(!hasPixelBaseline()){publish("没有已确认的像素基线；先查询并成功发送一次完整画布。重连/重新查询后不猜测旧画面");return false;}
        Tdp.Delta plan=new Tdp.Delta();int result=partial?Tdp.deltaBatch(knownPixels,gray,8,plan):Tdp.deltaPlan(knownPixels,gray,plan);
        if(partial&&result==1)result=0;
        if(result!=0){publish(result==1?"变化超过32个小区域；本次未发送，请手动选择整图更新":"画布无效；本次未发送");return false;}
        copyPlan(plan);deltaIndex=0;
        if(plan.count==0){deltaStarted=deltaEnded=now();hasDeltaTiming=true;publish("画面没有变化，未发送任何蓝牙数据");return true;}
        if(files+plan.count>512){publish("本次会话的文件额度不足，未启动局部更新");return false;}
        deltaTarget=gray.clone();deltaStarted=now();deltaEnded=0;hasDeltaTiming=true;deltaDeadline=deltaStarted+10;
        nextDeltaPacket();return deltaTarget!=null;
    }
    private void copyPlan(Tdp.Delta p){delta.count=p.count;delta.pixels=p.pixels;for(int i=0;i<p.count;i++)System.arraycopy(p.rects[i],0,delta.rects[i],0,4);}
    private void nextDeltaPacket(){
        if(deltaTarget==null||deltaIndex>=delta.count)return;
        if(now()>=deltaDeadline){fail("局部更新超过10秒，已停止；画面可能只更新了一部分，需要重建基线");return;}
        int[] r=delta.rects[deltaIndex];byte[] px=new byte[r[2]*r[3]];
        for(int row=0;row<r[3];row++)System.arraycopy(deltaTarget,(r[1]+row)*512+r[0],px,row*r[2],r[2]);
        if(!send(Tdp.rect(sessionID(),request(),revision(),r[0],r[1],r[2],r[3],px),false))fail("局部更新未提交；已停止并清除像素基线");
    }
    private void nextFramePacket(){
        if(now()>=frameDeadline){fail("整帧超时，未继续发送；眼镜事务将超时丢弃。重新查询后再试");return;}
        byte[] p;
        if(offset<Tdp.PIXELS){chunkLength=(int)Math.min(maxPixels(),Tdp.PIXELS-offset);p=Tdp.chunk(sessionID(),request(),base,tx,offset,frame,offset,chunkLength);}
        else p=Tdp.finish(Tdp.COMMIT,sessionID(),request(),base,tx);
        if(!send(p,false))fail("无法继续成帧；已停止，不重复提交");
    }
    private void finishIfComplete(){
        if(packet==null||fileBusy||!apAck)return;
        // The file terminal can be the last callback: it never bypasses the deadlines.
        if((deltaTarget!=null&&now()>=deltaDeadline)||(frame!=null&&now()>=frameDeadline)||now()>=deadline){fail("双回执完成时已超时；结果未知，清除像素基线且不继续发送");return;}
        byte[] finished=packet;int op=finished[5];packet=null;
        nextSend=now()+((frame!=null||deltaTarget!=null)?0:0.15);
        if(op==Tdp.QUERY){needsRenew=true;publish("收到真实 SID；等待续租回执后才允许绘制");return;}
        if(op==Tdp.CLOSE){fail("眼镜返回 CLOSED；页面关闭回执已收到");return;}
        if(op==Tdp.KEEPALIVE){needsRenew=false;renewAt=now()+30;publish("会话已验证并续租；可以发送测试图");return;}
        if(op==Tdp.CHUNK){offset+=chunkLength;completedChunks++;}
        if(op==Tdp.COMMIT){knownPixels=frame.clone();baselineSID=sessionID();baselineRevision=revision();}
        if(op==Tdp.RECT){
            int x=Tdp.u16(finished,32),y=Tdp.u16(finished,34),w=Tdp.u16(finished,36),h=Tdp.u16(finished,38);
            if(knownPixels!=null&&baselineSID==sessionID()&&baselineRevision==Tdp.u32(finished,16)){
                for(int row=0;row<h;row++)System.arraycopy(finished,40+row*w,knownPixels,(y+row)*512+x,w);
                baselineRevision=revision();
            }else knownPixels=null;
            if(deltaTarget!=null){
                deltaIndex++;
                if(deltaIndex==delta.count){deltaEnded=now();deltaTarget=null;renewAt=now()+30;publish(String.format(Locale.ROOT,"局部更新%d块完成 · %.2f秒；镜片效果待确认",deltaIndex,deltaElapsed()));}
                else{publish(String.format(Locale.ROOT,"局部更新 %d / %d；保留未变化画面",deltaIndex,delta.count));queuePump();}
                return;
            }
        }
        if(op==Tdp.COMMIT||op==Tdp.RECT){
            if(frame!=null)frameEnded=now();
            frame=null;renewAt=now()+30;publish(op==Tdp.COMMIT?String.format(Locale.ROOT,"整帧139块已提交 · %.1f秒；UI_SUBMITTED，镜片效果待确认",frameElapsed()):"眼镜返回 UI_SUBMITTED；已提交绘制，镜片效果仍需确认");
        }else{publish(String.format(Locale.ROOT,"成帧中：%d / 139 块；尚未提交画面",completedChunks));queuePump();}
    }
    /** File-lane terminal for the in-flight packet (FILE_OK / FILE_FAILED / FILE_UNKNOWN). */
    void fileDone(int outcome){
        if(!fileBusy)return;fileBusy=false;
        if(outcome==FILE_FAILED){fail("文件通道返回失败，已停止；不自动重试修改画面的命令");return;}
        if(packet==null){publish(state+"；文件已结束，可在眼镜开页后重新查询");return;}
        if(outcome!=FILE_OK){fail("协议回执超时，结果未知；未继续传输");return;}
        finishIfComplete();
    }
    /** A business message. -1 = not ours / ignored; 0 = expected reply for the in-flight packet; 1 = in-flight packet refused. */
    int reply(String peer,int business,byte[] payload){
        if(!device.equals(peer))return -1;Tdp.Reply r=Tdp.carrierDecode(business,payload);if(r==null)return -1;
        if(r.request==0){
            if(r.result==Tdp.CLOSED&&r.sid==sessionID())fail("眼镜实体退出，停止所有发送");
            else if(r.result==Tdp.CAPS&&r.sid!=0&&!busy()&&!ready())publish("已收到眼镜开页提示；请点查询验证 SID，尚未授权绘制");
            return -1;
        }
        if(packet==null||r.request!=Tdp.u32(packet,12))return -1;
        if(deltaTarget!=null&&now()>=deltaDeadline){fail("局部更新超时；清除基线，迟到回执不恢复发送");return 1;}
        if(frame!=null&&now()>=frameDeadline){fail("整帧超时，已停止；迟到回执不触发后续发送");return 1;}
        if(now()>=deadline){fail("协议回执超时，结果未知；未继续传输");return 1;}
        int op=packet[5];long sid=Tdp.u32(packet,8),rev=Tdp.u32(packet,16);
        if(op!=Tdp.QUERY&&r.sid!=sid&&!((r.result==Tdp.NO_SESSION||r.result==Tdp.CLOSED)&&r.sid==0))return -1;
        int expected=op==Tdp.QUERY?Tdp.CAPS:op==Tdp.KEEPALIVE?Tdp.ALIVE:op==Tdp.CLOSE?Tdp.CLOSED:(op==Tdp.RECT||op==Tdp.COMMIT)?Tdp.UI_SUBMITTED:Tdp.STAGED;
        long expectedRev=(rev+((op==Tdp.RECT||op==Tdp.COMMIT)?1:0))&U32;
        if(r.result!=expected||(op!=Tdp.QUERY&&r.revision!=expectedRev)){fail(r.result==Tdp.NO_SESSION?"眼镜显示会话未打开；请先进入 Turbo Display SID 页面，再重新查询":"眼镜拒绝：错误码 "+r.result+"；停止并要求重新查询");return 1;}
        oConsume(r);
        if(op!=Tdp.CLOSE&&!oReady()){fail("能力回执不兼容；没有启用新显示功能");return 1;}
        apAck=true;finishIfComplete();return 0;
    }
    void setForeground(boolean active){foreground=active;if(!active)fail("已暂停发送与续租；返回后需重新查询，不会永久占用显示");}
    void tick(){
        if(deltaTarget!=null&&now()>=deltaDeadline){fail("局部更新超时；画面可能部分更新，不自动重试");return;}
        if(frame!=null&&now()>=frameDeadline){fail("整帧超时，已停止；保留未终结的文件互锁，不自动重试");return;}
        if(packet!=null&&now()>=deadline){fail("查询/命令超时：文件终态"+(fileBusy?"未到":"已到")+"，AP回执"+(apAck?"已到":"未到")+"；结果未知，已停止");return;}
        if(!foreground||packet!=null||fileBusy||now()<nextSend)return;
        if(needsRenew&&oReady()){if(!control(Tdp.KEEPALIVE))fail("续租未发出，请重新查询");return;}
        if(deltaTarget!=null){nextDeltaPacket();return;}
        if(frame!=null){nextFramePacket();return;}
        if(ready()&&now()>=renewAt){if(!control(Tdp.KEEPALIVE))fail("续租未发出，请重新查询");}
    }
}
