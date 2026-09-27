package com.turboio.addon;
final class NativeTransfer {
 interface Receiver{void message(String peer,byte[] data);}interface Completion{void done(TransferGate.State state,int result);}
 static Receiver receiver;static Completion completion;static byte[] sent;static int sends;static long request,session;static boolean busy,refuse;static String peer="glasses";
 static void receive(Receiver r){receiver=r;}static String connected(){return peer;}static boolean busy(){return busy;}static String status(){return "mock";}
 static boolean send(String name,byte[] data,long req,long sid,Completion c){if(busy||refuse)return false;sent=data;request=req;session=sid;completion=c;busy=true;sends++;return true;}
 static void ack(String d,long req,long sid,int result){if(busy&&d.equals(peer)&&req==request&&sid==session)finish(result==0?TransferGate.State.CONFIRMED:TransferGate.State.REJECTED,result);}
 static void finish(TransferGate.State state,int result){Completion c=completion;completion=null;busy=false;c.done(state,result);}
}
