package com.turboio.addon;
import android.content.*;
import android.os.SystemClock;

final class NativeNavigation {
    private static SharedPreferences prefs;private static NativeNavSession session;private static NativeNavCodec.Reply pending;private static Runnable changed;private static String target="";
    static void init(Context c){if(prefs!=null)return;prefs=c.getSharedPreferences("turboio_native_nav",0);NativeTransfer.receive(NativeNavigation::event);}
    static void listen(Runnable r){changed=r;}static String status(){return (session==null?"尚未开启TNV1原生导航":session.status())+"\n"+NativeTransfer.status();}
    static boolean active(){return session!=null&&(session.state()==NativeNavSession.State.STARTING||session.state()==NativeNavSession.State.RUNNING||session.state()==NativeNavSession.State.STOPPING);}
    static String phase(){if(session==null)return "idle";switch(session.state()){case STARTING:return "starting";case RUNNING:return "ready";case STOPPING:return "stopping";case UNCERTAIN:return "uncertain";default:return "idle";}}
    static boolean start(NativeNavCodec.Scene scene){if(active()||phase().equals("uncertain")||NativeTransfer.busy()||NavGlasses.active()||MusicBridge.active()||ReaderBridge.active())return false;target=NativeTransfer.connected();if(target.isEmpty())return false;long sid=Math.max(System.currentTimeMillis()/1000,prefs.getLong("sid",0)+1);if(sid>0xffffffffL)return false;prefs.edit().putLong("sid",sid).apply();session=new NativeNavSession(target,sid,(packet,identity,request)->{pending=null;return NativeTransfer.send("turbo-navigation.tnv",packet,request,identity,8000,(state,result)->{if(session==null||session.session()!=identity)return;session.complete(request,state==TransferGate.State.CONFIRMED,result,pending,SystemClock.elapsedRealtime());pending=null;notifyUI();});});boolean started=session.start(scene,SystemClock.elapsedRealtime());NativeTransfer.MAIN.removeCallbacks(tick);if(started)NativeTransfer.MAIN.postDelayed(tick,250);notifyUI();return started;}
    static void offer(NativeNavCodec.Scene scene){if(session!=null){session.offer(scene,SystemClock.elapsedRealtime());}}
    static void stop(){if(session!=null){session.stop(SystemClock.elapsedRealtime());notifyUI();}}
    static void confirmIdle(){if(active()||NativeTransfer.busy())return;session=null;target="";NativeTransfer.MAIN.removeCallbacks(tick);notifyUI();}
    private static void notifyUI(){if(changed!=null)changed.run();}
    private static final Runnable tick=new Runnable(){public void run(){if(session==null)return;session.pump(NativeTransfer.connected(),SystemClock.elapsedRealtime());notifyUI();if(active())NativeTransfer.MAIN.postDelayed(this,250);}};
    private static void event(String peer,byte[] data){if(session==null||!target.equals(peer)||!session.pending())return;NativeNavCodec.Reply r=NativeNavCodec.reply(CustomEnvelope.decode(data,"turbo_nav_v1",32));if(r==null||r.sid!=session.session()||r.seq!=session.sequence())return;pending=r;NativeTransfer.ack(peer,r.seq,r.sid,r.result);}
}
