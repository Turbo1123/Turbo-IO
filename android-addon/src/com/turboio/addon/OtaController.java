package com.turboio.addon;

import android.app.*;
import android.content.*;
import android.os.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicBoolean;

/** Main-thread experiment owner, durable post-start interlock, official SDK transport. */
public final class OtaController {
 private static final Handler MAIN=new Handler(Looper.getMainLooper());
 private static final ThreadLocal<Object> OWN_MESSAGE=new ThreadLocal<>();
 private static final AtomicInteger EVENTS=new AtomicInteger();
 private static final AtomicBoolean FAULT_QUEUED=new AtomicBoolean();
 private static final Set<String> INTERACTIVE=new HashSet<>(Arrays.asList("APP_MARKET","MARS_STREAMING","MARS_PHOTO_TRANSFER","LOG_REPORT","VOICE_ASSISTANT","RECORDING_SERVICE","LAUNCHER","FILE_TRANSFER","AI_SUBTITLE","TELEPROMPTER","NOTIFICATION","SCHEDULE_TODO","PROACTIVE_AI","AI_WIDGET","NAVIGATION","FILE_TRANSFER_LAUNCHER"));
 private static Context app;private static SharedPreferences journal;
 private static volatile boolean initialized,exclusive,preparing,pending;
 private static volatile long officialBusyUntil;
 private static OtaPackage firmware;private static OtaSession session;
 private static boolean importing,sending,foreground=true;
 private static volatile long generation;private static long installSeen,sendSerial;
 private static String note="默认锁定 · 尚未导入指定固件",lease="",savedPeer="";
 private static final ArrayDeque<byte[]> inbound=new ArrayDeque<>();
 private static final List<String> log=new ArrayList<>();
 private static int sdkConfirmed;
 private static int savedChunks=-1;
 private static OtaSession.State recorded;
 static synchronized void init(Context c){if(initialized)return;app=c.getApplicationContext();journal=app.getSharedPreferences("turboio_ota_journal_v1",0);pending=journal.getBoolean("pending",false);savedPeer=journal.getString("peerSha256","");exclusive=pending;if(pending)note="上轮已开始升级，连接历史不完整；保持锁定，等待自然重启回首页后人工确认";initialized=true;if(pending)MAIN.postDelayed(tick,1000);
  ((Application)app).registerActivityLifecycleCallbacks(new Application.ActivityLifecycleCallbacks(){public void onActivityResumed(Activity a){if(host(a))foreground=true;}public void onActivityStopped(Activity a){if(host(a)&&!a.isChangingConfigurations()){foreground=false;if(session!=null&&!session.started())cancelPreparation();}}private boolean host(Activity a){return a.getClass().getName().equals("com.rayneo.venus.MainActivity");}public void onActivityCreated(Activity a,Bundle b){}public void onActivityStarted(Activity a){}public void onActivityPaused(Activity a){}public void onActivitySaveInstanceState(Activity a,Bundle b){}public void onActivityDestroyed(Activity a){}});
 }
 private static boolean bootstrap(){if(initialized)return true;try{Object c=Class.forName("android.app.ActivityThread").getMethod("currentApplication").invoke(null);if(c instanceof Context)init((Context)c);}catch(Exception ignored){}return initialized;}
 static boolean busy(){return exclusive||preparing||pending;}
 static boolean intercepting(){return exclusive||pending;}
 static boolean critical(){return pending;}
 private static String fingerprint(String peer){return OtaPackage.hash("SHA-256",peer.getBytes(StandardCharsets.UTF_8));}
 private static void record(String event){if(log.size()==96)log.remove(0);log.add(SystemClock.elapsedRealtime()+" "+event);}
 static String status(){String base="ANDROID 1.0.5 · OTA-02 / INTEGRATION-08k\n"+note+"\n候选："+(firmware==null?"未载入":OtaPackage.NAME+" · 15/15 校验通过")+"\nAP：9,590,856 字节 · 只有 AP 与原厂不同\n";
  if(session!=null)base+="阶段："+session.state()+"\n电量："+(session.battery()<0?"待读取":session.battery()+"%")+"\n授权："+(session.state()==OtaSession.State.AUTHORIZED?"1":"0")+"\n请求片数："+session.chunks()+" · SDK 已确认消息："+sdkConfirmed+"\nAP 请求覆盖："+session.covered()+" / "+OtaPackage.AP_SIZE+" 字节\n";
  return base+"结果保护："+(pending?"待回读，不可重试":"未开始刷写")+"\n"+(session==null&&pending&&journal!=null?"上次记录："+journal.getString("phase","UNKNOWN")+" · "+journal.getString("chunks","0")+" 片":"")+"\n"+(session==null?"":session.recoveryStatus(SystemClock.elapsedRealtime())+"\n"+session.error());
 }
 static String diagnostic(){return status()+"\nZIP SHA-256 "+OtaPackage.ZIP_SHA+"\nAP SHA-256 "+OtaPackage.AP_SHA+"\n"+String.join("\n",log);}
 static void importPackage(byte[] data){if(busy()||importing){note="请先结束准备或核对上轮结果，未替换固件";return;}importing=true;firmware=null;note="本机核对 ZIP、15 个成员和 AP-only 清单；不连接眼镜";new Thread(()->{OtaPackage checked=null;try{checked=OtaPackage.verify(data);}catch(Exception ignored){}OtaPackage result=checked;MAIN.post(()->{importing=false;if(busy())return;firmware=result;session=null;note=result==null?"导入拒绝：只支持指定 TAP1 原样包；没有发送数据":"候选校验通过：13 个非 AP 负载与原厂一致，AP/清单使用新摘要";record(result==null?"IMPORT_REJECTED":"IMPORT_VERIFIED");});},"TurboIO-ota-verify").start();}
 static synchronized void prepare(){if(!initialized||importing||firmware==null||busy()||SystemClock.elapsedRealtime()<officialBusyUntil){note="无法准备：检查已导入候选、上轮升级保护与官方升级状态";return;}String peer=NativeTransfer.connected();String owner="ota-"+UUID.randomUUID();if(peer.isEmpty()||!NativeTransfer.acquireMessages(owner)){note="眼镜未连接或其他任务未退出；没有发送";return;}
  lease=owner;preparing=true;exclusive=false;sending=false;generation++;inbound.clear();sdkConfirmed=0;savedChunks=-1;installSeen=0;session=new OtaSession(firmware);recorded=null;note="15 分钟本机准备：读取版本、电量、空间及空闲状态；不刷写";record("PREPARE");send(session.prepare(peer,SystemClock.elapsedRealtime()));MAIN.removeCallbacks(tick);MAIN.postDelayed(tick,250);
 }
 static void authorize(String token){try{if(session==null||!foreground||sending)throw new IllegalStateException();session.authorize(token,NativeTransfer.connected(),SystemClock.elapsedRealtime());note="授权：1 · 尚未开始；请核对包和电量后单独点开始";record("AUTHORIZED");}catch(RuntimeException e){note="授权未通过；请使用 TAP1，并在完整预检后两分钟内操作";settle();}}
 static void start(){if(session==null||!foreground||sending||pending||session.state()!=OtaSession.State.AUTHORIZED){note="开始条件未满足；未发送 Mode 2";return;}
  if(!OtaService.alive()){try{app.startForegroundService(new Intent(app,OtaService.class));note="正在开启升级保障服务；服务就绪后再次点「开始一次升级」";}catch(RuntimeException e){note="系统拒绝前台服务，未开始升级";}return;}
  String peer=NativeTransfer.connected();long now=SystemClock.elapsedRealtime();
  // Validate freshness BEFORE the durable start intent. Expired preparation is
  // known-not-started; it must never masquerade as an uncertain installation.
  try{session.validateStart(peer,now);}catch(RuntimeException e){session.revoke();settle();note="预检已过期或连接变化；未发送升级指令，请重新只读预检和授权";record("START_PREFLIGHT_REJECTED_NO_SEND");return;}
  // Durable intent BEFORE creating/sending Mode2. A crash here stays locked even
  // if not a single firmware byte reached the glasses. Never infer safe retry.
  savedPeer=fingerprint(peer);if(!journal.edit().putBoolean("pending",true).putString("peerSha256",savedPeer).putString("candidateSha256",OtaPackage.ZIP_SHA).putString("phase","START_INTENT").putString("recoveryPolicy","reconnect-or-manual-v1").commit()){note="本机保护记录未落盘，禁止开始";return;}
  pending=true;byte[] start;try{start=session.start(peer,now);}catch(RuntimeException e){session.recover(peer,now);fail("开始条件变化；已保留保护，请等待并人工确认");return;}
  record("MODE2_INTENT");note="开始请求已提交；保持蓝牙、供电，不要强退、切换官方升级或重复点击";send(start);settle();
 }
 static void cancelPreparation(){if(pending||session!=null&&session.started()){note="已经开始或结果待确认，不能当作普通任务取消；请等待并回读";return;}if(session!=null)session.revoke();cleanup();note="准备已关闭，授权已撤销；未刷写";record("PREPARE_CLOSED");}
 private static boolean samePendingPeer(String peer){return pending&&peer!=null&&!peer.isEmpty()&&fingerprint(peer).equals(savedPeer);}
 private static void restoreSession(String peer,long now){if(session==null&&samePendingPeer(peer)){session=new OtaSession(null);session.recover(peer,now);record("RECOVERY_HISTORY_LOST");}}
 static void confirmRecoveryHome(String token){String peer=NativeTransfer.otaConnection();long now=SystemClock.elapsedRealtime();restoreSession(peer,now);if(!samePendingPeer(peer)||session==null||!session.confirmHome(token,peer,now)){note="恢复确认未通过：须同一眼镜、等待保护时间结束并确认已自然重启回首页；未发送";return;}
  // This records a human assertion, not evidence of a successful boot. A fresh
  // query and a separate final inspection remain mandatory. No automatic send.
  if(!journal.edit().putString("recoveryEvidence","USER_CONFIRMED_HOME").commit()){session.recover(peer,now);note="恢复确认未落盘，继续锁定";return;}record("USER_CONFIRMED_HOME");note="人工确认已记录；未解锁、未发送，请单独回查状态";
 }
 static void readback(){if(!pending||sending){note="没有待回读的实验，或正在等待回执";return;}String peer=NativeTransfer.otaConnection();if(!samePendingPeer(peer)){note="请连接本次同一副眼镜；不会向其他设备查询或重传";return;}if(session!=null&&session.started()&&session.state()!=OtaSession.State.UNKNOWN&&session.state()!=OtaSession.State.INSTALLING&&session.state()!=OtaSession.State.READBACK){note="传输仍进行中，不能切换为回读";return;}
  restoreSession(peer,SystemClock.elapsedRealtime());try{byte[] request=session.readback(peer,SystemClock.elapsedRealtime());exclusive=true;generation++;inbound.clear();send(request);note="只读取启动校验与空闲状态；不会重发固件";MAIN.removeCallbacks(tick);MAIN.postDelayed(tick,250);}catch(RuntimeException e){note="回查被保护拦截：请等待自然重启/重连；历史不完整时先人工确认，未发送";}
 }
 static void releaseAfterInspection(){if(session==null||session.state()!=OtaSession.State.READBACK){note="请先完成同一眼镜的启动状态回读";return;}String peer=NativeTransfer.otaConnection();session.check(peer,SystemClock.elapsedRealtime());if(session.state()!=OtaSession.State.READBACK){settle();return;}
  try{session.release(peer,SystemClock.elapsedRealtime());if(!journal.edit().putBoolean("pending",false).putString("phase","USER_INSPECTED").commit())throw new IllegalStateException();pending=false;session.discardPackage();firmware=null;cleanup();note="用户已检查镜片与新功能，保护已解除；版本回读本身不证明 AP 内容";record("USER_INSPECTED");}catch(RuntimeException e){pending=true;session.recover(session.peer(),SystemClock.elapsedRealtime());journal.edit().putBoolean("pending",true).commit();note="保护未解除；请等待并重新人工确认/回读";}
 }
 private static void cleanup(){generation++;sending=false;inbound.clear();preparing=false;exclusive=pending;NativeTransfer.releaseMessages(lease);lease="";MAIN.removeCallbacks(tick);if(!pending)OtaService.finish();}
 private static void fail(String why){if(session!=null)session.fail(why,SystemClock.elapsedRealtime());note=why;generation++;sending=false;inbound.clear();record("FAILED_OR_UNKNOWN");settle();}
 private static synchronized void settle(){if(session==null)return;OtaSession.State s=session.state();if(s!=recorded||pending&&session.chunks()!=savedChunks&&session.chunks()%25==0){if(s!=recorded)record(s.name());recorded=s;savedChunks=session.chunks();if(pending&&!journal.edit().putString("phase",s.name()).putString("chunks",String.valueOf(session.chunks())).putString("apCovered",String.valueOf(session.covered())).putString("sdkConfirmed",String.valueOf(sdkConfirmed)).commit()){session.fail("诊断记录写入失败",SystemClock.elapsedRealtime());note="诊断未落盘；保留升级保护";s=session.state();}}
  if(s==OtaSession.State.LOCKED){cleanup();return;}
  if(s==OtaSession.State.READY){exclusive=true;preparing=false;note="只读预检通过；15 分钟准备窗口内，授权前需保持预检不超过两分钟";}
  if(s==OtaSession.State.UNKNOWN){generation++;sending=false;inbound.clear();firmware=null;session.discardPackage();OtaService.finish();}
  if(s==OtaSession.State.INSTALLING&&installSeen==0){installSeen=SystemClock.elapsedRealtime();firmware=null;session.discardPackage();note="眼镜已报告进入安装；不要操作，等待重启。不是升级成功回执";}
  if(s==OtaSession.State.READBACK){note="原厂启动校验已确认、眼镜空闲；仍须检查桌面和 TAP1 功能后解除保护";OtaService.finish();}
 }
 private static final Runnable tick=new Runnable(){public void run(){long now=SystemClock.elapsedRealtime();String peer=NativeTransfer.otaConnection();restoreSession(peer,now);if(session!=null){session.check(peer,now);settle();}if(installSeen>0&&now-installSeen>600000)OtaService.finish();if(pending||session!=null&&session.owns())MAIN.postDelayed(this,pending&&(session==null||session.state()==OtaSession.State.UNKNOWN||session.state()==OtaSession.State.INSTALLING||session.state()==OtaSession.State.READBACK)?1000:250);}};
 private static void send(byte[] bytes){if(bytes==null||session==null||session.state()==OtaSession.State.UNKNOWN||session.state()==OtaSession.State.LOCKED)return;if(sending){fail("发送队列冲突，未重试");return;}long token=generation,serial=++sendSerial;try{if(!session.peer().equals(NativeTransfer.connected()))throw new IllegalStateException();Object manager=NavReflect.field(NavReflect.type("E3.u"),"h"),biz=NavReflect.call(NavReflect.type("P3.h"),"valueOf","MARS_FOTA"),priority=NavReflect.call(NavReflect.type("E3.b"),"valueOf","NORMAL");Object message=NavReflect.make("E3.Q",bytes,UUID.randomUUID().toString(),session.peer(),biz,null,priority,false,false,null,null);sending=true;
   Object callback=NavReflect.proxy("kotlin.jvm.functions.Function2",(name,args)->{boolean ok=args.length>1&&args[1]==null;MAIN.post(()->{if(token!=generation||serial!=sendSerial||!sending)return;sending=false;if(!ok){fail("官方 SDK 未确认发送；升级结果待核对");return;}sdkConfirmed++;drain();});});
   OWN_MESSAGE.set(message);try{NavReflect.call(manager,"u",message,callback);}finally{OWN_MESSAGE.remove();}
  }catch(Exception e){fail("无法提交到官方 OTA 通道，未自动重试");}}
 private static void drain(){while(!sending&&!inbound.isEmpty()&&session!=null){byte[] b=inbound.removeFirst();byte[] answer=session.accept(session.peer(),b,SystemClock.elapsedRealtime());settle();if(answer!=null)send(answer);}}
 private static void enqueueFault(String why){long token=generation;if(!FAULT_QUEUED.compareAndSet(false,true))return;MAIN.post(()->{FAULT_QUEUED.set(false);if(token==generation&&busy())fail(why);});}
 /** Executed BEFORE official Flutter delivery, only for our exclusive experiment. */
 public static boolean consume(String kind,Map<?,?> data){if(!"messageReceived".equals(kind)||data==null)return false;try{Object raw=data.get("message");if(!(raw instanceof Map))return false;Map<?,?> m=(Map<?,?>)raw;if(HostBusiness.id(m.get("businessId"))!=9)return false;if(!bootstrap())return true;if(!busy())return false;boolean steal=intercepting();
   Object d=m.get("deviceId"),v=m.get("payload");if(!(d instanceof String)||((String)d).length()>256||!(v instanceof byte[])||((byte[])v).length>8192){enqueueFault("OTA 事件超出格式预算");return steal;}if(EVENTS.incrementAndGet()>16){EVENTS.decrementAndGet();enqueueFault("OTA 入站队列超限");return steal;}String device=(String)d;byte[] bytes=((byte[])v).clone();long token=generation;MAIN.post(()->{try{if(token!=generation||session==null||!device.equals(session.peer()))return;if(inbound.size()>=8){fail("OTA 连续请求超限");return;}inbound.add(bytes);drain();}finally{EVENTS.decrementAndGet();}});return steal;
  }catch(RuntimeException e){return intercepting();}}
 /** Exact SDK queue hook. Owned identity can only be set during our synchronous u(). */
 public static synchronized boolean allowQueue(Object message){try{Object biz=NavReflect.field(message,"c");if(!(biz instanceof Enum))return false;String name=((Enum<?>)biz).name();if(!"MARS_FOTA".equals(name)){if(!INTERACTIVE.contains(name))return true;return bootstrap()&&!intercepting();}if(!bootstrap())return false;if(intercepting())return message==OWN_MESSAGE.get();if(message==OWN_MESSAGE.get())return true;Object data=NavReflect.field(message,"e");if(data instanceof byte[])try{OtaFrame f=OtaFrame.decode((byte[])data);if(f.type==4){if(preparing){enqueueFault("官方也在请求升级；本次准备已撤销");return false;}officialBusyUntil=SystemClock.elapsedRealtime()+1800000;}else if(preparing&&f.type>=5&&f.type<=9)enqueueFault("发现原厂升级传输，保留原厂通路并撤销实验准备");}catch(RuntimeException ignored){if(preparing)enqueueFault("原厂 OTA 消息格式未知，本次准备已撤销");}return true;}catch(Exception e){return false;}}
 public static void blocked(Object message){try{Object callback=NavReflect.field(message,"k");if(callback!=null)NavReflect.call(callback,"invoke",message,NavReflect.field(NavReflect.type("P3.A"),"r"));}catch(Exception ignored){}}
 public static boolean allowFile(){return bootstrap()&&!intercepting();}
 static void serviceLost(){if(pending&&session!=null&&session.state()!=OtaSession.State.INSTALLING&&session.state()!=OtaSession.State.READBACK&&session.state()!=OtaSession.State.UNKNOWN)fail("升级保障服务已丢失；结果待确认，禁止自动恢复");}
}
