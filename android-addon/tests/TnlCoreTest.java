package com.turboio.addon;
import java.nio.charset.StandardCharsets;import java.time.*;import java.util.*;

/** Enhanced lifelog core (port of iOS TNLContext.m): candidates, reviewed context, model body, cited answers. */
public final class TnlCoreTest {
    static int n;static void ok(boolean b,String why){n++;if(!b)throw new AssertionError("enhanced lifelog "+n+" "+why);}
    static String fails(Runnable r){try{r.run();return "";}catch(IllegalArgumentException e){return e.getMessage();}}
    static Map<String,Object> note(String key,String title,String content,double at,int event){return NotificationArchive.record(key,"com.example.cal","日程",title,"",content,0,event,"s1",at);}
    static byte[] reply(String content,String finish){Map<String,Object> msg=new LinkedHashMap<>();msg.put("role","assistant");msg.put("content",content);Map<String,Object> ch=new LinkedHashMap<>();ch.put("message",msg);if(finish!=null)ch.put("finish_reason",finish);Map<String,Object> r=new LinkedHashMap<>();r.put("choices",Arrays.asList(ch));return BoundedJson.canonical(r);}
    public static void main(String[] a){
        ZoneId zone=ZoneId.of("Asia/Shanghai");Instant start=LocalDate.of(2026,10,23).atStartOfDay(zone).toInstant(),end=start.plus(Duration.ofDays(1));double t0=start.getEpochSecond();
        List<Map<String,Object>> archive=new ArrayList<>(Arrays.asList(note("k1","会议","下午三点开会",t0+3600,0),note("k1","会议","改为四点开会",t0+7200,1),note("k2","删掉","已移除",t0+7300,2),
            note("k3","登录","您的验证码是 123456",t0+7400,0),note("k4","明天","不在范围",t0+90000,0),note("k5","重复","同样内容",t0+8000,0)));
        List<Map<String,Object>> c=TnlCore.candidates(archive,start,end);
        // Android keys are reused per conversation: a re-post with different text is a new message, not an update.
        ok(c.size()==3&&c.get(0).get("text").equals("会议\n\n下午三点开会")&&c.get(1).get("text").equals("会议\n\n改为四点开会")&&c.get(0).get("timeMeaning").equals("phone_received_at")&&((String)c.get(0).get("id")).matches("n-[0-9a-f]{64}"),"distinct messages on one key kept; removal / sensitive / out of range excluded");
        List<Map<String,Object>> same=Arrays.asList(note("k7","群","同一条",t0+100,0),note("k7","群","同一条",t0+200,1));ok(TnlCore.candidates(same,start,end).size()==1,"identical re-post collapses to the latest");
        ok(TnlCore.candidates(archive,start,start.plusSeconds(90001)).isEmpty(),"range ≤ 90000 s");
        List<CeLifelog.Row> speech=new ArrayList<>();for(int i=0;i<70;i++)speech.add(new CeLifelog.Row("第"+i+"段讨论",start.plusSeconds(60L*i).toString()));
        speech.add(new CeLifelog.Row("支付密码是 abc",start.plusSeconds(9000).toString()));speech.add(new CeLifelog.Row("昨天","2026-10-21T05:00:00Z"));
        Set<String> sel=new HashSet<>(Collections.singletonList((String)c.get(1).get("id")));
        Map<String,Object> ctx=TnlCore.context(speech,archive,sel,start,end,"Asia/Shanghai");
        ok(ctx.get("notificationCount").equals(1L)&&ctx.get("speechCount").equals(64L)&&((Number)ctx.get("speechOmitted")).longValue()==7&&Boolean.TRUE.equals(ctx.get("partial")),"64 speech rows, omitted counted (6 over cap + 1 sensitive)");
        List<?> rows=(List<?>)ctx.get("rows");String prev="";for(Object r:rows){String at=(String)((Map<?,?>)r).get("at");ok(at.compareTo(prev)>=0,"time order");prev=at;}
        ok(fails(()->TnlCore.context(speech,archive,new HashSet<>(Collections.singletonList("n-0000")),start,end,"Asia/Shanghai")).equals("选中的通知已变化，请重新读取和预览。"),"stale selection");
        ok(fails(()->TnlCore.context(new ArrayList<>(),archive,new HashSet<>(),start,end,"Asia/Shanghai")).equals("没有可总结内容；请加载官方智记原文，或选择至少一条通知。"),"empty");
        List<Map<String,Object>> big=new ArrayList<>();char[] fill=new char[1300];Arrays.fill(fill,'字');Set<String> all=new HashSet<>();
        for(int i=0;i<12;i++)big.add(note("b"+i,"t"+i,new String(fill)+i,t0+100+i,0));for(Map<String,Object> x:TnlCore.candidates(big,start,end))all.add((String)x.get("id"));
        ok(fails(()->TnlCore.context(new ArrayList<>(),big,all,start,end,"Asia/Shanghai")).equals("选中的通知超过 32 KiB，请减少选择。"),"selected notifications over 32 KiB");
        // Model body: exact prompt, sorted user JSON, unknown keys refused.
        Map<String,Object> body=TnlCore.body(ctx,"deepseek-chat");List<?> msgs=(List<?>)body.get("messages");
        ok(TnlCore.SYSTEM.startsWith("你是增强智记的事实整理器，不是官方全天智记。")&&TnlCore.SYSTEM.endsWith("全部证据不够时明确不确定。")&&((Map<?,?>)msgs.get(0)).get("content").equals(TnlCore.SYSTEM)&&body.get("max_tokens").equals(2500L)&&body.get("temperature").toString().equals("0.2"),"prompt and body");
        Map<String,Object> extra=new LinkedHashMap<>(ctx);extra.put("note","x");ok(fails(()->TnlCore.body(extra,"m")).equals("预览包含未允许的字段，请重新读取。"),"extra key refused");
        // Answers must cite known sources.
        String id=(String)((Map<?,?>)rows.get(0)).get("id");
        List<Map<String,Object>> items=TnlCore.validate(reply("```json\n{\"items\":[{\"text\":\"通知称会议改到四点。\",\"sources\":[\""+id+"\",\""+id+"\"]}]}```","stop"),ctx);
        ok(items.size()==1&&((List<?>)items.get(0).get("sources")).size()==1,"fenced JSON, duplicate sources collapsed");
        String bad="模型返回格式或来源引用无效；没有保存，也不会自动重试。";
        ok(fails(()->TnlCore.validate(reply("{\"items\":[{\"text\":\"x\",\"sources\":[\"s-unknown\"]}]}","stop"),ctx)).equals(bad),"unknown source");
        ok(fails(()->TnlCore.validate(reply("{\"items\":[{\"text\":\"x\",\"sources\":[\""+id+"\"]}]}","length"),ctx)).equals(bad),"finish_reason length");
        StringBuilder many=new StringBuilder("{\"items\":[");for(int i=0;i<21;i++){if(i>0)many.append(',');many.append("{\"text\":\"x\",\"sources\":[\""+id+"\"]}");}many.append("]}");
        ok(fails(()->TnlCore.validate(reply(many.toString(),"stop"),ctx)).equals(bad),"21 items");
        ok(TnlCore.validate(reply("{\"items\":[{\"text\":\"ok\",\"sources\":[\""+id+"\"]}]}",null),ctx).size()==1,"missing finish_reason accepted");
        String render=TnlCore.render(items,ctx);ok(render.startsWith("增强智记 · AI 生成，非官方日记\n仅依据选中的本机片段，不代表全天完整记录。\n\n• 通知称会议改到四点。\n来源："),"render "+render);
        String preview=TnlCore.preview(ctx);ok(preview.startsWith("增强智记 · 非官方日记\n10-23 00:00:00 至 10-24 00:00:00\n时区：Asia/Shanghai\n智记片段 64 条 · 通知 1 条 · 未纳入智记片段 7 条\n"),"preview "+preview.substring(0,80));
        System.out.println("TnlCoreTest: "+n+" checks; candidates, context, body, answers, render");
    }
}
