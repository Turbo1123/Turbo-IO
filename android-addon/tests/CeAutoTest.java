package com.turboio.addon;
import java.io.File;import java.nio.file.*;import java.time.*;import java.util.*;import java.util.function.*;

/** Daily automation (port of iOS CEAutoPlan.m): opt-in, once-per-day generation from yesterday's cached text, send
 * window [minute, minute+15), binding to destination/model/scope/peer/zone, restart safety. */
public final class CeAutoTest {
    static int n;static void ok(boolean b,String why){n++;if(!b)throw new AssertionError("auto english "+n+" "+why);}
    static Instant at(String local){return LocalDateTime.parse(local).atZone(ZoneId.of("Asia/Shanghai")).toInstant();}
    static Map<String,Object> settings(String target,int count,int minute){Map<String,Object> s=new LinkedHashMap<>();s.put("target",target);s.put("count",(long)count);s.put("minute",(long)minute);return s;}
    static Map<String,Object> card(String w){Map<String,Object> c=new LinkedHashMap<>();c.put("english",w);c.put("quote","讨论计划");c.put("meaning","计划");c.put("example","Let's plan.");c.put("kind","generated_expression");return c;}
    static final class Env{
        Instant now=at("2026-10-23T19:00");Map<String,Object> ctx=new HashMap<>();
        List<Consumer<Object[]>> reads=new ArrayList<>();List<Object[]> generates=new ArrayList<>();List<Object[]> sends=new ArrayList<>();List<Map<String,Object>> reviews=new ArrayList<>();boolean cancelled;
        Env(){ctx.put("destination","https://api.deepseek.com/chat/completions");ctx.put("model","deepseek-chat");ctx.put("scope","abc");ctx.put("peer","peerhash");ctx.put("zone","Asia/Shanghai");ctx.put("ready",true);ctx.put("canSend",false);}
        CeAuto plan(File f){CeAuto p=new CeAuto(f);p.clock=()->now;p.context=()->new HashMap<>(ctx);
            p.read=done->reads.add(r->done.accept((List<CeLifelog.Row>)r[0],(String)r[1]));
            p.generate=(sel,done)->{generates.add(new Object[]{sel,done});return ()->cancelled=true;};
            p.send=(cards,s,done)->sends.add(new Object[]{cards,s,done});p.reviews=(day,target,count)->reviews;return p;}
    }
    @SuppressWarnings("unchecked") public static void main(String[] a)throws Exception{
        Path dir=Files.createTempDirectory("ce-auto");File file=dir.resolve("auto-plan.json").toFile();Env e=new Env();CeAuto p=e.plan(file);
        ok(!p.enabled()&&"off".equals(p.snapshot().get("phase")),"default off");
        e.ctx.put("ready",false);ok(p.enable(settings("CET6",3,1200)).equals("需要已连接眼镜、唯一官方账号缓存和有效模型配置；本机队列须可写。"),"enable needs ready");e.ctx.put("ready",true);
        ok(p.enable(settings("CET6",3,1200))==null&&p.enabled()&&"waiting".equals(p.snapshot().get("phase")),"enabled");
        p.tick();ok(e.reads.size()==1,"reads once on the new day");
        List<CeLifelog.Row> rows=Arrays.asList(new CeLifelog.Row("我们讨论明天的计划","2026-10-22T02:00:00Z"),new CeLifelog.Row("我的密码是 123456","2026-10-22T03:00:00Z"),new CeLifelog.Row("今天的内容","2026-10-23T03:00:00Z"));
        e.reads.get(0).accept(new Object[]{rows,null});ok(e.generates.size()==1&&"generating".equals(p.snapshot().get("phase"))&&Long.valueOf(1).equals(p.snapshot().get("excluded")),"generates from yesterday, sensitive excluded");
        Map<String,Object> sel=(Map<String,Object>)e.generates.get(0)[0];List<?> src=(List<?>)sel.get("sources");ok(src.size()==1&&((Map<?,?>)src.get(0)).get("quote").equals("我们讨论明天的计划")&&sel.get("day").equals("2026-10-22"),"yesterday only");
        ((BiConsumer<List<Map<String,Object>>,String>)e.generates.get(0)[1]).accept(Arrays.asList(card("plan"),card("Plan"),card("schedule")),null);
        ok("queued".equals(p.snapshot().get("phase"))&&Long.valueOf(2).equals(p.snapshot().get("candidateCount")),"queued, duplicate word dropped");
        p.tick();ok(e.sends.isEmpty()&&"题库已备好，等待连接与空闲通道。".equals(p.snapshot().get("note")),"waits for an idle channel");
        e.ctx.put("canSend",true);p.tick();ok(e.sends.size()==1&&"sending".equals(p.snapshot().get("phase")),"sends");Map<String,Object> s=(Map<String,Object>)e.sends.get(0)[1];ok(Boolean.TRUE.equals(s.get("reminder"))&&s.get("minute").equals(1200L),"send settings");
        // Restart while sending → uncertain, no automatic resend.
        CeAuto restarted=e.plan(file);ok("uncertain".equals(restarted.snapshot().get("phase"))&&"上次操作被中断，今天不自动重传；可使用手动页核对。".equals(restarted.snapshot().get("note")),"restart while sending is uncertain");
        ((Consumer<Boolean>)e.sends.get(0)[2]).accept(true);ok("delivered".equals(p.snapshot().get("phase"))&&"2026-10-23".equals(p.snapshot().get("delivered")),"delivered");
        p.tick();ok(e.reads.size()==1&&e.sends.size()==1&&e.generates.size()==1,"once per day");
        e.now=at("2026-10-23T21:00");p.tick();ok("delivered".equals(p.snapshot().get("phase")),"delivered day not turned into missed");
        // Next day: past the window → missed (no late nudge).
        e.now=at("2026-10-24T20:16");p.tick();ok("missed".equals(p.snapshot().get("phase"))&&e.reads.size()==1,"missed after minute+15");
        // Reviews only: no model request.
        e.now=at("2026-10-25T08:00");e.reviews=Arrays.asList(card("review"));CeAuto r1=e.plan(dir.resolve("r1.json").toFile());r1.enable(settings("CET6",1,1200));r1.tick();
        e.reads.get(e.reads.size()-1).accept(new Object[]{rows,null});ok("queued".equals(r1.snapshot().get("phase"))&&e.generates.size()==1&&"已备好到期复习，无需模型请求。".equals(r1.snapshot().get("note")),"due reviews without a model call");
        // Binding change → consent_changed.
        e.ctx.put("model","other");r1.tick();ok("consent_changed".equals(r1.snapshot().get("phase"))&&r1.snapshot().get("candidateCount")!=null,"binding change");
        e.ctx.put("model","deepseek-chat");r1.tick();ok("consent_changed".equals(r1.snapshot().get("phase")),"stays until re-authorized");
        // No text: waiting with the iOS note, no model call.
        e.reviews=new ArrayList<>();CeAuto r2=e.plan(dir.resolve("r2.json").toFile());r2.enable(settings("CET4",5,1200));r2.tick();e.reads.get(e.reads.size()-1).accept(new Object[]{new ArrayList<CeLifelog.Row>(),null});
        ok("waiting".equals(r2.snapshot().get("phase"))&&"昨日暂无合适的本机正文；不编造题目，等待正文缓存。".equals(r2.snapshot().get("note")),"no text");
        r2.tick();ok(e.reads.size()==3,"re-read waits 15 minutes");e.now=e.now.plusSeconds(901);r2.tick();ok(e.reads.size()==4,"re-read after 15 minutes");e.reads.get(3).accept(new Object[]{new ArrayList<CeLifelog.Row>(),null});
        // Disable clears queued cards; system clock going back pauses.
        r2.disable();ok(!r2.enabled()&&"off".equals(r2.snapshot().get("phase"))&&"自动化已关闭，本机待发题库已清除。".equals(r2.snapshot().get("note")),"disable");
        CeAuto r3=e.plan(dir.resolve("r3.json").toFile());r3.enable(settings("CET4",5,1200));r3.tick();e.reads.get(e.reads.size()-1).accept(new Object[]{new ArrayList<CeLifelog.Row>(),null});e.now=e.now.minusSeconds(3*86400);r3.tick();ok("系统日期倒退，暂停自动执行。".equals(r3.snapshot().get("note")),"clock rollback");
        // Corrupt store → storage_error, never enabled.
        Files.write(dir.resolve("bad.json"),"{\"version\":1,\"enabled\":true,\"phase\":\"waiting\"}".getBytes("UTF-8"));CeAuto bad=e.plan(dir.resolve("bad.json").toFile());
        ok("storage_error".equals(bad.snapshot().get("phase"))&&Boolean.TRUE.equals(bad.snapshot().get("storageError"))&&bad.enable(settings("CET4",5,1200))!=null,"corrupt store");
        // Generation cancelled by suspend → uncertain.
        e.now=at("2026-10-26T08:00");CeAuto r4=e.plan(dir.resolve("r4.json").toFile());r4.enable(settings("CET4",2,1200));r4.tick();e.reads.get(e.reads.size()-1).accept(new Object[]{Arrays.asList(new CeLifelog.Row("昨天讨论预算","2026-10-25T02:00:00Z")),null});
        r4.suspend();ok(e.cancelled&&"uncertain".equals(r4.snapshot().get("phase")),"suspend cancels generation");
        ((BiConsumer<List<Map<String,Object>>,String>)e.generates.get(e.generates.size()-1)[1]).accept(Arrays.asList(card("budget")),null);ok("uncertain".equals(r4.snapshot().get("phase")),"late generation result ignored");
        System.out.println("CeAutoTest: "+n+" checks; consent, once-per-day, window, binding, restart, storage");
    }
}
