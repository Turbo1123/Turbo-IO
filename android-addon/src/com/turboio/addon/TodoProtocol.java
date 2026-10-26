package com.turboio.addon;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.util.*;

/** SCHEDULE_TODO (biz 22) protocol (port of iOS TodoProtocol): the RNLink envelope, the official full-list snapshot
 * (type 6, phone→glasses), physical completion events (type 4), the official create_task intent, the "exactly one new
 * row" proof and the per-turn official-todo gate. Pure; ids stay exact decimal text. */
final class TodoProtocol {
    private TodoProtocol(){}
    static final class Envelope{long type;Map<String,Object> json;}
    static final class Item{final String wireId,title;final long status;Item(String w,String t,long s){wireId=w;title=t;status=s;}
        @Override public boolean equals(Object o){return o instanceof Item&&((Item)o).wireId.equals(wireId)&&((Item)o).title.equals(title)&&((Item)o).status==status;}
        @Override public int hashCode(){return Objects.hash(wireId,title,status);}}
    static final class Snapshot{List<Item> items=new ArrayList<>();long total;boolean isLastBatch;
        boolean full(){return isLastBatch&&total==items.size();}
        static Snapshot of(Item...rows){Snapshot s=new Snapshot();s.items.addAll(Arrays.asList(rows));s.total=rows.length;s.isLastBatch=true;return s;}}
    static final class Physical{String wireId,deviceId,rawModifiedTime;long status;}
    private static final BigDecimal MAX=BigDecimal.valueOf(Long.MAX_VALUE);
    /** Exact non-negative integer text (never via double): Long, or an integral BigDecimal ≤ int64 max. */
    static String integer(Object v){
        if(v instanceof Long||v instanceof Integer){long n=((Number)v).longValue();return n<0?null:Long.toString(n);}
        if(v instanceof BigDecimal){BigDecimal d=(BigDecimal)v;if(d.signum()<0||d.stripTrailingZeros().scale()>0||d.compareTo(MAX)>0)return null;return d.toBigInteger().toString();}
        return null;
    }
    private static boolean code(Object v,long expected){return Long.toString(expected).equals(integer(v));}
    private static boolean identifier(Object v){return v instanceof String&&((String)v).matches("[A-Za-z0-9:_-]{1,200}");}
    private static long var(byte[] b,int[] p){long v=0;for(int i=0;i<10;i++){if(p[0]>=b.length)throw new IllegalArgumentException();int c=b[p[0]++]&255;if(i==9&&(c&0xfe)!=0)throw new IllegalArgumentException();v|=(long)(c&127)<<(7*i);if((c&128)==0)return v;}throw new IllegalArgumentException();}
    private static Map<String,Object> object(Object v){
        if(v instanceof Map)return BoundedJson.map(v);if(!(v instanceof String))return null;byte[] b=((String)v).getBytes(StandardCharsets.UTF_8);if(b.length>65536)return null;
        try{Object o=BoundedJson.readDevice(b);return o instanceof Map?BoundedJson.map(o):null;}catch(RuntimeException e){return null;}
    }
    /** The todo envelope: version 1, a type, a non-empty JSON object, field 4 empty if present. */
    static Envelope envelope(byte[] b){
        try{
            if(b==null||b.length==0||b.length>262144)return null;int[] p={0};Set<Long> seen=new HashSet<>();long version=0,type=0;byte[] json=null;
            while(p[0]<b.length){long key=var(b,p),tag=key>>>3,wire=key&7;if(tag==0||tag>4||!seen.add(tag))return null;
                if(tag<=2){if(wire!=0)return null;long v=var(b,p);if(tag==1)version=v;else type=v;}
                else{if(wire!=2)return null;long len=var(b,p);if(len<0||len>b.length-p[0])return null;if(tag==3)json=Arrays.copyOfRange(b,p[0],p[0]+(int)len);if(tag==4&&len!=0)return null;p[0]+=(int)len;}}
            if(version!=1||!seen.contains(2L)||json==null||json.length==0)return null;
            Object o=BoundedJson.readLarge(json,262144,20000);if(!(o instanceof Map))return null;
            Envelope e=new Envelope();e.type=type;e.json=BoundedJson.map(o);return e;
        }catch(RuntimeException e){return null;}
    }
    static Snapshot snapshot(byte[] data){
        Envelope e=envelope(data);if(e==null||e.type!=6)return null;Object list=e.json.get("eventList"),last=e.json.get("isLastBatch");String total=integer(e.json.get("total"));
        if(!(list instanceof List)||((List<?>)list).size()>2000||total==null||Long.parseLong(total)>2000||((List<?>)list).size()>Long.parseLong(total)||!(last instanceof Boolean))return null;
        Snapshot s=new Snapshot();Set<String> seen=new HashSet<>();
        for(Object row:(List<?>)list){if(!(row instanceof Map))return null;Map<?,?> r=(Map<?,?>)row;String wire=integer(r.get("eventID"));Object title=r.get("title");
            if(!code(r.get("eventType"),1)||!(code(r.get("status"),0)||code(r.get("status"),1))||wire==null||!seen.add(wire)||!(title instanceof String)||((String)title).isEmpty()||((String)title).length()>240)return null;
            s.items.add(new Item(wire,(String)title,Long.parseLong(integer(r.get("status")))));}
        s.total=Long.parseLong(total);s.isLastBatch=(Boolean)last;return s;
    }
    static Physical physical(String kind,Map<?,?> data){
        try{
            if(!"messageReceived".equals(kind)||data==null||!(data.get("message") instanceof Map))return null;Map<?,?> m=(Map<?,?>)data.get("message");
            if(HostBusiness.id(m.get("businessId"))!=22||!identifier(m.get("deviceId"))||!(m.get("payload") instanceof byte[]))return null;
            Envelope e=envelope((byte[])m.get("payload"));if(e==null||e.type!=4)return null;Map<String,Object> r=e.json;String wire=integer(r.get("eventID")),stamp=integer(r.get("lastModifiedTime"));
            if(!code(r.get("eventType"),1)||!(code(r.get("status"),0)||code(r.get("status"),1))||wire==null||stamp==null)return null;
            Physical p=new Physical();p.wireId=wire;p.deviceId=(String)m.get("deviceId");p.status=Long.parseLong(integer(r.get("status")));p.rawModifiedTime=stamp;return p;
        }catch(RuntimeException e){return null;}
    }
    /** NSCharacterSet whitespaceAndNewline trim (Unicode spaces included). */
    static String trim(String s){int a=0,b=s.length();while(a<b&&(Character.isWhitespace(s.charAt(a))||Character.isSpaceChar(s.charAt(a))))a++;while(b>a&&(Character.isWhitespace(s.charAt(b-1))||Character.isSpaceChar(s.charAt(b-1))))b--;return s.substring(a,b);}
    /** The official create_task intent's title, or null. params and params.task may each be a map or JSON text. */
    static String createIntent(String domain,String intent,Object params){
        if(!"task".equals(domain)||!"create_task".equals(intent))return null;Map<String,Object> obj=object(params);if(obj==null)return null;Map<String,Object> task=object(obj.get("task"));if(task==null)return null;
        Object content=task.get("content");if(!(content instanceof String)||((String)content).length()>240)return null;String title=trim((String)content);return title.isEmpty()?null:title;
    }
    private static Map<String,Item> complete(Snapshot s){
        if(s==null||!s.isLastBatch||s.total!=s.items.size()||s.items.size()>2000)return null;Map<String,Item> rows=new LinkedHashMap<>();
        for(Item i:s.items){String w=i.wireId;
            if(w==null||w.isEmpty()||w.length()>19||!w.matches("[0-9]+")||(w.length()>1&&w.startsWith("0"))||(w.length()==19&&w.compareTo("9223372036854775807")>0))return null;
            if(rows.containsKey(w)||i.title==null||i.title.isEmpty()||i.title.length()>240||(i.status!=0&&i.status!=1))return null;rows.put(w,i);}
        return rows;
    }
    /** The single new row with this title and status 0, if after is before plus exactly that row; else null. */
    static Item newCandidate(Snapshot before,Snapshot after,String title){
        if(title==null||title.isEmpty()||title.length()>240)return null;Map<String,Item> old=complete(before),cur=complete(after);
        if(old==null||cur==null||cur.size()!=old.size()+1)return null;
        for(Map.Entry<String,Item> e:old.entrySet())if(!e.getValue().equals(cur.get(e.getKey()))||e.getValue().title.equals(title))return null;
        Item c=null;for(Map.Entry<String,Item> e:cur.entrySet())if(!old.containsKey(e.getKey()))c=e.getValue();
        return c!=null&&c.title.equals(title)&&c.status==0?c:null;
    }
    /** Once the official todo flow claims a voice turn, our model never takes it over until the next turn. */
    static final class TurnGate{
        private boolean official;
        boolean official(){return official;}
        void beginTurn(){official=false;}
        boolean observe(String domain,String intent,String command,Object params,String session,String expected,boolean sameListener){
            if(!sameListener||(expected!=null&&!expected.isEmpty()&&session!=null&&!session.isEmpty()&&!expected.equals(session))||!"create_task".equals(command)||createIntent(domain,intent,params)==null)return false;
            official=true;return true;
        }
    }
}
