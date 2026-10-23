package com.turboio.addon;
import android.os.SystemClock;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.*;
import java.util.concurrent.Executor;

/** TDG1 glasses runtime status (TVP2 diagnostics-v1): a 10-minute sampled session started by the
 * file turbo-diagnostics.tdg, samples back as turbo_diagnostics_v1 envelopes, report saved every 5 s.
 * Never starts, restarts or renews by itself; a stop always reaches the glasses once. Port of iOS
 * TDPhoneRun + TDPhoneStore. Reports never contain the device identity. */
final class DiagnosticsRun {
    static final long BUILD=0x01000001L,LEASE_MS=600000;
    static final String FILE="turbo-diagnostics.tdg",COMMAND="turbo_diagnostics_v1";
    private static final String[] LABELS={"LVGL 配置容量","LVGL 当前用量","LVGL 历史峰值","LVGL 空闲量","LVGL 最大空闲块","系统堆统计容量","系统堆用量","系统堆峰值","系统堆空闲量","系统最大空闲块","已接入统计的扩展分配","已接入统计的分配峰值","分配失败","接收包数","接收数据量","接收处理最大耗时","渲染提交数（非 FPS）","提交最大耗时","扩展错误计数"};
    private static final Map<String,String> REASONS=new HashMap<>();
    static{REASONS.put("user_stop","已手动结束");REASONS.put("lease_elapsed","10 分钟到期 · 本轮结束");REASONS.put("first_sample_timeout","10 秒未收到首条采样");
        REASONS.put("telemetry_silent","20 秒无新采样 · 原因未知，已结束");REASONS.put("submit_failed","采集请求提交失败");REASONS.put("transfer_failed","诊断文件传输失败");
        REASONS.put("probe_slow","眼镜因采样耗时超标停止");REASONS.put("peer_context_changed","眼镜已变化，已结束");REASONS.put("archive_unavailable","本机报告目录不可用或已满（100 份），未开始");}
    static String label(String name){for(int i=0;i<TdgCodec.NAMES.length;i++)if(TdgCodec.NAMES[i].equals(name))return LABELS[i];return name;}

    private final File root;private final Executor writer;
    private String peer="",reason,runId="";private volatile String saveStatus="尚未采集";private File reportDir;
    private boolean active,received,inFlight,stopOwed;private double stopOwedSince;private long session,lastSeq,lastTick,gaps,evicted,droppedEvents,revision;
    private double began,deadline,lastReceipt,lastSave;
    private final ArrayDeque<Map<String,Object>> samples=new ArrayDeque<>();private final ArrayDeque<Map<String,Object>> events=new ArrayDeque<>();

