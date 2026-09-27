package com.turboio.addon;
import android.content.Context;
import android.content.SharedPreferences;
import android.os.SystemClock;

/** Glasses own the countdown; closing this screen never stops a timer. */
final class FocusController {
    private static SharedPreferences prefs;private static FocusCodec.Reply snapshot,pending;private static String peer="";
    private static long observed,request,requestSID,lastQuery;private static Runnable changed;private static String note="先读取眼镜计时状态";
    private static final class StartIntent {final String peer;final int seconds;final long at;StartIntent(String p,int s){peer=p;seconds=s;at=SystemClock.elapsedRealtime();}}
    private static StartIntent startIntent;
    static void init(Context c){if(prefs!=null)return;prefs=c.getSharedPreferences("turboio_focus",0);NativeTransfer.receive(FocusController::message);}
    static void listen(Runnable r){changed=r;}static void detach(){changed=null;startIntent=null;}
    static String status(){return note+"\n"+NativeTransfer.status();}
    static FocusCodec.Reply snapshot(){return snapshot;}
    static long remaining(){if(snapshot==null)return 0;long dt=snapshot.status==FocusCodec.RUNNING?SystemClock.elapsedRealtime()-observed:0;return Math.max(0,snapshot.remainingMS-dt);}
    private static void update(){if(changed!=null)changed.run();}
    static boolean fresh(){return snapshot!=null&&observed>0&&peer.equals(NativeTransfer.connected())&&SystemClock.elapsedRealtime()-observed<20000;}
    static void query(){startIntent=null;lastQuery=SystemClock.elapsedRealtime();send(FocusCodec.QUERY,0,0,0,0);}
    static void refreshIfNeeded(){long now=SystemClock.elapsedRealtime();if(startIntent==null&&snapshot!=null&&(snapshot.status==FocusCodec.RUNNING||snapshot.status==FocusCodec.PAUSED)&&now-observed>=12000&&now-lastQuery>=12000&&!NativeTransfer.busy()&&!NativeTransfer.connected().isEmpty())query();}
    static void start(int seconds){
        if(seconds<10||seconds>7200){note="专注时长须为10秒至120分钟";update();return;}
        if(startIntent!=null||NativeTransfer.busy()){note="正在确认上一操作，请稍候";update();return;}
        String target=NativeTransfer.connected();if(target.isEmpty()){note="请先连接眼镜";update();return;}
        if(!fresh()){startIntent=new StartIntent(target,seconds);lastQuery=SystemClock.elapsedRealtime();send(FocusCodec.QUERY,0,0,0,0);return;}
        startFresh(seconds);
    }
    private static void startFresh(int seconds){if(snapshot.status==FocusCodec.RUNNING||snapshot.status==FocusCodec.PAUSED){note="已有计时，请先结束";update();return;}long sid=Math.max(Math.max(System.currentTimeMillis()/1000,prefs.getLong("sid",0)+1),snapshot.sid+1);if(sid>0xffffffffL){note="会话编号已达上限";update();return;}prefs.edit().putLong("sid",sid).apply();send(FocusCodec.START,sid,snapshot.revision,seconds,0);}
    static void operate(int op){startIntent=null;if(!fresh()){note="先刷新状态，再重试操作";query();return;}if(snapshot.sid==0){note="没有正在进行的眼镜计时";update();return;}send(op,snapshot.sid,snapshot.revision,0,0);}
    private static void send(int op,long sid,long revision,int seconds,int phase){if(NativeTransfer.busy()){note="上一操作尚未完成";update();return;}long seq=prefs.getLong("seq",0)+1;if(seq>0xffffffffL){note="请求编号已达上限";update();return;}prefs.edit().putLong("seq",seq).apply();request=seq;requestSID=sid;pending=null;String target=NativeTransfer.connected();
        StartIntent intent=op==FocusCodec.QUERY?startIntent:null;
        boolean sent=NativeTransfer.send("turbo-focus.tfp",FocusCodec.command(op,sid,seq,revision,seconds,phase),seq,sid,(state,result)->{boolean confirmed=state==TransferGate.State.CONFIRMED&&pending!=null&&pending.result==0;if(confirmed){snapshot=pending;peer=target;observed=SystemClock.elapsedRealtime();note="眼镜状态已同步";}else{observed=0;note="操作未完成或被拒绝，请查询后重试";}pending=null;
            // Only this explicit start's query can continue it, once. No replay
            // after timeout, leaving the page, another action or peer change.
            if(intent!=null&&startIntent==intent){startIntent=null;long elapsed=SystemClock.elapsedRealtime()-intent.at;
                if(confirmed&&elapsed>=0&&elapsed<=10000&&intent.peer.equals(NativeTransfer.connected())&&fresh()){startFresh(intent.seconds);return;}
                note="开始请求未执行：状态确认超时、失败或连接变化，请重试";
            }update();});if(sent)note=intent!=null?"正在确认眼镜空闲，确认后开始本次专注":"等待眼镜计时回执";else {startIntent=null;note="通道忙碌或未连接，本次操作未发送";}update();}
    private static void message(String d,byte[] b){FocusCodec.Reply r=FocusCodec.reply(CustomEnvelope.decode(b,"turbo_focus_v1",64));if(r==null||!d.equals(NativeTransfer.connected())||r.seq!=request||r.requestSID!=requestSID)return;pending=r;NativeTransfer.ack(d,r.seq,r.requestSID,r.result);}
}
