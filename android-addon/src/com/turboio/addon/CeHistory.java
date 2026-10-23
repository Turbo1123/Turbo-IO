package com.turboio.addon;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

/** Local review record of delivered study cards (port of iOS ContextEnglishHistory.m): ≤40 rows, ≤128 KiB, per glasses
 * peer and target, 30-day window. TEP1 progress from the glasses sets result and next due day (remembered +3, else +1).
 * A store that fails validation is refused, never overwritten. */
final class CeHistory implements CeSession.History {
    private static final int MAX_BYTES=131072,MAX_ROWS=40;
    private final File file;
    CeHistory(File file){this.file=file;}
    /** crc32 of the lowercase ASCII term (0 → 1); 0 when not 1–24 ASCII bytes. */
    static long word(String english){
        if(english==null)return 0;String s=english.toLowerCase(Locale.ROOT);for(int i=0;i<s.length();i++)if(s.charAt(i)>127)return 0;
        byte[] d=s.getBytes(StandardCharsets.US_ASCII);if(d.length==0||d.length>24)return 0;long h=CeWire.crc32(d,0,d.length);return h==0?1:h;
    }
    private static boolean integer(Object o){return (o instanceof Long||o instanceof Integer)&&((Number)o).longValue()>=0&&((Number)o).longValue()<=0xffffffffL;}
    private static long num(Map<String,Object> r,String k){return ((Number)r.get(k)).longValue();}
    private List<Map<String,Object>> load(){
        if(!file.exists())return new ArrayList<>();if(!file.isFile()||file.length()>MAX_BYTES)return null;
        try(InputStream in=new FileInputStream(file)){
            Map<String,Object> json=BoundedJson.map(BoundedJson.readLarge(BoundedHTTP.read(in,MAX_BYTES),MAX_BYTES,40000));
            if(!Long.valueOf(1).equals(json.get("version")))return null;List<Object> rows=BoundedJson.list(json.get("rows"));if(rows.size()>MAX_ROWS)return null;
            List<Map<String,Object>> out=new ArrayList<>();
            for(Object o:rows){Map<String,Object> r=new LinkedHashMap<>(BoundedJson.map(o));
                if(!CeSession.TARGETS.contains(r.get("target"))||!(r.get("peer") instanceof String)||((String)r.get("peer")).length()>200||!(r.get("card") instanceof Map))return null;
                Map<String,Object> card=BoundedJson.map(r.get("card"));CeWire.Card c=CeCore.card(card);if(c==null||!CeWire.cardValid(c))return null;
                for(String k:new String[]{"day","due","word","result","reported"})if(!integer(r.get(k)))return null;
                if(num(r,"result")>3||num(r,"word")!=word(c.english))return null;out.add(r);}
            return out;
        }catch(IOException|RuntimeException e){return null;}
    }
    private boolean save(List<Map<String,Object>> rows){
        Map<String,Object> doc=new LinkedHashMap<>();doc.put("version",1L);doc.put("rows",rows);byte[] data=BoundedJson.canonical(doc);if(data.length>MAX_BYTES)return false;
        File dir=file.getParentFile();if(dir!=null&&!dir.isDirectory()&&!dir.mkdirs())return false;
        File tmp=new File(file.getPath()+".tmp");
        try(FileOutputStream out=new FileOutputStream(tmp)){out.write(data);out.getFD().sync();}catch(IOException e){tmp.delete();return false;}
        tmp.setReadable(false,false);tmp.setReadable(true,true);tmp.setWritable(false,false);tmp.setWritable(true,true);
        return tmp.renameTo(file)||(file.delete()&&tmp.renameTo(file));
    }
    private static Map<String,Object> safe(CeWire.Card c){
        Map<String,Object> m=new LinkedHashMap<>();m.put("english",c.english);m.put("quote",c.quote);m.put("meaning",c.meaning);m.put("example",c.example);
        m.put("kind",c.generated?"generated_expression":"original_english");m.put("sourceLabel",c.generated?"根据记录生成的表达":"记录中出现的英文");return m;
    }
    @Override public synchronized boolean remember(List<CeWire.Card> cards,String peer,String target,long day){
        if(day<=0||peer==null||peer.isEmpty()||peer.length()>200||!CeSession.TARGETS.contains(target)||cards==null||cards.isEmpty()||cards.size()>CeWire.MAX_CARDS)return false;
        for(CeWire.Card c:cards)if(!CeWire.cardValid(c))return false;
        List<Map<String,Object>> rows=load();if(rows==null)return false;
        rows.removeIf(r->day>num(r,"day")&&day-num(r,"day")>30);
        for(CeWire.Card c:cards){long w=word(c.english);Map<String,Object> row=new LinkedHashMap<>();
            row.put("card",safe(c));row.put("peer",peer);row.put("target",target);row.put("day",day);row.put("due",day+1);row.put("word",w);row.put("result",0L);row.put("reported",0L);
            for(Iterator<Map<String,Object>> i=rows.iterator();i.hasNext();){Map<String,Object> r=i.next();
                if(peer.equals(r.get("peer"))&&target.equals(r.get("target"))&&num(r,"word")==w){if(num(r,"reported")>=day){row.put("reported",r.get("reported"));row.put("result",r.get("result"));row.put("due",r.get("due"));}i.remove();break;}}
            rows.add(row);}
        while(rows.size()>MAX_ROWS)rows.remove(0);return save(rows);
    }
    @Override public synchronized boolean progress(byte[] raw,String peer){
        CeWire.Progress p=CeWire.progress(raw);if(p==null||p.tx==0||p.day==0)return false;
        List<Map<String,Object>> rows=load();if(rows==null)return false;boolean changed=false;
        for(Map<String,Object> r:rows){if(!r.get("peer").equals(peer)||num(r,"day")>p.day||num(r,"reported")>p.day)continue;
            for(int i=0;i<p.used;i++)if(num(r,"word")==p.words[i]){long old=num(r,"result");
                // A same-day reserved/skipped report can precede the real answer; ignore it after a definitive answer.
                if(num(r,"reported")==p.day&&(old==1||old==2)&&p.results[i]==3)break;
                r.put("result",(long)p.results[i]);r.put("reported",p.day);r.put("due",p.day+(p.results[i]==CeWire.REMEMBERED?3:1));changed=true;break;}}
        return !changed||save(rows);
    }
    /** Due review cards for this peer/target (born 1–30 days before day), soonest first, at most min(limit,10). */
    synchronized List<Map<String,Object>> reviews(String peer,String target,long day,int limit){
        List<Map<String,Object>> out=new ArrayList<>(),rows=load();if(rows==null||limit<=0)return out;
        rows.sort(Comparator.comparingLong(r->num(r,"due")));
        for(Map<String,Object> r:rows){long born=num(r,"day");if(!r.get("peer").equals(peer)||!r.get("target").equals(target)||born>=day||day-born>30||num(r,"due")>day)continue;
            Map<String,Object> card=new LinkedHashMap<>(BoundedJson.map(r.get("card")));card.put("sourceLabel","复习 · "+(card.get("sourceLabel") instanceof String?card.get("sourceLabel"):""));out.add(card);if(out.size()>=Math.min(limit,10))break;}
        return out;
    }
    synchronized boolean clear(){return save(new ArrayList<>());}
}
