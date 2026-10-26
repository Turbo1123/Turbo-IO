package com.turboio.addon;
import java.nio.file.*;import java.util.*;

public final class OtaTest {
 static int count;static void ok(boolean value){count++;if(!value)throw new AssertionError("assertion "+count);}
 interface Work{void run()throws Exception;}static void rejects(Work r){count++;try{r.run();throw new AssertionError("expected rejection "+count);}catch(Exception expected){}}
 static byte[] reply(int type,Object json){return OtaFrame.encode(type,json,null);}
 static Map<String,Object> version(){return OtaFrame.object("OsVersion",OtaPackage.VERSION,"OtaValidationStateCode",4294967295L,"OtaValidationState","idle","OtaValidationConfirmed",true,"PackageInfoVersions",Arrays.asList(1,2),"PackageTypes",Arrays.asList("files","zip"));}
 static OtaPackage p;
 static OtaSession prepared(){OtaSession s=new OtaSession(p);ok(OtaFrame.decode(s.prepare("device-test",0)).type==1);ok(OtaFrame.decode(s.accept("device-test",reply(1,version()),100)).type==2);ok(OtaFrame.decode(s.accept("device-test",reply(2,OtaFrame.object("BatteryLevel",90)),200)).type==3);ok(OtaFrame.decode(s.accept("device-test",reply(3,OtaFrame.object("Result",true)),300)).type==11);ok(s.accept("device-test",reply(11,OtaFrame.object("Result",true)),400)==null);ok(s.state()==OtaSession.State.READY);return s;}
 public static void main(String[] args)throws Exception{
  byte[] archive=Files.readAllBytes(Paths.get(args[0]));p=OtaPackage.verify(archive);ok(p.size("nuttx_ap.bin")==OtaPackage.AP_SIZE);ok(BoundedJson.list(p.manifest()).size()==15);
  // TVP2-only: the legacy self-sender (OtaSession transfer) can never be authorized; package and frame checks stay.
  rejects(()->OtaPackage.verify(null));rejects(()->OtaPackage.verify(Arrays.copyOf(archive,100)));byte[] changed=archive.clone();changed[400]^=1;rejects(()->OtaPackage.verify(changed));
  rejects(()->p.size("../nuttx_ap.bin"));rejects(()->p.slice("OtaFileInfo.json",0,10));rejects(()->p.slice("nuttx_ap.bin",-1,1));rejects(()->p.slice("nuttx_ap.bin",0,51201));rejects(()->p.slice("nuttx_ap.bin",Integer.MAX_VALUE,4));rejects(()->p.slice("nuttx_ap.bin",OtaPackage.AP_SIZE,1));rejects(()->p.slice("nuttx_ap.bin",0,0));
  byte[] copy=p.slice("nuttx_ap.bin",0,100);byte old=copy[0];copy[0]^=1;ok(p.slice("nuttx_ap.bin",0,100)[0]==old);List<Object> manifest=BoundedJson.list(p.manifest());manifest.clear();ok(BoundedJson.list(p.manifest()).size()==15);
  for(int type=1;type<15;type++){OtaFrame f=OtaFrame.decode(reply(type,OtaFrame.object("type",type)));ok(f.type==type&&f.binary.length==0);}
  // Previously NewsTele incorrectly used NavCore.packet, which rejects type2/4/6/8.
  for(int type=2;type<=8;type++){OtaFrame f=OtaFrame.decode(reply(type,OtaFrame.object("did","test","action",1)));ok(f.type==type);}
  rejects(()->OtaFrame.encode(0,null,null));rejects(()->OtaFrame.encode(256,null,null));rejects(()->OtaFrame.encode(7,null,new byte[51201]));rejects(()->OtaFrame.decode(new byte[65537]));
  byte[] frame=reply(1,null);for(int i=0;i<4;i++){byte[] cut=Arrays.copyOf(frame,i);rejects(()->OtaFrame.decode(cut));}
  rejects(()->OtaFrame.decode(new byte[]{8,1,16,1,8,1}));rejects(()->OtaFrame.decode(new byte[]{8,(byte)0x81,0,16,1}));rejects(()->OtaFrame.decode(new byte[]{8,1,16,1,26,4,123,125}));rejects(()->OtaFrame.decode(new byte[]{8,1,16,1,40,1}));rejects(()->OtaFrame.decode(new byte[]{8,1,16,1,26,1,(byte)255}));
  for(int type:new int[]{1,2,11})ok(OtaFrame.readOnly(reply(type,null)));for(int type:new int[]{3,4,5,6,7,9})ok(!OtaFrame.readOnly(reply(type,null)));
  OtaSession denied=new OtaSession(p);rejects(()->denied.start("device-test",0));rejects(()->denied.authorize("TVP2","device-test",0));ok(!denied.started());
  OtaSession low=new OtaSession(p);low.prepare("device-test",0);low.accept("device-test",reply(1,version()),100);low.accept("device-test",reply(2,OtaFrame.object("BatteryLevel",49)),200);ok(low.state()==OtaSession.State.LOCKED&&!low.started());
  for(Object battery:new Object[]{-1,101,"90",true}){OtaSession s=new OtaSession(p);s.prepare("device-test",0);s.accept("device-test",reply(1,version()),100);s.accept("device-test",reply(2,OtaFrame.object("BatteryLevel",battery)),200);ok(s.state()==OtaSession.State.LOCKED);}
  for(String field:new String[]{"OsVersion","OtaValidationState","OtaValidationConfirmed","PackageTypes"}){OtaSession s=new OtaSession(p);s.prepare("device-test",0);Map<String,Object> bad=version();bad.remove(field);s.accept("device-test",reply(1,bad),10);ok(s.state()==OtaSession.State.LOCKED);}
  OtaSession stale=prepared();rejects(()->stale.authorize("wrong","device-test",500));rejects(()->stale.authorize("TVP2","device-test",121000));stale.check("device-test",900001);ok(stale.state()==OtaSession.State.LOCKED);
  // Fresh READY session: no token (old TAP1, the TVP2 phrase, anything) authorizes the self-sender.
  for(String token:new String[]{"TAP1","TAP1-TEST-01","TMIG1","TVP2"}){OtaSession s=prepared();rejects(()->s.authorize(token,"device-test",500));ok(s.state()==OtaSession.State.READY&&!s.started());rejects(()->s.start("device-test",600));ok(!s.started());}
  OtaSession recovery=new OtaSession(null);recovery.recover("device-test",0);rejects(()->recovery.prepare("device-test",100));rejects(()->recovery.start("device-test",100));ok(recovery.state()==OtaSession.State.UNKNOWN);rejects(()->recovery.readback("device-test",100));recovery.check("device-test",100);ok(!recovery.confirmHome("已回首页","device-test",110));ok(recovery.confirmHome("已回首页","device-test",120001));recovery.readback("device-test",120002);recovery.accept("device-test",reply(1,version()),120003);recovery.accept("device-test",reply(11,OtaFrame.object("Result",false)),120004);ok(recovery.state()==OtaSession.State.UNKNOWN);
  System.out.println("OTA package/frame/state tests passed ("+count+" assertions). No device I/O.");
 }
}
