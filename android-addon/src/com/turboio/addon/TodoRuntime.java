package com.turboio.addon;
import android.content.*;
import android.os.*;
import java.lang.reflect.Method;
import java.util.*;
import java.util.function.Consumer;

/** Official todo path (port of iOS TodoRuntime): observes the official full list (biz 22 type 6, outgoing) and
 * physical completion events (type 4), captures a real official create_task NLP result, and creates one item only by
 * replaying an official NLP result into the official listener. Success is only "exactly one new matching row"; no
 * retry; an unknown tool result blocks every later tool write, across restarts. Main thread except queue()/event(). */
final class TodoRuntime {
    private static final Handler MAIN=new Handler(Looper.getMainLooper());
    private static final String UNRESOLVED="todo_unresolved_submission";
    private static Context app;
    private static TodoProtocol.Snapshot snapshot,baseline;private static String device="",testTitle,testWire,testDevice;
    private static String state="尚未观察到官方待办列表";private static long snapshotAt,templateAt,chatAt;
    private static Object template,listener,chatContext,chatListener;private static boolean busy,injecting,toolOperation;private static Boolean physicalComplete;
    private static int snapshots,taskEvents,physicalEvents;private static Consumer<String> toolCompletion;private static long round;
    static Runnable changed;
    private TodoRuntime(){}
    static void init(Context c){app=c.getApplicationContext();}
    private static SharedPreferences prefs(){return app.getSharedPreferences("turboio_todo",0);}
    private static void publish(String s){state=s;Runnable r=changed;if(r!=null)try{r.run();}catch(RuntimeException ignored){}}
    static boolean busy(){return busy;}
    static String state(){return state;}
    static String counts(){return "列表"+snapshots+"次 · 新增回调"+taskEvents+"次 · 实体回传"+physicalEvents+"次\n"+(testTitle==null?"":testTitle)+"\n真实ID："+(testWire!=null?"已匹配":"未匹配")+"；完成："+(Boolean.TRUE.equals(physicalComplete)?"是":"否");}
    private static long now(){return SystemClock.elapsedRealtime();}

