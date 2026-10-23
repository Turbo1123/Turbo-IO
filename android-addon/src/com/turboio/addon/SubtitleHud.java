package com.turboio.addon;
import android.os.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

/** Glue for the subtitle HUD lab (iOS SubtitleHUD.m): one SubtitleTrial on the stock AI_SUBTITLE business, the
 * default verified preview/stop templates, a user idle confirmation valid 120 s before every start, an 8 s SDK
 * deadline for text, observe-only incoming events and an in-memory evidence ring. Main thread only. */
final class SubtitleHud {
    private static final Handler MAIN=new Handler(Looper.getMainLooper());
    private static final SubtitleTrial trial=new SubtitleTrial(SubtitleHud::submit);
    private static String device="";private static boolean confirmed,textPending;private static long confirmedAt;private static double textDeadline;
    private static final ArrayDeque<String> events=new ArrayDeque<>();
    static Runnable changed;
    private SubtitleHud(){}
    static SubtitleTrial trial(){return trial;}
    static boolean active(){return trial.active();}
    private static double now(){return SystemClock.elapsedRealtime()/1000.0;}
    private static void notifyUI(){Runnable r=changed;if(r!=null)try{r.run();}catch(RuntimeException ignored){}}
    private static Map<String,Object> m(Object...kv){Map<String,Object> r=new LinkedHashMap<>();for(int i=0;i<kv.length;i+=2)r.put((String)kv[i],kv[i+1]);return r;}
    static Map<String,Object> preview(){return m("sid","template","force",false,"scope","temporary","config",m("font_size",2L,"content_width",100L,"max_lines",5L,"position","center","is_display",true,"straight_view","original"));}
    static Map<String,Object> stopTemplate(){return m("sid","template","reason_code",10L,"text","");}
    private static void record(String direction,int type,String extra){if(events.size()>=80)events.removeFirst();events.addLast(String.format(Locale.ROOT,"%.1fs %s type%d%s",now()%100000,direction,type,extra));}
    static List<String> events(){return new ArrayList<>(events);}
    static boolean confirmedIdle(){return confirmed&&SystemClock.elapsedRealtime()-confirmedAt<120000;}
    /** The user asserts the lens left every session (not a protocol ACK). */
    static boolean confirmIdle(){if(!trial.reset())return false;MAIN.removeCallbacks(tick);textPending=false;confirmed=true;confirmedAt=SystemClock.elapsedRealtime();notifyUI();return true;}
    /** Start a temporary preview. Why a refusal happened is returned in why[0]. */
    static boolean start(String[] why){
        if(trial.active()){why[0]="已有字幕实验";return false;}
        if(!confirmedIdle()){why[0]="请先实际确认眼镜已退出（2分钟内有效）";return false;}
        if(NavGlasses.active()||NativeTransfer.busy()){why[0]="请先结束字幕导航、实时字幕或其他传输";return false;}
        String d=NativeTransfer.connected();if(d.isEmpty()){why[0]="眼镜未连接";return false;}
        device=d;confirmed=false;textPending=false;
        boolean ok=trial.start(preview(),stopTemplate(),now());MAIN.removeCallbacks(tick);if(trial.active())MAIN.postDelayed(tick,1000);notifyUI();
        if(!ok)why[0]=trial.note();return ok;
    }
    static boolean next(){boolean ok=trial.next(now());notifyUI();return ok;}
    static void stop(String reason){if(!trial.active())return;trial.stop(reason,now());if(trial.active())confirmed=false;notifyUI();}
    private static boolean submit(int type,String json){
        if(Looper.myLooper()!=Looper.getMainLooper()||device.isEmpty()||!device.equals(NativeTransfer.connected()))return false;
        if(type==5&&textPending)return false;
        try{NavGlasses.submit(device,type,json,ok->{if(type==5)textPending=false;record("sdk",type,ok?" ok":" refused");
                if(!ok){if(type==3)trial.stopRefused();else trial.stop("SDK拒绝提交",now());}notifyUI();});}
        catch(Exception e){return false;}
        if(type==5){textPending=true;textDeadline=now()+8;}if(type==3)textPending=false;record("submit",type,"");return true;
    }
    private static final Runnable tick=new Runnable(){public void run(){
        try{double now=now();
            if(trial.active()&&!device.equals(NativeTransfer.connected()))trial.stop("官方字幕会话或设备变化，停止本次实验",now);
            if(textPending&&now>=textDeadline){textPending=false;trial.stop("SDK文字提交8秒无完成回调",now);}
            trial.tick(now);
        }catch(RuntimeException ignored){}
        notifyUI();if(trial.active())MAIN.postDelayed(this,1000);
    }};
    /** Observe-only: incoming AI_SUBTITLE messages from our device after official delivery. Audio bodies are never kept. */
    static void event(String kind,Map<?,?> data){
        if(!"messageReceived".equals(kind)||data==null||!trial.active())return;
        Object raw=data.get("message");if(!(raw instanceof Map))return;Map<?,?> msg=(Map<?,?>)raw;
        if(HostBusiness.id(msg.get("businessId"))!=19)return;String d=String.valueOf(msg.get("deviceId"));
        Object bytes=msg.get("payload");if(!(bytes instanceof byte[])||((byte[])bytes).length>262144)return;
        NavCore.Envelope e=NavCore.decode((byte[])bytes);if(e==null)return;
        Map<String,Object> json;
        if(e.type==4)json=new HashMap<>();
        else{try{json=BoundedJson.map(BoundedJson.read(e.json.getBytes(StandardCharsets.UTF_8)));}catch(RuntimeException x){return;}}
        int type=e.type;Map<String,Object> j=json;
        MAIN.post(()->{if(!device.equals(d)||!trial.active())return;record("receive",type,type==4?"":(trial.sid().equals(j.get("sid"))?" own-sid":" other-sid"));trial.receive(type,j,now());notifyUI();});
    }
}
