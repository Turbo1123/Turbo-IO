package com.turboio.addon;
import android.os.SystemClock;
import java.io.File;import java.nio.charset.StandardCharsets;import java.nio.file.*;import java.util.*;

/** TDG1 session: start file, samples in, timeouts, stop always sent once, bounded report without device identity. */
public final class DiagnosticsRunTest {
    static int n;static void ok(boolean b,String why){n++;if(!b)throw new AssertionError("diagnostics "+n+" "+why);}
    static File root;
    static long op(int i){return NativeTransfer.sent.get(i).bytes[5];}
    static long session(){return HexCarrier.u32(NativeTransfer.sent.get(0).bytes,8);}
    /** Type-6 envelope as the firmware emits it: {"cmd":"turbo_diagnostics_v1","payload":{"data":"<256 hex>"}}. */
    static byte[] envelope(byte[] raw){StringBuilder h=new StringBuilder();for(byte b:raw)h.append(String.format("%02x",b&255));
        byte[] json=("{\"cmd\":\"turbo_diagnostics_v1\",\"payload\":{\"data\":\""+h+"\"}}").getBytes(StandardCharsets.UTF_8);
        byte[] out=new byte[7+json.length];out[0]=8;out[1]=1;out[2]=16;out[3]=6;out[4]=26;out[5]=(byte)((json.length&127)|128);out[6]=(byte)(json.length>>7);System.arraycopy(json,0,out,7,json.length);return out;}
    static byte[] sample(long session,long seq,long tick,int flags,long build){byte[] p=new byte[128];p[0]='T';p[1]='D';p[2]='G';p[3]='1';p[4]=1;p[6]=(byte)128;
        HexCarrier.w32(p,8,session);HexCarrier.w32(p,12,seq);HexCarrier.w32(p,16,tick);HexCarrier.w32(p,20,1);HexCarrier.w32(p,24,0x7FFFE);HexCarrier.w32(p,28,build);
        for(int i=1;i<19;i++)HexCarrier.w32(p,32+4*i,i*100);HexCarrier.w32(p,120,flags);HexCarrier.w32(p,124,HexCarrier.crc(p,124));return p;}
    static void feed(String from,byte[] raw){NativeTransfer.receiver.message(from,envelope(raw));}
    static DiagnosticsRun fresh(){NativeTransfer.sent.clear();NativeTransfer.peer="test-peer";DiagnosticsRun r=new DiagnosticsRun(root,Runnable::run);NativeTransfer.receiver=r::message;return r;}
    public static void main(String[] a)throws Exception{
        root=Files.createTempDirectory("tdg-test").toFile();
        // Start: one file with a 600 s START, sequence 1.
        DiagnosticsRun r=fresh();ok(r.start(),"start");ok(NativeTransfer.sent.size()==1&&"turbo-diagnostics.tdg".equals(NativeTransfer.sent.get(0).name),"file");
        byte[] c=NativeTransfer.sent.get(0).bytes;ok(op(0)==TdgCodec.START&&HexCarrier.u32(c,12)==1&&HexCarrier.u32(c,16)==600000,"start command");long sid=session();
        ok(r.status().contains("等待眼镜首条采样"),"waiting");
        // First valid sample confirms START at app level; foreign/old/duplicate samples are ignored.
        feed("test-peer",sample(sid,1,1000,0,DiagnosticsRun.BUILD));ok(r.count()==1&&NativeTransfer.sent.get(0).acked,"first sample acks start");NativeTransfer.settle(true);
        feed("other-glasses",sample(sid,2,2000,0,DiagnosticsRun.BUILD));feed("test-peer",sample(sid^1,2,2000,0,DiagnosticsRun.BUILD));feed("test-peer",sample(sid,1,2000,0,DiagnosticsRun.BUILD));feed("test-peer",sample(sid,2,2000,0,0x02000001L));
        ok(r.count()==1,"foreign, other session, repeated seq, other build ignored");
        feed("test-peer",sample(sid,4,3000,0,DiagnosticsRun.BUILD));ok(r.count()==2,"gap accepted");
        Map<String,Object> latest=r.latest();Map<?,?> metrics=(Map<?,?>)latest.get("metrics");ok(metrics.get("lv_configured_bytes")==null&&Long.valueOf(100).equals(metrics.get("lv_used_bytes")),"unmeasured is null");
        // 20 s of silence ends the run with exactly one STOP (sequence 2).
        SystemClock.now+=20001;r.poll();ok(!r.active()&&r.status().contains("20 秒无新采样"),"silent");ok(NativeTransfer.sent.size()==2&&op(1)==TdgCodec.STOP&&HexCarrier.u32(NativeTransfer.sent.get(1).bytes,12)==2,"one stop");
        ok(NativeTransfer.sent.get(1).acked,"stop self-acked (no reply expected)");NativeTransfer.settle(true);
        feed("test-peer",sample(sid,5,4000,0,DiagnosticsRun.BUILD));ok(r.count()==2&&!r.active(),"never revived");
        String md=r.reportMarkdown(),json=new String(r.reportJSON(),StandardCharsets.UTF_8);
        ok(json.contains("\"format\":\"TurboIO-Diagnostics-1\"")&&json.contains("\"sequence_gaps\":2")&&json.contains("\"lv_configured_bytes\":null"),"report json");
        ok(!json.contains("test-peer")&&!md.contains("test-peer"),"no device id in reports");
        File dir=r.reportDirectory();ok(new File(dir,"diagnostics.json").isFile()&&new File(dir,"diagnostics.md").isFile(),"saved");
        // No first sample within 10 s.
        r=fresh();r.start();SystemClock.now+=10001;r.poll();ok(r.status().contains("10 秒未收到首条采样"),"first timeout");
        ok(NativeTransfer.sent.size()==1,"stop waits for the start transfer");NativeTransfer.settle(true);ok(NativeTransfer.sent.size()==2&&op(1)==TdgCodec.STOP,"queued stop sent once");NativeTransfer.settle(true);ok(NativeTransfer.sent.size()==2,"only one");
        // Slow probe flag ends the run.
        r=fresh();r.start();sid=session();feed("test-peer",sample(sid,1,1000,1,DiagnosticsRun.BUILD));ok(!r.active()&&r.status().contains("采样耗时"),"probe slow");
        // Failed START transfer: submit failure, nothing more to stop on the glasses' side beyond one STOP attempt.
        r=fresh();r.start();NativeTransfer.settle(false);ok(!r.active()&&r.status().contains("传输失败"),"transfer failed");
        // User stop and peer change.
        r=fresh();r.start();sid=session();feed("test-peer",sample(sid,1,1000,0,DiagnosticsRun.BUILD));NativeTransfer.settle(true);r.stop("user_stop");ok(r.status().contains("手动结束")&&op(NativeTransfer.sent.size()-1)==TdgCodec.STOP,"user stop");NativeTransfer.settle(true);
        r=fresh();r.start();sid=session();feed("test-peer",sample(sid,1,1000,0,DiagnosticsRun.BUILD));NativeTransfer.settle(true);NativeTransfer.peer="other-glasses";r.poll();ok(!r.active()&&r.status().contains("眼镜已变化"),"peer change");
        // Lease: 600 s.
        NativeTransfer.peer="test-peer";r=fresh();r.start();sid=session();long t=1;for(int i=1;i<=601;i++){feed("test-peer",sample(sid,i,t+=1000,0,DiagnosticsRun.BUILD));if(i==1)NativeTransfer.settle(true);}
        ok(r.count()==600&&new String(r.reportJSON(),StandardCharsets.UTF_8).contains("\"evicted_samples\":1"),"bounded samples");
        SystemClock.now+=600001;r.poll();ok(r.status().contains("10 分钟到期"),"lease");NativeTransfer.settle(true);
        // Busy channel or full archive: refuse to start, never delete old reports.
        r=fresh();NativeTransfer.busyOther=true;ok(!r.start()&&NativeTransfer.sent.isEmpty(),"busy");NativeTransfer.busyOther=false;
        File full=Files.createTempDirectory("tdg-full").toFile();for(int i=0;i<100;i++)new File(full,"run"+i).mkdirs();
        NativeTransfer.sent.clear();DiagnosticsRun f=new DiagnosticsRun(full,Runnable::run);ok(!f.start()&&NativeTransfer.sent.isEmpty()&&full.list().length==100,"archive bound");
        ok("LVGL 配置容量".equals(DiagnosticsRun.label("lv_configured_bytes"))&&"errors".equals(DiagnosticsRun.label("unknown"))==false&&"unknown".equals(DiagnosticsRun.label("unknown")),"labels");
        System.out.println("DiagnosticsRunTest: "+n+" checks; start, samples, timeouts, stop once, bounds, report privacy");
    }
}
