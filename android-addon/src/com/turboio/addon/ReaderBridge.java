package com.turboio.addon;
import android.content.*;
import android.os.*;
import java.util.*;

/** One page transaction, at most one queued replacement, no automatic retry after uncertainty. */
final class ReaderBridge {
 interface Source{void event(ReaderCodec.Reply r);}
 private static SharedPreferences prefs;private static Source source;private static String peer="",note="阅读同步未开始";private static long sid,seq,revision,event,clock,next;
 private static boolean active,pending,opening,closing,failed;private static byte[] page,queued;private static int stage,offset,done,total;private static long rejectReason;private static final Set<Long> seen=new LinkedHashSet<>();
 static void init(Context c,Source s){source=s;if(prefs!=null)return;prefs=c.getSharedPreferences("turboio_reader_bridge",0);NativeTransfer.receive(ReaderBridge::receive);}
 static boolean active(){return active;}static boolean busy(){return pending||page!=null;}static String status(){return note;}
 static void open(byte[] first){if(active){publish(first);return;}if(failed){note="上次结果未确认，请确认眼镜回首页再恢复";return;}if(NativeTransfer.busy()||NativeNavigation.active()||NavGlasses.active()||MusicBridge.active()){note="请先结束其他显示任务";return;}peer=NativeTransfer.connected();if(peer.isEmpty()){note="请先连接眼镜";return;}sid=Math.max(System.currentTimeMillis()/1000,prefs.getLong("sid",0)+1);if(sid>0xffffffffL||!prefs.edit().putLong("sid",sid).commit()){note="会话存储失败";return;}seq=revision=event=clock=next=0;seen.clear();opening=active=true;closing=false;page=null;queued=first.clone();BackgroundWork.acquire("阅读",16);NativeTransfer.MAIN.removeCallbacks(tick);tick.run();}
 static void publish(byte[] bytes){if(!active||closing)return;if(bytes==null||bytes.length<64||bytes.length>24576)throw new IllegalArgumentException();queued=bytes.clone();}
 static void close(){queued=null;closing=true;if(active)pump();}
 static void reset(){if(pending||NativeTransfer.busy())return;active=failed=opening=closing=false;page=queued=null;NativeTransfer.MAIN.removeCallbacks(tick);BackgroundWork.release("阅读");note="已确认退出，可重新发送";}
 private static void fail(String s){active=false;failed=true;page=queued=null;BackgroundWork.release("阅读");note=s+(s.startsWith("眼镜拒绝阅读包")?" · 入口原因 "+rejectReason+"（"+entryReason(rejectReason)+"）":"");NativeTransfer.MAIN.removeCallbacks(tick);}
 private static final Runnable tick=new Runnable(){public void run(){pump();if(active)NativeTransfer.MAIN.postDelayed(this,120);}};
 private static void pump(){long now=SystemClock.elapsedRealtime();if(!active||pending||now<next)return;if(!peer.equals(NativeTransfer.connected())){fail("连接变化，已停止；未自动重发");return;}
  int op,off=0;byte[] payload=null;
  if(closing)op=6;else if(opening)op=1;else{if(page==null&&queued!=null){page=queued;queued=null;revision++;stage=0;offset=done=0;total=2+(page.length+479)/480;}
   if(page!=null){if(stage==0){op=2;payload=new byte[8];ReaderCodec.put(payload,0,page.length);ReaderCodec.put(payload,4,ReaderCodec.crc(page));}else if(offset<page.length){op=3;off=offset;payload=Arrays.copyOfRange(page,offset,Math.min(page.length,offset+480));}else op=4;}
   else if(now-clock>=8000){op=7;off=(int)event;}else return;}
  if(seq==0xffffffffL){fail("序列耗尽");return;}long request=++seq;int operation=op,count=payload==null?0:payload.length;long rev=(op==1?0:revision);pending=true;rejectReason=0;clock=now;
  boolean sent=NativeTransfer.send("turbo-reader.twr",ReaderCodec.command(op,sid,request,rev,off&0xffffffffL,payload),request,sid,15000,(state,result)->{pending=false;if(state!=TransferGate.State.CONFIRMED){fail(state==TransferGate.State.REJECTED?"眼镜拒绝阅读包（"+result+"），已停发":"阅读结果未确认；停止且不重试");if(operation==1&&state==TransferGate.State.REJECTED){failed=false;note+="；未进入阅读，条件恢复后可重新点击发送";}return;}if(operation==1)opening=false;else if(operation==2){stage=1;done++;}else if(operation==3){offset+=count;done++;}else if(operation==4){page=null;done++;}else if(operation==6){active=closing=false;page=queued=null;BackgroundWork.release("阅读");}next=SystemClock.elapsedRealtime()+120;note=operation==6?"眼镜已确认退出":"眼镜已确认 "+done+" / "+total+" 包";});
  if(!sent){pending=false;fail("通道不可用，已停止");}else note="发送 "+Math.min(total,done+1)+" / "+total+" 包 · 等待双回执";
 }
 private static void receive(String d,byte[] bytes){ReaderCodec.Reply r=ReaderCodec.reply(CustomEnvelope.decode(bytes,"turbo_read_v1",48));if(r==null||!d.equals(NativeTransfer.connected()))return;
  if(r.event==0){if(pending&&d.equals(peer)&&r.sid==sid&&r.seq==seq){rejectReason=r.result==0?0:r.value;NativeTransfer.ack(d,r.seq,r.sid,r.result);}return;}
  if(r.result!=0){if(active&&r.sid==sid&&d.equals(peer))fail("眼镜退出/拒绝阅读（"+r.result+" / 原因"+r.value+"）");return;}
  if(r.id==0||seen.contains(r.id))return;if(r.event==1&&r.sid==0){if(active)return;}else if(!active||!d.equals(peer)||r.sid!=sid)return;
  seen.add(r.id);if(seen.size()>128)seen.remove(seen.iterator().next());event=r.id;clock=0;
  if(r.event==4){active=false;page=queued=null;BackgroundWork.release("阅读");note="眼镜已退出阅读";}source.event(r);
 }
 static String entryReason(long reason){switch((int)reason){case 1:return "前台归属、镜腿展开或业务空闲条件未满足";case 2:return "配对或连接状态未满足";case 3:return "旧阅读页仍在关闭";case 4:return "其他显示页面占用";case 5:return "等待渲染空闲";case 6:return "阅读视图创建失败";case 7:return "视图事件注册失败";case 8:return "显示保持申请失败";case 9:return "页面进入超时";default:return "固件未提供更细原因";}}
}
