package com.turboio.addon;
import java.nio.charset.StandardCharsets;import java.util.*;

/** SubtitleTrial (port of iOS TIOSubtitleTrial, subtitle-hud-v1.1) — SubtitleHUDTests cases. */
public final class SubtitleTrialTest {
    static int n;static void ok(boolean b,String why){n++;if(!b)throw new AssertionError("subtitle "+n+" "+why);}
    static Map<String,Object> m(Object...kv){Map<String,Object> r=new LinkedHashMap<>();for(int i=0;i<kv.length;i+=2)r.put((String)kv[i],kv[i+1]);return r;}
    static Map<String,Object> json(byte[] packet){NavCore.Envelope e=NavCore.decode(packet);return BoundedJson.map(BoundedJson.read(e.json.getBytes(StandardCharsets.UTF_8)));}
    public static void main(String[] a){
        // StopContract.
        Map<String,Object> official=m("sid","different-official-id","reason_code",10L,"text","");
        Map<String,Object> c=SubtitleTrial.stopContract(official,"official");ok(c!=null&&"official".equals(c.get("sid"))&&"different-official-id".equals(official.get("sid")),"stop contract reuses the preview sid");
        ok(SubtitleTrial.stopContract(m("sid","x","reason_code",11L,"text",""),"p")==null&&SubtitleTrial.stopContract(m("sid","x","reason_code",10L,"text","private"),"p")==null&&SubtitleTrial.stopContract(m("sid","x","reason_code",10L,"text","","force",false),"p")==null,"stop contract strict");
        ok(SubtitleTrial.stopContract(m("sid","x","reason_code",true,"text",""),"p")==null,"bool reason refused");
        List<byte[]> sent=new ArrayList<>();boolean[] fail={false};
        SubtitleTrial t=new SubtitleTrial((type,js)->{if(fail[0])return false;byte[] p=NavCore.packet(type,js);if(p==null)return false;sent.add(p);return true;});
        Map<String,Object> config=m("font_size",2L,"content_width",100L,"max_lines",5L,"position","center","is_display",true,"straight_view","original");
        Map<String,Object> preview=m("sid","official","force",false,"scope","temporary","config",config),stop=m("sid","official","reason_code",10L,"text","");
        ok(!t.next(1)&&!t.start(m(),stop,1)&&!t.start(preview,m("sid","wrong","reason_code",10L,"text",""),1),"start validation");
        ok(!t.start(m("sid","official","force",true,"scope","temporary","config",config),stop,1)&&!t.start(m("sid","official","force",false,"scope","persistent","config",config),stop,1),"force / scope refused");
        ok(t.start(preview,stop,10)&&!t.sid().equals("official")&&t.sid().matches("[0-9a-f]{32}")&&t.phase().equals("starting"),"start");
        Map<String,Object> s0=json(sent.get(0));ok(NavCore.decode(sent.get(0)).type==7&&t.sid().equals(s0.get("sid"))&&"temporary".equals(s0.get("scope"))&&Boolean.FALSE.equals(s0.get("force")),"preview packet");
        ok(!t.start(preview,stop,10)&&!t.next(11),"single start, no text while starting");
        t.receive(8,m("sid","nope","code",1L),11);ok(t.phase().equals("starting"),"foreign ack ignored");
        t.receive(8,m("sid",t.sid(),"code",1L),12);ok(t.phase().equals("ready")&&t.note().equals("同 SID 设置回执已收到；点发送A，不代表文字可见或无录音"),"ack → ready, iOS note");
        ok(t.next(13)&&!t.next(14)&&t.next(16)&&!t.next(18.5)&&t.next(19)&&!t.next(25),"three frames ≥3 s apart");ok(sent.size()==4,"preview + 3");
        Map<String,Object> f1=json(sent.get(1));ok(Long.valueOf(3).equals(f1.get("mode"))&&Long.valueOf(0).equals(f1.get("status"))&&"导航显示测试 7392\n前方右转 80米".equals(BoundedJson.map(f1.get("content")).get("source_transcript")),"frame A");
        ok("导航显示测试 3815\n前方右转 35米".equals(BoundedJson.map(json(sent.get(3)).get("content")).get("source_transcript")),"frame C");
        t.tick(249);ok(t.phase().equals("ready"),"249 s ready");t.tick(250);ok(t.phase().equals("stopping")&&NavCore.decode(sent.get(sent.size()-1)).type==3&&Long.valueOf(10).equals(json(sent.get(sent.size()-1)).get("reason_code"))&&t.sid().equals(json(sent.get(sent.size()-1)).get("sid")),"4 min → stop with own sid");
        t.tick(258);ok(t.phase().equals("uncertain")&&!t.start(preview,stop,259),"uncertain blocks restart");
        // Audio.
        NavCore.Envelope audio=NavCore.decode(new byte[]{8,1,16,4,0x22,3,(byte)0xff,0,(byte)0x80});ok(audio!=null&&audio.type==4,"audio decodes");
        t.reset();ok(t.phase().equals("idle")&&t.start(preview,stop,300),"reset then start");int before=sent.size();t.receive(4,m(),300.5);
        ok(t.audioPackets()==1&&t.phase().equals("stopping")&&sent.size()==before+1,"audio stops");t.receive(4,m(),301);ok(t.audioPackets()==2&&sent.size()==before+1,"no second stop");
        boolean threw=false;try{NavCore.packet(1,"{}");}catch(IllegalArgumentException e){threw=true;}ok(NavCore.decode(new byte[]{8,1,16,4,0x22,0x7f})==null&&threw,"malformed audio / type 1 refused");
        // ACK timeout.
        t.reset();t.start(preview,stop,400);t.tick(410);ok(t.phase().equals("stopping"),"10 s without ack");
        // Type 3 with our sid stops; non-1/2 code stops.
        t.reset();t.start(preview,stop,420);t.receive(8,m("sid",t.sid(),"code",3L),421);ok(t.phase().equals("stopping"),"unknown ack code stops");
        t.reset();t.start(preview,stop,430);t.receive(8,m("sid",t.sid(),"code",1L),431);t.receive(3,m("sid",t.sid()),432);ok(t.phase().equals("stopping"),"same-sid stop");
        // Live caption.
        t.reset();ok(t.startLiveCaption(preview,stop,500)&&!t.sendText("hello",500.5),"no text before ack");t.receive(8,m("sid",t.sid(),"code",2L),501);
        ok(t.sendText("hello",502)&&!t.sendText("too fast",502.1)&&t.sendText("world",502.5),"0.5 s cadence");
        StringBuilder big=new StringBuilder();for(int i=0;i<129;i++)big.append('中');ok(!t.sendText(big.toString(),510)&&!t.next(520),"384 B cap; manual frames refused in caption");
        t.tick(800);ok(t.phase().equals("ready"),"800 ready");t.tick(1700);ok(t.phase().equals("stopping"),"20 min");
        // Navigation.
        t.reset();t.startNavigation(preview,stop,1800);t.receive(8,m("sid",t.sid(),"code",1L),1801);ok(t.sendText("nav",1802)&&!t.sendText("nav2",1802.5),"3 s navigation cadence");t.tick(2040);ok(t.phase().equals("stopping"),"240 s navigation");
        // Send failures.
        t.reset();fail[0]=true;ok(!t.start(preview,stop,3000)&&t.phase().equals("uncertain"),"failed preview submit → stop that cannot submit → uncertain");fail[0]=false;
        t.reset();t.start(preview,stop,3100);t.receive(8,m("sid",t.sid(),"code",1L),3101);fail[0]=true;ok(!t.next(3102)&&t.phase().equals("uncertain"),"failed text → uncertain stop");fail[0]=false;
        ok(t.note().equals("退出无法提交，请用眼镜按钮退出；禁止再次开始"),"uncertain note: "+t.note());
        t.reset();t.start(preview,stop,3200);t.receive(8,m("sid",t.sid(),"code",1L),3201);ok(t.next(3202),"A");t.stop("用户停止",3203);ok(t.note().equals("用户停止；已请求退出，镜片未确认"),"stop note");
        System.out.println("SubtitleTrialTest: "+n+" checks; stop contract, start validation, A/B/C cadence, lifetime, audio stop, ack timeout, caption and navigation limits, send failures");
    }
}