    /** Queue tap (host thread): an official SCHEDULE_TODO send. Never blocks. */
    static void queue(String dev,byte[] payload){byte[] copy=payload.clone();MAIN.post(()->observeSnapshot(dev,copy));}
    private static void observeSnapshot(String dev,byte[] payload){
        if(dev==null||dev.isEmpty()||dev.length()>200)return;TodoProtocol.Snapshot s=TodoProtocol.snapshot(payload);if(s==null)return;snapshots++;
        if(!s.full()){snapshot=null;publish("收到分批列表，未将其当作全量基线");return;}
        if(busy){
            if(!dev.equals(testDevice)){busy=false;finishTool("unknown");publish("设备发生变化；测试停止，未绑定");}
            else{TodoProtocol.Item c=TodoProtocol.newCandidate(baseline,s,testTitle);
                if(c!=null){testWire=c.wireId;busy=false;publish("官方列表出现唯一新项，已关联真实ID；仍需镜片验收");if(toolOperation){prefs().edit().remove(UNRESOLVED).commit();finishTool("created");}}}
        }
        snapshot=s;device=dev;snapshotAt=now();
        if(!busy&&testWire==null)publish(template!=null?"已取得官方列表与新增模板；可测试创建入口":"已取得官方全量列表基线；等待官方语音新增模板");
    }
    /** After official delivery (host thread): physical completion for our test item. */
    static void event(String kind,Map<?,?> data){
        TodoProtocol.Physical p=TodoProtocol.physical(kind,data);if(p==null)return;
        MAIN.post(()->{physicalEvents++;if(testWire!=null&&testWire.equals(p.wireId)&&p.deviceId.equals(testDevice)){physicalComplete=p.status==1;publish(p.status==1?"收到此测试项的眼镜完成回传，真实ID匹配":"收到此测试项的眼镜未完成回传");}else publish(state);});
    }
    private static Object get(Object o,String name)throws Exception{Method m=o.getClass().getMethod("get"+name);return m.invoke(o);}
    private static String str(Object o){return o instanceof String?(String)o:"";}
    /** Official NLP results (main, before our chat policy). Captures a real create_task template. */
    static void observeNlp(Object source,Object response){
        try{
            if(injecting||app==null||response==null)return;
            if(!"task".equals(get(response,"Domain"))||!"create_task".equals(get(response,"Intent"))||!Boolean.TRUE.equals(get(response,"Finished"))||Boolean.TRUE.equals(get(response,"Offline")))return;
            taskEvents++;Object cmd=get(response,"Command");
            if(cmd==null||!"create_task".equals(get(cmd,"Name"))||TodoProtocol.createIntent("task","create_task",get(cmd,"Params"))==null){publish("已收到官方新增回调，但参数形状不匹配；禁止构造调用");return;}
            template=response;listener=source;templateAt=now();publish("已取得真实官方新增模板；可执行一次命名测试");
        }catch(Exception e){}
    }
    /** The current voice chat context (the official NLP result our model reply is answering). */
    static void setChatContext(Object source,Object response){chatListener=source;chatContext=response;chatAt=now();}
    private static final String[] FIELDS={"Sub","DialogId","SessionId","Domain","Intent","Round","Query","Spoken","Answer","Finished","Offline","HasNextRound","RawData"};
    private static Object copyResult(Object from)throws Exception{
        Class<?> c=from.getClass();Object to=c.getConstructor().newInstance();
        for(String f:FIELDS){Method g=c.getMethod("get"+f);c.getMethod("set"+f,g.getReturnType()).invoke(to,g.invoke(from));}return to;
    }
    private static void set(Object o,String name,Class<?> type,Object v)throws Exception{o.getClass().getMethod("set"+name,type).invoke(o,v);}
    private static Object command(Object result,Map<String,String> params,Map<?,?> otherState)throws Exception{
        Class<?> cc=result.getClass().getMethod("getCommand").getReturnType();Object cmd=cc.getConstructor().newInstance();
        set(cmd,"Name",String.class,"create_task");set(cmd,"Params",Map.class,params);set(cmd,"CommandRequestId",String.class,UUID.randomUUID().toString());set(cmd,"OtherState",Map.class,otherState==null?new HashMap<>():otherState);return cmd;
    }
    private static String taskJson(String title){Map<String,Object> t=new LinkedHashMap<>();t.put("content",title);return new String(BoundedJson.canonical(t),java.nio.charset.StandardCharsets.UTF_8);}
    /** The page test: one named item through the captured official template. Returns the user-facing message. */
    static String createTestTask(){
        if(app==null||Looper.myLooper()!=Looper.getMainLooper())return "待办观察入口未就绪。";
        if(busy||testTitle!=null)return "本进程已提交过一次测试；不会自动重试或重复创建。";
        long now=now();if(snapshot==null||now-snapshotAt>120000||template==null||listener==null||now-templateAt>120000)return "请先用眼镜语音新增一条专用测试待办，再在两分钟内回此页测试。";
        String title="Turbo桥接入口测试 "+UUID.randomUUID().toString().substring(0,6);Object response;
        try{
            Object cmd=get(template,"Command");Object p=get(cmd,"Params");if(!(p instanceof Map)||TodoProtocol.createIntent("task","create_task",p)==null)return "参数形状不匹配，未调用。";
            Map<String,String> params=new LinkedHashMap<>();for(Map.Entry<?,?> e:((Map<?,?>)p).entrySet())if(e.getKey() instanceof String&&e.getValue() instanceof String)params.put((String)e.getKey(),(String)e.getValue());
            Object task=((Map<?,?>)p).get("task");if(!(task instanceof String))return "参数形状不匹配，未调用。";
            Map<String,Object> t=new LinkedHashMap<>(BoundedJson.map(BoundedJson.readDevice(((String)task).getBytes(java.nio.charset.StandardCharsets.UTF_8))));t.put("content",title);
            params.put("task",new String(BoundedJson.canonical(t),java.nio.charset.StandardCharsets.UTF_8));
            Object other=get(cmd,"OtherState");response=copyResult(template);set(response,"Command",response.getClass().getMethod("getCommand").getReturnType(),command(response,params,other instanceof Map?(Map<?,?>)other:null));
            set(response,"Query",String.class,"创建待办 "+title);set(response,"Answer",String.class,"");set(response,"Spoken",String.class,"");
        }catch(NoSuchMethodException e){return "官方包装类型不匹配。";}catch(Exception e){return "无法构造官方包装，未调用。";}
        baseline=snapshot;testDevice=device;testTitle=title;testWire=null;physicalComplete=null;toolOperation=false;busy=true;long mine=++round;publish("仅提交一次官方创建回调；等待官方真实列表和ID，未声明成功");
        injecting=true;try{TurboAddon.deliverNlp(listener,response);}catch(Exception e){busy=false;publish("官方回调调用异常；结果未知，禁止重试");}finally{injecting=false;}
        MAIN.postDelayed(()->{if(mine==round&&busy){busy=false;publish("25秒内未观察到唯一新项；结果未知，不自动重发");}},25000);
        return "已提交："+title;
    }
    private static void finishTool(String status){if(!toolOperation)return;Consumer<String> c=toolCompletion;toolCompletion=null;toolOperation=false;if(c!=null)c.accept(status);}
    /** create_todo: created | not_ready | rejected | unknown, delivered once on main. */
    static void createFromTool(String title,Consumer<String> completion){
        if(TodoProtocol.createIntent("task","create_task",Collections.singletonMap("task",Collections.singletonMap("content",title)))==null||busy||app==null||prefs().getBoolean(UNRESOLVED,false)||(testTitle!=null&&testWire==null)){completion.accept("rejected");return;}
        long now=now();
        if(snapshot==null||now-snapshotAt>120000||chatContext==null||chatListener==null||now-chatAt>120000){completion.accept("not_ready");return;}
        String clean=TodoProtocol.trim(title);for(TodoProtocol.Item i:snapshot.items)if(i.title.equals(clean)){completion.accept("rejected");return;}
        Object response;
        try{response=copyResult(chatContext);
            Map<String,String> params=new LinkedHashMap<>();params.put("task",taskJson(clean));
            set(response,"Domain",String.class,"task");set(response,"Intent",String.class,"create_task");set(response,"Sub",String.class,"workflow");
            set(response,"HasNextRound",boolean.class,true);set(response,"Finished",boolean.class,true);set(response,"Offline",boolean.class,false);
            set(response,"Answer",String.class,"");set(response,"Spoken",String.class,"");set(response,"RawData",String.class,"");
            set(response,"Command",response.getClass().getMethod("getCommand").getReturnType(),command(response,params,null));
        }catch(Exception e){completion.accept("not_ready");return;}
        if(!prefs().edit().putBoolean(UNRESOLVED,true).commit()){completion.accept("rejected");return;}
        baseline=snapshot;testDevice=device;testTitle=clean;testWire=null;physicalComplete=null;toolOperation=true;toolCompletion=completion;busy=true;long mine=++round;
        publish("create_todo已调用官方入口；等待真实列表，不宣称创建成功");
        injecting=true;try{TurboAddon.deliverNlp(chatListener,response);}catch(Exception e){busy=false;publish("create_todo调用异常，结果未知；禁止重试");finishTool("unknown");}finally{injecting=false;}
        MAIN.postDelayed(()->{if(mine==round&&busy&&toolOperation){busy=false;publish("create_todo未确认唯一新ID，结果未知；禁止重试");finishTool("unknown");}},25000);
    }
}
