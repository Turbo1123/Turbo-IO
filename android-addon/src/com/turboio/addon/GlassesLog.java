package com.turboio.addon;
import android.app.*;
import android.content.Context;
import android.os.*;
import java.io.File;
import java.util.*;
import java.util.concurrent.*;

/** Glasses log glue (port of iOS GlassesLogProbe, log-local-v3): one owned start_log_task over LOG_REPORT, its ACK and
 * received archive consumed before the official app sees them, a private SHA-256-verified copy, persisted ownership,
 * no automatic retries. The consume and queue entry points run on host threads and never throw. */
public final class GlassesLog {
    static final String VERSION="log-local-v3";
    private static final Handler MAIN=new Handler(Looper.getMainLooper());
    private static final ExecutorService IO=Executors.newSingleThreadExecutor();
    private static Context app;private static File home;private static GlassesLogGate gate;
    private static volatile String routeDevice="";private static volatile long routeAt=-1;private static volatile boolean appActive=true;
    private static String note="尚未请求眼镜日志。请保持官方眼镜连接。";private static boolean copying,restoring;private static File archive;
    private static long started,round;private static Runnable changed;
    private GlassesLog(){}
    static void init(Context c){
        if(app!=null)return;app=c.getApplicationContext();home=new File(app.getNoBackupFilesDir(),"turboio/glasses-log");home.mkdirs();
        synchronized(GlassesLog.class){gate=new GlassesLogGate(GlassesLogFiles.readJson(new File(home,"owner.json")));}
        ((Application)app).registerActivityLifecycleCallbacks(new Application.ActivityLifecycleCallbacks(){
            public void onActivityResumed(Activity a){appActive=true;}public void onActivityPaused(Activity a){appActive=false;}
            public void onActivityCreated(Activity a,Bundle b){}public void onActivityStarted(Activity a){}public void onActivityStopped(Activity a){}public void onActivitySaveInstanceState(Activity a,Bundle b){}public void onActivityDestroyed(Activity a){}});
    }
    static void listen(Runnable r){changed=r;}
    private static void changed(String text){note=text;Runnable r=changed;if(r!=null)try{r.run();}catch(RuntimeException ignored){}}
    static String note(){return note;}static File archive(){return archive;}
    private static Map<String,Object> snapshot(){synchronized(GlassesLog.class){return gate==null?new LinkedHashMap<>():gate.snapshot();}}
    private static boolean saveOwner(Map<String,Object> s){return home!=null&&GlassesLogFiles.writeJson(new File(home,"owner.json"),s);}
    static boolean hasRecord(){return !snapshot().isEmpty();}
    private static boolean renewable(){Map<String,Object> s=snapshot();Object q=s.get("quarantined");
        return archive!=null&&!copying&&!restoring&&Boolean.TRUE.equals(s.get("settled"))&&routeDevice.equals(s.get("device"))&&q instanceof List&&((List<?>)q).size()<GlassesLogGate.MAX_ROUNDS;}
    static boolean ready(){long now=SystemClock.elapsedRealtime();return !copying&&!restoring&&!routeDevice.isEmpty()&&appActive&&routeAt>=0&&now-routeAt<120000&&now>=routeAt&&(snapshot().isEmpty()||renewable());}

