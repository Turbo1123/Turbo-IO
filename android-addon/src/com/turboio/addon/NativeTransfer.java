package com.turboio.addon;

import android.content.Context;
import android.os.*;
import java.io.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;

/** One shared bounded file lane. Transport success AND matching application ACK required. */
public final class NativeTransfer {
    interface Receiver { void message(String peer,byte[] bytes); }
    interface Completion { void done(TransferGate.State state,int result); }
    static final Handler MAIN=new Handler(Looper.getMainLooper());
    private static final ExecutorService IO=Executors.newSingleThreadExecutor();
    private static final AtomicInteger QUEUED=new AtomicInteger();
    private static final List<Receiver> receivers=new ArrayList<>();
    private static final Set<Runnable> listeners=new HashSet<>();
    private static final Map<String,Long> external=new HashMap<>();
    private static Context context;private static TransferGate gate;private static Completion completion;
    private static String peer="",task="",filename="";private static File spool;private static boolean writing;
    private static final ArrayDeque<Map<String,Object>> early=new ArrayDeque<>();
    private static long received,acks,sentCount;private static int lastBusiness=-1,lastBytes;private static String status="等待连接",messageOwner="";private static long quarantine;
    static void init(Context c){context=c.getApplicationContext();}
    static void receive(Receiver r){if(!receivers.contains(r))receivers.add(r);}
    static void listen(Runnable r){listeners.add(r);}static void unlisten(Runnable r){listeners.remove(r);}
    static String status(){return status;}
    static String diagnostic(){return "连接："+(connected().isEmpty()?"未连接":"已连接")+" · 发包 "+sentCount+" · 应用回执 "+acks+" · Launcher收包 "+received+" · 最近业务 "+lastBusiness+" / "+lastBytes+" 字节\n"+status;}
    private static void trace(String text){android.util.Log.i("TurboIOTransfer",text);}
    private static void mark(String s){status=s;for(Runnable r:new ArrayList<>(listeners))try{r.run();}catch(RuntimeException ignored){}}
    static String connected(){try{Object list=NavReflect.call(NavReflect.type("E3.u"),"g");String found="";for(Object d:(List<?>)list)if(Boolean.TRUE.equals(NavReflect.call(d,"b"))){if(!found.isEmpty())return "";Object id=NavReflect.field(d,"a");if(!(id instanceof String))return "";found=(String)id;}return found;}catch(Exception e){return "";}}
    /** OTA evidence must distinguish an empty connected list from an SDK failure. */
    static String otaConnection(){try{Object list=NavReflect.call(NavReflect.type("E3.u"),"g");if(!(list instanceof List))return null;String found="";for(Object d:(List<?>)list){Object connected=NavReflect.call(d,"b");if(!(connected instanceof Boolean))return null;if(Boolean.TRUE.equals(connected)){if(!found.isEmpty())return null;Object id=NavReflect.field(d,"a");if(!(id instanceof String)||((String)id).isEmpty())return null;found=(String)id;}}return found;}catch(Exception e){return null;}}
    static boolean busy(){return OtaController.busy()||OfficialOtaBridge.busy()||!messageOwner.isEmpty()||writing||(gate!=null&&gate.busy());}
    static boolean fileBusy(){return writing||(gate!=null&&gate.busy());}
    static boolean acquireMessages(String owner){long now=SystemClock.elapsedRealtime();external.values().removeIf(deadline->deadline<now);if(owner==null||owner.isEmpty()||busy()||now<quarantine||!external.isEmpty()||NavGlasses.active()||NativeNavigation.active()||MusicBridge.active()||ReaderBridge.active()||connected().isEmpty())return false;messageOwner=owner;return true;}
    static void releaseMessages(String owner){if(messageOwner.equals(owner))messageOwner="";}
    static void sendMessage(String owner,String device,byte[] payload,Runnable failed)throws Exception{if(!messageOwner.equals(owner)||!device.equals(connected())||payload.length>8192)throw new IllegalStateException();Object manager=NavReflect.field(NavReflect.type("E3.u"),"h"),business=NavReflect.call(NavReflect.type("P3.h"),"valueOf","LAUNCHER"),priority=NavReflect.call(NavReflect.type("E3.b"),"valueOf","NORMAL");Object message=NavReflect.make("E3.Q",payload,UUID.randomUUID().toString(),device,business,null,priority,false,false,null,null);Object callback=NavReflect.proxy("kotlin.jvm.functions.Function2",(name,args)->{if(args.length>1&&args[1]!=null)MAIN.post(failed);});NavReflect.call(manager,"u",message,callback);}
    static boolean send(String name,byte[] bytes,long request,long session,Completion callback){
        return send(name,bytes,request,session,60000,callback);
    }
    static boolean send(String name,byte[] bytes,long request,long session,long timeout,Completion callback){
        return sendOwned("",name,bytes,request,session,timeout,callback);
    }
    static boolean sendOwned(String leaseOwner,String name,byte[] bytes,long request,long session,long timeout,Completion callback){
        if(Looper.myLooper()!=Looper.getMainLooper())throw new IllegalStateException("main thread required");
        boolean own=!leaseOwner.isEmpty()&&leaseOwner.equals(messageOwner);
        if(name==null||!(name.matches("turbo-[a-z-]+\\.[a-z]{3}")||own&&name.matches("[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}"))||timeout<1000||timeout>60000||callback==null)throw new IllegalArgumentException();
        long now=SystemClock.elapsedRealtime();external.values().removeIf(deadline->deadline<now);
        if(OtaController.busy()||OfficialOtaBridge.busy()||context==null||writing||(gate!=null&&gate.busy())||(!messageOwner.isEmpty()&&!own)||now<quarantine||!external.isEmpty()||NavGlasses.active()||(ReaderBridge.active()&&!name.equals("turbo-reader.twr"))||(NativeNavigation.active()&&!name.equals("turbo-navigation.tnv"))||(MusicBridge.active()&&!name.equals("turbo-music.tmu"))){mark("其他传输/显示会话尚未结束，请先退出；未发送");return false;}
        String current=connected();if(current.isEmpty()){mark("请先在官方 App 连接一副眼镜");return false;}
        if(bytes==null||bytes.length<1||bytes.length>(own?48000:20700)){mark("命令超出预算，未发送");return false;}
        sentCount++;trace("send file="+name+" bytes="+bytes.length+" request="+request+" session="+session);gate=new TransferGate();gate.begin(current,name,request,session,now,timeout);peer=current;task="";filename=name;completion=callback;early.clear();spool=null;writing=true;byte[] data=bytes.clone();mark("准备发送 · "+data.length+" 字节");
        TransferGate owner=gate;IO.execute(()->{File file=null;try{File root=new File(context.getFilesDir(),"turboio-spool");if(!root.isDirectory()&&!root.mkdirs())throw new IOException();File[] retained=root.listFiles();if(retained==null||retained.length>=32)throw new IOException("spool limit");File dir=new File(root,UUID.randomUUID().toString());if(!dir.mkdir())throw new IOException();file=new File(dir,name);try(FileOutputStream out=new FileOutputStream(file)){out.write(data);out.getFD().sync();}File ready=file;
                MAIN.post(()->{if(gate!=owner)return;writing=false;spool=ready;try{gate.tick(connected(),SystemClock.elapsedRealtime());if(!gate.busy()){settle();return;}Object manager=NavReflect.field(NavReflect.type("E3.u"),"h"),small=NavReflect.field(NavReflect.type("Q3.q"),"b");Object id=NavReflect.call(manager,"v",ready,peer,small,UUID.randomUUID().toString());task=id instanceof String?(String)id:"";gate.submitted(task);mark("正在发送 · 等待文件与眼镜回执");while(!early.isEmpty())fileEvent(early.removeFirst());settle();MAIN.postDelayed(tick,250);}catch(Exception e){gate.failed();settle();}});
            }catch(Exception e){File failed=file;MAIN.post(()->{if(gate!=owner)return;writing=false;spool=failed;gate.failed();settle();});}});return true;
    }
    static void ack(String d,long request,long session,int result){if(gate==null)return;acks++;trace("ack request="+request+" session="+session+" result="+result);gate.tick(connected(),SystemClock.elapsedRealtime());gate.acknowledgement(d,request,session,result);settle();}
    private static final Runnable tick=new Runnable(){public void run(){if(gate==null||!gate.busy())return;gate.tick(connected(),SystemClock.elapsedRealtime());settle();if(gate.busy())MAIN.postDelayed(this,250);}};
    private static void settle(){if(gate==null||gate.busy())return;TransferGate.State state=gate.state();Completion c=completion;if(c==null)return;trace("settle state="+state+" file="+filename+" evidence="+gate.evidence());completion=null;MAIN.removeCallbacks(tick);
        if(state==TransferGate.State.CONFIRMED)mark("传输完成，眼镜已确认执行");else if(state==TransferGate.State.REJECTED)mark("眼镜拒绝（"+gate.result()+"）；请重新查询状态");else{quarantine=SystemClock.elapsedRealtime()+60000;mark("执行结果未确认；保留文件，60秒内不重发，请重新查询");}
        if(gate.mayDeleteSpool()&&spool!=null){File own=spool;IO.execute(()->{if(own.delete())own.getParentFile().delete();});}c.done(state,gate.result());
    }
    /** Called after vendor event delivery. Takes only bounded metadata, not their mutable Map. */
    public static void event(String kind,Map<?,?> data){
        try{EntryProbe.event(kind,data);}catch(RuntimeException ignored){}
        try{NavGlasses.event(kind,data);}catch(RuntimeException ignored){}
        if(data==null||kind==null||QUEUED.get()>=128)return;
        try{if(kind.equals("messageReceived")){Object raw=data.get("message");if(!(raw instanceof Map))return;Map<?,?> m=(Map<?,?>)raw;int biz=HostBusiness.id(m.get("businessId"));lastBusiness=biz;Object payload=m.get("payload");lastBytes=payload instanceof byte[]?((byte[])payload).length:0;if(biz==20){String d=small(m.get("deviceId"),256);Object raw20=m.get("payload");if(!d.isEmpty()&&raw20 instanceof byte[]&&((byte[])raw20).length<=8192){byte[] b20=((byte[])raw20).clone();post(()->NewsTele.receive(d,b20));}return;}if(biz!=15)return;String d=small(m.get("deviceId"),256);Object rawBytes=m.get("payload");if(d.isEmpty()||!(rawBytes instanceof byte[])||((byte[])rawBytes).length>8192)return;byte[] b=((byte[])rawBytes).clone();received++;trace("rx business=15 bytes="+b.length+" "+LauncherMeta.describe(b));post(()->{for(Receiver r:new ArrayList<>(receivers)){try{r.message(d,b);}catch(RuntimeException ignored){}}});
            }else if(Arrays.asList("fileShareStart","fileShareProgress","fileShareSuccess","fileShareFailed").contains(kind)){Object device=data.get("device");if(!(device instanceof Map))return;String d=small(((Map<?,?>)device).get("id"),256),id=small(data.get("taskId"),256),role=small(data.get("role"),32);if(d.isEmpty()||id.isEmpty())return;Map<String,Object> e=new HashMap<>();e.put("kind",kind);e.put("peer",d);e.put("task",id);e.put("role",role);e.put("file",small(data.get("fileName"),128));Object progress=data.get("progress");if(progress instanceof Number)e.put("progress",((Number)progress).intValue());post(()->fileEvent(e));}
        }catch(RuntimeException ignored){}
    }
    private static void post(Runnable r){if(QUEUED.incrementAndGet()>128){QUEUED.decrementAndGet();return;}MAIN.post(()->{try{r.run();}finally{QUEUED.decrementAndGet();}});}
    private static String small(Object o,int max){return o instanceof String&&((String)o).length()<=max?(String)o:"";}
    private static void fileEvent(Map<String,Object> e){String kind=(String)e.get("kind"),d=(String)e.get("peer"),id=(String)e.get("task");boolean sender="sender".equals(e.get("role"));
        if(gate!=null&&gate.busy()&&task.isEmpty()&&peer.equals(d)&&sender){if(early.size()<8)early.add(e);else{gate.failed();settle();}return;}
        if(!sender)return;String identity=d+":"+id;
        if(!peer.equals(d)||!task.equals(id)){if(kind.equals("fileShareStart")||kind.equals("fileShareProgress")){if(external.size()<32)external.put(identity,SystemClock.elapsedRealtime()+120000);}else external.remove(identity);return;}
        if(gate==null||!gate.busy())return;gate.tick(connected(),SystemClock.elapsedRealtime());if(!gate.busy()){settle();return;}
        if(kind.equals("fileShareProgress")){Object p=e.get("progress");if(p instanceof Integer&&(int)p>=0&&(int)p<=100)mark("文件发送 "+p+"% · 等待眼镜回执");}
        else if(kind.equals("fileShareSuccess")){gate.fileResult(d,id,(String)e.get("file"),true,true);settle();}
        else if(kind.equals("fileShareFailed")){// Host failure event omits filename; exact peer+native task binds our file.
            gate.fileResult(d,id,filename,true,false);settle();}
    }
}
