package com.turboio.addon;
import java.nio.charset.StandardCharsets;import java.util.*;

/** Recording text summary (port of iOS RecordingText.m) and the lifelog Markdown export. */
public final class RecordingTextTest {
    static int n;static void ok(boolean b,String why){n++;if(!b)throw new AssertionError("recording text "+n+" "+why);}
    static String rep(char c,int k){char[] a=new char[k];Arrays.fill(a,c);return new String(a);}
    static Map<String,Object> reply(String content,String finish,boolean tools){Map<String,Object> m=new LinkedHashMap<>();m.put("content",content);if(tools)m.put("tool_calls",Arrays.asList(1L));Map<String,Object> c=new LinkedHashMap<>();c.put("message",m);c.put("finish_reason",finish);Map<String,Object> r=new LinkedHashMap<>();r.put("choices",Arrays.asList(c));return r;}
    public static void main(String[] a){
        ok(RecordingText.chunks("  \n ")==null&&RecordingText.chunks(rep('x',300001))==null&&RecordingText.chunks(null)==null,"blank / oversize refused");
        String t1=rep('a',4500)+"\n"+rep('b',5499);List<String> c1=RecordingText.chunks(t1);ok(c1.size()==2&&c1.get(0).length()==4501&&c1.get(0).endsWith("\n"),"cut after the newline past 3000");
        String t2=rep('a',2000)+"\n"+rep('b',7999);List<String> c2=RecordingText.chunks(t2);ok(c2.size()==2&&c2.get(0).length()==6000,"newline before 3000 ignored");
        String t3=rep('a',5999)+"😀"+rep('b',100);List<String> c3=RecordingText.chunks(t3);ok(c3.get(0).length()==6001&&c3.get(0).endsWith("😀"),"surrogate pair not split");
        for(String t:new String[]{t1,t2,t3,rep('z',18000)}){StringBuilder b=new StringBuilder();for(String c:RecordingText.chunks(t))b.append(c);ok(b.toString().equals(t),"lossless");}
        ok(RecordingText.chunks(rep('z',18000)).size()==3,"three windows");
        Map<String,Object> p=RecordingText.payload("deepseek-chat","正文",true);List<?> msgs=(List<?>)p.get("messages");
        ok(((Map<?,?>)msgs.get(0)).get("content").equals(RecordingText.SYSTEM)&&RecordingText.SYSTEM.startsWith("你是录音转写整理助手。")&&RecordingText.SYSTEM.endsWith("不要声称已经总结全文。")&&p.get("max_tokens").equals(4096L)&&p.containsKey("thinking"),"payload");
        ok(!RecordingText.payload("m","x",false).containsKey("thinking")&&RecordingText.payload("m",rep('x',8001),false)==null&&RecordingText.payload("m\u0001","x",false)==null&&RecordingText.payload("","x",false)==null,"payload bounds");
        ok("整理".equals(RecordingText.answer(reply("整理","stop",false)))&&RecordingText.answer(reply("整理","length",false))==null&&RecordingText.answer(reply("整理","stop",true))==null&&RecordingText.answer(reply("  ","stop",false))==null,"answer rules");
        String md=RecordingText.markdown("deepseek-chat",Arrays.asList("一","二"),"原文");
        ok(md.equals("# 自有模型整理\n\n模型：deepseek-chat\n\n来源：用户确认的转写文字；保留官方 ASR。共 2 段，全部处理完成。以下是逐段整理，不冒充全文综合结论；行动项仅为建议，未自动创建待办。\n\n## 第 1 段\n\n一\n\n## 第 2 段\n\n二\n\n\n---\n\n# 输入转写（原样保留）\n\n原文\n"),"markdown");
        String lm=RecordingText.lifelogMarkdown(Arrays.asList(new CeLifelog.Row("晚一点","2026-10-23T03:00:05Z"),new CeLifelog.Row("早一点","2026-10-23T02:00:00Z")),java.time.ZoneId.of("Asia/Shanghai"));
        ok(lm.equals("# 全天智记文字\n\n来自官方 App 本机缓存的逐句正文，不是完整历史或原音频。时间为片段开始时间。\n\n- 10:00:00 早一点\n- 11:00:05 晚一点\n"),"lifelog markdown "+lm);
        System.out.println("RecordingTextTest: "+n+" checks; chunks, payload, answer, markdown");
    }
}
