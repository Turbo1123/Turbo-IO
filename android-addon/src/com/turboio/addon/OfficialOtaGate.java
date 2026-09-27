package com.turboio.addon;

import java.util.*;

/** Passive policy, not an OTA sender. All inputs are official SDK wire frames.
 * Never generates an upgrade command; the Android vendor owns the conversation.
 */
final class OfficialOtaGate {
 static final long PREFLIGHT_TTL_MS=120000;
 interface Journal { boolean starting(String peerHash); }
 enum Phase { LOCKED, ARMED, STARTING, VERSION, MANIFEST, TRANSFER, INSTALLING, UNKNOWN }
 private final Journal journal;
 private OtaPackage firmware;
 private Phase phase=Phase.LOCKED;
 private String peer="",error="";
 private long grant,last=-1,deadline;
 private final long[] requested=new long[12],fresh=new long[12];
 private final boolean[] good=new boolean[12];
 private Object requestedSlice;
 private boolean wantVersion,wantManifest,started;
 private int chunks,apCovered;
 private long bytes;
 private final TreeMap<Integer,Integer> apRanges=new TreeMap<>();
 OfficialOtaGate(Journal j){journal=j;Arrays.fill(requested,-1);Arrays.fill(fresh,-1);}
 Phase phase(){return phase;}String error(){return error;}String peer(){return peer;}
 boolean pending(){return started;}int chunks(){return chunks;}int covered(){return apCovered;}
 long bytes(){return bytes;}
 boolean active(){return phase==Phase.ARMED||started;}
 void bind(String device){
  if(device==null||device.isEmpty()||device.length()>256||active())throw new IllegalStateException("bind denied");
  peer=device;Arrays.fill(requested,-1);Arrays.fill(fresh,-1);Arrays.fill(good,false);
 }
 void arm(OtaPackage candidate,String device,String token,long now){
  if(phase!=Phase.LOCKED||candidate==null||!peer.equals(device)||!"TAP1-TEST-01".equals(token))throw new IllegalStateException("arm denied");
  firmware=candidate;grant=now+900000;last=now;phase=Phase.ARMED;error="";
 }
 void revoke(){if(started)return;phase=Phase.LOCKED;grant=0;firmware=null;}
 void restore(String device,long now){peer=device;started=true;phase=Phase.UNKNOWN;last=now;error="process history lost";}
 void fail(String reason){if(error.isEmpty())error=reason;phase=started?Phase.UNKNOWN:Phase.LOCKED;grant=0;firmware=null;requestedSlice=null;}
 void tick(String current,long now){
  if(last>now){fail("monotonic clock reversed");return;}last=now;
  if(!peer.equals(current)){
   Arrays.fill(good,false);Arrays.fill(requested,-1);
   if(phase!=Phase.INSTALLING&&phase!=Phase.UNKNOWN&&active())fail("connection changed");
  }
  if(phase==Phase.ARMED&&now>=grant)fail("grant expired");
  if(started&&phase!=Phase.UNKNOWN&&phase!=Phase.INSTALLING&&deadline>0&&now>=deadline)fail("official response timeout");
 }
 private boolean recent(int t,long now,long ttl){return good[t]&&fresh[t]>=0&&now>=fresh[t]&&now-fresh[t]<=ttl;}
 boolean freshBoot(long now){return recent(1,now,60000)&&recent(11,now,60000);}
 boolean readyToArm(long now){return recent(1,now,PREFLIGHT_TTL_MS)&&recent(2,now,PREFLIGHT_TTL_MS)&&recent(11,now,PREFLIGHT_TTL_MS);}
 String idleEvidence(long now){return "idleGood="+good[11]+" replyAgeMs="+(fresh[11]<0?-1:now-fresh[11])+" pendingAgeMs="+(requested[11]<0?-1:now-requested[11]);}
 boolean queryPending(int type,long now){return requested[type]>=0&&now-requested[type]<=15000;}
 String preflight(long now){return "版本="+recent(1,now,PREFLIGHT_TTL_MS)+" 电量="+recent(2,now,PREFLIGHT_TTL_MS)+" 空间="+recent(3,now,PREFLIGHT_TTL_MS)+" 空闲="+recent(11,now,PREFLIGHT_TTL_MS);}
 private static boolean same(Object a,Object b){return Arrays.equals(BoundedJson.canonical(a),BoundedJson.canonical(b));}
 private static void require(boolean b,String why){if(!b)throw new IllegalArgumentException(why);}
 /** Returns permission only; callers must forward the original unmodified message. */
 boolean outbound(String current,byte[] raw,long now,boolean foreground,boolean serviceReady){
  tick(current,now);
  try{
   require(peer.equals(current)&&!peer.isEmpty(),"wrong peer");
   OtaFrame f=OtaFrame.decode(raw);
   if(OtaFrame.readOnly(raw)){
    // Read-only queries remain available after UNKNOWN for explicit recovery.
    // A redundant vendor poll does not erase an already validated reply.
    // Its original TTL is NOT extended; a negative/malformed reply invalidates it.
    requested[f.type]=now;return true;
   }
   if(f.type==3&&!started){
    require(f.binary.length==0&&same(f.json,OtaFrame.object("OtaSize",OtaPackage.ZIP_SIZE)),"space request differs");
    requested[3]=now;return true;
   }
   if(f.type==4){
    require(!started&&phase==Phase.ARMED&&now<grant,"no unused grant");
    require(f.binary.length==0&&same(f.json,OtaFrame.object("Mode",2)),"only official files Mode2");
    require(foreground&&serviceReady,"foreground/service unavailable");
    require(recent(1,now,PREFLIGHT_TTL_MS)&&recent(2,now,PREFLIGHT_TTL_MS)&&recent(3,now,PREFLIGHT_TTL_MS)&&recent(11,now,PREFLIGHT_TTL_MS),"fresh preflight missing");
    // Persist BEFORE forwarding Mode2. Failure does not grant any send permission.
    require(journal.starting(OtaPackage.hash("SHA-256",peer.getBytes(java.nio.charset.StandardCharsets.UTF_8))),"journal unavailable");
    started=true;phase=Phase.STARTING;grant=0;deadline=now+30000;return true;
   }
   require(started&&firmware!=null,"no live transfer");
   if(f.type==5){require(phase==Phase.VERSION&&wantVersion&&f.binary.length==0&&same(f.json,OtaFrame.object("OtaVersion",OtaPackage.VERSION)),"version response differs");wantVersion=false;phase=Phase.MANIFEST;deadline=now+30000;return true;}
   if(f.type==6){require(phase==Phase.MANIFEST&&wantManifest&&f.binary.length==0&&same(f.json,firmware.manifest()),"manifest differs");wantManifest=false;phase=Phase.TRANSFER;deadline=now+60000;return true;}
   if(f.type==7){
    require(phase==Phase.TRANSFER&&requestedSlice!=null&&same(f.json,requestedSlice),"slice not requested");
    Map<String,Object> j=BoundedJson.map(f.json);String name=BoundedJson.text(j.get("Name"),64);
    int start=BoundedJson.number(j.get("Start"),0,Integer.MAX_VALUE),size=BoundedJson.number(j.get("Size"),1,51200);
    require(Arrays.equals(f.binary,firmware.slice(name,start,size)),"slice bytes differ");
    require(chunks<2000&&bytes+size<=64000000,"transfer budget exceeded");
    requestedSlice=null;chunks++;bytes+=size;if(name.equals("nuttx_ap.bin"))cover(start,start+size);deadline=now+60000;return true;
   }
   throw new IllegalArgumentException("unsupported outgoing OTA type");
  }catch(RuntimeException e){fail(e.getMessage()==null?"invalid outbound":e.getMessage());return false;}
 }
 /** Observe BEFORE delivery to Flutter; never consumes or changes the event. */
 void inbound(String current,byte[] raw,long now){
  tick(current,now);if(!peer.equals(current))return;
  try{
   OtaFrame f=OtaFrame.decode(raw);require(f.binary.length==0,"unexpected inbound bytes");
   Map<String,Object> j=BoundedJson.map(f.json);
   if(f.type==1||f.type==2||f.type==3||f.type==11){
    if(requested[f.type]<0||now-requested[f.type]>15000)return;
    requested[f.type]=-1;fresh[f.type]=now;good[f.type]=false;
    if(f.type==1)good[1]=OtaPackage.VERSION.equals(j.get("OsVersion"))&&"idle".equals(j.get("OtaValidationState"))&&Boolean.TRUE.equals(j.get("OtaValidationConfirmed"))&&BoundedJson.list(j.get("PackageTypes")).contains("files");
    else if(f.type==2)good[2]=BoundedJson.number(j.get("BatteryLevel"),0,100)>=50;
    else good[f.type]=Boolean.TRUE.equals(j.get("Result"));
    return;
   }
   if(!started||phase==Phase.UNKNOWN||phase==Phase.INSTALLING)return;
   if(f.type==4){require(phase==Phase.STARTING&&Boolean.TRUE.equals(j.get("Result")),"official start rejected");phase=Phase.VERSION;deadline=now+30000;return;}
   if(f.type==5){require(phase==Phase.VERSION&&j.isEmpty(),"unexpected version request");wantVersion=true;return;}
   if(f.type==6){require(phase==Phase.MANIFEST&&same(j,OtaFrame.object("OtaVersion",OtaPackage.VERSION)),"unexpected manifest request");wantManifest=true;return;}
   if(f.type==7){require(phase==Phase.TRANSFER&&requestedSlice==null,"overlapping slice request");BoundedJson.keys(j,"Name","Start","Size");firmware.slice(BoundedJson.text(j.get("Name"),64),BoundedJson.number(j.get("Start"),0,Integer.MAX_VALUE),BoundedJson.number(j.get("Size"),1,51200));requestedSlice=j;deadline=now+60000;return;}
   if(f.type==9){require(phase==Phase.TRANSFER&&requestedSlice==null&&j.isEmpty()&&apCovered==OtaPackage.AP_SIZE,"premature install signal");phase=Phase.INSTALLING;firmware=null;deadline=0;return;}
   // Progress is observation only; it cannot unlock or complete a session.
   if(f.type==8||f.type==10)return;
   throw new IllegalArgumentException("unsupported incoming OTA type");
  }catch(RuntimeException e){fail(e.getMessage()==null?"invalid inbound":e.getMessage());}
 }
 private void cover(int start,int end){
  Map.Entry<Integer,Integer> e=apRanges.floorEntry(start);if(e!=null&&e.getValue()>=start){start=e.getKey();end=Math.max(end,e.getValue());apCovered-=e.getValue()-e.getKey();apRanges.remove(e.getKey());}
  while((e=apRanges.ceilingEntry(start))!=null&&e.getKey()<=end){end=Math.max(end,e.getValue());apCovered-=e.getValue()-e.getKey();apRanges.remove(e.getKey());}
  apRanges.put(start,end);apCovered+=end-start;
 }
}
