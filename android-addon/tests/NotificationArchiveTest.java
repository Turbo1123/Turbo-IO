package com.turboio.addon;
import java.io.*;import java.nio.charset.StandardCharsets;import java.nio.file.*;import java.util.*;

/** Local notification archive (port of iOS TNAStore / TNADecodeEvent limits): bounded, deduplicated, searchable. */
public final class NotificationArchiveTest {
    static int n;static void ok(boolean b,String why){n++;if(!b)throw new AssertionError("notification archive "+n+" "+why);}
    static Map<String,Object> rec(String key,String title,String content,double at){return NotificationArchive.record(key,"com.tencent.mm","微信",title,"",content,1792990000000L,0,"session-1",at);}
    public static void main(String[] a)throws Exception{
        Map<String,Object> r=rec("0|com.tencent.mm|1|null|10086","张三","明天开会",1792990000);
        ok(r!=null&&r.get("origin").equals("phone-nls")&&((String)r.get("id")).length()==64&&r.get("timestamp").equals("1792990000000"),"record");
        Map<String,Object> later=rec("0|com.tencent.mm|1|null|10086","张三","明天开会",1792990100);ok(r.get("id").equals(later.get("id")),"fingerprint ignores receivedAt");
        ok(NotificationArchive.record("k","p","n","t\u0000","","c",1,0,"s",1)==null&&NotificationArchive.record("","p","n","t","","c",1,0,"s",1)==null&&NotificationArchive.record("k","p","n","t","","c",1,3,"s",1)==null,"invalid records refused");
        char[] big=new char[32769];Arrays.fill(big,'x');ok(NotificationArchive.record("k","p","n","t","",new String(big),1,0,"s",1)==null,"content cap");
        Path dir=Files.createTempDirectory("tna");NotificationArchive.Store s=new NotificationArchive.Store(dir.toFile());
        ok(s.insert(r,1792990000).equals("inserted")&&s.insert(later,1792990100).equals("duplicate"),"dedupe");
        ok(s.insert(rec("k2","李四","Budget REVIEW",1792990200),1792990200).equals("inserted"),"second");
        List<Map<String,Object>> hits=s.search("review",10);ok(hits.size()==1&&hits.get(0).get("title").equals("李四"),"case-insensitive content search");
        ok(s.search("微信",10).size()==2&&s.search("",10).get(0).get("title").equals("李四"),"app name search, newest first");
        // Reopen: persisted and deduplicated against.
        NotificationArchive.Store again=new NotificationArchive.Store(dir.toFile());ok(again.search("",10).size()==2&&again.insert(r,1792990300).equals("duplicate"),"reopen");
        // Corrupt line skipped and compacted away.
        Files.write(dir.resolve("notifications.log"),"{not json}\n".getBytes(StandardCharsets.UTF_8),StandardOpenOption.APPEND);
        NotificationArchive.Store c=new NotificationArchive.Store(dir.toFile());ok(c.search("",10).size()==2,"corrupt line skipped");ok(c.prune(1792990300)&&!new String(Files.readAllBytes(dir.resolve("notifications.log")),StandardCharsets.UTF_8).contains("not json"),"compacted");
        // 30 days.
        ok(c.prune(1792990000+31*86400.0)&&c.search("",10).isEmpty(),"30-day retention");
        // 2000 records.
        Path d2=Files.createTempDirectory("tna2");NotificationArchive.Store m=new NotificationArchive.Store(d2.toFile());double t=1792990000;
        for(int i=0;i<2001;i++)ok(m.insert(rec("k"+i,"t"+i,"c",t+i),t+i).equals("inserted"),"insert "+i);
        ok(((Number)m.status().get("count")).intValue()==2000&&m.search("t0",3000).stream().noneMatch(x->x.get("title").equals("t0"))&&m.search("",1).get(0).get("title").equals("t2000"),"≤2000, oldest evicted");
        // 8 MiB.
        Path d3=Files.createTempDirectory("tna3");NotificationArchive.Store b=new NotificationArchive.Store(d3.toFile());char[] chunk=new char[20000];Arrays.fill(chunk,'字');
        for(int i=0;i<150;i++)ok(b.insert(rec("b"+i,"t"+i,new String(chunk),t+i),t+i).equals("inserted"),"big "+i);
        long bytes=((Number)b.status().get("bytes")).longValue();ok(bytes<=8*1024*1024&&((Number)b.status().get("count")).intValue()<150&&b.search("",1).get(0).get("title").equals("t149"),"8 MiB cap evicts oldest ("+bytes+")");
        ok(b.clear()&&b.search("",10).isEmpty()&&((Number)b.status().get("count")).intValue()==0,"clear");
        ok(!b.status().toString().contains("字"),"status has no content");
        System.out.println("NotificationArchiveTest: "+n+" checks; record, dedupe, search, persistence, retention caps");
    }
}
