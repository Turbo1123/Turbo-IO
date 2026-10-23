package com.turboio.addon;
import android.app.Application;import android.os.*;import java.nio.file.*;import java.util.*;
public final class OtaControllerTest {
 static int n;static void ok(boolean value){n++;if(!value)throw new AssertionError("check "+n+"\n"+OtaController.status());}
 static OtaSession state()throws Exception{java.lang.reflect.Field f=OtaController.class.getDeclaredField("session");f.setAccessible(true);return (OtaSession)f.get(null);}
 static void poll()throws Exception{java.lang.reflect.Field f=OtaController.class.getDeclaredField("tick");f.setAccessible(true);((Runnable)f.get(null)).run();Handler.drain();}
 static void manualRecovery()throws Exception{int before=NavReflect.sent.size();poll();OtaController.readback();Handler.drain();ok(NavReflect.sent.size()==before);SystemClock.now+=120001;poll();OtaController.readback();Handler.drain();ok(NavReflect.sent.size()==before);OtaController.confirmRecoveryHome("已回首页");ok(NavReflect.sent.size()==before);}
 static Map<String,Object> version(){return OtaFrame.object("OsVersion",OtaPackage.VERSION,"OtaValidationState","idle","OtaValidationConfirmed",true,"PackageTypes",Arrays.asList("files","zip"));}
 static void event(int type,Object j){Map<String,Object> m=OtaFrame.object("message",OtaFrame.object("businessId","MARS_FOTA","deviceId",NativeTransfer.current,"payload",OtaFrame.encode(type,j,null)));boolean intercepted=OtaController.intercepting();ok(OtaController.consume("messageReceived",m)==intercepted);Handler.drain();}
 static void ready()throws Exception{
  OtaController.prepare();Handler.drain();ok(!OtaController.intercepting()&&OtaController.allowFile());
  // Never swallow an existing vendor transfer during the initial read-only probe.
  NavReflect.Message existing=new NavReflect.Message(OtaFrame.encode(7,OtaFrame.object("Name","nuttx_ap.bin","Start",0,"Size",4),new byte[4]),NativeTransfer.current,NavReflect.Biz.MARS_FOTA);ok(OtaController.allowQueue(existing));Handler.drain();ok(!OtaController.busy());
  OtaController.prepare();Handler.drain();NavReflect.Message competing=new NavReflect.Message(OtaFrame.encode(4,OtaFrame.object("Mode",2),null),NativeTransfer.current,NavReflect.Biz.MARS_FOTA);ok(!OtaController.allowQueue(competing));Handler.drain();ok(!OtaController.busy());
  OtaController.prepare();Handler.drain();event(1,version());event(2,OtaFrame.object("BatteryLevel",80));event(3,OtaFrame.object("Result",true));event(11,OtaFrame.object("Result",true));ok(state().state()==OtaSession.State.READY);}
 public static void main(String[] args)throws Exception{Application app=new Application();
  // Stale persisted success/manual evidence from an older process must not be trusted.
  if(args.length>1){app.prefs.m.put("phase","READBACK");app.prefs.m.put("recoveryEvidence","USER_CONFIRMED_HOME");}
  if(args.length>1){app.prefs.m.put("pending",true);app.prefs.m.put("peerSha256",OtaPackage.hash("SHA-256","device-test".getBytes(java.nio.charset.StandardCharsets.UTF_8)));OtaController.init(app);ok(OtaController.busy()&&OtaController.critical());ok(NavReflect.sent.isEmpty());ok(!OtaController.allowFile());OtaController.prepare();OtaController.start();Handler.drain();ok(NavReflect.sent.isEmpty());manualRecovery();OtaController.readback();Handler.drain();ok(OtaFrame.decode(NavReflect.sent.get(0).data).type==1);event(1,version());event(11,OtaFrame.object("Result",true));ok(state().state()==OtaSession.State.READBACK&&OtaController.busy());app.prefs.fail=true;OtaController.releaseAfterInspection();ok(OtaController.busy()&&app.prefs.getBoolean("pending",false));app.prefs.fail=false;manualRecovery();OtaController.readback();Handler.drain();event(1,version());event(11,OtaFrame.object("Result",true));OtaController.releaseAfterInspection();ok(!OtaController.busy());System.out.println("OTA fresh-process recovery: "+n+" checks, never auto-resumes.");return;}
  OtaController.init(app);ok(!OtaController.busy());ok(OtaController.allowFile());NavReflect.Message vendor=new NavReflect.Message(OtaFrame.encode(1,null,null),NativeTransfer.current,NavReflect.Biz.MARS_FOTA);ok(OtaController.allowQueue(vendor));
  byte[] zip=Files.readAllBytes(Paths.get(args[0]));OtaController.importPackage(zip);for(int i=0;i<300&&!OtaController.status().contains("候选校验通过");i++){Thread.sleep(10);Handler.drain();}ok(OtaController.status().contains("候选校验通过"));ok(NavReflect.sent.isEmpty());ready();ok(OtaController.busy()&&!OtaController.allowFile());ok(!OtaController.allowQueue(vendor));ok(!OtaController.allowQueue(new NavReflect.Message(new byte[0],NativeTransfer.current,NavReflect.Biz.LAUNCHER)));ok(OtaController.allowQueue(new NavReflect.Message(new byte[0],NativeTransfer.current,NavReflect.Biz.HEARTBEAT)));int before=NavReflect.sent.size();OtaController.start();Handler.drain();ok(NavReflect.sent.size()==before);for(String token:new String[]{"wrong","TAP1","TMIG1","TVP2"}){OtaController.authorize(token);ok(state().state()==OtaSession.State.READY);}
  // Failed persistence MUST precede and prevent any Mode2 send.
  OtaController.start();Handler.drain();ok(NavReflect.sent.size()==before&&!app.prefs.getBoolean("pending",false));OtaService.ready=true;
  // Reproduce Fold3: service confirmation consumed the 2-minute freshness window.
  // No Mode2 and no pending journal are permitted before fresh start validation.
  SystemClock.now+=120001;OtaController.start();Handler.drain();
  ok(NavReflect.sent.size()==before&&!app.prefs.getBoolean("pending",false));
   ok(state().state()!=OtaSession.State.AUTHORIZED&&!state().started());
   // TVP2-only: the self-sender never authorizes, so no Mode 2 can ever be sent from this controller.
   ok(OtaController.status().contains("AP：7,435,336 字节")&&!OtaController.status().contains("1.0.5"));ok(state().state()==OtaSession.State.READY);OtaController.authorize("TVP2");ok(state().state()==OtaSession.State.READY);before=NavReflect.sent.size();OtaService.ready=true;OtaController.start();Handler.drain();ok(NavReflect.sent.size()==before&&!app.prefs.getBoolean("pending",false));
   for(NavReflect.Message message:NavReflect.sent)ok(OtaFrame.decode(message.data).type!=4);
  System.out.println("OTA controller: "+n+" mock SDK/journal/queue checks; no device I/O.");
 }
}
