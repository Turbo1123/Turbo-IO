package com.turboio.addon;

import android.os.SystemClock;
import java.util.Map;
import java.util.UUID;

/** One read-only stock idle query. Never starts OTA or changes a glasses business. */
final class EntryProbe {
 private static final String OWNER="entry-read-only";
 private static String peer="",note="尚未检查入口状态";
 private static long generation,until;
 static String status(){return note;}
 static void event(String kind,Map<?,?> data){
  if(!"messageReceived".equals(kind)||data==null)return;
  Object raw=data.get("message");if(!(raw instanceof Map))return;Map<?,?> m=(Map<?,?>)raw;
  if(HostBusiness.id(m.get("businessId"))!=9)return;Object d=m.get("deviceId"),b=m.get("payload");
  if(!(d instanceof String)||((String)d).length()>256||!(b instanceof byte[])||((byte[])b).length>8192)return;
  byte[] copy=((byte[])b).clone();NativeTransfer.MAIN.post(()->receive((String)d,copy));
 }
 static void query(){
  if(!NativeTransfer.acquireMessages(OWNER)){note="当前通道占用，未查询";return;}
  peer=NativeTransfer.connected();long token=++generation;until=SystemClock.elapsedRealtime()+5000;
  note="正在只读查询眼镜业务空闲状态";
  try{
   byte[] payload=OtaFrame.encode(11,null,null);
   if(!OtaFrame.readOnly(payload))throw new IllegalStateException();
   Object manager=NavReflect.field(NavReflect.type("E3.u"),"h"),business=NavReflect.call(NavReflect.type("P3.h"),"valueOf","MARS_FOTA"),priority=NavReflect.call(NavReflect.type("E3.b"),"valueOf","NORMAL");
   Object message=NavReflect.make("E3.Q",payload,UUID.randomUUID().toString(),peer,business,null,priority,false,false,null,null);
   Object callback=NavReflect.proxy("kotlin.jvm.functions.Function2",(name,args)->{if(args.length>1&&args[1]!=null)NativeTransfer.MAIN.post(()->finish(token,"状态查询发送失败"));});
   NavReflect.call(manager,"u",message,callback);
   NativeTransfer.MAIN.postDelayed(()->finish(token,"状态查询超时；未重试、未改变业务"),5000);
  }catch(Exception e){finish(token,"状态查询不可用；未改变业务");}
 }
 static void receive(String device,byte[] bytes){
  if(until==0||SystemClock.elapsedRealtime()>until||!peer.equals(device)||!peer.equals(NativeTransfer.connected()))return;
  try{OtaFrame f=OtaFrame.decode(bytes);if(f.type!=11||f.binary.length!=0||!(f.json instanceof Map))return;
   Object idle=((Map<?,?>)f.json).get("Result");if(!(idle instanceof Boolean))return;
   finish(generation,(Boolean)idle?"原厂空闲检查：空闲（不等同于阅读页入口已通过）":"原厂空闲检查：忙碌（语音/智记或其他前台业务）");
  }catch(RuntimeException ignored){}
 }
 private static void finish(long token,String value){if(token!=generation||until==0)return;until=0;note=value;NativeTransfer.releaseMessages(OWNER);android.util.Log.i("TurboIOTransfer","entry probe: "+value);}
}