    /** Queue tap (host thread): LAUNCHER traffic is route evidence; an official type-16 log request is blocked while we own one. */
    static boolean queue(String business,String device,byte[] payload){
        if(payload.length>8192)return true;A2uiFrame.Frame f=A2uiFrame.decode(payload);if(f==null)return true;
        if("LAUNCHER".equals(business)){routeDevice=device;routeAt=SystemClock.elapsedRealtime();return true;}
        if(f.type==16){synchronized(GlassesLog.class){if(gate!=null&&gate.ownsRequest(device))return false;}}
        return true;
    }
    /** Pre-delivery consumer (host thread). true = the official app never sees this event. */
    public static boolean consume(String kind,Map<?,?> data){
        try{
            if(kind==null||data==null||!("messageReceived".equals(kind)||kind.startsWith("fileShare")))return false;
            GlassesLogGate.Decision d;Map<String,Object> after;
            synchronized(GlassesLog.class){if(gate==null||gate.device()==null)return false;Map<String,Object> before=gate.snapshot();d=gate.accept(kind,data);if(!d.consume)return false;after=gate.snapshot();if(!after.equals(before))saveOwner(after);}
            Map<String,Object> retiredSnapshot=after;MAIN.post(()->handle(d,retiredSnapshot));return true;
        }catch(Throwable t){return false;}
    }
    private static void handle(GlassesLogGate.Decision d,Map<String,Object> snap){
        if(d.retired)return;if(d.candidate!=null){Object r=snap.get("retired");if(r instanceof List&&((List<?>)r).contains(d.candidate.taskId))return;}
        if(d.ack!=null)changed("已截获眼镜日志任务回执；等待匹配UUID的归档，不转交Flutter");
        if(d.awaitingAck)changed("归档事件先于回执：已隔离，等待任务UUID核对");
        if(d.mismatch)changed("日志事件不匹配，已隔离但不复制；没有重试");
        GlassesLogContract.Candidate c=d.candidate;if(c==null||copying||archive!=null)return;
        if(!GlassesLogContract.windowValid(started/1000.0,SystemClock.elapsedRealtime()/1000.0,appActive,true)){changed("迟到或后台文件事件已隔离，未复制；原文件保留，任务结果未知");return;}
        copying=true;String device=(String)snap.get("device");
        IO.execute(()->{GlassesLogFiles.Copy copy=null;
            for(File sandbox:sandboxes()){java.nio.file.Path p=GlassesLogFiles.localPath(c.filePath,sandbox,GlassesLogFiles.LIMIT);if(p!=null){copy=GlassesLogFiles.copy(p,sandbox,home,GlassesLogFiles.LIMIT);break;}}
            boolean saved=copy!=null&&GlassesLogFiles.saveReceipt(home,copy,device,c.taskId);GlassesLogFiles.Copy done=copy;
            MAIN.post(()->{copying=false;if(saved){archive=done.file;changed("已保存独立日志副本；原件未删，本模块未上传。压缩格式待Mac核验");}
                else changed("归档或恢复凭据校验失败；保留文件，不允许新一轮，请由Mac检查");});});
    }
    private static List<File> sandboxes(){List<File> s=new ArrayList<>();File ext=app.getExternalFilesDir(null);if(ext!=null)s.add(new File(ext,"cc_transfer"));s.add(new File(app.getFilesDir(),"cc_transfer"));return s;}
    static void restore(){
        if(app==null||archive!=null||restoring||copying)return;restoring=true;Map<String,Object> s=snapshot();String device=(String)s.get("device");boolean receiptExists=new File(home,"archive.json").isFile();
        IO.execute(()->{GlassesLogFiles.Restored r=device==null?null:GlassesLogFiles.restore(home,device);
            MAIN.post(()->{restoring=false;boolean ok=false;
                if(r!=null)synchronized(GlassesLog.class){if(gate.reconcile(r.task,device)&&saveOwner(gate.snapshot()))ok=true;}
                if(ok){archive=r.file;changed(r.recovered?"已恢复首次日志副本，可分享；SHA256核对通过。首次隔离失败，这不是重新采集。":"已恢复本地日志副本，可分享；SHA256核对通过。");}
                else changed(receiptExists?"已有归档恢复凭据，但验证未通过；未重新采集。":!s.isEmpty()?"检测到历史任务，尚无可验证副本。未重发，也不是等待两分钟连接。":"尚未采集。先确认官方眼镜连接，再请求一次。");});});
    }
    /** One owned log request. Never retried. */
    static void start(){
        Map<String,Object> s=snapshot();
        if(!s.isEmpty()&&!renewable()){changed("本轮任务未完成归档核验，或设备不匹配；未重复发送。请保留当前状态，由Mac核对日志。");return;}
        if(!ready()){changed("尚未发送：未取得近期官方通信。请回官方首页确认眼镜连接，再进入本页；不是等待两分钟。");return;}
        String device=routeDevice;if(!device.equals(NativeTransfer.connected())||NativeTransfer.busy()){changed("尚未发送：未取得近期官方通信。请回官方首页确认眼镜连接，再进入本页；不是等待两分钟。");return;}
        long seq=new java.security.SecureRandom().nextInt(0x3fffffff)+1L;Object manager,message;
        Map<String,Object> payload=new LinkedHashMap<>();payload.put("data","");payload.put("mode",0L);payload.put("value",0L);
        Map<String,Object> json=new LinkedHashMap<>();json.put("cmd","start_log_task");json.put("payload",payload);byte[] packet=A2uiFrame.packet(16,seq,json);
        if(packet==null){changed("未发送：官方传输ABI不可用");return;}
        // Resolve the whole host send path before arming ownership, so an ABI failure never leaves a stuck round.
        try{manager=NavReflect.field(NavReflect.type(HostAbi.manager()),"h");Object business=NavReflect.call(NavReflect.type(HostAbi.business()),"valueOf","LOG_REPORT"),priority=NavReflect.call(NavReflect.type(HostAbi.priority()),"valueOf","NORMAL");
            message=NavReflect.make(HostAbi.message(),packet,UUID.randomUUID().toString(),device,business,null,priority,false,false,null,null);}
        catch(Exception e){changed("未发送：官方传输ABI不可用");return;}
        // Verify the previous archive (32 MiB SHA-256) before taking the lock that host-thread consume() needs.
        GlassesLogFiles.Restored previous=archive!=null?GlassesLogFiles.restore(home,device):null;
        synchronized(GlassesLog.class){
            if(archive!=null){GlassesLogFiles.Restored v=previous;String task=gate.task();
                if(v==null||task==null||!task.equals(v.task)||!v.file.equals(archive)||!GlassesLogFiles.writeJson(new File(home,"receipt-"+task+".json"),GlassesLogFiles.readJson(new File(home,"archive.json")))||!gate.beginNext(device,GlassesLog::saveOwner)){changed("未发送：旧归档核验或新隔离记录保存失败；保留旧副本");return;}
                archive=null;
            }else if(!gate.begin(device)||!saveOwner(gate.snapshot())){changed("未发送：无法建立持久化隔离记录");return;}
        }
        started=SystemClock.elapsedRealtime();long mine=++round;Map<String,Object> extra=new LinkedHashMap<>();
        changed("已请求一次眼镜日志，等待回执；180秒接收窗口，不自动重试");
        try{Object callback=NavReflect.proxy("kotlin.jvm.functions.Function2",(name,args)->MAIN.post(()->{if(mine!=round||archive!=null)return;
                changed(args.length>1&&args[1]==null?"SDK接收了请求，仍需眼镜回执和归档":"SDK回调未确认成功，结果未知；不重试，隔离保留");}));
            QueueTap.OWN.set(message);try{NavReflect.call(manager,HostAbi.send(),message,callback);}finally{QueueTap.OWN.remove();}
        }catch(Exception e){changed("发送调用异常，结果未知；隔离保留，不重试");}
        MAIN.postDelayed(()->{if(mine==round&&archive==null&&!copying)changed("180秒未保存归档，结果未知。未取消眼镜任务；迟到事件继续隔离，不重试");},180000);
    }
}
