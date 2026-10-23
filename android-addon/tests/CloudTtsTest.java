package com.turboio.addon;
import java.nio.charset.StandardCharsets;
import java.util.*;

/** Ali Flash realtime TTS: iOS chunker, DashScope duplex flow, key never in JSON, late audio dropped. */
public final class CloudTtsTest {
    static int n;static void ok(boolean b,String why){n++;if(!b)throw new AssertionError("cloud tts "+n+" "+why);}
    static final class FakeTransport implements CloudTts.Transport{String url,key;CloudTts.Listener listener;final List<String> sent=new ArrayList<>();int opens,closes;
        public void open(String u,String k,CloudTts.Listener l){url=u;key=k;listener=l;opens++;}public boolean send(String json){sent.add(json);return true;}public void close(){closes++;}
        String last(){return sent.get(sent.size()-1);}}
    static final class FakePcm implements CloudTts.Pcm{boolean route=true;int bytes,stops;public boolean available(){return route;}public boolean write(byte[] b){bytes+=b.length;return true;}public void stop(){stops++;}}
    static String ev(String event){return "{\"header\":{\"event\":\""+event+"\",\"task_id\":\"t\"},\"payload\":{}}";}
    static String chunk(String s,boolean fin){int[] c={0};String r=CloudTts.chunk(s,fin,c);return r==null?null:r+"|"+c[0];}
    public static void main(String[] a){
        // Chunker == TIOVoiceTTSChunk.
        ok(chunk("好。",false)==null,"stop before index 3 does not cut");ok("你好世界。|5".equals(chunk("你好世界。后面",false)),"stop cut");
        String longSoft=new String(new char[66]).replace('\0','字')+"，余下";ok(("|67").equals(chunk(longSoft,false).substring(chunk(longSoft,false).indexOf('|'))),"soft cut after 65");
        String noStop=new String(new char[150]).replace('\0','字');ok(chunk(noStop,false).endsWith("|150"),"force cut at limit=min(len,180) once >=140");String longer=new String(new char[200]).replace('\0','字');ok(chunk(longer,false).endsWith("|180"),"limit 180");
        ok(chunk("短句没有标点",false)==null&&"短句没有标点|6".equals(chunk("短句没有标点",true)),"final flush");
        String pair=new String(new char[179]).replace('\0','字')+"😀"+new String(new char[20]).replace('\0','字');ok(chunk(pair,false).endsWith("|181"),"surrogate pair kept whole");
        ok(CloudTts.endpointValid("wss://dashscope.aliyuncs.com/api-ws/v1/inference")&&CloudTts.endpointValid("wss://x.maas.aliyuncs.com/api-ws/v1/inference"),"valid endpoints");
        for(String u:new String[]{"ws://dashscope.aliyuncs.com/api-ws/v1/inference","wss://evil.com/api-ws/v1/inference","wss://dashscope.aliyuncs.com/api-ws/v1/inference?k=1","wss://dashscope.aliyuncs.com:8443/api-ws/v1/inference","wss://u@dashscope.aliyuncs.com/api-ws/v1/inference","wss://.maas.aliyuncs.com/api-ws/v1/inference","wss://dashscope.aliyuncs.com/other"})ok(!CloudTts.endpointValid(u),"invalid "+u);
        String run=CloudTts.runTask("task-1");ok(run.contains("\"model\":\"qwen-audio-3.1-tts-flash\"")&&run.contains("\"voice\":\"longanhuan_v3.1\"")&&run.contains("\"format\":\"pcm\"")&&run.contains("\"sample_rate\":24000")&&run.contains("\"action\":\"run-task\"")&&run.contains("\"streaming\":\"duplex\""),"run-task fields");
        ok("task-started".equals(CloudTts.event(ev("task-started")))&&"".equals(CloudTts.event("not json")),"event parse");
        // Flow: run-task first; continue-task only after task-started; finish-task once.
        FakeTransport t=new FakeTransport();FakePcm pcm=new FakePcm();CloudTts s=new CloudTts(t,pcm,()->"sk-secret-key");
        s.beginTurn();s.append("第一句话。第二句",false);ok(t.opens==1&&t.sent.size()==1&&t.sent.get(0).contains("run-task"),"opened with run-task");
        ok(!t.sent.get(0).contains("sk-secret-key")&&!s.status().contains("sk-secret"),"key never in JSON or status");
        t.listener.text(ev("task-started"));ok(t.sent.size()==2&&t.last().contains("continue-task")&&t.last().contains("第一句话。"),"continue after start");
        s.append("第一句话。第二句话。",true);ok(t.sent.stream().filter(x->x.contains("finish-task")).count()==1&&t.sent.get(t.sent.size()-2).contains("第二句话。"),"final chunk then finish-task");
        s.append("第一句话。第二句话。",true);ok(t.sent.stream().filter(x->x.contains("finish-task")).count()==1,"finish once");
        t.listener.binary(new byte[480]);ok(pcm.bytes==480,"audio played");
        t.listener.text(ev("task-finished"));ok(t.closes==1,"closed after finish");
        // Late audio after cancel/new turn is dropped.
        CloudTts.Listener old=t.listener;s.beginTurn();old.binary(new byte[480]);ok(pcm.bytes==480,"late audio dropped");
        // Rewritten text (not a prefix) is refused for this turn.
        s.append("新的回答。",false);s.append("完全不同",false);ok(s.status().contains("未追加"),"non-prefix refused");
        // Failure and caps.
        FakeTransport f=new FakeTransport();CloudTts fs=new CloudTts(f,new FakePcm(),()->"k");fs.beginTurn();fs.append("一二三四。",true);f.listener.text(ev("task-failed"));ok(fs.status().contains("TTS 服务返回失败")&&f.closes==1,"task-failed");
        FakeTransport cap=new FakeTransport();CloudTts cs=new CloudTts(cap,new FakePcm(),()->"k");cs.beginTurn();StringBuilder big=new StringBuilder();for(int i=0;i<400;i++)big.append("一句话。");cs.append(big.toString(),true);cap.listener.text(ev("task-started"));
        long cont=cap.sent.stream().filter(x->x.contains("continue-task")).count();int chars=0;for(String x:cap.sent)if(x.contains("continue-task"))chars+=x.length();ok(cont<=18,"<=18 segments");
        int textChars=0;for(String x:cap.sent)if(x.contains("continue-task")){int i=x.indexOf("\"text\":\"")+8;textChars+=x.indexOf('"',i)-i;}ok(textChars<=1800,"<=1800 characters");
        FakeTransport nk=new FakeTransport();CloudTts ns=new CloudTts(nk,new FakePcm(),()->"");ns.beginTurn();ns.append("你好你好。",true);ok(nk.opens==0&&ns.status().contains("未配置 TTS Key"),"no key, no connection");
        FakePcm off=new FakePcm();off.route=false;FakeTransport nr=new FakeTransport();CloudTts rs=new CloudTts(nr,off,()->"k");rs.beginTurn();rs.append("你好你好。",true);ok(nr.opens==0&&rs.status().contains("眼镜音频未连接"),"no bluetooth, no connection");
        System.out.println("CloudTtsTest: "+n+" checks; chunker, endpoint, duplex flow, key privacy, late audio, caps");
    }
}
