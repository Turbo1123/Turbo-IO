package com.turboio.addon;
import java.io.*;
import java.math.BigDecimal;
import java.util.*;

/** Separately saved enhanced-lifelog results (port of iOS TNLStore.m): ≤30 results, newest first, kept 30 days and
 * ≤480 KiB on save / 512 KiB on read. Stores only the rendered text, provider host, model, range and counts — never
 * the transcript, notifications or keys. A corrupt file is refused and never overwritten by a save. */
final class TnlStore {
    private static final int MAX_FILE=512*1024,TRIM=480*1024,MAX_RESULTS=30,MAX_TEXT=24000;
    private final File dir,file;
    TnlStore(File dir){this.dir=dir;file=new File(dir,"results.json");}
    /** Results (expired ones deleted from the file), or null when the file is unreadable/corrupt. */
    synchronized List<Map<String,Object>> read(double now){
        if(!file.exists())return new ArrayList<>();
        List<Object> rows;
        try(InputStream in=new FileInputStream(file)){if(!file.isFile()||file.length()>MAX_FILE)return null;rows=BoundedJson.list(BoundedJson.readLarge(BoundedHTTP.read(in,MAX_FILE),MAX_FILE,20000));}catch(IOException|RuntimeException e){return null;}
        if(rows.size()>MAX_RESULTS)return null;List<Map<String,Object>> out=new ArrayList<>();
        for(Object o:rows){if(!(o instanceof Map))return null;Map<String,Object> r=BoundedJson.map(o);Object t=r.get("text"),at=r.get("createdAt");
            if(!(t instanceof String)||((String)t).length()>MAX_TEXT||!(at instanceof Number))return null;if(((Number)at).doubleValue()>=now-30*86400.0)out.add(r);}
        // Expired results are removed on access, not merely hidden.
        if(out.size()!=rows.size()&&!write(out))return null;return out;
    }
    private boolean write(List<Map<String,Object>> rows){
        byte[] d=BoundedJson.canonical(rows);if(d.length>MAX_FILE)return false;
        if(!dir.isDirectory()&&!dir.mkdirs())return false;File tmp=new File(dir,"results.json.tmp");
        try(FileOutputStream out=new FileOutputStream(tmp)){out.write(d);out.getFD().sync();}catch(IOException e){tmp.delete();return false;}
        tmp.setReadable(false,false);tmp.setReadable(true,true);return tmp.renameTo(file);
    }
    synchronized boolean save(String text,String provider,String model,Map<String,Object> context,double now){
        if(text==null||text.isEmpty()||text.length()>MAX_TEXT||provider==null||provider.length()>300||model==null||model.length()>200)return false;
        List<Map<String,Object>> rows=read(now);if(rows==null)return false;
        Map<String,Object> r=new LinkedHashMap<>();r.put("id",UUID.randomUUID().toString());r.put("createdAt",BigDecimal.valueOf(now));r.put("text",text);r.put("provider",provider);r.put("model",model);
        r.put("start",context.get("start")==null?"":context.get("start"));r.put("end",context.get("end")==null?"":context.get("end"));
        r.put("speechCount",context.get("speechCount")==null?0L:context.get("speechCount"));r.put("notificationCount",context.get("notificationCount")==null?0L:context.get("notificationCount"));
        rows.add(0,r);while(rows.size()>MAX_RESULTS)rows.remove(rows.size()-1);while(rows.size()>1&&BoundedJson.canonical(rows).length>TRIM)rows.remove(rows.size()-1);
        return write(rows);
    }
    synchronized boolean clear(){return write(new ArrayList<>());}
}
