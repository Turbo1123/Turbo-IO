package com.turboio.addon;
import java.io.*;
import java.net.URI;
import java.nio.file.*;
import java.security.MessageDigest;
import java.time.*;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.regex.Pattern;

/** The official app's locally cached lifelog transcript (port of iOS CEOfficialLifelog.m): only verbatim speech clips
 * of cached full-event responses, never summaries, titles, locations or participants. Read-only, one account only.
 * Row time is the clip start time from the cache (receipt basis), formatted as an ISO-8601 instant. */
final class CeLifelog {
    static final class Row{final String text,at;Row(String text,String at){this.text=text;this.at=at;}}
    private static final Pattern ROUTE=Pattern.compile("^/lifelog/api/v1/events/[0-9]+/full$"),FILE=Pattern.compile("^api_cache_user_[0-9]+\\.hive$");
    private static Map<?,?> dict(Object o){return o instanceof Map?(Map<?,?>)o:Collections.emptyMap();}
    private static List<?> list(Object o){return o instanceof List?(List<?>)o:Collections.emptyList();}
    private static String text(Object o){return o instanceof String?(String)o:"";}
    /** NSNumber stringValue / string of 12–14 digits in ms, between 2020 and 2100. */
    private static Instant stamp(Object o){
        String s=o instanceof Number?(((Number)o).doubleValue()==Math.rint(((Number)o).doubleValue())?String.valueOf((long)((Number)o).doubleValue()):String.valueOf(o)):text(o);
        if(s.length()<12||s.length()>14||!s.chars().allMatch(c->c>='0'&&c<='9'))return null;double t=Double.parseDouble(s)/1000.;
        return t>=1577836800&&t<=4102444800L?Instant.ofEpochMilli((long)Double.parseDouble(s)):null;
    }
    private static boolean control(String s){for(int i=0;i<s.length();){int cp=s.codePointAt(i);i+=Character.charCount(cp);int t=Character.getType(cp);if(t==Character.CONTROL||t==Character.FORMAT)return true;}return false;}
    static List<Row> rows(byte[] cache,ZoneId zone){
        Map<Object,Object> hive=CeHive.read(cache);Map<String,Map<?,?>> latest=new TreeMap<>();
        for(Map.Entry<Object,Object> e:hive.entrySet()){
            if(!(e.getKey() instanceof String))continue;URI url;try{url=new URI((String)e.getKey());}catch(Exception x){continue;}String path=url.getPath()==null?"":url.getPath();
            if(!"https".equals(url.getScheme())||!"xr-api-p.rayneo.cn".equals(url.getHost())||!ROUTE.matcher(path).matches())continue;
            Map<?,?> entry=dict(e.getValue()),response=dict(entry.get("response"));Object code=response.get("code");
            if(!(code instanceof Number)||(((Number)code).longValue()!=0&&((Number)code).longValue()!=200))continue;
            Map<?,?> prev=latest.get(path);if(prev==null||text(entry.get("createdAt")).compareTo(text(prev.get("createdAt")))>0)latest.put(path,entry);
        }
        List<Row> rows=new ArrayList<>();Set<String> seen=new HashSet<>();int total=0;DateTimeFormatter iso=DateTimeFormatter.ISO_INSTANT;
        for(Map<?,?> entry:latest.values()){Map<?,?> event=dict(dict(entry.get("response")).get("data"));
            for(Object raw:list(event.get("transcriptionContents"))){
                StringBuilder chunk=new StringBuilder();Instant start=null,previous=null;String speaker=null;
                for(Object rawClip:list(dict(raw).get("clips"))){
                    if(++total>20000)throw new IllegalArgumentException("官方缓存的逐句记录超过读取上限，请缩小本机缓存范围。");
                    Map<?,?> clip=dict(rawClip);String t=text(clip.get("content")),who=text(clip.get("speakerName"));Instant at=stamp(clip.get("startTime"));
                    if(!"speech".equals(text(clip.get("clipType")))||at==null||t.isEmpty()||t.length()>600||control(t)){start=flush(chunk,start,rows,seen,iso);previous=null;continue;}
                    double gap=previous!=null?(at.toEpochMilli()-previous.toEpochMilli())/1000.0:0;
                    boolean sameDay=start==null||start.atZone(zone).toLocalDate().equals(at.atZone(zone).toLocalDate());
                    if(chunk.length()>0&&(chunk.length()+t.length()+1>400||gap>30||gap<0||!who.equals(speaker)||!sameDay))start=flush(chunk,start,rows,seen,iso);
                    if(start==null)start=at;if(chunk.length()>0)chunk.append(' ');chunk.append(t);speaker=who;previous=at;
                }
                flush(chunk,start,rows,seen,iso);
            }
        }
        rows.sort((x,y)->y.at.compareTo(x.at));return rows;
    }
    private static Instant flush(StringBuilder chunk,Instant start,List<Row> rows,Set<String> seen,DateTimeFormatter iso){
        if(chunk.length()==0||start==null){chunk.setLength(0);return null;}String at=iso.format(start.truncatedTo(java.time.temporal.ChronoUnit.SECONDS)),text=chunk.toString();
        if(seen.add(at+"|"+text)&&rows.size()<20000)rows.add(new Row(text,at));chunk.setLength(0);return null;
    }
    private static List<File> caches(List<File> dirs){List<File> out=new ArrayList<>();for(File d:dirs){File[] files=d.listFiles();if(files==null)continue;for(File f:files)if(FILE.matcher(f.getName()).matches())out.add(f);}return out;}
    /** SHA-256 of the single account cache file name ("" when none or ambiguous): the automation consent scope. */
    static String scope(List<File> dirs){
        List<File> found=caches(dirs);if(found.size()!=1)return "";
        try{byte[] h=MessageDigest.getInstance("SHA-256").digest(found.get(0).getName().getBytes("UTF-8"));StringBuilder s=new StringBuilder();for(byte x:h)s.append(String.format(Locale.ROOT,"%02x",x&255));return s.toString();}catch(Exception e){return "";}
    }
    /** Rows of the single api_cache_user_<n>.hive in the host's files / app_flutter dirs; empty when none. */
    static List<Row> read(List<File> dirs,ZoneId zone){
        List<File> found=caches(dirs);if(found.isEmpty())return Collections.emptyList();
        if(found.size()!=1)throw new IllegalArgumentException("检测到多个官方账号缓存，暂不自动读取，以免混入其他账号记录。");
        File f=found.get(0);String busy="官方缓存正在更新或超过32 MB读取上限，请稍后重试；原数据未改动。";
        if(Files.isSymbolicLink(f.toPath())||!f.isFile())throw new IllegalArgumentException("暂时无法只读打开官方缓存，请解锁手机后重试。");
        long size=f.length(),modified=f.lastModified();if(size<0||size>CeHive.MAX_BYTES)throw new IllegalArgumentException(busy);
        byte[] data;try(InputStream in=new FileInputStream(f)){data=BoundedHTTP.read(in,CeHive.MAX_BYTES);}catch(IOException e){throw new IllegalArgumentException(busy);}
        if(data.length!=size||f.length()!=size||f.lastModified()!=modified)throw new IllegalArgumentException(busy);
        return rows(data,zone);
    }
}
