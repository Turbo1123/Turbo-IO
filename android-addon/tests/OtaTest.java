package com.turboio.addon;
import java.nio.file.*;import java.util.*;

public final class OtaTest {
 static int count;static void ok(boolean value){count++;if(!value)throw new AssertionError("assertion "+count);}
 interface Work{void run()throws Exception;}static void rejects(Work r){count++;try{r.run();throw new AssertionError("expected rejection "+count);}catch(Exception expected){}}
 static byte[] reply(int type,Object json){return OtaFrame.encode(type,json,null);}
 static Map<String,Object> version(){return OtaFrame.object("OsVersion",OtaPackage.VERSION,"OtaValidationStateCode",4294967295L,"OtaValidationState","idle","OtaValidationConfirmed",true,"PackageInfoVersions",Arrays.asList(1,2),"PackageTypes",Arrays.asList("files","zip"));}
 static OtaPackage p;
 static OtaSession prepared(){OtaSession s=new OtaSession(p);ok(OtaFrame.decode(s.prepare("device-test",0)).type==1);ok(OtaFrame.decode(s.accept("device-test",reply(1,version()),100)).type==2);ok(OtaFrame.decode(s.accept("device-test",reply(2,OtaFrame.object("BatteryLevel",90)),200)).type==3);ok(OtaFrame.decode(s.accept("device-test",reply(3,OtaFrame.object("Result",true)),300)).type==11);ok(s.accept("device-test",reply(11,OtaFrame.object("Result",true)),400)==null);ok(s.state()==OtaSession.State.READY);return s;}
 static OtaSession transfer(){OtaSession s=prepared();s.authorize("TAP1","device-test",500);ok(s.state()==OtaSession.State.AUTHORIZED);OtaFrame start=OtaFrame.decode(s.start("device-test",600));ok(start.type==4&&BoundedJson.number(BoundedJson.map(start.json).get("Mode"),2,2)==2);ok(s.accept("device-test",reply(4,OtaFrame.object("Result",true)),700)==null);ok(s.state()==OtaSession.State.VERSION);ok(OtaFrame.decode(s.accept("device-test",reply(5,null),800)).type==5);OtaFrame list=OtaFrame.decode(s.accept("device-test",reply(6,OtaFrame.object("OtaVersion",OtaPackage.VERSION)),900));ok(list.type==6&&BoundedJson.list(list.json).size()==14);ok(s.state()==OtaSession.State.TRANSFER);return s;}
 public static void main(String[] args)throws Exception{
  byte[] archive=Files.readAllBytes(Paths.get(args[0]));p=OtaPackage.verify(archive);ok(p.size("nuttx_ap.bin")==OtaPackage.AP_SIZE);ok(BoundedJson.list(p.manifest()).size()==14);
  // Visible firmware identity at the pinned menu literal; not just a phone label.
  ok(Arrays.equals(p.slice("nuttx_ap.bin",0x91b5e3,13),new byte[]{(byte)0xe6,(byte)0x98,(byte)0xbe,(byte)0xe7,(byte)0xa4,(byte)0xba,84,69,83,84,0,0,0}));
  rejects(()->OtaPackage.verify(null));rejects(()->OtaPackage.verify(Arrays.copyOf(archive,100)));byte[] changed=archive.clone();changed[400]^=1;rejects(()->OtaPackage.verify(changed));
  rejects(()->p.size("../nuttx_ap.bin"));rejects(()->p.slice("OtaFileInfo.json",0,10));rejects(()->p.slice("nuttx_ap.bin",-1,1));rejects(()->p.slice("nuttx_ap.bin",0,51201));rejects(()->p.slice("nuttx_ap.bin",Integer.MAX_VALUE,4));rejects(()->p.slice("nuttx_ap.bin",OtaPackage.AP_SIZE,1));rejects(()->p.slice("nuttx_ap.bin",0,0));
  byte[] copy=p.slice("nuttx_ap.bin",0,100);byte old=copy[0];copy[0]^=1;ok(p.slice("nuttx_ap.bin",0,100)[0]==old);List<Object> manifest=BoundedJson.list(p.manifest());manifest.clear();ok(BoundedJson.list(p.manifest()).size()==14);
  for(int type=1;type<15;type++){OtaFrame f=OtaFrame.decode(reply(type,OtaFrame.object("type",type)));ok(f.type==type&&f.binary.length==0);}
  // Previously NewsTele incorrectly used NavCore.packet, which rejects type2/4/6/8.
  for(int type=2;type<=8;type++){OtaFrame f=OtaFrame.decode(reply(type,OtaFrame.object("did","test","action",1)));ok(f.type==type);}
  rejects(()->OtaFrame.encode(0,null,null));rejects(()->OtaFrame.encode(256,null,null));rejects(()->OtaFrame.encode(7,null,new byte[51201]));rejects(()->OtaFrame.decode(new byte[65537]));
  byte[] frame=reply(1,null);for(int i=0;i<4;i++){byte[] cut=Arrays.copyOf(frame,i);rejects(()->OtaFrame.decode(cut));}
  rejects(()->OtaFrame.decode(new byte[]{8,1,16,1,8,1}));rejects(()->OtaFrame.decode(new byte[]{8,(byte)0x81,0,16,1}));rejects(()->OtaFrame.decode(new byte[]{8,1,16,1,26,4,123,125}));rejects(()->OtaFrame.decode(new byte[]{8,1,16,1,40,1}));rejects(()->OtaFrame.decode(new byte[]{8,1,16,1,26,1,(byte)255}));
  for(int type:new int[]{1,2,11})ok(OtaFrame.readOnly(reply(type,null)));for(int type:new int[]{3,4,5,6,7,9})ok(!OtaFrame.readOnly(reply(type,null)));
  OtaSession denied=new OtaSession(p);rejects(()->denied.start("device-test",0));rejects(()->denied.authorize("TAP1","device-test",0));ok(!denied.started());
  OtaSession low=new OtaSession(p);low.prepare("device-test",0);low.accept("device-test",reply(1,version()),100);low.accept("device-test",reply(2,OtaFrame.object("BatteryLevel",49)),200);ok(low.state()==OtaSession.State.LOCKED&&!low.started());
  for(Object battery:new Object[]{-1,101,"90",true}){OtaSession s=new OtaSession(p);s.prepare("device-test",0);s.accept("device-test",reply(1,version()),100);s.accept("device-test",reply(2,OtaFrame.object("BatteryLevel",battery)),200);ok(s.state()==OtaSession.State.LOCKED);}
  for(String field:new String[]{"OsVersion","OtaValidationState","OtaValidationConfirmed","PackageTypes"}){OtaSession s=new OtaSession(p);s.prepare("device-test",0);Map<String,Object> bad=version();bad.remove(field);s.accept("device-test",reply(1,bad),10);ok(s.state()==OtaSession.State.LOCKED);}
  OtaSession stale=prepared();rejects(()->stale.authorize("wrong","device-test",500));rejects(()->stale.authorize("TAP1","device-test",121000));stale.check("device-test",900001);ok(stale.state()==OtaSession.State.LOCKED);
  OtaSession revoked=prepared();revoked.authorize("TAP1","device-test",500);revoked.revoke();rejects(()->revoked.start("device-test",600));
  OtaSession disconnected=prepared();disconnected.authorize("TAP1","device-test",500);rejects(()->disconnected.start("other",600));ok(!disconnected.started());
  OtaSession late=prepared();late.authorize("TAP1","device-test",500);rejects(()->late.start("device-test",121000));
  OtaSession once=transfer();rejects(()->once.start("device-test",1000));once.check("",1100);ok(once.state()==OtaSession.State.UNKNOWN&&once.started());
  OtaSession expired=transfer();expired.check("device-test",61000);ok(expired.state()==OtaSession.State.UNKNOWN);
  OtaSession premature=transfer();ok(premature.accept("device-test",reply(9,null),1000)==null);ok(premature.state()==OtaSession.State.UNKNOWN);
  for(Map<String,Object> bad:Arrays.asList(OtaFrame.object("Name","../nuttx_ap.bin","Start",0,"Size",10),OtaFrame.object("Name","nuttx_ap.bin","Start",2147483647,"Size",10),OtaFrame.object("Name","nuttx_ap.bin","Start",0,"Size",51201),OtaFrame.object("Name","nuttx_ap.bin","Start",0,"Size",0),OtaFrame.object("Name","nuttx_ap.bin","Start",0,"Size",10,"extra",1))){OtaSession s=transfer();ok(s.accept("device-test",reply(7,bad),1000)==null);ok(s.state()==OtaSession.State.UNKNOWN);}
  OtaSession good=transfer();int ap=OtaPackage.AP_SIZE;long now=1000;for(int at=ap;at>0;){int size=Math.min(51200,at);at-=size;Map<String,Object> j=OtaFrame.object("Name","nuttx_ap.bin","Start",at,"Size",size);OtaFrame f=OtaFrame.decode(good.accept("device-test",reply(7,j),now++));ok(f.type==7&&Arrays.equals(f.binary,p.slice("nuttx_ap.bin",at,size)));ok(BoundedJson.number(BoundedJson.map(f.json).get("Start"),0,ap)==at);}
  ok(good.covered()==ap);good.accept("device-test",reply(7,OtaFrame.object("Name","nuttx_ap.bin","Start",0,"Size",100)),now++);ok(good.covered()==ap);ok(good.accept("device-test",reply(9,null),now++)==null);ok(good.state()==OtaSession.State.INSTALLING);
  final long t=now;rejects(()->good.readback("other",t));rejects(()->good.readback("device-test",t));
  rejects(()->good.release("device-test",t));good.check("",now++);ok(good.state()==OtaSession.State.INSTALLING);now+=1001;good.check("",now);good.check("device-test",++now);now+=60001;
  ok(OtaFrame.decode(good.readback("device-test",now++)).type==1);ok(OtaFrame.decode(good.accept("device-test",reply(1,version()),now++)).type==11);good.accept("device-test",reply(11,OtaFrame.object("Result",true)),now++);ok(good.state()==OtaSession.State.READBACK&&good.bootValidated());good.release("device-test",now++);ok(!good.owns()&&!good.started());
  OtaSession recovery=new OtaSession(null);recovery.recover("device-test",0);rejects(()->recovery.prepare("device-test",100));rejects(()->recovery.start("device-test",100));ok(recovery.state()==OtaSession.State.UNKNOWN);rejects(()->recovery.readback("device-test",100));recovery.check("device-test",100);ok(!recovery.confirmHome("已回首页","device-test",110));ok(recovery.confirmHome("已回首页","device-test",120001));recovery.readback("device-test",120002);recovery.accept("device-test",reply(1,version()),120003);recovery.accept("device-test",reply(11,OtaFrame.object("Result",false)),120004);ok(recovery.state()==OtaSession.State.UNKNOWN);
  System.out.println("OTA package/frame/state tests passed ("+count+" assertions). No device I/O.");
 }
}
