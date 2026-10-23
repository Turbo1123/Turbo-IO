package com.turboio.addon;
import java.io.*;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.text.Normalizer;
import java.util.*;

/** Private local notification archive (Android counterpart of iOS notification-archive-v1 TNAStore): one bounded
 * record per observed notification event, deduplicated by content fingerprint, kept 30 days, ≤2000 records and ≤8 MiB.
 * Append-only JSON lines with compaction; no network API and no notification text in status. One serial executor. */
final class NotificationArchive {
    static final int MAX_RECORD=65536,MAX_TEXT=32768,MAX_RECORDS=2000;static final long MAX_BYTES=8L*1024*1024;static final double RETAIN=30*86400.0;
    private NotificationArchive(){}
    private static String text(String v,int limit){if(v==null)return "";if(v.length()>limit||v.indexOf('\0')>=0)return null;return v;}
    private static String sha256(byte[] b){try{byte[] h=MessageDigest.getInstance("SHA-256").digest(b);StringBuilder s=new StringBuilder();for(byte x:h)s.append(String.format(Locale.ROOT,"%02x",x&255));return s.toString();}catch(Exception e){throw new IllegalStateException(e);}}
    static String fingerprint(Map<String,Object> record){Map<String,Object> copy=new TreeMap<>(record);copy.remove("id");copy.remove("receivedAt");return sha256(BoundedJson.canonical(copy));}
    /** Bounded record of one notification event (eventId 0 added, 1 modified, 2 removed); null when invalid. */
    static Map<String,Object> record(String key,String pkg,String appName,String title,String subtitle,String content,long postTime,int eventId,String session,double receivedAt){
        String uid=text(key,128),app=text(pkg,256),name=text(appName,2048),t=text(title,2048),sub=text(subtitle,2048),body=text(content,MAX_TEXT),s=text(session,64);
        if(uid==null||uid.isEmpty()||app==null||app.isEmpty()||name==null||t==null||sub==null||body==null||s==null||s.isEmpty()||eventId<0||eventId>2||!(receivedAt>0)||Double.isInfinite(receivedAt))return null;
        Map<String,Object> r=new TreeMap<>();r.put("uid",uid);r.put("session",s);r.put("appId",app);r.put("eventId",(long)eventId);r.put("receivedAt",BigDecimal.valueOf(receivedAt));r.put("origin","phone-nls");
        r.put("appName",name);r.put("title",t);r.put("subtitle",sub);r.put("content",body);r.put("timestamp",postTime>0?String.valueOf(postTime):"");
        if(BoundedJson.canonical(r).length>MAX_RECORD)return null;r.put("id",fingerprint(r));return r;
    }
    static boolean valid(Map<String,Object> r){
        if(r==null||!"phone-nls".equals(r.get("origin")))return false;
        for(String[] f:new String[][]{{"uid","128"},{"appId","256"},{"session","64"}}){Object v=r.get(f[0]);if(!(v instanceof String)||((String)v).isEmpty()||text((String)v,Integer.parseInt(f[1]))==null)return false;}
        for(String k:new String[]{"appName","title","subtitle","content","timestamp"}){Object v=r.get(k);if(!(v instanceof String)||text((String)v,k.equals("content")?MAX_TEXT:k.equals("timestamp")?128:2048)==null)return false;}
        Object e=r.get("eventId"),at=r.get("receivedAt");
        return (e instanceof Long||e instanceof Integer)&&((Number)e).longValue()>=0&&((Number)e).longValue()<=2&&at instanceof Number&&((Number)at).doubleValue()>0&&fingerprint(r).equals(r.get("id"));
    }
    private static String fold(String s){return Normalizer.normalize(s,Normalizer.Form.NFD).replaceAll("\\p{M}+","").toLowerCase(Locale.ROOT);}

