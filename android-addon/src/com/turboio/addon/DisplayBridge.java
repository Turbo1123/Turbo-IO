package com.turboio.addon;
import android.os.*;

/** Glue for the TDP1 lab (iOS DisplayPhoneUI Setup/CheckPeer + DisplayPhoneTransport): one TdpSession pinned to the
 * current official peer. Each packet is turbo-display.tdp on the shared NativeTransfer lane (5 s); the matching
 * turbo_display_v1 reply self-acks the shared gate (0 accepted, 1 refused) and the gate's terminal is the file
 * terminal. Main thread only. */
final class DisplayBridge {
    private static final Handler MAIN=new Handler(Looper.getMainLooper());
    private static TdpSession session;private static String peer;private static boolean invalidated,installed;
    static Runnable changed;
    private DisplayBridge(){}
    static TdpSession session(){return session;}
    /** A frame, delta or packet is in flight: other glasses features and OTA wait. */
    static boolean active(){return session!=null&&session.busy();}
    private static void notifyUI(){Runnable r=changed;if(r!=null)try{r.run();}catch(RuntimeException ignored){}}
    /** Bind (or keep) the session for the current official peer. Never discards a session with uncertain ownership. */
    static boolean setup(){
        if(!installed){installed=true;NativeTransfer.receive(DisplayBridge::message);}
        String current=NativeTransfer.connected();if(current==null||current.isEmpty())return false;
        if(session!=null&&current.equals(peer)){invalidated=false;return true;}
        if(session!=null&&session.busy())return false;
        peer=current;invalidated=false;
        session=new TdpSession(current,()->SystemClock.elapsedRealtime()/1000.0,DisplayBridge::send,MAIN::post);
        session.changed=DisplayBridge::notifyUI;return true;
    }
    static void checkPeer(){if(session!=null&&!invalidated&&!peer.equals(NativeTransfer.connected())){invalidated=true;session.disconnect();}}
    static void tick(){checkPeer();if(session!=null)session.tick();}
    static void foreground(boolean active){if(session!=null)session.setForeground(active);}
    private static boolean send(byte[] packet){
        TdpSession owner=session;
        if(owner==null||!Tdp.valid(packet)||!owner.device().equals(NativeTransfer.connected()))return false;
        return NativeTransfer.send(Tdp.FILE,packet,Tdp.u32(packet,12),Tdp.u32(packet,8),5000,(state,result)->{
            if(owner!=session)return;
            owner.fileDone(state==TransferGate.State.CONFIRMED||state==TransferGate.State.REJECTED?TdpSession.FILE_OK:state==TransferGate.State.FAILED?TdpSession.FILE_FAILED:TdpSession.FILE_UNKNOWN);
            notifyUI();});
    }
    private static void message(String from,byte[] bytes){
        TdpSession s=session;if(s==null)return;checkPeer();
        byte[] p=s.inflight();int verdict=s.reply(from,15,bytes);
        if(verdict>=0&&p!=null)NativeTransfer.ack(from,Tdp.u32(p,12),Tdp.u32(p,8),verdict);
        notifyUI();
    }
}
