package com.turboio.addon;

import java.util.*;

/** Pure scheduling policy: one in flight, newest snapshot only, no blind retries. A session that is offered a TNR3
 * road map becomes "extended" (iOS NativeNavigation.m): it probes QUERY once, then sends SCENE2 (or SCENE) when the
 * map changed, otherwise POSE on change ≥0.2 s apart or as a 1 s keep-alive, and CLEAR when a committed map is
 * withdrawn. Urgent TNV1 UPDATEs (icon/mode/road/turn) keep priority; a pose older than 4 s is never sent. */
public final class NativeNavSession {
    public interface Sender { boolean send(byte[] packet,long sid,long sequence); }
    public enum State { IDLE,STARTING,RUNNING,STOPPING,STOPPED,UNCERTAIN }
    private final String peer;private final long sid;private final Sender sender;
    private State state=State.IDLE;private long seq,lastOffer,lastCommit,lastWire,next,deadline;
    private byte[] latest,committed,sending;private String latestKey="",committedKey,sendingKey;private boolean pending;private int op,count;
    private byte[] mapLatest,map2Latest,mapCommitted,mapSending,poseLatest,poseCommitted;private long poseAt,lastPose;private int maps,poses;private boolean extended,probed,mapV2;
    private String note="尚未开始";
    public NativeNavSession(String peer,long sid,Sender sender){if(peer==null||peer.isEmpty()||sid<=0||sid>0xffffffffL||sender==null)throw new IllegalArgumentException();this.peer=peer;this.sid=sid;this.sender=sender;}
    public State state(){return state;}public boolean pending(){return pending;}public long sequence(){return seq;}public long session(){return sid;}
    public boolean extended(){return extended;}public boolean hasMap(){return mapLatest!=null;}public int maps(){return maps;}public int poses(){return poses;}public boolean roadLabels(){return mapV2;}
    public String status(){return note+" · 原生帧 "+count+(extended?" · 地图 "+maps+" / 位姿 "+poses+(mapV2?" · 路名":""):"");}
    private static String key(NativeNavCodec.Scene s){return s.icon+"|"+s.mode+"|"+s.road+"|"+s.turn;}
    public boolean start(NativeNavCodec.Scene scene,long now){if(state!=State.IDLE)return false;latest=NativeNavCodec.scene(scene);latestKey=key(scene);lastOffer=now;state=State.STARTING;if(!send(NativeNavCodec.START,latest,now)){state=State.STOPPED;note="传输繁忙，未开始";return false;}return true;}
    public void offer(NativeNavCodec.Scene scene,long now){if(state!=State.RUNNING&&state!=State.STARTING)return;latest=NativeNavCodec.scene(scene);latestKey=key(scene);lastOffer=now;}
    /** Latest road map (SCENE, optional SCENE2) and pose; anything invalid, stale (>4 s), from the future or of another
     * generation withdraws the map, which sends CLEAR once if one was committed. */
    public void mapOffer(byte[] scene,byte[] scene2,byte[] pose,long poseAtMs,long now){
        boolean valid=scene!=null&&pose!=null&&poseAtMs<=now&&now-poseAtMs<=4000&&NavMapCodec.bodyValid(NavMapCodec.SCENE,scene)&&NavMapCodec.bodyValid(NavMapCodec.POSE,pose)&&HexCarrier.u32(scene,0)==HexCarrier.u32(pose,0);
        if(!valid){mapLatest=map2Latest=poseLatest=null;return;}
        map2Latest=scene2!=null&&NavMapCodec.bodyValid(NavMapCodec.SCENE2,scene2)&&HexCarrier.u32(scene2,0)==HexCarrier.u32(scene,0)?scene2.clone():null;
        extended=true;mapLatest=scene.clone();poseLatest=pose.clone();poseAt=poseAtMs;
    }
    public void stop(long now){if(state==State.STARTING||state==State.RUNNING){state=State.STOPPING;note="等待当前传输完成后退出";pump(peer,now);}}
    private void fail(String reason){state=State.UNCERTAIN;note=reason;/* in-flight ownership remains in NativeTransfer */}
    private boolean send(int operation,byte[] body,long now){
        if(pending||seq==0xffffffffL)return false;long request=seq+1;
        byte[] packet=operation>=NavMapCodec.SCENE?NavMapCodec.wrap(operation,sid,request,body):NativeNavCodec.packetBytes(operation,sid,request,body);if(packet==null)return false;
        pending=true;op=operation;sending=body;sendingKey=latestKey;seq=request;lastWire=now;deadline=now+(operation==NavMapCodec.POSE?3000:8000);note="等待文件及TNA1回执";
        if(!sender.send(packet,sid,seq)){pending=false;sending=null;mapSending=null;return false;}return true;
    }
    private static byte[] aged(byte[] pose,long age){byte[] p=pose.clone();p[10]=(byte)age;p[11]=(byte)(age>>8);return p;}
    public void pump(String current,long now){
        if(state==State.IDLE||state==State.STOPPED||state==State.UNCERTAIN)return;
        if(!peer.equals(current)){fail("连接已变化，停止发送；请在眼镜确认旧画面退出");return;}
        if(pending){if(now>=deadline)fail(op==NavMapCodec.POSE?"小地图位姿3秒未确认，停止发送；不会自动重发":"原生导航8秒未确认，停止发送；不会自动重发");return;}
        if(now<next)return;
        if(state==State.STOPPING){if(!send(NativeNavCodec.STOP,null,now))fail("退出未能提交，请用眼镜按键退出");return;}
        if(state!=State.RUNNING)return;
        if(extended&&!probed){if(!send(NativeNavCodec.QUERY,null,now))next=now+1000;return;}
        if(extended&&mapCommitted!=null&&mapLatest==null){if(!send(NavMapCodec.CLEAR,null,now))next=now+1000;return;}
        boolean fresh=now-lastOffer<=15000,changed=!Arrays.equals(latest,committed),urgent=committedKey!=null&&!latestKey.equals(committedKey);
        if(fresh&&(urgent||now-lastCommit>=10000||(changed&&now-lastCommit>=1000))){if(!send(NativeNavCodec.UPDATE,latest,now)){next=now+1000;note="传输繁忙，合并最新导航帧";}return;}
        if(extended&&fresh&&poseLatest!=null&&now>=poseAt&&now-poseAt<=4000){
            byte[] map=mapV2&&map2Latest!=null?map2Latest:mapLatest;long age=now-poseAt;
            if(map!=null&&!Arrays.equals(map,mapCommitted)){
                boolean ok;if(mapV2&&map2Latest!=null){byte[] combined=map.clone();System.arraycopy(aged(poseLatest,age),0,combined,combined.length-12,12);mapSending=map;ok=send(NavMapCodec.SCENE2,combined,now);}
                else ok=send(NavMapCodec.SCENE,map,now);
                if(!ok){mapSending=null;next=now+1000;}return;
            }
            if(mapCommitted!=null&&now-lastPose>=200&&(poseCommitted==null||!Arrays.equals(Arrays.copyOf(poseLatest,10),Arrays.copyOf(poseCommitted,10))||now-lastPose>=1000)){if(!send(NavMapCodec.POSE,aged(poseLatest,age),now))next=now+1000;return;}
        }
        if(!extended&&fresh&&changed){if(!send(NativeNavCodec.UPDATE,latest,now)){next=now+1000;note="传输繁忙，合并最新导航帧";}return;}
        if(now-lastWire>=10000){if(!send(NativeNavCodec.HEARTBEAT,null,now))next=now+1000;}
    }
    public void complete(long request,boolean confirmed,int result,NativeNavCodec.Reply reply,long now){
        if(request!=seq||!pending)return;pending=false;if(state==State.UNCERTAIN)return;
        if(now>=deadline||!confirmed||reply==null||reply.sid!=sid||reply.seq!=seq||result!=0||reply.result!=0||(op==NativeNavCodec.STOP?reply.active:!reply.active)){fail("导航结果未确认或被拒绝（"+result+"），不自动重发");return;}
        next=now+(extended?0:1000);
        if(op==NativeNavCodec.START||op==NativeNavCodec.UPDATE){committed=sending;committedKey=sendingKey;lastCommit=now;count++;}
        if(op==NativeNavCodec.QUERY){probed=true;mapV2=(reply.capabilities&1)!=0;}
        if(op==NavMapCodec.SCENE){mapCommitted=sending;poseCommitted=null;maps++;}
        if(op==NavMapCodec.SCENE2){mapCommitted=mapSending;poseCommitted=Arrays.copyOfRange(sending,sending.length-12,sending.length);lastPose=now;maps++;poses++;}
        if(op==NavMapCodec.POSE){poseCommitted=sending;lastPose=now;poses++;}
        if(op==NavMapCodec.CLEAR){mapCommitted=null;poseCommitted=null;}
        sending=null;mapSending=null;
        if(op==NativeNavCodec.STOP){state=State.STOPPED;note="眼镜已确认退出原生导航";}else {if(state==State.STARTING)state=State.RUNNING;note="眼镜已确认原生导航";}
    }
}
