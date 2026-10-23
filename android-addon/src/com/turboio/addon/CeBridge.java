package com.turboio.addon;
import android.content.*;
import android.os.*;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.*;

/** Android glue for context English (iOS ContextEnglishBridge/Transport/Client/AutoRuntime): TEL1 over the shared
 * NativeTransfer file carrier (turbo-english.tel; TEA1/TEP1 custom-envelope replies), the explicit model request,
 * the official cache reader, local history, and the opt-in automation tick (every 15 s while the host process runs).
 * Main thread only, except the bounded reader / network executors. Never logs cards, excerpts or keys. */
final class CeBridge {
    static final String FILE="turbo-english.tel",ACK="turbo_english_v1",PROGRESS="turbo_english_progress_v1";
    private static final Handler MAIN=NativeTransfer.MAIN;
    private static final ExecutorService IO=Executors.newSingleThreadExecutor(),NET=Executors.newSingleThreadExecutor();
    private static Context app;private static SharedPreferences prefs;private static CeSession session;private static CeHistory history;private static CeAuto auto;
    private static String note="尚未发送";private static BiConsumer<String,Boolean> listener,pending;

    static synchronized void init(Context c){
        if(app!=null)return;app=c.getApplicationContext();prefs=app.getSharedPreferences("turboio_english",0);File root=new File(app.getFilesDir(),"turboio/english");
        history=new CeHistory(new File(root,"reviews.json"));
        session=new CeSession(new CeSession.Carrier(){
            public String peer(){return NativeTransfer.connected();}
            public boolean otaProtected(){return OtaController.busy()||OfficialOtaBridge.busy();}
            public boolean send(byte[] packet,long request,long sid){return NativeTransfer.send(FILE,packet,request,sid,12000,(state,result)->{session.completed(state,SystemClock.elapsedRealtime());pump();});}
            public void ack(String peer,long request,long sid,int result){NativeTransfer.ack(peer,request,sid,result);}
            public void note(String text,boolean terminal){note=text;BiConsumer<String,Boolean> l=listener,p=pending;if(terminal)pending=null;if(l!=null)l.accept(text,terminal);if(p!=null&&p!=l)p.accept(text,terminal);}
        },new CeSession.Store(){
            public long querySequence(){return prefs.getLong("query_sequence",0);}public void querySequence(long v){prefs.edit().putLong("query_sequence",v).commit();}
            public long lastTx(){return prefs.getLong("last_tx",0);}public void lastTx(long v){prefs.edit().putLong("last_tx",v).commit();}
        },history);
        NativeTransfer.receive(CeBridge::message);
        auto=new CeAuto(new File(root,"auto-plan.json"));auto.context=CeBridge::context;
        auto.read=done->readArchive((rows,error)->done.accept(rows,error));
        auto.generate=CeBridge::generate;
        auto.send=(cards,s,done)->{if(!Boolean.TRUE.equals(context().get("canSend"))){done.accept(false);return;}
            send(cards,(String)s.get("target"),((Number)s.get("count")).intValue(),((Number)s.get("minute")).intValue(),true,false,(text,terminal)->{if(terminal)done.accept(session.lastDeliveryConfirmed()?Boolean.TRUE:session.lastNotSubmitted()?null:Boolean.FALSE);});};
        auto.reviews=(day,target,count)->history.reviews(NativeTransfer.connected(),target,LocalDate.now().toEpochDay(),count);
        MAIN.postDelayed(autoTick,15000);
    }
    private static final Runnable autoTick=new Runnable(){public void run(){try{auto.tick();}catch(RuntimeException ignored){}MAIN.postDelayed(this,15000);}};
    private static final Runnable pumpTick=new Runnable(){public void run(){pump();if(session.active())MAIN.postDelayed(this,250);}};
    private static void pump(){session.pump(SystemClock.elapsedRealtime());}
    private static void message(String peer,byte[] data){
        byte[] ack=CustomEnvelope.decode(data,ACK,CeWire.ACK_BYTES);if(ack!=null){session.reply(peer,ack);return;}
        byte[] progress=CustomEnvelope.decode(data,PROGRESS,CeWire.PROGRESS_BYTES);if(progress!=null)session.progress(peer,progress);
    }
    static void listen(BiConsumer<String,Boolean> l){listener=l;}
    static String note(){return note;}
    static boolean sending(){return session!=null&&session.active();}
    static CeHistory history(){return history;}
    static CeAuto auto(){return auto;}
    /** Send validated cards (or the synthetic test set) to the connected glasses; progress gets every status line. */
    static void send(List<Map<String,Object>> cards,String target,int count,int minute,boolean reminder,boolean synthetic,BiConsumer<String,Boolean> progress){
        List<CeWire.Card> deck=new ArrayList<>();for(Map<String,Object> c:cards){CeWire.Card k=CeCore.card(c);if(k==null){progress.accept("候选超出眼镜显示预算或格式无效，未截断；请重新生成更短表达。",true);return;}deck.add(k);}
        if(session.active()){progress.accept("上一轮传输尚未释放；请等待完成或重新连接后查询。",true);return;}
        pending=progress;session.start(deck,target,count,minute,reminder,synthetic,SystemClock.elapsedRealtime(),System.currentTimeMillis()/1000,ZoneId.systemDefault());
        if(session.active()){MAIN.removeCallbacks(pumpTick);MAIN.postDelayed(pumpTick,250);}
    }
    static void cancelSend(){if(session!=null)session.cancel();}

