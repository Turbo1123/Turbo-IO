package com.turboio.addon;
import android.content.*;
import android.os.*;
import java.util.*;

/** One file at a time, track-generation-bound replies, bounded assets and no blind retry. */
final class MusicBridge {
 interface Source{byte[] state(long event);void command(int event);}
 private static SharedPreferences prefs;private static Source source;private static String peer="",note="音乐同步未开启";
 private static long sid,gen,seq,event,clock,next;private static boolean active,open,close,pending,failed;
 private static byte[] cover,lyrics;private static int coverAt,lyricAt,packets;
 private static final Set<Long> events=new LinkedHashSet<>();
 static void init(Context c,Source s){source=s;if(prefs!=null)return;prefs=c.getSharedPreferences("turboio_music",0);NativeTransfer.receive(MusicBridge::message);}
 static boolean active(){return active;}static String status(){return note;}
 static void open(byte[] art,List<MusicCodec.Line> lines){if(pending){note="上一首仍在传输，等待完成后重试同步";return;}if(NativeTransfer.busy()||NativeNavigation.active()||ReaderBridge.active()||NavGlasses.active()){note="其他显示任务正在运行，未发送";return;}
  String target=NativeTransfer.connected();if(target.isEmpty()){note="请先连接眼镜；手机音乐仍可播放";return;}if(!peer.equals(target)){events.clear();event=0;}peer=target;
  if(failed){note="上次同步未确认，请先确认眼镜回首页";return;}
  sid=Math.max(System.currentTimeMillis()/1000,prefs.getLong("sid",0)+1);if(sid>0xffffffffL){note="会话编号耗尽";return;}if(!prefs.edit().putLong("sid",sid).commit()){note="会话编号保存失败";return;}gen=1;seq=0;packets=0;coverAt=lyricAt=0;cover=art!=null&&art.length==MusicCodec.COVER_BYTES?art.clone():null;lyrics=MusicCodec.lyrics(lines);open=active=true;BackgroundWork.acquire("音乐显示",16);failed=close=false;next=clock=0;NativeTransfer.MAIN.removeCallbacks(tick);tick.run();
 }
 static void assets(byte[] art,List<MusicCodec.Line> lines){if(cover==null&&art!=null&&art.length==MusicCodec.COVER_BYTES)cover=art.clone();if((lyrics==null||lyrics.length==0)&&lines!=null&&!lines.isEmpty())lyrics=MusicCodec.lyrics(lines);}
 static void changed(){clock=0;}
 static void close(){close=true;if(!active){note="当前没有已确认活动会话；如镜片仍显示，请从眼镜退出";return;}pump();}
 static void resetAfterUserConfirmation(){if(pending||NativeTransfer.busy())return;active=failed=open=close=false;BackgroundWork.release("音乐显示");cover=lyrics=null;NativeTransfer.MAIN.removeCallbacks(tick);note="已确认眼镜回首页；可重新同步";}
 static boolean busy(){return pending;}
 private static void fail(String s){failed=true;active=false;BackgroundWork.release("音乐显示");note=s;NativeTransfer.MAIN.removeCallbacks(tick);}
 private static void rejected(int operation,TransferGate.State state,int result){
  // A matched BUSY response to OPEN is a definitive refusal, not a lost ACK.
  // The firmware closes any partially created view before returning BUSY.
  // Stop here; only a new user action may create another session. Do not
  // relax uncertain delivery or failures after an accepted OPEN.
  if(operation==MusicCodec.OPEN&&state==TransferGate.State.REJECTED&&result==3){
   fail("眼镜暂不允许进入音乐（忙碌 3）；退出其他眼镜页面后，可点“显示到眼镜”重试");
   failed=open=close=false;cover=lyrics=null;return;
  }
  fail(state==TransferGate.State.REJECTED?"眼镜拒绝音乐包（"+result+"）；先确认退出再重试":"音乐同步结果未确认，已停止；不自动重发");
 }
 private static final Runnable tick=new Runnable(){public void run(){pump();if(active)NativeTransfer.MAIN.postDelayed(this,250);}};
 private static void pump(){long now=SystemClock.elapsedRealtime();if(!active||failed||pending||now<next)return;if(!peer.equals(NativeTransfer.connected())){fail("蓝牙连接变化，停止同步；手机播放不受影响");return;}
  int op;byte[] payload;int offset=0;boolean last=false;
  if(close){op=MusicCodec.CLOSE;payload=null;}else if(open){op=MusicCodec.OPEN;payload=source.state(event);clock=now;}else if(now-clock>=3000){op=MusicCodec.CLOCK;payload=source.state(event);clock=now;}
  else if(lyrics!=null&&lyricAt<lyrics.length){op=MusicCodec.LYRICS;offset=lyricAt;payload=Arrays.copyOfRange(lyrics,offset,Math.min(lyrics.length,offset+4064));last=offset+payload.length==lyrics.length;}
  else if(cover!=null&&coverAt<cover.length){op=MusicCodec.COVER;offset=coverAt;payload=Arrays.copyOfRange(cover,offset,Math.min(cover.length,offset+4064));last=offset+payload.length==cover.length;}else return;
  if(seq>=0xffffffffL){fail("音乐序号耗尽");return;}long request=++seq,identity=sid;int operation=op,bytes=payload==null?0:payload.length;
  byte[] packet=MusicCodec.command(op,sid,gen,request,offset,last,payload);pending=true;
  boolean sent=NativeTransfer.send("turbo-music.tmu",packet,request,sid,15000,(state,result)->{pending=false;if(sid!=identity)return;if(state!=TransferGate.State.CONFIRMED){rejected(operation,state,result);return;}packets++;if(operation==MusicCodec.OPEN)open=false;if(operation==MusicCodec.OPEN||operation==MusicCodec.CLOCK)clock=SystemClock.elapsedRealtime();if(operation==MusicCodec.CLOSE){active=close=false;BackgroundWork.release("音乐显示");cover=lyrics=null;}if(operation==MusicCodec.COVER)coverAt+=bytes;if(operation==MusicCodec.LYRICS)lyricAt+=bytes;next=SystemClock.elapsedRealtime()+150;note="眼镜已确认 "+packets+" 包 · 封面 "+coverAt+"/"+(cover==null?0:cover.length)+" 字节 · 歌词 "+lyricAt+"/"+(lyrics==null?0:lyrics.length)+" 字节";});
  if(!sent){pending=false;fail("通道忙碌或未连接，未继续同步");}else note="发送音乐第 "+(packets+1)+" 包 · 等待双回执";
 }
 private static void message(String d,byte[] b){MusicCodec.Reply r=MusicCodec.reply(CustomEnvelope.decode(b,"turbo_music_v1",32));if(r==null||!d.equals(NativeTransfer.connected()))return;
  android.util.Log.i("TurboIOTransfer","music reply event="+r.event+" result="+r.result+" active="+r.active+" awake="+r.awake+" session="+r.sid+" generation="+r.gen+" sequence="+r.seq+" request="+r.request);
  if(r.event==0){if(pending&&d.equals(peer)&&r.sid==sid&&r.gen==gen&&r.seq==seq)NativeTransfer.ack(d,r.seq,r.sid,r.result);return;}
  // Resume from the glasses can request the currently selected song only after
  // user enabled sync; never wakes a killed Android process or bypasses consent.
  if(r.result!=0||r.request==0||(r.event!=1&&(!d.equals(peer)||r.sid!=sid||r.gen!=gen))||events.contains(r.request))return;
  events.add(r.request);if(events.size()>128)events.remove(events.iterator().next());event=r.request;
  // A new glasses-side RESUME from its empty waiting page is explicit user
  // intent plus peer-confirmed inactive state. It may recover a failed phone
  // session, unlike a timeout or a duplicate event. Never replace an in-flight
  // transfer or an active session this way.
  if(r.event==1&&!r.active&&!pending&&!active){failed=open=close=false;cover=lyrics=null;note="眼镜请求重新进入，准备同步当前歌曲";}
  if(r.event==6){active=false;BackgroundWork.release("音乐显示");open=false;NativeTransfer.MAIN.removeCallbacks(tick);note="眼镜音乐页已退出";}source.command(r.event);clock=0;
 }
}
