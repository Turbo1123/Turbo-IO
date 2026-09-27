package com.turboio.addon;

/** Passive evidence only. A reconnect is NOT proof of a successful firmware boot. */
final class OtaRecoveryGuard {
 static final long INSTALL_QUIET_MS=60000, MANUAL_QUIET_MS=120000;
 static final long DOWN_MS=1000, STABLE_MS=2000, MANUAL_VALID_MS=120000;
 private final String peer;
 private final long since;
 private final boolean manualRequired;
 private long downSince=-1,connectedSince=-1,manualUntil=-1,last=-1;
 private boolean downObserved,reconnected;
 OtaRecoveryGuard(String peer,long now,boolean manualRequired){this.peer=peer;since=now;this.manualRequired=manualRequired;}
 void observe(String current,long now){
  if(now<since||last>now){downSince=-1;connectedSince=-1;downObserved=false;reconnected=false;manualUntil=-1;return;}
  last=now;
  if(peer.equals(current)){
   if(connectedSince<0)connectedSince=now;
   if(downObserved)reconnected=true;
   downSince=-1;
  }else{
   connectedSince=-1;reconnected=false;manualUntil=-1;
   // null means SDK read failed / multiple devices, NOT a confirmed disconnect.
   if("".equals(current)){
    if(downSince<0)downSince=now;
    if(now-downSince>=DOWN_MS)downObserved=true;
   }else{downSince=-1;downObserved=false;}
  }
 }
 boolean allowed(String current,long now){observe(current,now);return peer.equals(current)&&connectedSince>=0&&now-connectedSince>=STABLE_MS&&now-since>=INSTALL_QUIET_MS&&((!manualRequired&&reconnected)||(manualUntil>=now));}
 boolean confirmHome(String token,String current,long now){observe(current,now);if(!"已回首页".equals(token)||!peer.equals(current)||connectedSince<0||now-connectedSince<STABLE_MS||now-since<MANUAL_QUIET_MS)return false;manualUntil=now+MANUAL_VALID_MS;return true;}
 String status(long now){
  long remaining=Math.max(0,INSTALL_QUIET_MS-(now-since));
  if(remaining>0)return "安装保护：至少还需等待 "+((remaining+999)/1000)+" 秒；到时不会自动解锁或发送";
  if(manualUntil>=now)return "已人工确认回首页；仍须新回读和最终检查，未解除保护";
  if(!manualRequired&&reconnected)return "已观察到断开/重连；仅可申请回读，不代表安装成功";
  return (manualRequired?"连接历史不完整，保持锁定":"尚未观察到安装后的有效断开/重连")+"；若已自然重启并回首页，可走人工确认，最早还需 "+Math.max(0,(MANUAL_QUIET_MS-(now-since)+999)/1000)+" 秒";
 }
}
