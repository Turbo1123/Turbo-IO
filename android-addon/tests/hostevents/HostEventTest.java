package com.turboio.addon;
import java.util.*;
/** Exercises production NativeTransfer.event, not a replacement transport. */
public class HostEventTest {
 static int checks,launcher;static byte[] received;
 static void ok(boolean b){checks++;if(!b)throw new AssertionError("callback "+checks);}
 static Map<String,Object> message(Object business,Object data){Map<String,Object> m=new HashMap<>();m.put("businessId",business);m.put("deviceId","test-peer");m.put("payload",data);return Collections.singletonMap("message",m);}
 public static void main(String[] args){
  NativeTransfer.receive((peer,b)->{throw new IllegalArgumentException("broken observer must not block others");});
  NativeTransfer.receive((peer,b)->{ok(peer.equals("test-peer"));launcher++;received=b;});
  byte[] data={8,1,16,6};
  for(Object business:new Object[]{"LAUNCHER","15",15,15L}){int before=launcher;NativeTransfer.event("messageReceived",message(business,data));ok(launcher==before+1);ok(received!=data&&Arrays.equals(received,data));}
  for(Object business:new Object[]{"TELEPROMPTER","20",20}){int before=NewsTele.count;NativeTransfer.event("messageReceived",message(business,data));ok(NewsTele.count==before+1);}
  int before=launcher;
  for(Object business:new Object[]{null,15.0,"launcher","LAUNCHER_EXTRA","MARS_FOTA",9})NativeTransfer.event("messageReceived",message(business,data));
  NativeTransfer.event("messageReceived",message("LAUNCHER",new byte[8193]));
  NativeTransfer.event("messageReceived",message("LAUNCHER",Arrays.asList(8,1)));
  NativeTransfer.event("messageReceived",null);NativeTransfer.event(null,message("LAUNCHER",data));
  ok(launcher==before);ok(NewsTele.count==3);
  // Phase 5a: the TIMG file is the one 4-letter-extension name and the one exact 64 KiB+32 size admitted.
  ok(NativeTransfer.admits("turbo-photo.timg",false,65568)&&!NativeTransfer.admits("turbo-photo.timg",false,65567)&&!NativeTransfer.admits("turbo-photo.timg",false,65569));
  ok(NativeTransfer.admits("turbo-photo.timg",false,1000)&&!NativeTransfer.admits("turbo-other.timg",false,1000)&&!NativeTransfer.admits("turbo-x.tdpx",false,10));
  ok(NativeTransfer.admits("turbo-ride.tdr",false,20700)&&!NativeTransfer.admits("turbo-ride.tdr",false,20701)&&!NativeTransfer.admits("turbo-ride.tdr",false,65568)&&NativeTransfer.admits("turbo-ride.tdr",true,48000)&&!NativeTransfer.admits("turbo-ride.tdr",false,0));
  // A display frame in flight makes the shared lane busy for every start path.
  ok(!NativeTransfer.busy());DisplayBridge.on=true;ok(NativeTransfer.busy());DisplayBridge.on=false;
  System.out.println("HostEventTest: "+checks+" production callback checks; no device/file/network I/O");
 }
}
class NavReflect {
 interface Callback{void accept(String method,Object[] args)throws Exception;}
 static Object call(Object o,String s,Object...args)throws Exception{return Collections.emptyList();}
 static Object field(Object o,String s)throws Exception{return null;}
 static Class<?> type(String name)throws Exception{return Object.class;}
 static Object make(String name,Object...args)throws Exception{return null;}
 static Object proxy(String name,Callback cb)throws Exception{return null;}
}
class OtaController {static boolean busy(){return false;}}
class EntryProbe {static void event(String kind,Map<?,?> data){}}
class NavGlasses {static boolean active(){return false;}static void event(String k,Map<?,?> m){}}
class NativeNavigation {static boolean active(){return false;}}
class ReaderBridge {static boolean active(){return false;}}
class MusicBridge {static boolean active(){return false;}}
class DisplayBridge {static boolean on;static boolean active(){return on;}}
class NewsTele {static int count;static void receive(String peer,byte[] data){if(!peer.equals("test-peer"))throw new AssertionError();count++;}}
