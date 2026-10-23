package com.turboio.addon;
import android.content.*;
import android.os.*;
import java.io.*;
import java.net.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.function.*;

/** Android glue for the Didi sandbox (iOS RideBridge/RideTransport/RideRPC): TDR1 cards over the shared NativeTransfer
 * carrier (turbo-ride.tdr, DRA1 replies in turbo_ride_v1 envelopes), the sandbox HTTP call, the service singleton and
 * its 1 s tick. Main thread except the HTTP executor. The sandbox key never appears in any message. */
final class Ride {
    static final String FILE="turbo-ride.tdr",REPLY="turbo_ride_v1",KEY="didi_sandbox_key";
    private static final Handler MAIN=new Handler(Looper.getMainLooper());
    private static final ExecutorService NET=Executors.newSingleThreadExecutor();
    private static Context app;private static SharedPreferences prefs;private static DrService service;private static Runnable changed;
    // Bridge state: one packet in flight, pinned peer, 15 s deadline.
    private static String peer;private static long sid,seq,inflightSeq,inflightNonce;private static boolean inflight;private static int lastResult=DrWire.BAD;private static String bridgeNote;private static double deadline;
    private static Consumer<Boolean> pendingDone;
    private Ride(){}
    static synchronized DrService service(Context c){
        if(service!=null)return service;app=c.getApplicationContext();prefs=app.getSharedPreferences("turboio_ride",0);NativeTransfer.receive(Ride::message);
        service=new DrService(Ride::rpc,new DrService.Bridge(){
            public boolean busy(){return inflight;}public void send(DrWire.Scene s,Consumer<Boolean> done){sendOp(DrWire.SNAPSHOT,s,done);}
            public int lastResult(){return lastResult;}public String note(){return bridgeNote==null?"需要 TDR1 固件 · 只连接沙箱":bridgeNote;}
        },new DrService.Env(){
            public String peer(){return NativeTransfer.connected();}public String key(){return key();}public double now(){return SystemClock.elapsedRealtime()/1000.0;}
            public String order(){return prefs.getString("order",null);}public void order(String id){if(id==null)prefs.edit().remove("order").commit();else prefs.edit().putString("order",id).commit();}
            public boolean unknown(){return prefs.getBoolean("unknown",false);}public void unknown(boolean v){prefs.edit().putBoolean("unknown",v).commit();}
        });
        MAIN.postDelayed(tick,1000);return service;
    }
    static void listen(Runnable r){changed=r;}
    private static void notifyUI(){Runnable r=changed;if(r!=null)try{r.run();}catch(RuntimeException ignored){}}
    static String key(){try{return SecretStore.get(app,KEY);}catch(Exception e){return "";}}
    static boolean ready(Context c){try{return DrRpc.validKey(SecretStore.get(c.getApplicationContext(),KEY));}catch(Exception e){return false;}}
    static boolean saveKey(Context c,String key){if(!DrRpc.validKey(key))return false;try{SecretStore.put(c.getApplicationContext(),KEY,key);return true;}catch(Exception e){return false;}}
    private static final Runnable tick=new Runnable(){public void run(){try{pump();service.tick();notifyUI();}catch(RuntimeException ignored){}MAIN.postDelayed(this,1000);}};
    private static void pump(){
        String current=NativeTransfer.connected();
        if(peer!=null&&!peer.equals(current)){bridgeNote="眼镜连接变化，请重新确认";peer=null;DrWire.Reply closed=new DrWire.Reply();closed.event=DrWire.CLOSED;service.glassesEvent(closed);if(inflight)finish(false);return;}
        if(inflight&&SystemClock.elapsedRealtime()/1000.0>=deadline){bridgeNote="眼镜回执超时，未自动重复提交";finish(false);}
    }
    private static void finish(boolean ok){inflight=false;Consumer<Boolean> d=pendingDone;pendingDone=null;bridgeNote=ok?"眼镜已接收；沙箱确认仅执行一次":(bridgeNote!=null?bridgeNote:"眼镜未确认");if(d!=null)d.accept(ok);notifyUI();}
    static void close(){if(service!=null&&!inflight)sendOp(DrWire.CLOSE,null,ok->{});}
    private static void sendOp(int op,DrWire.Scene scene,Consumer<Boolean> done){
        String current=NativeTransfer.connected();
        if(inflight||current==null||current.isEmpty()||OtaController.busy()||OfficialOtaBridge.busy()){bridgeNote="连接未就绪、传输忙碌或升级保护中";done.accept(false);return;}
        if(sid==0){long v=Math.max(System.currentTimeMillis()/1000,prefs.getLong("sid",0)+1);if(v>=0xffffffffL){done.accept(false);return;}sid=v;prefs.edit().putLong("sid",v).commit();}
        if(seq>=0xffffffffL){done.accept(false);return;}
        byte[] packet=DrWire.encode(op,sid,seq+1,scene);if(packet==null){bridgeNote="滴滴显示参数无效";done.accept(false);return;}
        seq++;peer=current;inflight=true;inflightSeq=seq;inflightNonce=scene==null?0:scene.nonce;lastResult=DrWire.BAD;pendingDone=done;deadline=SystemClock.elapsedRealtime()/1000.0+15;bridgeNote="正在发送滴滴卡片（392 字节）…";
        boolean sent=NativeTransfer.send(FILE,packet,seq,sid,15000,(state,result)->{if(!inflight||pendingDone!=done)return;
            if(state==TransferGate.State.CONFIRMED&&lastResult==DrWire.OK)finish(true);
            else{if(state==TransferGate.State.REJECTED)bridgeNote="眼镜拒绝滴滴卡片（"+lastResult+"），请回首页后重发";else if(state==TransferGate.State.FAILED)bridgeNote="滴滴卡片传输失败";finish(false);}});
        if(!sent){inflight=false;pendingDone=null;bridgeNote="滴滴卡片提交失败";done.accept(false);}
    }
    private static void message(String from,byte[] data){
        byte[] raw=CustomEnvelope.decode(data,REPLY,32);DrWire.Reply q=DrWire.reply(raw);if(q==null||service==null)return;
        String current=NativeTransfer.connected();if(from==null||!from.equals(current))return;
        if(q.event==DrWire.OPENED){service.glassesEvent(q);notifyUI();return;}
        if(!from.equals(peer)||q.sid!=sid||q.seq!=seq)return;
        if(q.event==DrWire.ACK&&inflight&&q.seq==inflightSeq){lastResult=q.result;NativeTransfer.ack(from,q.seq,q.sid,q.result);}
        else if(q.event==DrWire.CLOSED){service.glassesEvent(q);}
        else if(q.event==DrWire.CONFIRMED&&q.result==DrWire.OK&&q.nonce==inflightNonce&&inflightNonce!=0&&q.consumed){service.glassesEvent(q);}
        notifyUI();
    }
    /** Sandbox MCP call: key only in the URL query, no redirects, 200 only, ≤1 MiB, fixed error texts; result on main. */
    private static void rpc(String tool,Map<String,Object> args,BiConsumer<Map<String,Object>,String> done){
        if(!DrRpc.allowed(tool)){done.accept(null,"不支持的沙箱工具");return;}String k=key();if(!DrRpc.validKey(k)){done.accept(null,"请先填写滴滴沙箱 Key");return;}
        String id=UUID.randomUUID().toString();byte[] body=DrRpc.body(id,tool,args);
        NET.execute(()->{DrRpc.Result r;HttpURLConnection h=null;
            try{h=(HttpURLConnection)new URL(DrRpc.ENDPOINT+"?key="+URLEncoder.encode(k,"UTF-8")).openConnection();h.setInstanceFollowRedirects(false);h.setUseCaches(false);h.setConnectTimeout(15000);h.setReadTimeout(25000);h.setRequestMethod("POST");h.setDoOutput(true);
                h.setRequestProperty("Content-Type","application/json");h.setRequestProperty("Accept","application/json, text/event-stream");try(OutputStream o=h.getOutputStream()){o.write(body);}
                int code=h.getResponseCode();
                if(code>=300&&code<400)r=new DrRpc.Result(null,"已拒绝重定向，未转发 Key");
                else if(code!=200||h.getContentLengthLong()>DrRpc.MAX_BYTES)r=new DrRpc.Result(null,"沙箱 HTTP 响应异常，未重试");
                else{byte[] data;try(InputStream in=h.getInputStream()){data=BoundedHTTP.read(in,DrRpc.MAX_BYTES);}catch(IOException e){data=null;}r=data==null?new DrRpc.Result(null,"沙箱响应过大"):DrRpc.parse(data,id);}
            }catch(Throwable e){r=new DrRpc.Result(null,"沙箱网络失败（-1）；未自动重试");}
            finally{if(h!=null)try{h.disconnect();}catch(Throwable ignored){}}
            DrRpc.Result res=r;MAIN.post(()->done.accept(res.result,res.error));});
    }
    /** didi_ride model tool, called from the chat thread: runs on main, waits ≤35 s. */
    static Map<String,Object> callTool(Context c,String rawArguments){
        Map<String,Object> args=DrTool.arguments(rawArguments);if(args==null){Map<String,Object> r=new LinkedHashMap<>();r.put("status","invalid");r.put("sandbox",true);r.put("message","参数无效");return r;}
        CountDownLatch latch=new CountDownLatch(1);AtomicHolder out=new AtomicHolder();
        MAIN.post(()->{try{service(c).tool(args,r->{out.value=r;latch.countDown();});}catch(RuntimeException e){latch.countDown();}});
        try{if(!latch.await(35,TimeUnit.SECONDS))return busy("滴滴沙箱响应超时；未自动重试");}catch(InterruptedException e){Thread.currentThread().interrupt();return busy("已中断");}
        return out.value!=null?out.value:busy("滴滴沙箱暂不可用");
    }
    private static final class AtomicHolder{volatile Map<String,Object> value;}
    private static Map<String,Object> busy(String note){Map<String,Object> r=new LinkedHashMap<>();r.put("status","unavailable");r.put("sandbox",true);r.put("real_order",false);r.put("message",note);return r;}
}