    DiagnosticsRun(File root,Executor writer){this.root=root;this.writer=writer;}
    private static double now(){return SystemClock.elapsedRealtime()/1000.0;}
    /** Seconds for the report: BoundedJson writes BigDecimal, not double. */
    private static java.math.BigDecimal sec(double v){return java.math.BigDecimal.valueOf(v).setScale(3,java.math.RoundingMode.HALF_UP);}
    private static java.math.BigDecimal wall(){return sec(System.currentTimeMillis()/1000.0);}
    boolean active(){return active;}int count(){return samples.size();}File reportDirectory(){return reportDir;}String saveStatus(){return saveStatus;}
    Map<String,Object> latest(){return samples.peekLast();}
    double remaining(){return active?Math.max(0,deadline-now()):0;}
    String status(){
        if(active)return !received?"等待眼镜首条采样":(now()-lastReceipt>5?"采样暂时中断 · 原因未知":"正在采集 · 可返回使用其他功能");
        String r=reason==null?"未开始":REASONS.getOrDefault(reason,"已结束");return stopNote.isEmpty()?r:r+"\n"+stopNote;
    }
    boolean start(){
        if(active)return false;String p=NativeTransfer.connected();if(p==null||p.isEmpty()||NativeTransfer.busy())return false;
        String[] entries;if(!(root.isDirectory()||root.mkdirs())||(entries=root.list())==null||entries.length>=100){reason="archive_unavailable";return false;} // bounded; old reports are never deleted
        if(stopOwed||inFlight)return false; // the previous run's STOP has not reached the glasses yet
        SecureRandom r=new SecureRandom();long s;do{s=r.nextInt()&0xffffffffL;}while(s==0);
        // Submit first: a refused tap must not consume one of the 100 report slots.
        if(!NativeTransfer.send(FILE,TdgCodec.command(TdgCodec.START,s,1,LEASE_MS),1,s,15000,(state,result)->settled(TdgCodec.START,state))){reason="submit_failed";return false;}
        // TDG1 has no command reply: like iOS, the START settles on the file result alone (a missing
        // first sample is reported as first_sample_timeout, not by holding or quarantining the lane).
        inFlight=true;NativeTransfer.ack(p,1,s,0);
        peer=p;session=s;lastSeq=lastTick=gaps=evicted=droppedEvents=revision=0;samples.clear();events.clear();reason=null;stopOwed=false;
        began=now();deadline=began+LEASE_MS/1000.0;lastSave=began;lastReceipt=0;received=false;active=true;lane();
        File next=new File(root,UUID.randomUUID().toString());if(next.mkdir()){reportDir=next;runId=next.getName();}else{reportDir=null;runId="";event("start_requested");stop("archive_unavailable");return false;}
        event("start_requested");checkpoint();return true;
    }
    private void settled(int op,TransferGate.State state){
        inFlight=false;
        if(op==TdgCodec.START){event(state==TransferGate.State.CONFIRMED?"file_finished":state==TransferGate.State.UNCERTAIN?"file_uncertain":"file_failed");if(state!=TransferGate.State.CONFIRMED)stop("transfer_failed");}
        trySendStop();lane();
    }
    /** An owed STOP is retried (e.g. after the lane's 60 s quarantine) until sent once; it is never dropped silently.
     * STOP has no reply from the glasses, so it is acknowledged here and settles on the file result alone. */
    private void trySendStop(){
        if(!stopOwed||inFlight)return;
        if(session==0){stopOwed=false;return;}
        if(!peer.equals(NativeTransfer.connected())){stopOwed=false;stopNote="眼镜已变化，结束指令未发送；原眼镜会在 10 分钟租期到后自动停止";return;}
        if(now()-stopOwedSince>=LEASE_MS/1000.0){stopOwed=false;stopNote="结束指令未能发送；眼镜会在 10 分钟租期到后自动停止";return;}
        if(NativeTransfer.send(FILE,TdgCodec.command(TdgCodec.STOP,session,2,0),2,session,10000,(state,result)->{inFlight=false;lane();})){inFlight=true;stopOwed=false;stopNote="";NativeTransfer.ack(peer,2,session,0);}
        else stopNote="结束指令等待传输通道空闲后发送";
    }
    private String stopNote="";
    /** Other message-lease owners (OTA, camera, cards, menu) stay out while sampling or a STOP is owed. */
    private void lane(){NativeTransfer.diagnosticsActive=active||stopOwed||inFlight;}
    void stop(String why){
        if(!active)return;reason=REASONS.containsKey(why)?why:"user_stop";event(reason);active=false;stopOwed=true;stopOwedSince=now();trySendStop();lane();checkpoint();
    }
    boolean busy(){return active||stopOwed||inFlight;}
    void poll(){
        if(stopOwed){trySendStop();lane();}
        if(!active)return;double t=now();
        if(!peer.equals(NativeTransfer.connected())){stop("peer_context_changed");return;}
        if(t>=deadline){stop("lease_elapsed");return;}
        if(!received&&t-began>=10){stop("first_sample_timeout");return;}
        if(received&&t-lastReceipt>=20){stop("telemetry_silent");return;}
        if(t-lastSave>=5)checkpoint();
    }
    /** NativeTransfer receiver: only this session's TDG1 samples from the same glasses. */
    void message(String device,byte[] bytes){
        byte[] raw=CustomEnvelope.decode(bytes,COMMAND,TdgCodec.SAMPLE_BYTES);if(raw==null)return;
        poll();if(!active||!peer.equals(device))return;
        TdgCodec.Sample s=TdgCodec.sample(raw);if(s==null||s.build!=BUILD||s.session!=session){event("reply_rejected");return;}
        if(lastSeq!=0){long ds=(s.sequence-lastSeq)&0xffffffffL,dt=(s.tickMs-lastTick)&0xffffffffL;if(ds==0||ds>=0x80000000L||dt>=0x80000000L){event("reply_rejected");return;}gaps+=ds-1;}
        Map<String,Object> metrics=new TreeMap<>();for(int i=0;i<TdgCodec.NAMES.length;i++)metrics.put(TdgCodec.NAMES[i],s.measured(i)?(Object)s.values[i]:null);
        Map<String,Object> row=new TreeMap<>();row.put("build",String.format(Locale.ROOT,"%08x",s.build));row.put("session",s.session);row.put("sequence",s.sequence);row.put("tick_ms",s.tickMs);
        row.put("phone_received_uptime_s",sec(now()));row.put("phone_received_wall_time_s",wall());row.put("probe_ms",s.probeMs);row.put("metrics",metrics);
        row.put("ring_events",s.eventCount);row.put("ring_overwritten",s.eventsLost);row.put("probe_stopped_for_latency",s.flags==1);
        if(samples.size()==600){samples.removeFirst();evicted++;}samples.addLast(row);lastSeq=s.sequence;lastTick=s.tickMs;lastReceipt=now();
        if(!received){received=true;event("first_sample");}
        if(s.flags==1)stop("probe_slow");else if(lastReceipt-lastSave>=5)checkpoint();
    }
    private void event(String code){
        if(!active&&!REASONS.containsKey(code))return;
        Map<String,Object> row=new TreeMap<>();row.put("event",code);row.put("phone_uptime_s",sec(now()));row.put("elapsed_s",sec(Math.max(0,now()-began)));row.put("wall_time_s",wall());
        if(events.size()==512){events.removeFirst();droppedEvents++;}events.addLast(row);
    }
    byte[] reportJSON(){
        Map<String,Object> r=new TreeMap<>();r.put("format","TurboIO-Diagnostics-1");r.put("samples",new ArrayList<>(samples));r.put("count",samples.size());r.put("sequence_gaps",gaps);r.put("evicted_samples",evicted);
        r.put("limitations",Arrays.asList("未测值为 null，不是 0","提交次数不等于面板 FPS","会话编号不是持久启动计数","此报告不包含完整崩溃转储，也不证明断电后日志可恢复"));
        r.put("phone_build","DIAGNOSTICS-ANDROID-01");r.put("run_id",runId);r.put("requested_seconds",LEASE_MS/1000);r.put("active",active);r.put("stop_reason",reason);r.put("revision",revision);
        r.put("updated_wall_time_s",wall());r.put("events",new ArrayList<>(events));r.put("events_dropped",droppedEvents);
        r.put("evidence_note","操作事件来自已校验的协议回执，不等于镜片视觉确认；采样静默不能确认为蓝牙断开。关闭/崩溃后最后存盘状态可能为 active，不能视为仍在运行。");
        return BoundedJson.canonical(r);
    }
    String reportMarkdown(){
        StringBuilder s=new StringBuilder("# Turbo IO 眼镜诊断\n\n保留采样：").append(samples.size()).append("；序号缺口：").append(gaps).append("；窗口淘汰：").append(evicted).append("。\n\n");
        Map<String,Object> last=latest();
        if(last==null)s.append("尚未收到眼镜采样，不能判断资源余量。\n");
        else{s.append("固件标识：").append(last.get("build")).append("；会话：").append(last.get("session")).append("；最新序号：").append(last.get("sequence")).append("。\n\n| 指标 | 数值 |\n| --- | ---: |\n");
            Map<?,?> m=(Map<?,?>)last.get("metrics");for(String name:TdgCodec.NAMES){Object v=m.get(name);s.append("| ").append(label(name)).append(" | ").append(v==null?"未测":v).append(" |\n");}
            s.append("\n内存容量不是当前可分配量；渲染提交不是面板 FPS。会话编号不是启动计数。本报告不等于崩溃日志；缓冲丢弃/传输缺口不能被解释为完整记录。\n");}
        s.append("\n## 自动记录\n\n状态：").append(status()).append("；事件：").append(events.size()).append("；事件淘汰：").append(droppedEvents).append("。\n");
        return s.toString();
    }
    /** Atomic temp-file + rename writes on the writer executor; failures are reported, never retried in a loop. */
    void checkpoint(){
        File dir=reportDir;if(dir==null)return;lastSave=now();revision++;byte[] json=reportJSON(),md=reportMarkdown().getBytes(StandardCharsets.UTF_8);
        if(json.length>4*1024*1024||md.length>1024*1024){saveStatus="报告超限 · 保存失败";return;}
        writer.execute(()->{boolean ok=write(new File(dir,"diagnostics.json"),json)&&write(new File(dir,"diagnostics.md"),md);saveStatus=ok?"报告已自动保存到本机":"自动保存失败 · 可手动分享";});
    }
    private static boolean write(File target,byte[] data){
        File tmp=new File(target.getParentFile(),target.getName()+".tmp");
        try(FileOutputStream out=new FileOutputStream(tmp)){out.write(data);out.getFD().sync();}catch(IOException e){return false;}
        return tmp.renameTo(target);
    }

    private static DiagnosticsRun current;private static boolean receiving;
    /** Process singleton bound to the glasses connected when it was created; a different peer gets a fresh run. */
    static DiagnosticsRun current(File root){
        String p=NativeTransfer.connected();
        if(current==null||(!current.active&&!current.peer.equals(p))){if(current!=null)current.stop("peer_context_changed");current=new DiagnosticsRun(root,java.util.concurrent.Executors.newSingleThreadExecutor());}
        if(!receiving){receiving=true;NativeTransfer.receive((d,b)->{DiagnosticsRun c=current;if(c!=null)c.message(d,b);});}
        return current;
    }
}
