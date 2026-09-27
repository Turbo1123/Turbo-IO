package com.turboio.addon;
import java.util.*;
final class NavReflect {
 enum Biz{MARS_FOTA,LAUNCHER,HEARTBEAT}enum Priority{NORMAL}static Object manager=new Object(),error=new Object();static boolean ack=true;
 static final List<Message> sent=new ArrayList<>();
 static class Message {String peer;byte[] data;Biz business;Callback cb;Message(byte[] d,String p,Biz b){data=d;peer=p;business=b;}}
 interface Callback{void accept(String n,Object[] args)throws Exception;}
 static Class<?> type(String name){if(name.equals("P3.h"))return Biz.class;if(name.equals("E3.b"))return Priority.class;return NavReflect.class;}
 static Object field(Object o,String name){if(name.equals("h"))return manager;if(name.equals("r"))return error;Message m=(Message)o;if(name.equals("c"))return m.business;if(name.equals("e"))return m.data;if(name.equals("b"))return m.peer;if(name.equals("k"))return m.cb;throw new IllegalArgumentException();}
 static Object make(String name,Object...args){return new Message((byte[])args[0],(String)args[2],(Biz)args[3]);}
 static Object proxy(String name,Callback cb){return cb;}
 static Object call(Object o,String name,Object...args)throws Exception{
  if(name.equals("valueOf"))return o==Biz.class?Biz.valueOf((String)args[0]):Priority.NORMAL;
  if(name.equals("u")){Message m=(Message)args[0];m.cb=(Callback)args[1];if(OtaController.allowQueue(m)){sent.add(m);if(ack)m.cb.accept("invoke",new Object[]{m,null});}else m.cb.accept("invoke",new Object[]{m,error});return null;}
  if(name.equals("invoke")){((Callback)o).accept("invoke",args);return null;}throw new IllegalArgumentException(name);
 }
}
