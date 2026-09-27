package com.turboio.addon;

import java.util.*;

/** Pure fail-closed protocol state. Milliseconds are monotonic, supplied by caller. */
final class OtaSession {
 enum State { LOCKED, CHECK_VERSION, CHECK_BATTERY, CHECK_SPACE, CHECK_IDLE, READY, AUTHORIZED, STARTING, VERSION, MANIFEST, TRANSFER, INSTALLING, UNKNOWN, READ_VERSION, READ_IDLE, READBACK }
 private OtaPackage firmware;
 private State state=State.LOCKED;
 private String peer="",error="",version="";
 private long preparation,deadline,fresh,grant;
 private boolean started,recovering,bootValidated;
 private OtaRecoveryGuard recoveryGuard;
 private int battery=-1,chunks,apCovered;
 private long sent;
 private final TreeMap<Integer,Integer> ranges=new TreeMap<>();
 OtaSession(OtaPackage p){firmware=p;}
 State state(){return state;}String error(){return error;}String peer(){return peer;}String version(){return version;}
 int battery(){return battery;}int chunks(){return chunks;}long sent(){return sent;}int covered(){return apCovered;}
 boolean started(){return started;}boolean bootValidated(){return bootValidated;}
 void discardPackage(){firmware=null;}
 boolean owns(){return state!=State.LOCKED;}
 private byte[] frame(int type,Object j){return OtaFrame.encode(type,j,null);}
 private byte[] query(State next,int type,long now){state=next;deadline=now+15000;return frame(type,null);}
 byte[] prepare(String device,long now){if(state!=State.LOCKED||firmware==null||device==null||device.isEmpty())throw new IllegalStateException("prepare denied");peer=device;preparation=now+900000;error="";return query(State.CHECK_VERSION,1,now);}
 void authorize(String token,String current,long now){check(current,now);if(state!=State.READY||!"TAP1".equals(token)||now-fresh>120000)throw new IllegalStateException("fresh checks and TAP1 required");state=State.AUTHORIZED;grant=Math.min(preparation,now+900000);}
 void validateStart(String current,long now){check(current,now);if(state!=State.AUTHORIZED||now>=grant||now-fresh>120000||battery<50)throw new IllegalStateException("authorization expired");}
 byte[] start(String current,long now){validateStart(current,now);started=true;state=State.STARTING;deadline=now+30000;grant=0;return frame(4,OtaFrame.object("Mode",2));}
 void fail(String reason,long now){error=reason;state=started||recovering?State.UNKNOWN:State.LOCKED;deadline=0;grant=0;bootValidated=false;if(state==State.UNKNOWN&&recoveryGuard==null)recoveryGuard=new OtaRecoveryGuard(peer,now,true);}
 void revoke(){if(started||recovering)return;state=State.LOCKED;grant=0;deadline=0;}
 void recover(String device,long now){peer=device;started=true;recovering=true;state=State.UNKNOWN;bootValidated=false;recoveryGuard=new OtaRecoveryGuard(peer,now,true);}
 boolean confirmHome(String token,String current,long now){return (state==State.UNKNOWN||state==State.INSTALLING||state==State.READBACK)&&recoveryGuard!=null&&recoveryGuard.confirmHome(token,current,now);}
 String recoveryStatus(long now){return recoveryGuard==null?"":recoveryGuard.status(now);}
 byte[] readback(String current,long now){if(!(state==State.UNKNOWN||state==State.INSTALLING||state==State.READBACK)||recoveryGuard==null||!recoveryGuard.allowed(current,now))throw new IllegalStateException("等待安装保护、重连或人工恢复确认；未发送");recovering=true;bootValidated=false;return query(State.READ_VERSION,1,now);}
 void release(String current,long now){check(current,now);if(state!=State.READBACK||!bootValidated||now-fresh>120000||recoveryGuard==null||!recoveryGuard.allowed(current,now))throw new IllegalStateException("fresh readback required");state=State.LOCKED;started=false;recovering=false;recoveryGuard=null;}
 void check(String current,long now){if(!owns())return;if(recoveryGuard!=null)recoveryGuard.observe(current,now);if(!peer.equals(current)){if(state!=State.INSTALLING&&state!=State.UNKNOWN)fail("连接变化，结果待确认",now);return;}
  if(!started&&now>=preparation){fail("15 分钟准备窗口已到期",now);return;}
  if(deadline>0&&now>=deadline){fail("回执超时，未自动重试",now);}}
 byte[] accept(String device,byte[] bytes,long now){check(device,now);if(state==State.LOCKED||state==State.UNKNOWN||state==State.READBACK)return null;
  try{if(!peer.equals(device))throw new IllegalArgumentException("wrong peer");OtaFrame f=OtaFrame.decode(bytes);if(f.binary.length!=0)throw new IllegalArgumentException("unexpected binary");Map<String,Object> j=BoundedJson.map(f.json);
   switch(state){
    case CHECK_VERSION:case READ_VERSION:
     require(f.type==1,"expected version");version=BoundedJson.text(j.get("OsVersion"),80);
     require(OtaPackage.VERSION.equals(version),"版本不匹配，仅支持 1.0.4.12");
     require("idle".equals(j.get("OtaValidationState"))&&Boolean.TRUE.equals(j.get("OtaValidationConfirmed")),"启动校验尚未确认");
     require(BoundedJson.list(j.get("PackageTypes")).contains("files"),"files 模式不支持");
     if(state==State.READ_VERSION){bootValidated=true;return query(State.READ_IDLE,11,now);}
     return query(State.CHECK_BATTERY,2,now);
    case CHECK_BATTERY:
     require(f.type==2,"expected battery");battery=BoundedJson.number(j.get("BatteryLevel"),0,100);require(battery>=50,"眼镜电量不足 50%");state=State.CHECK_SPACE;deadline=now+15000;return frame(3,OtaFrame.object("OtaSize",OtaPackage.ZIP_SIZE));
    case CHECK_SPACE:require(f.type==3&&Boolean.TRUE.equals(j.get("Result")),"存储预检拒绝");return query(State.CHECK_IDLE,11,now);
    case CHECK_IDLE:case READ_IDLE:require(f.type==11&&Boolean.TRUE.equals(j.get("Result")),"眼镜不是空闲状态");state=state==State.READ_IDLE?State.READBACK:State.READY;fresh=now;deadline=0;return null;
    case STARTING:require(f.type==4&&Boolean.TRUE.equals(j.get("Result")),"眼镜未接受开始升级");state=State.VERSION;deadline=now+30000;return null;
    case VERSION:require(f.type==5&&j.isEmpty(),"expected version request");state=State.MANIFEST;deadline=now+30000;return frame(5,OtaFrame.object("OtaVersion",OtaPackage.VERSION));
    case MANIFEST:require(f.type==6&&OtaPackage.VERSION.equals(j.get("OtaVersion")),"expected manifest request");state=State.TRANSFER;deadline=now+60000;return frame(6,firmware.manifest());
    case TRANSFER:
     if(f.type==9){require(j.isEmpty()&&apCovered==OtaPackage.AP_SIZE,"安装信号提前或 AP 传输不完整");state=State.INSTALLING;deadline=0;recoveryGuard=new OtaRecoveryGuard(peer,now,false);return null;}
     require(f.type==7,"expected slice request");BoundedJson.keys(j,"Name","Start","Size");String name=BoundedJson.text(j.get("Name"),64);int start=BoundedJson.number(j.get("Start"),0,Integer.MAX_VALUE),size=BoundedJson.number(j.get("Size"),1,51200);byte[] data=firmware.slice(name,start,size);
     require(chunks<2000&&sent+size<=64000000,"重复传输超过预算");chunks++;sent+=size;if(name.equals("nuttx_ap.bin"))cover(start,start+size);deadline=now+60000;return OtaFrame.encode(7,j,data);
    case INSTALLING:return null;
    default:throw new IllegalArgumentException("unexpected reply");
   }
  }catch(RuntimeException e){fail(e.getMessage()==null?"协议格式错误":e.getMessage(),now);return null;}
 }
 private static void require(boolean value,String reason){if(!value)throw new IllegalArgumentException(reason);}
 private void cover(int start,int end){Map.Entry<Integer,Integer> e=ranges.floorEntry(start);if(e!=null&&e.getValue()>=start){start=e.getKey();end=Math.max(end,e.getValue());apCovered-=e.getValue()-e.getKey();ranges.remove(e.getKey());}while((e=ranges.ceilingEntry(start))!=null&&e.getKey()<=end){end=Math.max(end,e.getValue());apCovered-=e.getValue()-e.getKey();ranges.remove(e.getKey());}ranges.put(start,end);apCovered+=end-start;}
}
