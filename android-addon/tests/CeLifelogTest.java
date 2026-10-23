package com.turboio.addon;
import java.io.*;import java.nio.charset.StandardCharsets;import java.nio.file.*;import java.time.ZoneId;import java.util.*;

/** Official lifelog source (iOS CEHiveSnapshot.m + CEOfficialLifelog.m): read-only Hive frames, full-event speech clips. */
public final class CeLifelogTest {
    static int n;static void ok(boolean b,String why){n++;if(!b)throw new AssertionError("lifelog "+n+" "+why);}
    // Minimal Hive writer: frame = length u32 | key | value | crc32(frame without crc).
    static void u32(ByteArrayOutputStream o,long v){for(int i=0;i<4;i++)o.write((int)(v>>(8*i)));}
    static void value(ByteArrayOutputStream o,Object v){
        if(v==null){o.write(0);return;}
        if(v instanceof Double||v instanceof Long){o.write(2);long bits=Double.doubleToLongBits(((Number)v).doubleValue());for(int i=0;i<8;i++)o.write((int)(bits>>(8*i)));return;}
        if(v instanceof Boolean){o.write(3);o.write((Boolean)v?1:0);return;}
        if(v instanceof String){byte[] b=((String)v).getBytes(StandardCharsets.UTF_8);o.write(4);u32(o,b.length);o.write(b,0,b.length);return;}
        if(v instanceof List){o.write(10);u32(o,((List<?>)v).size());for(Object x:(List<?>)v)value(o,x);return;}
        if(v instanceof Map){o.write(11);u32(o,((Map<?,?>)v).size());for(Map.Entry<?,?> e:((Map<?,?>)v).entrySet()){value(o,e.getKey());value(o,e.getValue());}return;}
        if(v instanceof int[]){o.write(((int[])v)[0]);return;} // raw type byte for negative tests
        throw new IllegalArgumentException();
    }
    static byte[] frame(String key,Object v,boolean delete){ByteArrayOutputStream body=new ByteArrayOutputStream();byte[] k=key.getBytes(StandardCharsets.UTF_8);body.write(1);body.write(k.length);body.write(k,0,k.length);if(!delete)value(body,v);
        byte[] b=body.toByteArray();ByteArrayOutputStream f=new ByteArrayOutputStream();u32(f,4+b.length+4);f.write(b,0,b.length);byte[] head=f.toByteArray();java.util.zip.CRC32 c=new java.util.zip.CRC32();c.update(head);u32(f,c.getValue());return f.toByteArray();}
    static Map<String,Object> m(Object...kv){Map<String,Object> r=new LinkedHashMap<>();for(int i=0;i<kv.length;i+=2)r.put((String)kv[i],kv[i+1]);return r;}
    static Map<String,Object> clip(String text,String who,long ms,String type){return m("content",text,"speakerName",who,"startTime",String.valueOf(ms),"clipType",type);}
    static byte[] cat(byte[]...parts){ByteArrayOutputStream o=new ByteArrayOutputStream();for(byte[] p:parts)o.write(p,0,p.length);return o.toByteArray();}
    public static void main(String[] a)throws Exception{
        long t0=1792990000000L;ZoneId utc=ZoneId.of("UTC");
        List<Object> clips=Arrays.asList(clip("Let's postpone","甲",t0,"speech"),clip("the review.","甲",t0+5000,"speech"),clip("好的","乙",t0+8000,"speech"),
            clip("[音乐]","乙",t0+9000,"music"),clip("我们开始","乙",t0+10000,"speech"),clip("三十一秒后","乙",t0+40500,"speech"));
        Map<String,Object> event=m("createdAt","2026-10-23T08:00:00Z","response",m("code",0L,"data",m("transcriptionContents",Arrays.asList(m("clips",clips)),"summary","不读取摘要")));
        Map<String,Object> older=m("createdAt","2026-10-22T08:00:00Z","response",m("code",0L,"data",m("transcriptionContents",Arrays.asList(m("clips",Arrays.asList(clip("旧版本","甲",t0,"speech")))))));
        Map<String,Object> evil=m("createdAt","2026-10-23T09:00:00Z","response",m("code",0L,"data",m("transcriptionContents",Arrays.asList(m("clips",Arrays.asList(clip("恶意","甲",t0+60000,"speech")))))));
        byte[] hive=cat(frame("https://xr-api-p.rayneo.cn/lifelog/api/v1/events/77/full",event,false),frame("https://xr-api-p.rayneo.cn/lifelog/api/v1/events/77/full?x=1",older,false),
            frame("https://evil.example/lifelog/api/v1/events/9/full",evil,false),frame("https://xr-api-p.rayneo.cn/lifelog/api/v1/events/9",evil,false),frame("http://xr-api-p.rayneo.cn/lifelog/api/v1/events/8/full",evil,false),frame("other",m("a",1L),false));
        List<CeLifelog.Row> rows=CeLifelog.rows(hive,utc);
        ok(rows.size()==4,"merged rows "+rows.size());
        ok(rows.get(rows.size()-1).text.equals("Let's postpone the review.")&&rows.get(rows.size()-1).at.equals("2026-10-26T04:46:40Z"),"same speaker within 30 s merged, ISO receipt time "+rows.get(rows.size()-1).at);
        Set<String> texts=new HashSet<>();for(CeLifelog.Row r:rows)texts.add(r.text);ok(texts.contains("好的")&&texts.contains("我们开始")&&texts.contains("三十一秒后")&&!texts.contains("旧版本")&&!texts.contains("恶意")&&!texts.contains("[音乐]"),"speaker change, non-speech and >30 s gap split; older entry ignored");
        ok(rows.get(0).at.compareTo(rows.get(1).at)>=0,"newest first");
        // A later frame for the same key replaces it; an empty-value frame deletes it.
        ok(CeLifelog.rows(cat(hive,frame("https://xr-api-p.rayneo.cn/lifelog/api/v1/events/77/full",null,true),frame("https://xr-api-p.rayneo.cn/lifelog/api/v1/events/77/full?x=1",null,true)),utc).isEmpty(),"deleted keys");
        // Corruption and unknown adapters are refused, not guessed.
        byte[] bad=hive.clone();bad[10]^=1;boolean refused=false;try{CeLifelog.rows(bad,utc);}catch(IllegalArgumentException e){refused=e.getMessage().contains("官方缓存正在变化");}ok(refused,"bad CRC");
        refused=false;try{CeHive.read(frame("k",new int[]{6},false));}catch(IllegalArgumentException e){refused=true;}ok(refused,"unknown value type 6");
        Map<Object,Object> plain=CeHive.read(cat(frame("k",m("n",2.5,"s","x","b",true,"l",Arrays.asList(1L,null)),false)));Map<?,?> v=(Map<?,?>)plain.get("k");
        ok(((Number)v.get("n")).doubleValue()==2.5&&"x".equals(v.get("s"))&&Boolean.TRUE.equals(v.get("b"))&&((List<?>)v.get("l")).size()==2,"primitive values");
        // Non-speech code / wrong code ignored.
        Map<String,Object> failed=m("createdAt","2026-10-24T08:00:00Z","response",m("code",500L,"data",m("transcriptionContents",Arrays.asList(m("clips",clips)))));
        ok(CeLifelog.rows(frame("https://xr-api-p.rayneo.cn/lifelog/api/v1/events/5/full",failed,false),utc).isEmpty(),"error response ignored");
        // Control characters break a row; >600 chars skipped.
        List<Object> odd=Arrays.asList(clip("a​b","甲",t0,"speech"),clip(new String(new char[601]).replace('\0','x'),"甲",t0+1000,"speech"),clip("ok","甲",t0+2000,"speech"));
        rows=CeLifelog.rows(frame("https://xr-api-p.rayneo.cn/lifelog/api/v1/events/6/full",m("createdAt","x","response",m("code",200L,"data",m("transcriptionContents",Arrays.asList(m("clips",odd))))),false),utc);
        ok(rows.size()==1&&rows.get(0).text.equals("ok"),"control / overlong clips dropped");
        // File discovery: exactly one account cache across the host dirs.
        Path root=Files.createTempDirectory("ce-hive");Path files=Files.createDirectories(root.resolve("files")),flutter=Files.createDirectories(root.resolve("app_flutter"));
        List<File> dirs=Arrays.asList(files.toFile(),flutter.toFile());
        ok(CeLifelog.read(dirs,utc).isEmpty()&&CeLifelog.scope(dirs).isEmpty(),"no cache: empty, no scope");
        Files.write(flutter.resolve("api_cache_user_123.hive"),hive);Files.write(flutter.resolve("api_cache_user_x.hive"),new byte[]{1});
        ok(CeLifelog.read(dirs,utc).size()==4&&CeLifelog.scope(dirs).length()==64,"single account cache read, scope hash");
        Files.write(files.resolve("api_cache_user_456.hive"),hive);refused=false;try{CeLifelog.read(dirs,utc);}catch(IllegalArgumentException e){refused=e.getMessage().contains("多个官方账号缓存");}ok(refused&&CeLifelog.scope(dirs).isEmpty(),"two accounts refused");
        System.out.println("CeLifelogTest: "+n+" checks; Hive frames, full-event speech rows, account guard");
    }
}
