package com.turboio.addon;

import android.app.Application;
import android.os.*;
import java.lang.reflect.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

/** Official GUARD bridge: the manual result-guard release is the last fence after a flash.
 * TVP2, stock and TMIG1 all report Strix OS 1.0.5.5, so release must need a fresh,
 * solicited readback from the same glasses plus a durable journal write. Fakes only. */
public final class OfficialOtaReleaseTest {
 static int n;static Application app;
 static void ok(boolean b){n++;if(!b)throw new AssertionError("release "+n+"\n"+OfficialOtaBridge.status());}
 static Object get(String f)throws Exception{Field x=OfficialOtaBridge.class.getDeclaredField(f);x.setAccessible(true);return x.get(null);}
 static void call(String m)throws Exception{Method x=OfficialOtaBridge.class.getDeclaredMethod(m);x.setAccessible(true);x.invoke(null);}
 static void tick()throws Exception{((Runnable)get("ticker")).run();}
 static boolean pending()throws Exception{return (Boolean)get("pending");}
 static void at(long t)throws Exception{SystemClock.now=t;tick();}
 static void reply(int type,Object json){Map<String,Object> m=new HashMap<>();m.put("businessId",9);m.put("deviceId",NativeTransfer.current);m.put("payload",OtaFrame.encode(type,json,null));Map<String,Object> e=new HashMap<>();e.put("message",m);OfficialOtaBridge.observe("messageReceived",e);}
 static Object version(String os){return OtaFrame.object("OsVersion",os,"OtaValidationState","idle","OtaValidationConfirmed",true,"PackageTypes",Arrays.asList("files"));}
 static void readback(String os)throws Exception{int before=NavReflect.sent.size();call("readback");ok(NavReflect.sent.size()==before+2);reply(1,version(os));reply(11,OtaFrame.object("Result",true));}
 public static void main(String[] args)throws Exception{
  // Fresh process after an interrupted official install: journal says pending for this peer.
  app=new Application();
  app.prefs.disk.put("pending",true);app.prefs.disk.put("peer",OtaPackage.hash("SHA-256","device-test".getBytes(StandardCharsets.UTF_8)));
  OfficialOtaBridge.init(app);Handler.drain();ok(pending());ok(get("recovery")!=null);
  call("release");ok(pending()&&Boolean.TRUE.equals(app.prefs.disk.get("pending")));          // no protection window yet
  at(100+OtaRecoveryGuard.MANUAL_QUIET_MS+1);call("release");ok(pending());                    // window passed, no readback
  int sent=NavReflect.sent.size();
  // Wrong firmware readback (old base) never releases; neither does an unsolicited reply.
  readback("Strix OS 1.0.4.12");call("release");ok(pending());
  reply(1,version("Strix OS 1.0.5.5"));reply(11,OtaFrame.object("Result",true));call("release");ok(pending());
  // Correct readback but a different pair of glasses connected: still guarded.
  readback("Strix OS 1.0.5.5");NativeTransfer.current="other-glasses";call("release");ok(pending());NativeTransfer.current="device-test";tick();
  // Durable journal write fails: guard stays, in memory and on disk.
  at(SystemClock.now+OtaRecoveryGuard.STABLE_MS+1);readback("Strix OS 1.0.5.5");app.prefs.fail=true;call("release");ok(pending()&&Boolean.TRUE.equals(app.prefs.disk.get("pending")));app.prefs.fail=false;
  // A readback older than 60 s is not fresh any more.
  readback("Strix OS 1.0.5.5");at(SystemClock.now+60001);call("release");ok(pending());
  // Link drops and comes straight back after a valid readback: the 2 s stable window applies again.
  at(SystemClock.now+OtaRecoveryGuard.STABLE_MS+1);readback("Strix OS 1.0.5.5");NativeTransfer.current="";at(SystemClock.now+OtaRecoveryGuard.DOWN_MS+1);NativeTransfer.current="device-test";tick();call("release");ok(pending());
  at(SystemClock.now+OtaRecoveryGuard.STABLE_MS+1);
  // Fresh solicited 1.0.5.5 + idle from the same glasses, journal writable: released exactly once.
  readback("Strix OS 1.0.5.5");call("release");ok(!pending()&&Boolean.FALSE.equals(app.prefs.disk.get("pending"))&&"USER_INSPECTED_TEST".equals(app.prefs.disk.get("phase")));
  ok(OfficialOtaBridge.status().contains("授权：0"));
  // Only read-only queries (type 1 / 11) ever left the phone in this whole recovery.
  for(int i=sent;i<NavReflect.sent.size();i++){int t=OtaFrame.decode(NavReflect.sent.get(i).e).type;ok(t==1||t==11);}
  System.out.println("Official OTA manual release: "+n+" checks; peer, freshness, version, solicitation and journal fences. No device I/O.");
 }
}