    /** Host dirs where hive_ce may keep api_cache_user_<n>.hive (path_provider support dir and documents dir). */
    static List<File> dirs(){return Arrays.asList(app.getFilesDir(),new File(app.getApplicationInfo().dataDir,"app_flutter"));}
    static void readArchive(BiConsumer<List<CeLifelog.Row>,String> done){
        ZoneId zone=ZoneId.systemDefault();IO.execute(()->{List<CeLifelog.Row> rows;String error=null;
            try{rows=CeLifelog.read(dirs(),zone);}catch(IllegalArgumentException e){rows=null;error=e.getMessage();}catch(RuntimeException e){rows=null;error=CeHive.ERROR;}
            List<CeLifelog.Row> r=rows;String err=error;MAIN.post(()->done.accept(r,err));});
    }
    static final class Config{String endpoint="",model="",key="";boolean disableThinking;String error;}
    static Config config(){
        Config c=new Config();SharedPreferences p=app.getSharedPreferences("turboio_settings",0);
        try{c.key=SecretStore.get(app);}catch(Exception e){c.key="";}
        c.model=p.getString("model","deepseek-flash");c.disableThinking=ChatPolicy.thinkingDisabled(p.contains("disable_thinking")?p.getBoolean("disable_thinking",true):null);
        String raw=p.getString("endpoint","https://api.deepseek.com/chat/completions");
        if(c.key==null||c.key.isEmpty()){c.error="请先配置自定义模型。";return c;}
        if(!CeCore.keyValid(c.key)){c.key="";c.error="模型地址或凭据无效";return c;}
        try{c.endpoint=CeCore.endpoint(raw);}catch(IllegalArgumentException e){c.error=e.getMessage();}
        return c;
    }
    /** One explicit model request for an approved selection; done runs once on main. The returned Runnable cancels. */
    static Runnable generate(Map<String,Object> selection,BiConsumer<List<Map<String,Object>>,String> done){
        AtomicBoolean finished=new AtomicBoolean();BiConsumer<List<Map<String,Object>>,String> once=(cards,error)->{if(finished.compareAndSet(false,true))done.accept(cards,error);};
        Config c=config();byte[] body;
        try{if(c.error!=null)throw new IllegalArgumentException(c.error);body=CeCore.body(selection,c.model,c.disableThinking);}catch(IllegalArgumentException e){String why=e.getMessage();MAIN.post(()->once.accept(null,why));return ()->{};}
        Map<String,Object> frozen=selection;
        Future<?> job=NET.submit(()->{String error=null;List<Map<String,Object>> cards=null;HttpURLConnection h=null;byte[] reply=null;
            // Transport stage: every failure maps to a fixed text — platform messages may echo headers (the key).
            try{h=(HttpURLConnection)new URL(c.endpoint).openConnection();h.setInstanceFollowRedirects(false);h.setUseCaches(false);h.setConnectTimeout(15000);h.setReadTimeout(60000);h.setRequestMethod("POST");h.setDoOutput(true);
                h.setRequestProperty("Content-Type","application/json");h.setRequestProperty("Accept","application/json");h.setRequestProperty("Authorization","Bearer "+c.key);
                try(OutputStream o=h.getOutputStream()){o.write(body);}
                int code=h.getResponseCode();if(code!=200||h.getContentLengthLong()>65536)error="模型服务拒绝请求或返回内容过大；未保存候选";
                else try(InputStream in=h.getInputStream()){reply=BoundedHTTP.read(in,65536);}catch(IOException e){error=String.valueOf(e.getMessage()).equals("size limit")?"模型响应超过 64 KiB，已停止":"模型连接失败或超时；不会自动重复上传片段";}
            }catch(Throwable e){error="模型连接失败或超时；不会自动重复上传片段";}
            finally{if(h!=null)h.disconnect();}
            // Validation stage: only CeCore's own fixed per-field messages reach the page.
            if(error==null)try{Object json;try{json=BoundedJson.readDevice(reply);}catch(RuntimeException e){json=null;}cards=CeCore.validate(json,frozen);}catch(IllegalArgumentException e){error=e.getMessage();}catch(RuntimeException e){error="模型返回无效";}
            List<Map<String,Object>> r=cards;String err=error;MAIN.post(()->once.accept(r,err));});
        return ()->{job.cancel(true);MAIN.post(()->once.accept(null,"已取消生成，未发送到眼镜"));};
    }
    private static String sha256(String s){if(s==null||s.isEmpty())return "";try{byte[] h=MessageDigest.getInstance("SHA-256").digest(s.getBytes(StandardCharsets.UTF_8));StringBuilder b=new StringBuilder();for(byte x:h)b.append(String.format(Locale.ROOT,"%02x",x&255));return b.toString();}catch(Exception e){return "";}}
    /** CEAutoRuntime Context(): the consent binding plus readiness. */
    static Map<String,Object> context(){
        Config c=config();String peer=NativeTransfer.connected(),scope=CeLifelog.scope(dirs());
        boolean ready=c.error==null&&!c.model.isEmpty()&&!scope.isEmpty()&&peer!=null&&!peer.isEmpty();
        Map<String,Object> m=new HashMap<>();m.put("destination",c.endpoint);m.put("model",c.model);m.put("scope",scope);m.put("peer",sha256(peer));m.put("zone",ZoneId.systemDefault().getId());m.put("ready",ready);
        m.put("canSend",ready&&NativeTransfer.canSubmit(FILE)&&!session.active());return m;
    }
}
