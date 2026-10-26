package com.turboio.addon;
import java.util.*;

/** Test-only transport double: one file transfer at a time, settled explicitly by the test. */
final class NativeTransfer {
    interface Receiver{void message(String peer,byte[] data);}interface Completion{void done(TransferGate.State state,int result);}
    static final class Sent{final String name;final byte[] bytes;final long request,session,timeout;Completion done;boolean acked;Sent(String n,byte[] b,long r,long s,long t,Completion c){name=n;bytes=b;request=r;session=s;timeout=t;done=c;}}
    static Receiver receiver;static String peer="test-peer";static boolean busyOther;static final List<Sent> sent=new ArrayList<>();
    /** Mirrors the real lane: an unconfirmed transfer quarantines every sender for 60 s. */
    static long quarantine;static volatile boolean diagnosticsActive;
    static void receive(Receiver r){receiver=r;}static String connected(){return peer;}
    static boolean busy(){return busyOther||(!sent.isEmpty()&&sent.get(sent.size()-1).done!=null);}
    static boolean send(String name,byte[] bytes,long request,long session,long timeout,Completion c){if(busy()||peer.isEmpty()||android.os.SystemClock.elapsedRealtime()<quarantine)return false;sent.add(new Sent(name,bytes.clone(),request,session,timeout,c));return true;}
    static void ack(String d,long request,long session,int result){if(sent.isEmpty())return;Sent s=sent.get(sent.size()-1);if(s.done!=null&&d.equals(peer)&&s.request==request&&s.session==session)s.acked=true;}
    /** Settle the in-flight transfer; CONFIRMED only when the app-level ack was given, as TransferGate requires. */
    static void settle(boolean fileOk){Sent s=sent.get(sent.size()-1);Completion c=s.done;s.done=null;TransferGate.State st=!fileOk?TransferGate.State.FAILED:s.acked?TransferGate.State.CONFIRMED:TransferGate.State.UNCERTAIN;
        if(st!=TransferGate.State.CONFIRMED)quarantine=android.os.SystemClock.elapsedRealtime()+60000;c.done(st,0);}
}
