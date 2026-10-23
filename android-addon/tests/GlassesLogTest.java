package com.turboio.addon;
import java.util.*;

/** A2UI frames, GlassesLogContract and GlassesLogGate (ports of iOS GlassesLogContractTests / GlassesLogGateTests). */
public final class GlassesLogTest {
    static int n;static void ok(boolean b,String why){n++;if(!b)throw new AssertionError("log "+n+" "+why);}
    static final String TASK="73920000-1234-4567-8123-000000008642",COMPACT=TASK.replace("-","");
    static Map<String,Object> m(Object...kv){Map<String,Object> r=new LinkedHashMap<>();for(int i=0;i<kv.length;i+=2)r.put((String)kv[i],kv[i+1]);return r;}
    static Map<String,Object> ack(String device,Object biz,Object status,String data,long seq){
        byte[] p=A2uiFrame.packet(17,seq,m("cmd","start_log_task_ack","payload",m("value",status,"mode",0L,"data",data)));
        return m("message",m("deviceId",device,"businessId",biz,"payload",p));}
    static Map<String,Object> file(String device,String role,String task,String name,String path){return m("device",m("id",device),"role",role,"taskId",task,"fileName",name,"filePath",path);}
    static Map<String,Object> good(String task){return file("test","receiver",task,"venus_123_log.tar.lz4","/data/user/0/x/files/cc_transfer/venus_123_log.tar.lz4");}
    public static void main(String[] a){
        // A2UI.
        byte[] req=A2uiFrame.packet(16,77,m("cmd","start_log_task","payload",m("data","","mode",0L,"value",0L)));A2uiFrame.Frame f=A2uiFrame.decode(req);
        ok(f!=null&&f.type==16&&f.sequence==77&&"start_log_task".equals(f.json.get("cmd")),"request round trip");
        ok(new String(Arrays.copyOfRange(req,6,6+(req[5]&255)),java.nio.charset.StandardCharsets.UTF_8).equals("{\"cmd\":\"start_log_task\",\"payload\":{\"data\":\"\",\"mode\":0,\"value\":0}}"),"sorted request JSON");
        ok(A2uiFrame.decode(new byte[]{8,1,16,16})==null&&A2uiFrame.decode(new byte[]{8,2,16,16,26,2,'{','}'})==null&&A2uiFrame.decode(new byte[]{8,1,16,16,26,2,'[',']'})==null,"needs version 1 and a JSON object");
        ok(A2uiFrame.decode(new byte[]{8,1,16,16,26,2,'{','}',34,1,0})==null&&A2uiFrame.decode(new byte[]{8,1,16,16,26,2,'{','}',56,1})==null,"field 4 must be empty; tag 7 refused");
        ok(A2uiFrame.decode(new byte[]{8,1,16,16,26,2,'{','}',8,1})==null,"duplicate field refused");
        // Task ids.
        ok(TASK.equals(GlassesLogContract.taskId(COMPACT.toUpperCase(Locale.ROOT)))&&GlassesLogContract.taskId("73920000-1234-4567-8123-00000000864z")==null&&GlassesLogContract.taskId("")==null&&GlassesLogContract.taskId(7)==null,"task id canonical");
        // ACK.
        GlassesLogContract.Ack k=GlassesLogContract.ack("messageReceived",ack("test","LOG_REPORT",0L,TASK,5),"test");ok(k!=null&&TASK.equals(k.taskId)&&k.status==0&&k.sequence==5,"ack");
        ok(TASK.equals(GlassesLogContract.ack("messageReceived",ack("test",11L,0L,COMPACT,5),"test").taskId),"compact ack, numeric business");
        ok(GlassesLogContract.ack("messageReceived",ack("other","LOG_REPORT",0L,TASK,5),"test")==null&&GlassesLogContract.ack("messageReceived",ack("test","LAUNCHER",0L,TASK,5),"test")==null,"device / business");
        ok(GlassesLogContract.ack("messageReceived",ack("test","LOG_REPORT",true,TASK,5),"test")==null&&GlassesLogContract.ack("messageReceived",ack("test","LOG_REPORT",0L,"wrong",5),"test")==null,"bool status / bad data");
        GlassesLogContract.Ack seven=GlassesLogContract.ack("messageReceived",ack("test","LOG_REPORT",7L,"",5),"test");ok(seven!=null&&seven.taskId.isEmpty()&&seven.status==7,"status kept raw");
        ok(GlassesLogContract.ack("fileShareSuccess",ack("test","LOG_REPORT",0L,TASK,5),"test")==null,"kind");
        // File events.
        ok(GlassesLogContract.file("fileShareSuccess",good(TASK),"test",TASK)!=null&&GlassesLogContract.file("fileShareSuccess",good(COMPACT),"test",TASK)!=null,"file");
        ok(GlassesLogContract.file("fileShareSuccess",file("other","receiver",TASK,"venus_123_log.tar.lz4","/x/venus_123_log.tar.lz4"),"test",TASK)==null,"other device");
        ok(GlassesLogContract.file("fileShareSuccess",good(UUID.randomUUID().toString()),"test",TASK)==null,"random task");
        ok(GlassesLogContract.file("fileShareSuccess",file("test","sender",TASK,"venus_123_log.tar.lz4","/x/venus_123_log.tar.lz4"),"test",TASK)==null,"sender role");
        ok(GlassesLogContract.file("fileShareSuccess",file("test","receiver",TASK,"voice.ogg","/x/voice.ogg"),"test",TASK)==null,"name");
        ok(GlassesLogContract.file("fileShareSuccess",file("test","receiver",TASK,"../venus_123_log.tar.lz4","/x/../venus_123_log.tar.lz4"),"test",TASK)==null,"traversal");
        ok(GlassesLogContract.file("fileShareSuccess",file("test","receiver",TASK,"venus_123_log.tar.lz4","https://x/venus_123_log.tar.lz4"),"test",TASK)==null,"not absolute");
        ok(GlassesLogContract.file("fileShareSuccess",file("test","receiver",TASK,"venus_123_log.tar.lz4","/x/other_name.tar.lz4"),"test",TASK)==null,"last component must match");
        ok(GlassesLogContract.file("fileShareSuccess",file("test","receiver",TASK,"venus_123_log.tar.lz4","/x/a/../venus_123_log.tar.lz4"),"test",TASK)==null,"dot-dot in path");
        // Window.
        ok(GlassesLogContract.windowValid(100,110,true,true)&&!GlassesLogContract.windowValid(100,280,true,true)&&!GlassesLogContract.windowValid(100,99,true,true)&&!GlassesLogContract.windowValid(Double.NaN,110,true,true)&&!GlassesLogContract.windowValid(100,110,false,true)&&!GlassesLogContract.windowValid(100,110,true,false),"window");
        // Gate 1.
        Map<String,Object> theAck=ack("test","LOG_REPORT",0L,TASK,5);
        GlassesLogGate g=new GlassesLogGate(null);ok(!g.accept("messageReceived",theAck).consume,"no device, no consume");
        ok(g.begin("test")&&!g.begin("test"),"begin once");ok(g.accept("messageReceived",theAck).consume,"ack consumed");
        GlassesLogGate.Decision d=g.accept("fileShareSuccess",good(TASK));ok(d.consume&&d.candidate!=null,"candidate");
        ok(!g.accept("fileShareSuccess",file("other","receiver",TASK,"venus_123_log.tar.lz4","/x/venus_123_log.tar.lz4")).consume,"other device passes through");
        ok(!g.accept("fileShareSuccess",good(UUID.randomUUID().toString())).consume,"random task passes through");
        d=g.accept("fileShareSuccess",file("test","receiver",TASK,"voice.ogg","/x/voice.ogg"));ok(d.consume&&d.candidate==null,"owned task, bad name: consumed, no copy");
        // Gate 2: restored.
        GlassesLogGate r=new GlassesLogGate(g.snapshot());ok(!r.begin("test")&&r.accept("fileShareSuccess",good(TASK)).consume,"restored gate consumes");
        // Gate 3: early file.
        GlassesLogGate e=new GlassesLogGate(null);e.begin("test");d=e.accept("fileShareSuccess",good(TASK));ok(d.consume&&d.awaitingAck,"early file awaits ack");
        ok(e.accept("messageReceived",ack("test","LOG_REPORT",0L,"",6)).consume,"empty ack consumed");d=e.accept("messageReceived",theAck);ok(d.consume&&d.candidate!=null,"ack releases early file");
        ok(!e.accept("messageReceived",m("message",m("deviceId","test","businessId","LAUNCHER","payload",new byte[]{1}))).consume,"unrelated passes");
        ok(!e.ownsRequest("test")&&Boolean.TRUE.equals(e.snapshot().get("settled")),"settled");
        ok(!e.accept("messageReceived",ack("test","LOG_REPORT",0L,UUID.randomUUID().toString(),7)).consume,"other uuid ack after settle passes");
        // Gate 4: compact.
        GlassesLogGate c=new GlassesLogGate(null);c.begin("test");c.accept("messageReceived",ack("test","LOG_REPORT",0L,COMPACT,5));ok(c.accept("fileShareSuccess",good(COMPACT)).candidate!=null,"compact both ways");
        // Gate 5: recovery.
        GlassesLogGate v=new GlassesLogGate(null);ok(!v.reconcile(TASK,"test"),"reconcile before begin");v.begin("test");
        ok(!v.reconcile(TASK,"other")&&!v.reconcile("bad","test")&&v.reconcile(COMPACT,"test")&&!v.ownsRequest("test")&&!v.reconcile(UUID.randomUUID().toString(),"test"),"reconcile rules");
        ok(!v.beginNext("other",s->true),"beginNext other device");Map<String,Object> before=v.snapshot();ok(!v.beginNext("test",s->false)&&v.snapshot().equals(before),"persist failure keeps state");
        List<Map<String,Object>> saved=new ArrayList<>();ok(v.beginNext("test",s->{saved.add(s);return true;})&&saved.get(0).equals(v.snapshot())&&v.ownsRequest("test")&&!v.beginNext("test",s->true),"beginNext");
        ok(v.accept("messageReceived",theAck).retired&&v.accept("fileShareSuccess",good(TASK)).retired,"old task retired");
        GlassesLogGate w=new GlassesLogGate(saved.get(0));ok(!w.reconcile(TASK,"test")&&w.accept("fileShareSuccess",good(TASK)).retired,"retired survives restart");
        String nt=UUID.randomUUID().toString();ok(w.accept("fileShareSuccess",good(nt)).awaitingAck,"new task early");ok(w.accept("messageReceived",ack("test","LOG_REPORT",0L,nt,1)).candidate!=null&&!w.ownsRequest("test"),"new round settles");
        GlassesLogGate b=new GlassesLogGate(null);b.begin("test");b.reconcile(TASK,"test");int rounds=0;for(int i=0;i<40;i++){if(!b.beginNext("test",s->true))break;rounds++;b.reconcile(UUID.randomUUID().toString(),"test");}ok(rounds==31,"32-round quarantine bound ("+rounds+")");
        // Review I1: an over-full quarantine on disk must never drop the current task on reload.
        { List<Object> q=new ArrayList<>();for(int i=0;i<33;i++)q.add(UUID.randomUUID().toString());String cur=(String)q.get(32);
          GlassesLogGate big=new GlassesLogGate(m("device","test","task",cur,"quarantined",q,"retired",new ArrayList<>(),"settled",false));
          ok(big.accept("fileShareSuccess",good(cur)).consume,"current task stays owned after reload"); }
        { GlassesLogGate cur=new GlassesLogGate(m("device","test","task",TASK,"quarantined",new ArrayList<>(),"retired",new ArrayList<>(),"settled",false));ok(cur.accept("fileShareSuccess",good(TASK)).consume,"current task is owned even if missing from the list"); }
        // Review M8: tolerant JSON for ACKs (a float field elsewhere must not hand the ACK to Flutter).
        { byte[] p=A2uiFrame.packet(17,5,m("cmd","start_log_task_ack","payload",m("value",0L,"mode",0L,"data",TASK)));String json=new String(Arrays.copyOfRange(p,6,6+(p[5]&255)),java.nio.charset.StandardCharsets.UTF_8).replace("}}",",\"extra\":1.5}}");
          byte[] j=json.getBytes(java.nio.charset.StandardCharsets.UTF_8);byte[] q=new byte[6+j.length];System.arraycopy(p,0,q,0,4);q[4]=26;q[5]=(byte)j.length;System.arraycopy(j,0,q,6,j.length);
          ok(A2uiFrame.decode(q)!=null,"float field tolerated"); }
        ok(new GlassesLogGate(m("device","")).snapshot().isEmpty()&&new GlassesLogGate(m("task",TASK)).snapshot().isEmpty(),"snapshot needs a device");
        System.out.println("GlassesLogTest: "+n+" checks; A2UI frames, task ids, ack/file contract, window, gate ownership/early/recovery/retire/bound");
    }
}
