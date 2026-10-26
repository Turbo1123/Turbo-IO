package com.turboio.addon;
import java.nio.charset.StandardCharsets;import java.nio.file.*;import java.util.*;

/** Enhanced lifelog results (port of iOS TNLStore.m): ≤30 results, 30 days, 512 KiB, no inputs or keys stored. */
public final class TnlStoreTest {
    static int n;static void ok(boolean b,String why){n++;if(!b)throw new AssertionError("enhanced lifelog store "+n+" "+why);}
    public static void main(String[] a)throws Exception{
        Path dir=Files.createTempDirectory("tnl");TnlStore s=new TnlStore(dir.toFile());double now=1792990000;
        Map<String,Object> ctx=new LinkedHashMap<>();ctx.put("start","2026-10-22T16:00:00Z");ctx.put("end","2026-10-23T16:00:00Z");ctx.put("speechCount",3L);ctx.put("notificationCount",1L);ctx.put("rows",Arrays.asList("secret input"));
        ok(s.read(now).isEmpty(),"empty");
        ok(s.save("第一份","api.deepseek.com","deepseek-chat",ctx,now),"save");ok(s.save("第二份","api.deepseek.com","deepseek-chat",ctx,now+1),"save 2");
        List<Map<String,Object>> rows=s.read(now+2);ok(rows.size()==2&&rows.get(0).get("text").equals("第二份")&&rows.get(0).get("speechCount").equals(3L),"newest first, counts kept");
        String file=new String(Files.readAllBytes(dir.resolve("results.json")),StandardCharsets.UTF_8);ok(!file.contains("secret input")&&!file.contains("rows"),"inputs never stored");
        for(int i=0;i<31;i++)s.save("份"+i,"h","m",ctx,now+10+i);ok(s.read(now+100).size()==30,"≤30 results");
        ok(s.read(now+31*86400.0).isEmpty()&&new String(Files.readAllBytes(dir.resolve("results.json")),StandardCharsets.UTF_8).equals("[]"),"expired deleted on read (file rewritten)");
        char[] big=new char[24000];Arrays.fill(big,'字');for(int i=0;i<12;i++)ok(s.save(new String(big),"h","m",ctx,now+i),"big "+i);
        ok(Files.size(dir.resolve("results.json"))<=480*1024&&s.read(now+20).size()<12,"trimmed to 480 KiB");
        ok(!s.save(new String(new char[24001]).replace('\0','x'),"h","m",ctx,now),"text cap");
        Files.write(dir.resolve("results.json"),"{broken".getBytes(StandardCharsets.UTF_8));ok(s.read(now)==null&&!s.save("x","h","m",ctx,now)&&new String(Files.readAllBytes(dir.resolve("results.json")),StandardCharsets.UTF_8).equals("{broken"),"corrupt file refused, never overwritten by save");
        ok(s.clear()&&s.read(now).isEmpty(),"clear");
        System.out.println("TnlStoreTest: "+n+" checks; order, caps, expiry, corruption, clear");
    }
}
