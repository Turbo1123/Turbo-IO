package com.turboio.addon;
import java.nio.file.*;import java.util.*;

public final class OfficialOtaGateTest {
 static OtaPackage pkg;static int checks,commits;static long now=1000;
 static void yes(boolean b){checks++;if(!b)throw new AssertionError("check "+checks);}
 static byte[] f(int t,Object j){return OtaFrame.encode(t,j,null);}
 static Object version(){return OtaFrame.object("OsVersion",OtaPackage.VERSION,"OtaValidationState","idle","OtaValidationConfirmed",true,"PackageTypes",Arrays.asList("files"));}
 static OfficialOtaGate gate(boolean durable){OfficialOtaGate g=new OfficialOtaGate(p->{commits++;return durable;});g.bind("peer");return g;}
 static void read(OfficialOtaGate g,int type,Object req,Object reply){yes(g.outbound("peer",f(type,req),now++,true,true));g.inbound("peer",f(type,reply),now++);}
 static void checks(OfficialOtaGate g){read(g,1,null,version());read(g,2,null,OtaFrame.object("BatteryLevel",80));read(g,3,OtaFrame.object("OtaSize",OtaPackage.ZIP_SIZE),OtaFrame.object("Result",true));read(g,11,null,OtaFrame.object("Result",true));}
 static void arm(OfficialOtaGate g){g.arm(pkg,"peer","TAP1-TEST-01",now++);}
 static void start(OfficialOtaGate g){yes(g.outbound("peer",f(4,OtaFrame.object("Mode",2)),now++,true,true));g.inbound("peer",f(4,OtaFrame.object("Result",true)),now++);}
 static void manifest(OfficialOtaGate g){g.inbound("peer",f(5,null),now++);yes(g.outbound("peer",f(5,OtaFrame.object("OtaVersion",OtaPackage.VERSION)),now++,true,true));g.inbound("peer",f(6,OtaFrame.object("OtaVersion",OtaPackage.VERSION)),now++);yes(g.outbound("peer",f(6,pkg.manifest()),now++,true,true));}
 static OfficialOtaGate transfer(){OfficialOtaGate g=gate(true);checks(g);arm(g);start(g);manifest(g);return g;}
 static void chunk(OfficialOtaGate g,int at,int size){Object r=OtaFrame.object("Name","nuttx_ap.bin","Start",at,"Size",size);g.inbound("peer",f(7,r),now++);yes(g.outbound("peer",OtaFrame.encode(7,r,pkg.slice("nuttx_ap.bin",at,size)),now++,true,true));}
 public static void main(String[] args)throws Exception{
  pkg=OtaPackage.verify(Files.readAllBytes(Paths.get(args[0])));
  OfficialOtaGate pre=gate(true);yes(!pre.readyToArm(now));
  read(pre,1,null,version());read(pre,11,null,OtaFrame.object("Result",true));yes(!pre.readyToArm(now));
  read(pre,2,null,OtaFrame.object("BatteryLevel",49));yes(!pre.readyToArm(now));
  read(pre,2,null,OtaFrame.object("BatteryLevel",72));yes(pre.readyToArm(now));
  yes(!pre.pending()&&pre.phase()==OfficialOtaGate.Phase.LOCKED);now+=120001;yes(!pre.readyToArm(now));
  pre=gate(true);checks(pre);yes(pre.readyToArm(now));
  yes(pre.outbound("peer",f(11,null),now++,true,true));yes(pre.readyToArm(now));
  pre.inbound("peer",f(11,OtaFrame.object("Result",false)),now++);yes(!pre.readyToArm(now));
  read(pre,11,null,OtaFrame.object("Result",true));yes(pre.readyToArm(now));
  yes(pre.outbound("peer",f(11,null),now++,true,true));now+=120001;yes(!pre.readyToArm(now));
  pre=gate(true);checks(pre);arm(pre);yes(pre.outbound("peer",f(11,null),now++,true,true));
  start(pre);yes(pre.pending());commits=0; // official Mode2 races a redundant poll, within old reply TTL
  pre=gate(true);checks(pre);now+=70000;yes(pre.readyToArm(now));
  read(pre,1,null,version());read(pre,2,null,OtaFrame.object("BatteryLevel",72));
  now+=50001;yes(!pre.readyToArm(now)); // idle is expired even though battery/version are fresh
  for(int type=1;type<=12;type++){
   OfficialOtaGate locked=gate(true);boolean allowed=locked.outbound("peer",f(type,null),now++,true,true);
   yes(allowed==(type==1||type==2||type==11));yes(!locked.pending());
  }
  for(int type=4;type<=10;type++){
   OfficialOtaGate restored=gate(true);restored.restore("peer",now++);
   yes(!restored.outbound("peer",f(type,null),now++,true,true));yes(restored.pending());
  }
  OfficialOtaGate g=gate(true);checks(g);yes(!g.outbound("peer",f(4,OtaFrame.object("Mode",2)),now++,true,true));yes(commits==0&&!g.pending());
  g=gate(false);checks(g);arm(g);yes(!g.outbound("peer",f(4,OtaFrame.object("Mode",2)),now++,true,true));yes(!g.pending());
  g=gate(true);arm(g);yes(!g.outbound("peer",f(4,OtaFrame.object("Mode",2)),now++,true,true));
  for(int variant=0;variant<6;variant++){
   g=gate(true);checks(g);arm(g);if(variant==0)now+=900001;if(variant==1)now+=120001;
   yes(!g.outbound(variant==2?"other":"peer",f(4,OtaFrame.object("Mode",variant==3?1:2)),now++,variant!=4,variant!=5));yes(!g.pending());
  }
  g=gate(true);checks(g);read(g,2,null,OtaFrame.object("BatteryLevel",49));arm(g);yes(!g.outbound("peer",f(4,OtaFrame.object("Mode",2)),now++,true,true));
  g=gate(true);checks(g);arm(g);start(g);yes(!g.outbound("peer",f(4,OtaFrame.object("Mode",2)),now++,true,true));yes(g.pending()&&g.phase()==OfficialOtaGate.Phase.UNKNOWN);
  g=gate(true);checks(g);arm(g);start(g);g.inbound("peer",f(5,null),now++);yes(!g.outbound("peer",f(5,OtaFrame.object("OtaVersion","wrong")),now++,true,true));
  g=gate(true);checks(g);arm(g);start(g);g.inbound("peer",f(5,null),now++);yes(g.outbound("peer",f(5,OtaFrame.object("OtaVersion",OtaPackage.VERSION)),now++,true,true));g.inbound("peer",f(6,OtaFrame.object("OtaVersion",OtaPackage.VERSION)),now++);List<Object> bad=BoundedJson.list(pkg.manifest());BoundedJson.map(bad.get(0)).put("BurnAddr",1);yes(!g.outbound("peer",f(6,bad),now++,true,true));
  g=transfer();Object r=OtaFrame.object("Name","nuttx_ap.bin","Start",0,"Size",100);g.inbound("peer",f(7,r),now++);byte[] data=pkg.slice("nuttx_ap.bin",0,100);data[2]^=1;yes(!g.outbound("peer",OtaFrame.encode(7,r,data),now++,true,true));
  g=transfer();yes(!g.outbound("peer",OtaFrame.encode(7,r,pkg.slice("nuttx_ap.bin",0,100)),now++,true,true));
  g=transfer();g.inbound("peer",f(7,OtaFrame.object("Name","../nuttx_ap.bin","Start",0,"Size",1)),now++);yes(g.phase()==OfficialOtaGate.Phase.UNKNOWN);
  g=transfer();g.inbound("peer",f(9,null),now++);yes(g.phase()==OfficialOtaGate.Phase.UNKNOWN);
  g=transfer();chunk(g,0,100);chunk(g,0,100);yes(g.covered()==100);g.tick("",now++);yes(g.phase()==OfficialOtaGate.Phase.UNKNOWN);yes(!g.outbound("peer",f(7,r),now++,true,true));
  g=transfer();g.tick("peer",now+60001);yes(g.phase()==OfficialOtaGate.Phase.UNKNOWN);
  g=gate(true);g.restore("peer",now++);read(g,1,null,version());read(g,11,null,OtaFrame.object("Result",true));yes(g.freshBoot(now));yes(!g.outbound("peer",f(4,OtaFrame.object("Mode",2)),now++,true,true));
  g=gate(true);g.inbound("peer",f(1,version()),now++);yes(!g.freshBoot(now)); // unsolicited replies are not evidence
  g=gate(true);yes(g.outbound("peer",f(1,null),now++,true,true));now+=15001;g.inbound("peer",f(1,version()),now++);read(g,11,null,OtaFrame.object("Result",true));yes(!g.freshBoot(now));
  g=transfer();chunk(g,0,10);g.tick("peer",now-100);yes(g.phase()==OfficialOtaGate.Phase.UNKNOWN);
  g=transfer();g.inbound("peer",f(7,r),now++);g.inbound("peer",f(7,r),now++);yes(g.phase()==OfficialOtaGate.Phase.UNKNOWN);
  g=transfer();for(int at=0;at<OtaPackage.AP_SIZE;at+=51200)chunk(g,at,Math.min(51200,OtaPackage.AP_SIZE-at));yes(g.covered()==OtaPackage.AP_SIZE);g.inbound("peer",f(9,null),now++);yes(g.phase()==OfficialOtaGate.Phase.INSTALLING&&g.pending());g.tick("",now++);yes(g.phase()==OfficialOtaGate.Phase.INSTALLING);
  System.out.println("Official OTA passive gate: "+checks+" assertions passed. Simulated wire only; no hardware sends.");
 }
}
