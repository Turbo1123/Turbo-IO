package com.turboio.addon;
import java.util.*;
final class NativeTransfer {
 static String current="device-test";
 static String connected(){return current==null?"":current;}static String otaConnection(){return current;}
 static boolean acquireMessages(String owner){return true;}static void releaseMessages(String owner){}
}
final class OtaController {static boolean critical(){return false;}static boolean busy(){return false;}}
final class OtaService {static boolean ready=true;static boolean alive(){return ready;}static void finish(){}}
final class NavReflect {
 enum Biz{MARS_FOTA,LAUNCHER}enum Priority{NORMAL}
 static final Object manager=new Object();
 /** Field names match the host message class so the bridge's reflective detach works. */
 static final class Message {String b;Biz c;byte[] e;Message(byte[] e,String b,Biz c){this.e=e;this.b=b;this.c=c;}}
 static final List<Message> sent=new ArrayList<>();
 static Class<?> type(String name){if(name.equals(HostAbi.business()))return Biz.class;if(name.equals(HostAbi.priority()))return Priority.class;return NavReflect.class;}
 static Object field(Object o,String name)throws Exception{if(name.equals("h"))return manager;Message m=(Message)o;if(name.equals("c"))return m.c;if(name.equals("e"))return m.e;if(name.equals("b"))return m.b;throw new IllegalArgumentException(name);}
 static Object make(String name,Object...a){return new Message((byte[])a[0],(String)a[2],(Biz)a[3]);}
 interface Callback{void accept(String name,Object[] args)throws Exception;}
 static Object proxy(String name,Callback cb){return cb;}
 static Object call(Object o,String name,Object...a)throws Exception{
  if(name.equals("valueOf"))return o==Biz.class?Biz.valueOf((String)a[0]):Priority.NORMAL;
  // The vendor queue hook consults the bridge before anything leaves the phone.
  if(name.equals(HostAbi.send())){Message m=(Message)a[0];if(Boolean.TRUE.equals(OfficialOtaBridge.allowQueue(m)))sent.add(m);return null;}
  throw new IllegalArgumentException(name);
 }
}
