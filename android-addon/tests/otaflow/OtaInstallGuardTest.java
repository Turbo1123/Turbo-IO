package com.turboio.addon;

import android.app.Application;
import android.os.*;
import java.nio.file.*;

/** Complete controller path, fake transport only. Regression for the 06 review finding. */
public final class OtaInstallGuardTest {
 static int n;
 static void ok(boolean b){n++;if(!b)throw new AssertionError("install guard "+n+"\n"+OtaController.status());}
 static void event(int type,Object json){OtaControllerTest.event(type,json);}
 static void poll()throws Exception{OtaControllerTest.poll();}
 static OtaSession state()throws Exception{return OtaControllerTest.state();}
 static void noQueries(int count){for(int i=0;i<3;i++){OtaController.readback();OtaController.releaseAfterInspection();Handler.drain();}ok(NavReflect.sent.size()==count);ok(OtaController.critical());}
 public static void main(String[] args)throws Exception{
  Application app=new Application();OtaController.init(app);OtaController.importPackage(Files.readAllBytes(Paths.get(args[0])));
  for(int i=0;i<500&&!OtaController.status().contains("候选校验通过");i++){Thread.sleep(10);Handler.drain();}
  ok(NavReflect.sent.isEmpty());OtaControllerTest.ready();OtaController.authorize("TAP1");OtaService.ready=true;OtaController.start();Handler.drain();
  event(4,OtaFrame.object("Result",true));event(5,null);event(6,OtaFrame.object("OtaVersion",OtaPackage.VERSION));
  for(int at=0;at<OtaPackage.AP_SIZE;at+=51200)event(7,OtaFrame.object("Name","nuttx_ap.bin","Start",at,"Size",Math.min(51200,OtaPackage.AP_SIZE-at)));
  event(9,null);ok(state().state()==OtaSession.State.INSTALLING);ok("INSTALLING".equals(app.prefs.disk.get("phase")));
  int before=NavReflect.sent.size();noQueries(before);OtaController.confirmRecoveryHome("已回首页");noQueries(before);
  // Unsolicited old-version/idle responses cannot manufacture READBACK.
  event(1,OtaControllerTest.version());event(11,OtaFrame.object("Result",true));noQueries(before);
  SystemClock.now+=60001;poll();noQueries(before); // time alone
  NativeTransfer.current=null;poll();SystemClock.now+=1500;poll();NativeTransfer.current="device-test";poll();SystemClock.now+=3000;poll();noQueries(before); // API failure not link loss
  NativeTransfer.current="different-eye";poll();SystemClock.now+=1500;poll();NativeTransfer.current="device-test";poll();SystemClock.now+=3000;poll();noQueries(before);
  NativeTransfer.current="";poll();SystemClock.now+=1001;poll();NativeTransfer.current="device-test";poll();noQueries(before);SystemClock.now+=2001;poll();
  ok(NavReflect.sent.size()==before); // passive reconnect never sends on its own
  OtaController.readback();Handler.drain();ok(NavReflect.sent.size()==before+1);ok(OtaFrame.decode(NavReflect.sent.get(before).data).type==1);
  event(1,OtaControllerTest.version());event(11,OtaFrame.object("Result",true));ok(state().state()==OtaSession.State.READBACK&&OtaController.critical());
  NativeTransfer.current="";poll();OtaController.releaseAfterInspection();ok(OtaController.critical());ok(state().state()==OtaSession.State.UNKNOWN);
  SystemClock.now+=1001;poll();NativeTransfer.current="device-test";poll();SystemClock.now+=2001;poll();OtaController.releaseAfterInspection();ok(OtaController.critical()); // old readback invalid
  OtaController.readback();Handler.drain();event(1,OtaControllerTest.version());event(11,OtaFrame.object("Result",true));OtaController.releaseAfterInspection();ok(!OtaController.critical());ok(Boolean.FALSE.equals(app.prefs.disk.get("pending")));
  int starts=0;for(NavReflect.Message message:NavReflect.sent)if(OtaFrame.decode(message.data).type==4)starts++;ok(starts==1);
  System.out.println("OTA install/reconnect controller: "+n+" checks + "+OtaControllerTest.n+" event checks; old immediate-release sequence denied.");
 }
}
