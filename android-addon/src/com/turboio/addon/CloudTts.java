package com.turboio.addon;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.util.*;

/** Ali Flash realtime TTS (qwen-audio-3.1-tts-flash) over DashScope duplex WebSocket, as iOS VoiceTTS:
 * run-task → task-started → continue-task per chunk → finish-task → task-finished; audio is PCM16 LE mono 24 kHz.
 * At most 1800 characters and 18 segments per answer. The key never enters JSON, logs or status. Callbacks from a
 * previous turn (generation) are dropped. Thread-safe: transport callbacks may arrive on network threads. */
final class CloudTts {
    interface Listener{void text(String json);void binary(byte[] pcm);void closed(String reason);}
    interface Transport{void open(String url,String key,Listener listener);boolean send(String json);void close();}
    interface Pcm{boolean available();boolean write(byte[] pcm16le);void stop();}
    interface Key{String get();}
    static final String DEFAULT_ENDPOINT="wss://dashscope.aliyuncs.com/api-ws/v1/inference";
    private static final String STOP="。！？!?；;\n",SOFT="，,、：: ";

    /** TIOVoiceTTSChunk: cut at a stop mark (index ≥3), else a soft mark once ≥65 chars, else at min(len,180) once that is ≥140,
     * else everything on the final call; never splits a surrogate pair. consumed[0] = chars taken from pending. */
    static String chunk(String pending,boolean fin,int[] consumed){
        consumed[0]=0;if(pending==null||pending.isEmpty())return null;
        int limit=Math.min(pending.length(),180),cut=-1;
        for(int i=0;i<limit;i++){char c=pending.charAt(i);if(STOP.indexOf(c)>=0&&i>=3){cut=i+1;break;}if(i>=65&&SOFT.indexOf(c)>=0){cut=i+1;break;}}
        if(cut<0){if(limit>=140||fin)cut=limit;else return null;}
        if(cut<pending.length()&&cut>0&&Character.isHighSurrogate(pending.charAt(cut-1))&&Character.isLowSurrogate(pending.charAt(cut)))cut++;
        consumed[0]=cut;return trim(pending.substring(0,cut));
    }
    private static String trim(String s){int a=0,b=s.length();while(a<b&&Character.isWhitespace(s.charAt(a)))a++;while(b>a&&Character.isWhitespace(s.charAt(b-1)))b--;return s.substring(a,b);}
    /** TIOVoiceTTSServiceURLValid: wss, dashscope.aliyuncs.com or *.maas.aliyuncs.com, /api-ws/v1/inference, port 443, nothing else. */
    static boolean endpointValid(String url){
        if(url==null||url.length()>300)return false;
        try{URI u=new URI(url);String host=u.getHost()==null?"":u.getHost().toLowerCase(Locale.ROOT);
            return "wss".equalsIgnoreCase(u.getScheme())&&(host.equals("dashscope.aliyuncs.com")||(host.endsWith(".maas.aliyuncs.com")&&host.length()>".maas.aliyuncs.com".length()))
                &&"/api-ws/v1/inference".equals(u.getPath())&&(u.getPort()==-1||u.getPort()==443)&&u.getUserInfo()==null&&u.getQuery()==null&&u.getFragment()==null;
        }catch(Exception e){return false;}
    }
    private static Map<String,Object> m(Object...kv){Map<String,Object> r=new TreeMap<>();for(int i=0;i<kv.length;i+=2)r.put((String)kv[i],kv[i+1]);return r;}
    private static String json(Object o){return new String(BoundedJson.canonical(o),StandardCharsets.UTF_8);}
    static String runTask(String taskId){
        return json(m("header",m("action","run-task","task_id",taskId,"streaming","duplex"),"payload",m("task_group","audio","task","tts","function","SpeechSynthesizer","model","qwen-audio-3.1-tts-flash",
            "parameters",m("text_type","PlainText","voice","longanhuan_v3.1","format","pcm","sample_rate",24000,"volume",50,"rate",1,"pitch",1,"enable_ssml",false),"input",m())));
    }
    static String continueTask(String taskId,String text){return json(m("header",m("action","continue-task","task_id",taskId,"streaming","duplex"),"payload",m("input",m("text",text))));}
    static String finishTask(String taskId){return json(m("header",m("action","finish-task","task_id",taskId,"streaming","duplex"),"payload",m("input",m())));}
    /** header.event of a server message, or "" when unparsable. */
    static String event(String json){try{Object e=BoundedJson.map(BoundedJson.map(BoundedJson.readDevice(json.getBytes(StandardCharsets.UTF_8))).get("header")).get("event");return e instanceof String?(String)e:"";}catch(RuntimeException x){return "";}}

