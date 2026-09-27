package com.turboio.addon;
import java.util.*;
/** Test-only transport double. Never compiled into the addon DEX. */
final class NativeTransfer {
    interface Receiver{void message(String peer,byte[] bytes);}
    static Receiver receiver;static String peer="test-peer",lease="";static List<byte[]> packets=new ArrayList<>();static Runnable fail;
    static final FakeMain MAIN=new FakeMain();static class FakeMain{final List<Runnable> delayed=new ArrayList<>();void postDelayed(Runnable r,long ms){delayed.add(r);}void expire(){List<Runnable> copy=new ArrayList<>(delayed);delayed.clear();for(Runnable r:copy)r.run();}}
    static void receive(Receiver r){receiver=r;}
    static String connected(){return peer;}
    static boolean acquireMessages(String owner){if(!lease.isEmpty()||peer.isEmpty())return false;lease=owner;return true;}
    static void releaseMessages(String owner){if(lease.equals(owner))lease="";}
    static void sendMessage(String owner,String device,byte[] payload,Runnable failed){if(!owner.equals(lease)||!peer.equals(device))throw new IllegalStateException();packets.add(payload.clone());fail=failed;}
}
