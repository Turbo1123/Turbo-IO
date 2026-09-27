package com.turboio.addon;

/** Shared file+application acknowledgement gate. Never equates SDK submission with success. */
public final class TransferGate {
    public enum State {IDLE,SUBMITTING,WAITING,CONFIRMED,REJECTED,FAILED,UNCERTAIN}
    private State state=State.IDLE;
    private String peer="",task="",file="";
    private long request,session,deadline;
    private boolean submitted,fileDone,ack;
    private int result;
    public State state(){return state;}
    public String evidence(){return "file="+fileDone+", appAck="+ack+", result="+result;}
    public boolean busy(){return state==State.SUBMITTING||state==State.WAITING;}
    public int result(){return result;}
    public boolean mayDeleteSpool(){return submitted&&fileDone;}
    public void begin(String p,String f,long r,long s,long now,long timeout){
        if(busy())throw new IllegalStateException("transfer busy");
        if(p==null||p.isEmpty()||f==null||!(f.matches("turbo-[a-z-]+\\.[a-z]+")||f.matches("[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}"))||r<1||r>0xffffffffL||s<0||s>0xffffffffL||now<0||timeout<1||timeout>120000||now>Long.MAX_VALUE-timeout)throw new IllegalArgumentException("transfer identity");
        peer=p;file=f;request=r;session=s;task="";deadline=now+timeout;
        submitted=fileDone=ack=false;result=0;state=State.SUBMITTING;
    }
    public void submitted(String nativeTask){
        if(!busy())return;
        if(nativeTask==null||nativeTask.isEmpty()||nativeTask.length()>256){state=State.UNCERTAIN;return;}
        if(submitted){if(!task.equals(nativeTask))state=State.UNCERTAIN;return;}
        task=nativeTask;submitted=true;state=State.WAITING;finish();
    }
    public boolean fileResult(String p,String nativeTask,String filename,boolean sender,boolean success){
        if(!busy()||!submitted||!sender||!peer.equals(p)||!task.equals(nativeTask)||!file.equals(filename))return false;
        if(!success){state=State.FAILED;return true;}
        fileDone=true;finish();return true;
    }
    public boolean acknowledgement(String p,long r,long s,int code){
        if(!busy()||!peer.equals(p)||request!=r||session!=s||code<0||code>255)return false;
        if(ack&&result!=code){state=State.UNCERTAIN;return false;}
        ack=true;result=code;finish();return true;
    }
    public void tick(String currentPeer,long now){
        if(!busy())return;
        if(!peer.equals(currentPeer)||now>=deadline)state=State.UNCERTAIN;
    }
    public void failed(){if(busy())state=State.UNCERTAIN;}
    private void finish(){if(submitted&&fileDone&&ack)state=result==0?State.CONFIRMED:State.REJECTED;}
}
