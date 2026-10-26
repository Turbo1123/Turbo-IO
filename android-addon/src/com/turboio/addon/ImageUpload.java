package com.turboio.addon;
import java.util.*;
import java.util.function.Consumer;
import java.util.zip.CRC32;

/** One manual image session (port of iOS TIOImageUpload): authorized by the session ID shown on the glasses, 30 s
 * window, one frame in flight, ≥1 s between frames; file delivery is not display confirmation; no blind retry.
 * Main thread only; times in seconds. */
final class ImageUpload {
    interface Sender{void send(byte[] packet,String device,String task,Consumer<Boolean> submitted);}
    private final Sender sender;private String device,task,state="receiver_not_verified";private long session,frame,crc;
    private double expires,sentAt,lastTime;private long generation;private boolean active,pending,submitted,fileOK,uncertain;
    Runnable changed;
    ImageUpload(Sender sender){this.sender=sender;}
    String state(){return state;}String task(){return task;}boolean pending(){return pending;}
    private void publish(String s){state=s;if(changed!=null)changed.run();}
    boolean authorize(String dev,long sid,double now){
        if(pending||active||dev==null||dev.isEmpty()||dev.length()>200||sid<=0||sid>0xffffffffL||Double.isNaN(now)||now<0)return false;
        device=dev;session=sid;frame=0;expires=now+30;lastTime=now;active=true;uncertain=false;generation++;publish("ready");return true;
    }
    boolean send(byte[] pixels,double now){
        if(Double.isNaN(now)||now<lastTime)return false;tick(now);
        if(!active||pending||uncertain||frame==0xffffffffL||(frame>0&&now-sentAt<1))return false;
        byte[] data=Timg.packet(pixels,session,frame+1);if(data==null)return false;
        frame++;CRC32 c=new CRC32();c.update(pixels);crc=c.getValue();task=UUID.randomUUID().toString();sentAt=now;pending=true;submitted=fileOK=false;long gen=++generation;String t=task;
        publish("submitting");
        Consumer<Boolean> done=ok->{if(gen!=generation||!t.equals(task)||!pending||uncertain)return;
            if(!ok){if(fileOK){refresh();return;}pending=false;active=false;publish("submission_failed");return;}submitted=true;refresh();};
        try{sender.send(data,device,t,done);}catch(RuntimeException e){done.accept(false);}
        return true;
    }
    private void refresh(){if(uncertain)return;if(fileOK)publish("file_received_waiting_renderer");else if(submitted)publish("transferring");}
    void fileResult(String dev,String t,boolean success){
        if(!pending||uncertain||!Objects.equals(dev,device)||!Objects.equals(t,task))return;
        if(!success){active=false;pending=false;publish("file_failed");return;}fileOK=true;pending=false;refresh();
    }
    /** Shared-gate outcome: CONFIRMED is file delivery; only FAILED/REJECTED are definite failures; anything else is unknown. */
    void fileOutcome(String dev,String t,TransferGate.State st){
        if(st==TransferGate.State.CONFIRMED){fileResult(dev,t,true);return;}
        if(st==TransferGate.State.FAILED||st==TransferGate.State.REJECTED){fileResult(dev,t,false);return;}
        if(!pending||uncertain||!Objects.equals(dev,device)||!Objects.equals(t,task))return;uncertain=true;active=false;publish("timeout_result_unknown");
    }
    void tick(double now){
        if(Double.isNaN(now)||now<lastTime)return;lastTime=now;
        if(pending&&!uncertain&&(now-sentAt>=15||now>=expires)){uncertain=true;active=false;publish("timeout_result_unknown");}
        else if(active&&now>=expires){active=false;publish("session_expired");}
    }
    void disconnect(){generation++;active=false;uncertain=pending;publish(pending?"disconnected_result_unknown":"disconnected");}
}
