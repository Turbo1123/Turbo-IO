package com.turboio.addon;

import java.util.*;

/** Pure scheduling policy: one in flight, newest snapshot only, no blind retries. */
public final class NativeNavSession {
    public interface Sender { boolean send(byte[] packet,long sid,long sequence); }
    public enum State { IDLE,STARTING,RUNNING,STOPPING,STOPPED,UNCERTAIN }
    private final String peer;private final long sid;private final Sender sender;
    private State state=State.IDLE;private long seq,lastOffer,lastCommit,lastWire,next,deadline;
    private byte[] latest,committed,sending;private boolean pending;private int op,count;
    private String note="尚未开始";
    public NativeNavSession(String peer,long sid,Sender sender){if(peer==null||peer.isEmpty()||sid<=0||sid>0xffffffffL||sender==null)throw new IllegalArgumentException();this.peer=peer;this.sid=sid;this.sender=sender;}
    public State state(){return state;}public boolean pending(){return pending;}public long sequence(){return seq;}public long session(){return sid;}
    public String status(){return note+" · 原生帧 "+count;}
    public boolean start(NativeNavCodec.Scene scene,long now){if(state!=State.IDLE)return false;latest=NativeNavCodec.scene(scene);lastOffer=now;state=State.STARTING;if(!send(NativeNavCodec.START,latest,now)){state=State.STOPPED;note="传输繁忙，未开始";return false;}return true;}
    public void offer(NativeNavCodec.Scene scene,long now){if(state!=State.RUNNING&&state!=State.STARTING)return;latest=NativeNavCodec.scene(scene);lastOffer=now;}
    public void stop(long now){if(state==State.STARTING||state==State.RUNNING){state=State.STOPPING;note="等待当前传输完成后退出";pump(peer,now);}}
    private void fail(String reason){state=State.UNCERTAIN;note=reason;/* in-flight ownership remains in NativeTransfer */}
    private boolean send(int operation,byte[] body,long now){if(pending||seq==0xffffffffL)return false;long request=seq+1;byte[] packet=NativeNavCodec.packetBytes(operation,sid,request,body);pending=true;op=operation;sending=body;seq=request;lastWire=now;deadline=now+8000;note="等待文件及TNA1回执";if(!sender.send(packet,sid,seq)){pending=false;sending=null;return false;}return true;}
    public void pump(String current,long now){if(state==State.IDLE||state==State.STOPPED||state==State.UNCERTAIN)return;if(!peer.equals(current)){fail("连接已变化，停止发送；请在眼镜确认旧画面退出");return;}if(pending){if(now>=deadline)fail("原生导航8秒未确认，停止发送；不会自动重发");return;}if(now<next)return;if(state==State.STOPPING){if(!send(NativeNavCodec.STOP,null,now))fail("退出未能提交，请用眼镜按键退出");return;}if(state!=State.RUNNING)return;if(now-lastOffer<=15000&&(!Arrays.equals(latest,committed)||now-lastCommit>=10000)){if(!send(NativeNavCodec.UPDATE,latest,now)){next=now+1000;note="传输繁忙，合并最新导航帧";}}else if(now-lastWire>=10000){if(!send(NativeNavCodec.HEARTBEAT,null,now))next=now+1000;}}
    public void complete(long request,boolean confirmed,int result,NativeNavCodec.Reply reply,long now){if(request!=seq||!pending)return;pending=false;if(state==State.UNCERTAIN)return;if(now>=deadline||!confirmed||reply==null||reply.sid!=sid||reply.seq!=seq||result!=0||reply.result!=0||(op==NativeNavCodec.STOP?reply.active:!reply.active)){fail("导航结果未确认或被拒绝（"+result+"），不自动重发");return;}next=now+1000;if(op==NativeNavCodec.START||op==NativeNavCodec.UPDATE){committed=sending;lastCommit=now;count++;}sending=null;if(op==NativeNavCodec.STOP){state=State.STOPPED;note="眼镜已确认退出原生导航";}else {if(state==State.STARTING)state=State.RUNNING;note="眼镜已确认原生导航";}}
}
