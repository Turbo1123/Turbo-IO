package com.turboio.addon;
import android.content.*;
import android.os.SystemClock;

final class AppController {
    private static SharedPreferences prefs;private static AppCodec.Reply snapshot,pending;private static String peer="",note="尚未读取四槽";private static long observed,request,session;private static Runnable changed;private static final java.util.Set<Runnable> observers=new java.util.HashSet<>();
    static void init(Context c){if(prefs!=null)return;prefs=c.getSharedPreferences("turboio_apps",0);NativeTransfer.receive(AppController::message);}
    static void listen(Runnable r){changed=r;}static void detach(){changed=null;}
    static void observe(Runnable r){observers.add(r);}static void unobserve(Runnable r){observers.remove(r);}
    static AppCodec.Reply snapshot(){return snapshot;}
    static String status(){return note+"\n"+NativeTransfer.status();}
    static boolean fresh(){return snapshot!=null&&observed>0&&snapshot.result==0&&!snapshot.needsQuery&&peer.equals(NativeTransfer.connected())&&SystemClock.elapsedRealtime()-observed<60000;}
    private static void update(){if(changed!=null)changed.run();for(Runnable r:new java.util.ArrayList<>(observers))r.run();}
    static void query(){send(AppCodec.QUERY,null,null,255);}
    static void install(AppCodec.Package pkg){if(!fresh()){note="先查询眼镜四槽，再确认安装";query();return;}send(AppCodec.INSTALL,pkg,null,255);}
    static void operate(int op,int slot,AppCodec.Slot expected){if(!fresh()||slot<0||slot>3||snapshot.slots[slot]!=expected){note="槽位已变化，先刷新再选择";query();return;}send(op,null,expected,slot);}
    private static void send(int op,AppCodec.Package pkg,AppCodec.Slot target,int slot){if(NativeTransfer.busy()){note="上一操作尚未完成";update();return;}long next=Math.max(prefs.getLong("request",0),snapshot==null?0:snapshot.lastRequest)+1;if(next>0xffffffffL){note="请求编号已达上限";update();return;}
        long nonce=op==AppCodec.QUERY?0:snapshot.session;byte[] bytes=AppCodec.command(op,next,nonce,pkg,target,slot);request=next;session=nonce;pending=null;String d=NativeTransfer.connected();prefs.edit().putLong("request",next).apply();observed=0;
        boolean sent=NativeTransfer.send("turbo-app.tax",bytes,next,nonce,(state,result)->{if((state==TransferGate.State.CONFIRMED||state==TransferGate.State.REJECTED)&&pending!=null){snapshot=pending;peer=d;observed=state==TransferGate.State.CONFIRMED?SystemClock.elapsedRealtime():0;note=state==TransferGate.State.CONFIRMED?"四槽状态已由眼镜确认":"眼镜拒绝（"+result+"）· 请重新查询";}else note="结果未确认，请查询后重试";pending=null;update();});if(sent)note="等待文件完成与 TAP1 回执";update();}
    private static void message(String d,byte[] b){AppCodec.Reply r=AppCodec.reply(CustomEnvelope.decode(b,"turbo_app_v1",376));if(r==null||!d.equals(NativeTransfer.connected())||r.request!=request||(session!=0&&r.session!=session))return;pending=r;NativeTransfer.ack(d,r.request,session,r.result);}
}
