package com.turboio.addon;
import java.util.*;
import java.util.concurrent.Executor;
import java.util.function.DoubleSupplier;

/** Notification observation (iOS TNAObserveEvent ingress rules, fed by the host's NotificationListenerService on
 * Android): opt-in, the listener thread only copies bounded fields, ≤64 pending writes on one serial executor,
 * toggling drops queued work, ongoing / host notifications are status and skipped. Status carries counts only. */
final class NotificationRuntime {
    static final class Fields{String key,pkg,appName,title,subtitle,content;long postTime;boolean ongoing;}
    interface Extractor{Fields fields(Object notification);}
    private final NotificationArchive.Store store;private final Executor executor;private final Extractor extractor;private final String host;private final DoubleSupplier clock;
    private final String session=UUID.randomUUID().toString();private final LinkedHashSet<String> seen=new LinkedHashSet<>();
    /** Package → display label; called on the executor, never on the listener (main) thread. */
    java.util.function.Function<String,String> labeler;
    private boolean enabled;private long generation;private int pending;
    private long observed,skipped,inserted,duplicates,invalid,overflow,writeFailures;
    NotificationRuntime(NotificationArchive.Store store,Executor executor,Extractor extractor,String hostPackage,DoubleSupplier clock){this.store=store;this.executor=executor;this.extractor=extractor;host=hostPackage;this.clock=clock;}
    synchronized void setEnabled(boolean on){enabled=on;generation++;}
    synchronized boolean enabled(){return enabled;}
    /** Toggling invalidates queued writes; one write already running may still finish. */
    synchronized void invalidate(){generation++;}
    NotificationArchive.Store store(){return store;}
    void posted(Object n){observe(n,false);}
    void removed(Object n){observe(n,true);}
    private void observe(Object n,boolean removed){
        long gen;
        synchronized(this){observed++;if(!enabled)return;if(pending>=64){overflow++;return;}gen=generation;}
        Fields f;try{f=extractor.fields(n);}catch(RuntimeException e){f=null;}
        if(f==null||f.key==null||f.pkg==null){synchronized(this){invalid++;}return;}
        if(f.ongoing||host.equals(f.pkg)){synchronized(this){skipped++;}return;}
        double at=clock.getAsDouble();Fields fields=f;
        synchronized(this){pending++;}
        executor.execute(()->{try{
            synchronized(this){pending--;if(!enabled||gen!=generation)return;}
            if(fields.appName==null){String name=fields.pkg;try{if(labeler!=null){String l=labeler.apply(fields.pkg);if(l!=null)name=l;}}catch(Throwable ignored){}fields.appName=name;}
            int event;if(removed){event=2;seen.remove(fields.key);}else{event=seen.contains(fields.key)?1:0;seen.add(fields.key);if(seen.size()>4096){Iterator<String> i=seen.iterator();i.next();i.remove();}}
            Map<String,Object> record=NotificationArchive.record(fields.key,fields.pkg,fields.appName,fields.title,fields.subtitle,fields.content,fields.postTime,event,session,at);
            if(record==null){synchronized(this){invalid++;}return;}
            synchronized(this){if(!enabled||gen!=generation)return;}
            String result=store.insert(record,at);
            synchronized(this){if("inserted".equals(result))inserted++;else if("duplicate".equals(result))duplicates++;else writeFailures++;}
        // Anything thrown here would reach the host's uncaught handler and kill the official app.
        }catch(Throwable t){synchronized(this){writeFailures++;}}});
    }
    Map<String,Object> status(){
        Map<String,Object> s=new LinkedHashMap<>(store.status());
        synchronized(this){s.put("enabled",enabled);s.put("observed",observed);s.put("skipped",skipped);s.put("inserted",inserted);s.put("duplicates",duplicates);s.put("invalid",invalid);s.put("overflow",overflow);s.put("writeFailures",writeFailures);s.put("pending",(long)pending);s.put("cloudUpload",false);}
        return s;
    }
}
