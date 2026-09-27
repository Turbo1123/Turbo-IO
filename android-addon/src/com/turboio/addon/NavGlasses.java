package com.turboio.addon;

import android.os.*;
import java.util.*;
import org.json.JSONObject;

/** Pure-display business 19 bridge, owns only its fresh SID. Never starts ASR. */
public final class NavGlasses {
    private static final Handler MAIN=new Handler(Looper.getMainLooper());
    private static volatile String device="",sid="",phase="idle";
    private static String note="眼镜显示未开启",latest="",sent="";
    private static int textSubmitted,textCompleted;private static boolean navigationSession;private static long lifetime=240000,interval=3000;
    private static long deadline,started,lastSend;private static boolean pending;
    private static Runnable changed;
    public static void listen(Runnable r){changed=r;}
    private static void mark(String p,String n){phase=p;note=n;if(changed!=null)changed.run();}
    public static String status(){return note+" · "+phase+" · 文字提交 "+textSubmitted+" / SDK完成 "+textCompleted+" · "+(navigationSession?"路线":"测试");}
    public static String phase(){return phase;}
    public static boolean active(){return !phase.equals("idle");}
    private static Object manager()throws Exception{return NavReflect.field(NavReflect.type("E3.u"),"h");}
    private static String connected()throws Exception{
        List<?> list=(List<?>)NavReflect.call(NavReflect.type("E3.u"),"g");String found="";
        for(Object d:list)if(Boolean.TRUE.equals(NavReflect.call(d,"b"))){if(!found.isEmpty())throw new IllegalStateException("multiple");found=(String)NavReflect.field(d,"a");}return found;
    }
    public static String connection(){try{return connected().isEmpty()?"眼镜未连接":"已找到官方连接";}catch(Exception e){return "连接信息不可用";}}
    public static boolean start(String text){return start(text,false);} public static boolean startCaption(String text){boolean ok=start(text,false);if(ok){lifetime=3600000;interval=700;}return ok;}
    public static boolean start(String text,boolean navigation){
        if(NativeNavigation.active()||ReaderBridge.active()||MusicBridge.active()||NativeTransfer.busy()){mark(phase,"请先结束原生导航或其他传输");return false;}
        lifetime=240000;interval=3000;NavSessionPolicy.Action action=NavSessionPolicy.action(phase);
        if(action==NavSessionPolicy.Action.REUSE){
            try{if(!device.equals(connected())){stop();return false;}latest=NavCore.clip(text,384);navigationSession=navigation;mark("ready","复用本 App 已确认的显示会话，等待文字更新");return true;}
            catch(Exception e){stop();return false;}
        }
        if(action!=NavSessionPolicy.Action.START){mark(phase,"上一会话未结束，请在开始按钮处处理退出确认");return false;}
        try{device=connected();if(device.isEmpty())throw new IllegalStateException();sid=UUID.randomUUID().toString().replace("-","");latest=NavCore.clip(text,384);sent="";lastSend=0;pending=false;started=SystemClock.elapsedRealtime();deadline=started+10000;
            textSubmitted=0;textCompleted=0;navigationSession=navigation;
            JSONObject config=new JSONObject().put("font_size",2).put("content_width",100).put("max_lines",5).put("position","center").put("is_display",true).put("straight_view","original");
            mark("starting","正在开启纯显示通道，等待眼镜回执");
            send(7,new JSONObject().put("sid",sid).put("force",false).put("scope","temporary").put("config",config));MAIN.removeCallbacks(tick);MAIN.postDelayed(tick,1000);return true;
        }catch(Exception e){mark("uncertain","无法开启；请确认连接和镜片状态");return false;}
    }
    public static void offer(String text){latest=NavCore.clip(text,384);}
    public static void stop(){if(phase.equals("idle")||phase.equals("stopping")||phase.equals("uncertain"))return;
        try{mark("stopping","已请求关闭，待确认镜片退出");deadline=SystemClock.elapsedRealtime()+8000;pending=false;send(3,new JSONObject().put("sid",sid).put("reason_code",10).put("text",""));}
        catch(Exception e){mark("uncertain","退出未确认，请用眼镜按钮关闭");}
    }
    public static void confirmIdle(){if(phase.equals("starting")||phase.equals("ready"))return;MAIN.removeCallbacks(tick);sid="";device="";latest="";pending=false;mark("idle","已由用户确认镜片退出");}
    private static void send(int type,JSONObject json)throws Exception{
        if(!device.equals(connected()))throw new IllegalStateException("device_changed");
        Object business=NavReflect.call(NavReflect.type("P3.h"),"valueOf","AI_SUBTITLE"),priority=NavReflect.call(NavReflect.type("E3.b"),"valueOf","NORMAL");
        Object message=NavReflect.make("E3.Q",NavCore.packet(type,json.toString()),UUID.randomUUID().toString(),device,business,null,priority,false,false,null,null);
        String owner=sid;
        Object callback=NavReflect.proxy("kotlin.jvm.functions.Function2",(name,args)->MAIN.post(()->{
            if(!sid.equals(owner))return;if(type==5){pending=false;if(args.length>1&&args[1]==null){textCompleted++;mark(phase,"导航/测试文字已完成 SDK 发送，镜片效果以实际为准");}}
            if(args.length>1&&args[1]!=null){if(type==3)mark("uncertain","SDK拒绝退出，请用眼镜按钮关闭");else stop();}
        }));NavReflect.call(manager(),"u",message,callback);
    }
    private static final Runnable tick=new Runnable(){public void run(){
        long now=SystemClock.elapsedRealtime();
        try{
            if(phase.equals("starting")&&now>=deadline){stop();}
            else if(phase.equals("ready")){
                if(now-started>=lifetime){stop();}
                else if(pending&&now>=deadline){stop();}
                else if(!pending&&!latest.isEmpty()&&!latest.equals(sent)&&now-lastSend>=interval){
                    pending=true;deadline=now+8000;lastSend=now;sent=latest;
                    textSubmitted++;send(5,new JSONObject().put("sid",sid).put("mode",3).put("status",0).put("content",new JSONObject().put("source_transcript",latest)));
                }
            }else if(phase.equals("stopping")&&now>=deadline)mark("uncertain","退出已提交，请确认镜片已回首页");
        }catch(Exception e){stop();}
        if(phase.equals("starting")||phase.equals("ready")||phase.equals("stopping"))MAIN.postDelayed(this,1000);
    }};
    /** Called after official event delivery; never suppresses vendor processing. */
    public static void event(String kind,Map<?,?> data){
        if(!kind.equals("messageReceived")||!active())return;
        try{Object raw=data.get("message");if(!(raw instanceof Map))return;Map<?,?> m=(Map<?,?>)raw;
            String d=String.valueOf(m.get("deviceId"));if(!d.equals(device))return;
            if(HostBusiness.id(m.get("businessId"))!=19)return;
            Object bytes=m.get("payload");if(!(bytes instanceof byte[]))return;
            NavCore.Envelope e=NavCore.decode((byte[])bytes);if(e==null)return;
            // Audio bodies are not retained, parsed or uploaded.
            final JSONObject j=e.type==4?new JSONObject():new JSONObject(e.json);
            MAIN.post(()->{if(!device.equals(d))return;if(e.type==4){stop();return;}if(!sid.equals(j.optString("sid")))return;
                if(e.type==8&&phase.equals("starting")){Object code=j.opt("code");if(code instanceof Number&&(((Number)code).doubleValue()==1||((Number)code).doubleValue()==2))mark("ready","眼镜已确认显示配置 · 文字可见性待验收");else stop();}
                if(e.type==3)stop();
            });
        }catch(Exception ignored){}
    }
}
