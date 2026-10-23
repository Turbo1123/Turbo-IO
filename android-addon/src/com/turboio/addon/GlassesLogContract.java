package com.turboio.addon;
import java.util.*;
import java.util.regex.Pattern;

/** Glasses log wire contract (port of iOS GlassesLogContract, log-local-v3): canonical task ids, the biz-11 type-17
 * start_log_task_ack, the receiver-side fileShareSuccess for venus_<n>_log.tar.lz4 and the 180 s window. Pure. */
final class GlassesLogContract {
    private GlassesLogContract(){}
    private static final Pattern NAME=Pattern.compile("^venus_[0-9]{1,20}_log\\.tar\\.lz4$"),HEX32=Pattern.compile("^[0-9a-fA-F]{32}$");
    static final class Ack{long status,sequence;String taskId;}
    static final class Candidate{final String taskId,fileName,filePath;Candidate(String t,String n,String p){taskId=t;fileName=n;filePath=p;}}
    /** Dashed lowercase UUID, from a 36-char UUID or 32 hex digits; null otherwise. */
    static String taskId(Object o){
        if(!(o instanceof String))return null;String s=(String)o;if(s.isEmpty()||s.length()>1024)return null;
        if(HEX32.matcher(s).matches())s=s.substring(0,8)+"-"+s.substring(8,12)+"-"+s.substring(12,16)+"-"+s.substring(16,20)+"-"+s.substring(20);
        if(s.length()!=36||!s.matches("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"))return null;
        try{return UUID.fromString(s).toString().toLowerCase(Locale.ROOT);}catch(IllegalArgumentException e){return null;}
    }
    private static boolean integral(Object o){return o instanceof Long||o instanceof Integer;}
    static Ack ack(String kind,Map<?,?> data,String device){
        try{
            if(!"messageReceived".equals(kind)||data==null||device==null)return null;Object raw=data.get("message");if(!(raw instanceof Map))return null;Map<?,?> m=(Map<?,?>)raw;
            if(HostBusiness.id(m.get("businessId"))!=11||!device.equals(m.get("deviceId")))return null;Object payload=m.get("payload");if(!(payload instanceof byte[]))return null;
            A2uiFrame.Frame f=A2uiFrame.decode((byte[])payload);if(f==null||f.type!=17||!"start_log_task_ack".equals(f.json.get("cmd"))||!(f.json.get("payload") instanceof Map))return null;
            Map<?,?> p=(Map<?,?>)f.json.get("payload");Object value=p.get("value"),mode=p.get("mode"),d=p.get("data");
            if(!integral(value)||!integral(mode)||((Number)mode).longValue()!=0||!(d instanceof String))return null;
            String t=((String)d).isEmpty()?"":taskId(d);if(t==null)return null;
            Ack a=new Ack();a.status=((Number)value).longValue();a.taskId=t;a.sequence=f.sequence;return a;
        }catch(RuntimeException e){return null;}
    }
    private static String text(Object o){return o instanceof String&&!((String)o).isEmpty()&&((String)o).length()<=1024?(String)o:null;}
    /** The receiver-side file event for our device and task; only the plain-name delivery (Android cc_transfer). */
    static Candidate file(String kind,Map<?,?> data,String device,String task){
        try{
            if(!"fileShareSuccess".equals(kind)||data==null||device==null||task==null)return null;
            Object dev=data.get("device");if(!(dev instanceof Map)||!device.equals(((Map<?,?>)dev).get("id"))||!"receiver".equals(data.get("role")))return null;
            String t=taskId(data.get("taskId")),want=taskId(task);if(t==null||!t.equals(want))return null;
            String name=text(data.get("fileName")),path=text(data.get("filePath"));if(name==null||path==null||!NAME.matcher(name).matches())return null;
            if(!path.startsWith("/")||path.indexOf('\0')>=0)return null;for(String part:path.split("/"))if(part.equals("..")||part.equals("."))return null;
            if(!path.substring(path.lastIndexOf('/')+1).equals(name))return null;
            return new Candidate(t,name,path);
        }catch(RuntimeException e){return null;}
    }
    static boolean windowValid(double started,double now,boolean active,boolean pending){
        return active&&pending&&!Double.isNaN(started)&&!Double.isInfinite(started)&&!Double.isNaN(now)&&!Double.isInfinite(now)&&started>0&&now>=started&&now-started<180;
    }
}
