package com.turboio.addon;
import java.nio.file.*;import java.util.*;import java.util.concurrent.atomic.*;import java.net.*;

/** Host 1.0.6 candidate: TMIG1 over a 1.0.4.12 or 1.0.5.5 base. Run with -Dturboio.host=1.0.6. */
public final class Tmig1CandidateTest {
 static int n;static long now=1000;
 static void ok(boolean b){n++;if(!b)throw new AssertionError("check "+n);}
 interface Work{void run()throws Exception;}static void rejects(Work w){n++;try{w.run();throw new AssertionError("expected rejection "+n);}catch(Exception expected){}}
 static byte[] f(int t,Object j){return OtaFrame.encode(t,j,null);}
 static Object version(String os){return OtaFrame.object("OsVersion",os,"OtaValidationState","idle","OtaValidationConfirmed",true,"PackageTypes",Arrays.asList("files"));}
 static void read(OfficialOtaGate g,int type,Object req,Object reply){ok(g.outbound("peer",f(type,req),now++,true,true));g.inbound("peer",f(type,reply),now++);}
 static void preflight(OfficialOtaGate g,String os){read(g,1,null,version(os));read(g,2,null,OtaFrame.object("BatteryLevel",80));read(g,3,OtaFrame.object("OtaSize",OtaPackage.ZIP_SIZE),OtaFrame.object("Result",true));read(g,11,null,OtaFrame.object("Result",true));}
 public static void main(String[] args)throws Exception{
  ok(OtaPackage.TMIG1&&"TMIG1".equals(OtaPackage.TOKEN)&&OtaPackage.PIN_COUNT==16&&"Strix OS 1.0.5.5".equals(OtaPackage.VERSION));
  byte[] zip=Files.readAllBytes(Paths.get(args[0]));
  OtaPackage pkg=OtaPackage.verify(zip);
  ok(pkg.size("nuttx_ap.bin")==OtaPackage.AP_SIZE&&pkg.size("bt_controller.bin")==625364);
  ok(BoundedJson.list(pkg.manifest()).size()==15);
  rejects(()->pkg.size("OtaFileInfo.json"));
  // Unmodified official 1.0.5.5 and the old TAP1 candidate are both refused.
  for(int i=1;i<args.length;i++){byte[] other=Files.readAllBytes(Paths.get(args[i]));rejects(()->OtaPackage.verify(other));}
  byte[] flipped=zip.clone();flipped[zip.length/2]^=1;rejects(()->OtaPackage.verify(flipped));

  // Preflight may start from either pinned base; any other OS version keeps the gate locked.
  for(String base:OtaPackage.BASES){OfficialOtaGate g=new OfficialOtaGate(p->true);g.bind("peer");preflight(g,base);ok(g.readyToArm(now));g.arm(pkg,"peer",OtaPackage.TOKEN,now++);ok(g.phase()==OfficialOtaGate.Phase.ARMED);}
  OfficialOtaGate old=new OfficialOtaGate(p->true);old.bind("peer");preflight(old,"Strix OS 1.0.4.11");ok(!old.readyToArm(now));
  OfficialOtaGate tap=new OfficialOtaGate(p->true);tap.bind("peer");preflight(tap,"Strix OS 1.0.4.12");rejects(()->tap.arm(pkg,"peer","TAP1-TEST-01",now++));
  // Post-install readback: only the TMIG1 target version counts as a fresh boot.
  OfficialOtaGate boot=new OfficialOtaGate(p->true);boot.bind("peer");
  read(boot,1,null,version("Strix OS 1.0.4.12"));read(boot,11,null,OtaFrame.object("Result",true));ok(!boot.freshBoot(now));
  read(boot,1,null,version("Strix OS 1.0.5.5"));read(boot,11,null,OtaFrame.object("Result",true));ok(boot.freshBoot(now));

  // Feed answers the 1.0.6 firmware query from either base with the TMIG1 archive.
  AtomicLong clock=new AtomicLong(1000);AtomicBoolean guard=new AtomicBoolean(true);
  try(OfficialOtaFeed feed=new OfficialOtaFeed(clock::get,guard::get)){
   int port=feed.start(0);feed.arm(zip);
   for(String code:new String[]{"01.00.04.0012","01.00.05.0005","01.00.04.0011"}){
    String q=OfficialOtaFeed.PATHS[0]+"?packageType=firmware&packageName=strix+OS&glassesType=S3&deviceType=android&versionCode="+code;
    OfficialOtaFeed.Reply r=feed.reply("GET "+q+" HTTP/1.1\r\nHost: 127.0.0.1:"+port+"\r\n\r\n");ok(r.code==200);
    Object data=BoundedJson.map(BoundedJson.read(r.body)).get("data");
    if(code.equals("01.00.04.0011")){ok(data==null);continue;}
    Map<String,Object> meta=BoundedJson.map(data);
    ok(((Number)meta.get("versionCode")).intValue()==100050005&&"0100050005".equals(meta.get("versionName")));
    String path=new URI((String)meta.get("downloadUrl")).getRawPath();ok(path.endsWith("/Strix_OS_1.0.5.5.zip"));
    ok(Arrays.equals(zip,feed.reply("GET "+path+" HTTP/1.1\r\nHost: 127.0.0.1:"+port+"\r\n\r\n").body));
   }
  }
  System.out.println("TMIG1 candidate (host 1.0.6): "+n+" checks; package pins, base/target versions, feed. No device I/O.");
 }
}