    private final Transport transport;private final Pcm pcm;private final Key key;private final String endpoint;
    private final ArrayDeque<String> queue=new ArrayDeque<>();private String full="",pending="",taskId="",status="云端待命";
    private int segments,characters;private long generation;private boolean open,ready,finalRequested,finishSent,networkFinished;
    CloudTts(Transport transport,Pcm pcm,Key key){this(transport,pcm,key,DEFAULT_ENDPOINT);}
    CloudTts(Transport transport,Pcm pcm,Key key,String endpoint){this.transport=transport;this.pcm=pcm;this.key=key;this.endpoint=endpointValid(endpoint)?endpoint:DEFAULT_ENDPOINT;}
    synchronized String status(){return status;}
    synchronized void beginTurn(){cancel();}
    synchronized void cancel(){
        generation++;if(open)transport.close();open=ready=finalRequested=finishSent=networkFinished=false;pcm.stop();
        queue.clear();full="";pending="";taskId="";segments=characters=0;status="云端待命";
    }
    /** Cumulative answer text; must extend the previous text for this turn. */
    synchronized void append(String text,boolean fin){
        if(text==null||(!full.isEmpty()&&!text.startsWith(full))||finalRequested&&!text.equals(full)){status="TTS 文本未追加";return;}
        String added=text.substring(full.length());full=text;
        if(!added.isEmpty()&&characters<1800){String part=added.substring(0,Math.min(added.length(),1800-characters));pending+=part;characters+=part.length();}
        if(fin)finalRequested=true;
        int[] used={0};
        while(segments<18){String part=chunk(pending,finalRequested,used);if(used[0]==0)break;pending=pending.substring(used[0]);if(!part.isEmpty()){queue.add(part);segments++;}}
        if(segments>=18)pending="";
        if(!open&&!queue.isEmpty())start();
        if(ready)flush();
    }
    private void start(){
        String k=key.get();if(k==null||k.isEmpty()){status="未配置 TTS Key";queue.clear();return;}
        if(!pcm.available()){status="眼镜音频未连接";queue.clear();return;}
        taskId=UUID.randomUUID().toString();open=true;status="正在连接实时 TTS";long mine=generation;
        transport.open(endpoint,k,new Listener(){
            public void text(String json){control(mine,json);}
            public void binary(byte[] b){audio(mine,b);}
            public void closed(String reason){lost(mine,reason);}
        });
        if(!transport.send(runTask(taskId)))fail("TTS 发送失败");
    }
    private synchronized void control(long mine,String json){
        if(mine!=generation)return;String e=event(json);
        if(e.equals("task-started")){ready=true;status="实时合成中";flush();}
        else if(e.equals("task-failed"))fail("TTS 服务返回失败");
        else if(e.equals("task-finished")){networkFinished=true;open=false;transport.close();status="播放完成";}
    }
    private void flush(){
        if(!ready||!open)return;
        while(!queue.isEmpty())if(!transport.send(continueTask(taskId,queue.poll()))){fail("TTS 发送失败");return;}
        if(finalRequested&&!finishSent){finishSent=true;if(!transport.send(finishTask(taskId)))fail("TTS 发送失败");}
    }
    private synchronized void audio(long mine,byte[] b){
        if(mine!=generation||b==null||b.length<2||b.length>512*1024)return;
        if(!pcm.available()){fail("眼镜音频未连接");return;}
        if(pcm.write(b))status="眼镜正在播放";else fail("眼镜音频播放失败");
    }
    private synchronized void lost(long mine,String reason){if(mine!=generation||networkFinished)return;if(open){open=false;status="TTS 连接中断";queue.clear();}}
    private void fail(String why){if(open)transport.close();open=ready=false;queue.clear();pcm.stop();status=why;}
}
