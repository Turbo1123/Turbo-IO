package com.turboio.addon;
import java.util.*;
import java.util.function.Predicate;

/** Ownership of one glasses-log round (port of iOS TIOGlassesLogGate): the device, the current task, up to 32
 * quarantined tasks (retired ones never revive), an early file buffered until its ACK, and settlement. Callers
 * serialise access. Pure; the snapshot is what owner.json stores. */
final class GlassesLogGate {
    static final int MAX_ROUNDS=32;
    static final class Decision{boolean consume,retired,mismatch,awaitingAck;GlassesLogContract.Ack ack;GlassesLogContract.Candidate candidate;}
    private String device,task;private final LinkedHashSet<String> quarantined=new LinkedHashSet<>(),retired=new LinkedHashSet<>();
    private String earlyKind;private Map<?,?> early;private boolean settled;
    GlassesLogGate(Map<String,Object> snapshot){
        if(snapshot==null)return;Object d=snapshot.get("device");if(!(d instanceof String)||((String)d).isEmpty())return;
        device=(String)d;task=GlassesLogContract.taskId(snapshot.get("task"));settled=task!=null&&Boolean.TRUE.equals(snapshot.get("settled"));
        // No cap on load (iOS parity): the ACK path may legitimately hold more than 32, and the current task is always owned.
        Object q=snapshot.get("quarantined");if(q instanceof List)for(Object o:(List<?>)q){String t=GlassesLogContract.taskId(o);if(t!=null)quarantined.add(t);}
        if(task!=null)quarantined.add(task);
        Object r=snapshot.get("retired");if(r instanceof List)for(Object o:(List<?>)r){String t=GlassesLogContract.taskId(o);if(t!=null&&quarantined.contains(t))retired.add(t);}
    }
    Map<String,Object> snapshot(){
        Map<String,Object> s=new LinkedHashMap<>();if(device==null)return s;
        s.put("device",device);s.put("task",task==null?"":task);s.put("quarantined",new ArrayList<Object>(quarantined));s.put("retired",new ArrayList<Object>(retired));s.put("settled",settled);return s;
    }
    String device(){return device;}String task(){return task;}int rounds(){return quarantined.size();}boolean settled(){return settled;}
    boolean begin(String d){if(device!=null||d==null||d.isEmpty())return false;device=d;return true;}
    /** A new round after a verified archive: everything quarantined becomes retired. persist sees the next snapshot first. */
    boolean beginNext(String d,Predicate<Map<String,Object>> persist){
        if(!settled||task==null||device==null||!device.equals(d)||quarantined.size()>=MAX_ROUNDS||persist==null)return false;
        Map<String,Object> next=new LinkedHashMap<>();next.put("device",device);next.put("task","");next.put("quarantined",new ArrayList<Object>(quarantined));next.put("retired",new ArrayList<Object>(quarantined));next.put("settled",false);
        if(!persist.test(next))return false;
        retired.clear();retired.addAll(quarantined);task=null;early=null;earlyKind=null;settled=false;return true;
    }
    boolean ownsRequest(String d){return device!=null&&!settled&&device.equals(d);}
    /** A verified restored receipt settles its task; a crash can never revive a retired receipt. */
    boolean reconcile(String t,String d){
        String c=GlassesLogContract.taskId(t);if(c==null||device==null||!device.equals(d)||(task!=null&&!task.equals(c))||(task==null&&quarantined.contains(c)))return false;
        task=c;quarantined.add(c);settled=true;return true;
    }
    Decision accept(String kind,Map<?,?> data){
        Decision r=new Decision();if(device==null||data==null)return r;
        GlassesLogContract.Ack ack=GlassesLogContract.ack(kind,data,device);
        if(ack!=null){String t=ack.taskId;
            if(!t.isEmpty()&&retired.contains(t)){r.consume=true;r.retired=true;return r;}
            if(settled&&!t.equals(task))return r;
            if(!t.isEmpty()&&task!=null&&!task.equals(t)){r.consume=true;r.mismatch=true;return r;}
            if(!t.isEmpty()){task=t;quarantined.add(t);}
            GlassesLogContract.Candidate c=task!=null&&early!=null?GlassesLogContract.file(earlyKind,early,device,task):null;if(task!=null){early=null;earlyKind=null;}
            r.consume=true;r.ack=ack;r.candidate=c;if(c!=null)settled=true;return r;
        }
        Object dev=data.get("device");if(!(dev instanceof Map)||!device.equals(((Map<?,?>)dev).get("id"))||!"receiver".equals(data.get("role")))return r;
        String t=GlassesLogContract.taskId(data.get("taskId"));if(t==null)return r;boolean owned=quarantined.contains(t);
        if(retired.contains(t)){r.consume=true;r.retired=true;return r;}
        GlassesLogContract.Candidate c=GlassesLogContract.file(kind,data,device,t);
        if(task==null&&c!=null){
            if(!owned&&quarantined.size()>=MAX_ROUNDS){r.consume=true;r.mismatch=true;return r;}
            quarantined.add(t);
            if(early!=null){r.consume=true;r.mismatch=true;return r;}
            early=data;earlyKind=kind;r.consume=true;r.awaitingAck=true;return r;
        }
        if(!owned)return r;
        if("fileShareSuccess".equals(kind)){r.consume=true;if(c!=null&&t.equals(task)){settled=true;r.candidate=c;}else r.mismatch=true;return r;}
        if("fileShareProgress".equals(kind)||"fileShareFailed".equals(kind)||"fileShareStart".equals(kind)){r.consume=true;return r;}
        return r;
    }
}
