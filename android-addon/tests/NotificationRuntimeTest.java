package com.turboio.addon;
import java.nio.file.*;import java.util.*;

/** Notification observation runtime (port of iOS TNAObserveEvent ingress rules): opt-in, bounded queue, generation
 * drops queued work on toggle, added/modified/removed event ids, status/ongoing and host notifications skipped. */
public final class NotificationRuntimeTest {
    static int n;static void ok(boolean b,String why){n++;if(!b)throw new AssertionError("notification runtime "+n+" "+why);}
    static Map<String,Object> note(String key,String title,boolean ongoing,String pkg){Map<String,Object> m=new HashMap<>();m.put("key",key);m.put("title",title);m.put("ongoing",ongoing);m.put("pkg",pkg);return m;}
    @SuppressWarnings("unchecked") public static void main(String[] a)throws Exception{
        List<Runnable> queue=new ArrayList<>();Path dir=Files.createTempDirectory("tnr");NotificationArchive.Store store=new NotificationArchive.Store(dir.toFile());double[] now={1792990000};
        NotificationRuntime.Extractor ex=o->{Map<String,Object> m=(Map<String,Object>)o;NotificationRuntime.Fields f=new NotificationRuntime.Fields();f.key=(String)m.get("key");f.pkg=(String)m.get("pkg");f.appName="微信";f.title=(String)m.get("title");f.subtitle="";f.content="正文";f.postTime=1792990000000L;f.ongoing=(Boolean)m.get("ongoing");return f;};
        NotificationRuntime rt=new NotificationRuntime(store,queue::add,ex,"com.rayneo.venus",()->now[0]);
        rt.posted(note("k1","张三",false,"com.tencent.mm"));ok(queue.isEmpty()&&((Number)rt.status().get("observed")).intValue()==1,"disabled: observed only, nothing queued");
        rt.setEnabled(true);rt.posted(note("k1","张三",false,"com.tencent.mm"));rt.posted(note("k1","张三(2)",false,"com.tencent.mm"));rt.removed(note("k1","张三(2)",false,"com.tencent.mm"));
        for(Runnable r:new ArrayList<>(queue))r.run();queue.clear();
        List<Map<String,Object>> rows=store.search("",10);ok(rows.size()==3,"three events stored");
        Set<Long> ids=new HashSet<>();for(Map<String,Object> r:rows)ids.add(((Number)r.get("eventId")).longValue());ok(ids.equals(new HashSet<>(Arrays.asList(0L,1L,2L))),"added / modified / removed");
        rt.posted(note("k9","下载中",true,"com.android.providers.downloads"));rt.posted(note("k8","Turbo",false,"com.rayneo.venus"));ok(queue.isEmpty()&&((Number)rt.status().get("skipped")).intValue()==2,"ongoing and host notifications skipped");
        for(int i=0;i<70;i++)rt.posted(note("q"+i,"t"+i,false,"com.x"));ok(queue.size()==64&&((Number)rt.status().get("overflow")).intValue()==6,"≤64 pending, overflow counted");
        rt.setEnabled(false);for(Runnable r:new ArrayList<>(queue))r.run();queue.clear();ok(store.search("",100).size()==3&&((Number)rt.status().get("pending")).intValue()==0,"disable drops queued work");
        rt.setEnabled(true);rt.posted(note("z","t",false,"com.x"));rt.setEnabled(true);for(Runnable r:new ArrayList<>(queue))r.run();queue.clear();ok(store.search("",100).size()==3,"re-enable (generation change) also drops older queued work");
        NotificationRuntime.Extractor bad=o->{throw new RuntimeException("boom");};NotificationRuntime broken=new NotificationRuntime(store,queue::add,bad,"h",()->now[0]);broken.setEnabled(true);broken.posted(note("x","t",false,"p"));
        ok(((Number)broken.status().get("invalid")).intValue()==1,"extractor failure counted, never thrown");
        ok(!rt.status().toString().contains("张三"),"status has no content");
        // Errors on the add-on executor are contained; app labels resolve off the listener thread.
        NotificationArchive.Store failing=new NotificationArchive.Store(dir.toFile()){@Override synchronized String insert(Map<String,Object> r,double now){throw new OutOfMemoryError("simulated");}};
        NotificationRuntime oom=new NotificationRuntime(failing,queue::add,ex,"h",()->now[0]);oom.setEnabled(true);oom.posted(note("o1","t",false,"com.x"));
        boolean contained=true;try{for(Runnable r:new ArrayList<>(queue))r.run();}catch(Throwable t){contained=false;}queue.clear();ok(contained&&((Number)oom.status().get("writeFailures")).intValue()==1,"Error on the executor contained and counted");
        int[] labels={0};NotificationRuntime.Extractor bare=o->{NotificationRuntime.Fields f=ex.fields(o);f.appName=null;return f;};
        NotificationRuntime lazy=new NotificationRuntime(store,queue::add,bare,"h",()->now[0]);lazy.labeler=pkg->{labels[0]++;return "标签";};lazy.setEnabled(true);lazy.posted(note("lab","t",false,"com.y"));
        ok(labels[0]==0,"no label lookup on the listener thread");for(Runnable r:new ArrayList<>(queue))r.run();queue.clear();ok(labels[0]==1&&store.search("com.y",5).get(0).get("appName").equals("标签"),"label resolved on the executor");
        System.out.println("NotificationRuntimeTest: "+n+" checks; opt-in, event ids, skips, queue bound, generation");
    }
}
