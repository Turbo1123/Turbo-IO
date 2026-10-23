package com.turboio.addon;
import java.util.*;

/** Pure-display AI_SUBTITLE trial (port of iOS TIOSubtitleTrial, subtitle-hud-v1.1): temporary preview under our
 * own SID, text only after the same-SID ACK, stop on subtitle audio or same-SID stop, bounded lifetime and cadence.
 * The sender returns false when a submission is refused. Times in seconds; main thread only. */
final class SubtitleTrial {
    interface Sender{boolean send(int type,String json);}
    static final String[] FRAMES={"导航显示测试 7392\n前方右转 80米","导航显示测试 9264\n前方右转 60米","导航显示测试 3815\n前方右转 35米"};
    private final Sender sender;
    private String phase="idle",note="等待官方预览与退出样本",sid;private boolean navigation,live;
    private double began,deadline,lastText;private int frame,audioPackets;
    SubtitleTrial(Sender sender){if(sender==null)throw new IllegalArgumentException();this.sender=sender;}
    String phase(){return phase;}String note(){return note;}String sid(){return sid==null?"":sid;}int frame(){return frame;}int audioPackets(){return audioPackets;}
    boolean navigation(){return navigation;}boolean live(){return live;}double began(){return began;}
    boolean active(){return !phase.equals("idle");}
    private static boolean integral(Object o,long v){return (o instanceof Long||o instanceof Integer)&&((Number)o).longValue()==v;}
    /** The official stop shape {sid,reason_code:10,text:""} exactly, rebuilt around the preview SID. */
    static Map<String,Object> stopContract(Map<String,Object> observed,String previewSid){
        if(observed==null||previewSid==null||previewSid.isEmpty()||!observed.keySet().equals(new HashSet<>(Arrays.asList("sid","reason_code","text"))))return null;
        Object s=observed.get("sid");if(!(s instanceof String)||((String)s).isEmpty()||!integral(observed.get("reason_code"),10)||!"".equals(observed.get("text")))return null;
        Map<String,Object> r=new LinkedHashMap<>();r.put("sid",previewSid);r.put("reason_code",10L);r.put("text","");return r;
    }
    private boolean send(int type,Map<String,Object> json){try{return sender.send(type,new String(BoundedJson.canonical(json),java.nio.charset.StandardCharsets.UTF_8));}catch(RuntimeException e){return false;}}
    private static Map<String,Object> m(Object...kv){Map<String,Object> r=new LinkedHashMap<>();for(int i=0;i<kv.length;i+=2)r.put((String)kv[i],kv[i+1]);return r;}
    boolean start(Map<String,Object> preview,Map<String,Object> stop,double now){
        if(active()||preview==null||stop==null||!"temporary".equals(preview.get("scope"))||!(preview.get("config") instanceof Map)||!Boolean.TRUE.equals(((Map<?,?>)preview.get("config")).get("is_display")))return false;
        Object force=preview.get("force");if(force!=null&&!Boolean.FALSE.equals(force)&&!integral(force,0))return false;
        Object ps=preview.get("sid");if(!(ps instanceof String)||!ps.equals(stop.get("sid")))return false;
        navigation=live=false;sid=UUID.randomUUID().toString().replace("-","").toLowerCase(Locale.ROOT);began=now;deadline=now+10;frame=0;audioPackets=0;lastText=0;
        phase="starting";note="已提交临时预览，等待同 SID 回执；尚未发导航文字";
        Map<String,Object> p=new LinkedHashMap<>(preview);p.put("sid",sid);p.put("force",false);p.put("scope","temporary");
        if(!send(7,p)){stop("预览提交失败，结果未知",now);return false;}return true;
    }
    boolean startNavigation(Map<String,Object> preview,Map<String,Object> stop,double now){if(!start(preview,stop,now))return false;navigation=true;return true;}
    boolean startLiveCaption(Map<String,Object> preview,Map<String,Object> stop,double now){if(!startNavigation(preview,stop,now))return false;live=true;return true;}
    private boolean text(String t){return send(5,m("sid",sid,"mode",3L,"status",0L,"content",m("source_transcript",t)));}
    /** Manual A/B/C frames: ready, ≤3, ≥3 s apart, within 240 s, never in navigation/caption sessions. */
    boolean next(double now){
        if(navigation||!phase.equals("ready")||frame>=3||(frame>0&&now-lastText<3)||now-began>=240)return false;
        if(!text(FRAMES[frame])){stop("文字提交失败",now);return false;}
        frame++;lastText=now;note="第"+frame+"段已提交（不是镜片回执）；请检查覆盖/追加、loading和常亮";return true;
    }
    boolean sendText(String t,double now){
        if(!navigation||!phase.equals("ready"))return false;
        if(frame>=(live?2400:80)||now-began>=(live?1200:240)||(frame>0&&now-lastText<(live?0.5:3)))return false;
        if(t==null||t.isEmpty()||t.getBytes(java.nio.charset.StandardCharsets.UTF_8).length>384)return false;
        if(!text(t)){stop("导航文字提交失败",now);return false;}
        frame++;lastText=now;note="导航文字已提交，非镜片渲染确认";return true;
    }
    /** An incoming AI_SUBTITLE message for this device (type 4 = audio, json may be empty). */
    void receive(int type,Map<String,Object> json,double now){
        if(!active())return;
        if(type==4){audioPackets++;stop("同设备字幕音频消息出现，已停止纯显示实验",now);return;}
        Object s=json==null?null:json.get("sid");if(sid==null||!sid.equals(s))return;
        if(type==8&&phase.equals("starting")){Object code=json.get("code");
            if(integral(code,1)||integral(code,2)){phase="ready";note="同 SID 设置回执已收到；点发送A，不代表文字可见或无录音";}else stop("预览回执拒绝或格式未知，不强制抢占",now);return;}
        if(type==3)stop("收到同 SID 停止消息；请确认镜片已退出",now);
    }
    void stop(String reason,double now){
        if(!active()||phase.equals("stopping")||phase.equals("uncertain"))return;
        deadline=now+8;phase="stopping";note=reason+"；已请求退出，镜片未确认";
        if(!send(3,m("sid",sid,"reason_code",10L,"text",""))){phase="uncertain";note="退出无法提交，请用眼镜按钮退出；禁止再次开始";}
    }
    /** The SDK refused the stop submission. */
    void stopRefused(){if(phase.equals("stopping")){phase="uncertain";note="SDK拒绝退出提交，请用实体按钮退出";}}
    void tick(double now){
        if(phase.equals("starting")&&now>=deadline)stop("10秒无匹配设置回执",now);
        else if(phase.equals("ready")&&now-began>=(live?1200:240))stop(live?"20分钟字幕保护到期":"4分钟保护到期",now);
        else if(phase.equals("stopping")&&now>=deadline){phase="uncertain";note="退出效果待确认；请用实体按钮退出，并在页面确认后再试";}
    }
    /** The user confirmed the lens left the session (not a protocol ACK). Only when idle, stopping or uncertain. */
    boolean reset(){if(phase.equals("starting")||phase.equals("ready"))return false;phase="idle";sid=null;note="用户确认镜片已退出；仍不是协议回执";return true;}
}