    static final class Store{
        private static final class Entry{final String id;final double received;final long seq;final byte[] line;final Map<String,Object> record;Entry(String id,double r,long s,byte[] l,Map<String,Object> rec){this.id=id;received=r;seq=s;line=l;record=rec;}}
        private final File dir,log;private final Map<String,Entry> byId=new HashMap<>();private final TreeSet<Entry> order=new TreeSet<>((x,y)->x.received!=y.received?Double.compare(x.received,y.received):Long.compare(x.seq,y.seq));
        private long bytes,seq,evicted;private boolean loaded,dirty;private String error="";
        Store(File dir){this.dir=dir;log=new File(dir,"notifications.log");}
        private boolean open(){
            if(loaded)return true;if(!dir.isDirectory()&&!dir.mkdirs()){error="无法创建本机归档目录";return false;}
            dir.setReadable(false,false);dir.setReadable(true,true);dir.setExecutable(false,false);dir.setExecutable(true,true);
            if(log.isFile())try(BufferedReader in=new BufferedReader(new InputStreamReader(new FileInputStream(log),StandardCharsets.UTF_8))){String line;
                while((line=in.readLine())!=null){byte[] b=line.getBytes(StandardCharsets.UTF_8);Map<String,Object> r=null;
                    if(b.length<=MAX_RECORD)try{r=BoundedJson.map(BoundedJson.readLarge(b,MAX_RECORD,64));}catch(RuntimeException e){r=null;}
                    if(!valid(r)||byId.containsKey((String)r.get("id"))){dirty=true;continue;}add(r,b);}
            }catch(IOException e){error="数据库暂不可用；请解锁手机后重试";return false;}
            loaded=true;return true;
        }
        private void add(Map<String,Object> r,byte[] line){Entry e=new Entry((String)r.get("id"),((Number)r.get("receivedAt")).doubleValue(),seq++,line,r);byId.put(e.id,e);order.add(e);bytes+=line.length;}
        private void remove(Entry e){order.remove(e);byId.remove(e.id);bytes-=e.line.length;evicted++;dirty=true;}
        private boolean rewrite(){
            File tmp=new File(dir,"notifications.log.tmp");
            try(FileOutputStream out=new FileOutputStream(tmp)){for(Entry e:order){out.write(e.line);out.write('\n');}out.getFD().sync();}catch(IOException e){tmp.delete();error="保存失败；空间不足或数据库不可用";return false;}
            tmp.setReadable(false,false);tmp.setReadable(true,true);if(!tmp.renameTo(log)){error="保存失败；空间不足或数据库不可用";return false;}dirty=false;return true;
        }
        /** "inserted", "duplicate" or "error"; never content. */
        synchronized String insert(Map<String,Object> record,double now){
            if(!valid(record)||!(now>0)||!open())return "error";if(byId.containsKey((String)record.get("id")))return "duplicate";
            byte[] line=BoundedJson.canonical(record);if(line.length>MAX_RECORD)return "error";
            try(FileOutputStream out=new FileOutputStream(log,true)){out.write(line);out.write('\n');out.getFD().sync();}catch(IOException e){error="保存失败；空间不足或数据库不可用";return "error";}
            log.setReadable(false,false);log.setReadable(true,true);add(record,line);
            if(!prune(now))return "error";error="";return "inserted";
        }
        /** 30-day window, then ≤2000 records, then ≤8 MiB of record bytes (oldest first); compacts when anything changed. */
        synchronized boolean prune(double now){
            if(!open())return false;
            while(!order.isEmpty()&&order.first().received<now-RETAIN)remove(order.first());
            while(order.size()>MAX_RECORDS)remove(order.first());
            while(bytes>MAX_BYTES&&!order.isEmpty())remove(order.first());
            return !dirty||rewrite();
        }
        /** Newest first; case- and diacritic-insensitive over app name, app id, title, subtitle and content. */
        synchronized List<Map<String,Object>> search(String query,int limit){
            List<Map<String,Object>> out=new ArrayList<>();if(!open())return out;String q=query==null||query.length()>200?"":fold(query);int cap=Math.min(Math.max(limit,1),2000);
            for(Iterator<Entry> i=order.descendingIterator();i.hasNext()&&out.size()<cap;){Map<String,Object> r=i.next().record;boolean match=q.isEmpty();
                for(String k:new String[]{"appName","appId","title","subtitle","content"})if(!match&&fold((String)r.get(k)).contains(q))match=true;
                if(match)out.add(new TreeMap<>(r));}
            return out;
        }
        synchronized Map<String,Object> status(){open();Map<String,Object> s=new LinkedHashMap<>();s.put("count",(long)order.size());s.put("bytes",bytes);s.put("evictedThisRun",evicted);s.put("error",error);return s;}
        synchronized boolean clear(){if(!open())return false;order.clear();byId.clear();bytes=0;dirty=true;return rewrite();}
    }
}
