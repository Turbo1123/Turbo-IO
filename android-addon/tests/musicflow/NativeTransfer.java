package com.turboio.addon;
final class NativeTransfer {
 interface Receiver{void message(String peer,byte[] b);}interface Completion{void done(TransferGate.State state,int result);}
 static class Main {void removeCallbacks(Runnable r){}void postDelayed(Runnable r,long ms){}}
 static final Main MAIN=new Main();static Receiver receiver;static Completion completion;static byte[] sent;static boolean busy;static long request,session;static int sends;static String peer="glasses";
 static void receive(Receiver r){receiver=r;}static String connected(){return peer;}static boolean busy(){return busy;}
 static boolean send(String name,byte[] bytes,long req,long sid,long timeout,Completion c){if(busy)return false;busy=true;sent=bytes;request=req;session=sid;completion=c;sends++;return true;}
 static void ack(String d,long req,long sid,int result){if(!d.equals(peer)||req!=request||sid!=session||!busy)return;complete(result==0?TransferGate.State.CONFIRMED:TransferGate.State.REJECTED,result);}
 static void complete(TransferGate.State s,int result){busy=false;Completion c=completion;completion=null;c.done(s,result);}
}
final class NativeNavigation{static boolean active(){return false;}}
final class NavGlasses{static boolean active(){return false;}}
