package com.turboio.addon;
import java.io.*;
import java.time.*;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.function.*;
import java.util.regex.Pattern;

/** Opt-in daily context-English automation (port of iOS CEAutoPlan.m). Bound to the approved destination, model,
 * account-cache scope, glasses peer and time zone; at most one model request per day from yesterday's cached text;
 * the deck is sent only inside [minute, minute+15) of the same day and never resent after an unknown outcome.
 * Runs only while the host gives it execution time. Main executor only; dependencies are injected. */
final class CeAuto {
    interface Send{void send(List<Map<String,Object>> cards,Map<String,Object> settings,Consumer<Boolean> done);}
    interface Reviews{List<Map<String,Object>> get(String day,String target,int count);}
    Supplier<Instant> clock=Instant::now;
    Supplier<Map<String,Object>> context;
    Consumer<BiConsumer<List<CeLifelog.Row>,String>> read;
    BiFunction<Map<String,Object>,BiConsumer<List<Map<String,Object>>,String>,Runnable> generate;
    Send send;Reviews reviews;

    private static final Pattern SENSITIVE=Pattern.compile("(?i)(https?://|[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}|[0-9][0-9 -]{6,}[0-9]|sk-|wrk-|cookie|token|password|密码|验证码|身份证|银行卡|账号|密钥|病历|诊断|患者|住址)");
    private static final String[] IDENTITY={"destination","model","scope","peer","zone"};
    private final File file;private Map<String,Object> state=new LinkedHashMap<>();
    private boolean busy,ioFailed;private long epoch;private long nextRead;private Runnable cancel;

    CeAuto(File file){
        this.file=file;state.put("version",1L);state.put("enabled",false);state.put("phase","off");
        if(!file.exists())return;
        Map<String,Object> s=null;
        try(InputStream in=new FileInputStream(file)){if(file.isFile()&&file.length()<=65536)s=new LinkedHashMap<>(BoundedJson.map(BoundedJson.readLarge(BoundedHTTP.read(in,65536),65536,20000)));}catch(IOException|RuntimeException e){s=null;}
        boolean valid=s!=null&&Long.valueOf(1).equals(s.get("version"))&&s.get("enabled") instanceof Boolean&&str(s.get("phase"),32);
        if(valid&&(Boolean)s.get("enabled"))valid=settings(s.get("settings"))&&identity(s.get("binding"));
        for(String k:new String[]{"day","attempted","delivered","highest"})if(valid&&s.get(k)!=null)valid=str(s.get(k),10)&&((String)s.get(k)).matches("^[0-9]{4}-[0-9]{2}-[0-9]{2}$");
        if(valid&&s.get("cards")!=null)valid=deck(s.get("cards"))&&settings(s.get("settings"))&&((List<?>)s.get("cards")).size()<=num(((Map<?,?>)s.get("settings")).get("count"));
        if(valid&&"queued".equals(s.get("phase")))valid=s.get("cards") instanceof List&&!((List<?>)s.get("cards")).isEmpty();
        if(valid){state=s;if("generating".equals(state.get("phase"))||"sending".equals(state.get("phase"))){state.put("phase","uncertain");state.put("note","上次操作被中断，今天不自动重传；可使用手动页核对。");}}
        else{ioFailed=true;state.put("phase","storage_error");}
    }
    private static boolean str(Object o,int n){return o instanceof String&&!((String)o).isEmpty()&&((String)o).length()<=n;}
    private static long num(Object o){return o instanceof Number?((Number)o).longValue():-1;}
    private static boolean integer(Object o,long lo,long hi){return (o instanceof Long||o instanceof Integer)&&((Number)o).longValue()>=lo&&((Number)o).longValue()<=hi;}
    private static boolean settings(Object o){if(!(o instanceof Map))return false;Map<?,?> s=(Map<?,?>)o;return CeSession.TARGETS.contains(s.get("target"))&&integer(s.get("count"),1,10)&&integer(s.get("minute"),0,1439);}
    private static boolean identity(Object o){if(!(o instanceof Map))return false;for(String k:IDENTITY)if(!str(((Map<?,?>)o).get(k),2048))return false;return true;}
    private static Map<String,Object> binding(Map<?,?> c){Map<String,Object> b=new LinkedHashMap<>();for(String k:IDENTITY)b.put(k,c.get(k));return b;}
    @SuppressWarnings("unchecked") private static boolean deck(Object o){
        if(!(o instanceof List)||((List<?>)o).isEmpty()||((List<?>)o).size()>CeWire.MAX_CARDS)return false;
        for(Object c:(List<?>)o){if(!(c instanceof Map))return false;CeWire.Card card=CeCore.card((Map<String,Object>)c);if(card==null||!CeWire.cardValid(card))return false;}return true;
    }
    private static String day(Instant t,ZoneId z){return t.atZone(z).toLocalDate().format(DateTimeFormatter.ISO_LOCAL_DATE);}
    private static ZoneId zone(Object z){try{return z instanceof String?ZoneId.of((String)z):null;}catch(DateTimeException e){return null;}}

    boolean enabled(){return Boolean.TRUE.equals(state.get("enabled"));}
    Map<String,Object> snapshot(){
        Map<String,Object> s=new LinkedHashMap<>();for(String k:new String[]{"enabled","phase","note","day","attempted","delivered","settings","excluded","sources","candidateCount"})if(state.get(k)!=null)s.put(k,state.get(k));
        s.put("busy",busy);s.put("storageError",ioFailed);return s;
    }
    private boolean save(){
        if(ioFailed)return false;
        try{byte[] d=BoundedJson.canonical(state);if(d.length>65536)throw new IOException();File dir=file.getParentFile();if(dir!=null&&!dir.isDirectory()&&!dir.mkdirs())throw new IOException();
            File tmp=new File(file.getPath()+".tmp");try(FileOutputStream out=new FileOutputStream(tmp)){out.write(d);out.getFD().sync();}
            tmp.setReadable(false,false);tmp.setReadable(true,true);if(!tmp.renameTo(file)&&!(file.delete()&&tmp.renameTo(file)))throw new IOException();return true;}
        catch(IOException|RuntimeException e){ioFailed=true;state.put("enabled",false);state.put("phase","storage_error");state.put("note","本机队列无法安全保存，自动化已停止。");return false;}
    }
    /** Null when enabled; otherwise the reason (iOS text). */
    String enable(Map<String,Object> settings){
        Map<String,Object> c=context!=null?context.get():null;
        if(ioFailed||busy||!settings(settings)||!identity(c)||!Boolean.TRUE.equals(c.get("ready")))return "需要已连接眼镜、唯一官方账号缓存和有效模型配置；本机队列须可写。";
        suspend();state.put("enabled",true);state.put("settings",new LinkedHashMap<>(settings));state.put("binding",binding(c));state.put("phase","waiting");state.put("note","已授权：昨日正文，每日一次生成；等待执行机会。");
        state.remove("cards");nextRead=0;return save()?null:"本机队列无法安全保存，自动化已停止。";
    }
    void disable(){
        boolean sending="sending".equals(state.get("phase"));suspend();state.put("enabled",false);state.put("phase","off");
        state.put("note",sending?"自动化已关闭；已开始的文件传输不能撤回，请等待本次结果。":"自动化已关闭，本机待发题库已清除。");
        state.remove("cards");state.remove("binding");save();
    }
    /** The host withdrew execution time: drop in-flight work; a started generation/send becomes "uncertain". */
    void suspend(){
        epoch++;Runnable c=cancel;cancel=null;busy=false;if(c!=null)c.run();
        if("generating".equals(state.get("phase"))||"sending".equals(state.get("phase"))){state.put("phase","uncertain");state.put("note","系统结束本轮运行时间；今天不自动重试，请手动核对。");save();}
    }
    private boolean matches(Map<String,Object> binding,String today){
        Map<String,Object> c=context!=null?context.get():null;ZoneId z=identity(c)?zone(c.get("zone")):null;
        return !ioFailed&&enabled()&&z!=null&&Boolean.TRUE.equals(c.get("ready"))&&binding(c).equals(binding)&&day(clock.get(),z).equals(today);
    }
    @SuppressWarnings("unchecked") void tick(){
        if(busy||ioFailed||!enabled()||context==null)return;
        Map<String,Object> c=context.get();Map<String,Object> binding=(Map<String,Object>)state.get("binding");
        if(!identity(c)||!Boolean.TRUE.equals(c.get("ready"))){state.put("note","等待 App 可运行、眼镜连接与本机正文可读。");return;}
        if("consent_changed".equals(state.get("phase")))return;
        if(!binding(c).equals(binding)){state.put("phase","consent_changed");state.put("note","账号、模型、设备或时区变化，请关闭后重新授权。");state.remove("cards");save();return;}
        ZoneId z=zone(c.get("zone"));if(z==null)return;Instant now=clock.get();String today=day(now,z);
        if(state.get("highest")!=null&&today.compareTo((String)state.get("highest"))<0){state.put("note","系统日期倒退，暂停自动执行。");return;}
        if(!today.equals(state.get("day"))){state.put("day",today);state.put("highest",today);state.remove("cards");state.put("phase","waiting");nextRead=0;if(!save())return;}
        if(today.equals(state.get("delivered")))return;
        Map<String,Object> settings=(Map<String,Object>)state.get("settings");LocalTime local=now.atZone(z).toLocalTime();
        long minute=local.getHour()*60+local.getMinute(),deadline=Math.min(1440,num(settings.get("minute"))+15);
        if(minute>=deadline){state.put("phase","missed");state.put("note","今天提醒窗口已过，不再迟到打扰；明天补做。");state.remove("cards");return;}
        String phase=(String)state.get("phase");
        if("queued".equals(phase)){
            if(!Boolean.TRUE.equals(c.get("canSend"))||send==null){state.put("note","题库已备好，等待连接与空闲通道。");return;}
            state.put("phase","sending");state.put("note","正在查询能力并发送题库。");if(!save())return;
            busy=true;long mine=++epoch;Map<String,Object> s=new LinkedHashMap<>();s.put("target",settings.get("target"));s.put("count",settings.get("count"));s.put("minute",settings.get("minute"));s.put("reminder",true);
            send.send((List<Map<String,Object>>)state.get("cards"),s,confirmed->{if(epoch!=mine)return;busy=false;
                // null: the channel refused before anything was submitted — keep the deck queued for a later tick.
                if(confirmed==null){state.put("phase","queued");state.put("note","题库已备好，等待连接与空闲通道。");save();return;}
                if(!matches(binding,today)){state.put("phase","uncertain");state.put("note","发送期间环境变化，请手动核对眼镜。");}
                else if(Boolean.TRUE.equals(confirmed)){state.put("phase","delivered");state.put("delivered",today);state.put("note","眼镜已确认保存，等待所设时间邀请；手机不再重复推送。");state.remove("cards");}
                else{state.put("phase","uncertain");state.put("note","传输未确认，停止自动重发；请在手动页核对。");}save();});
            return;
        }
        if(today.equals(state.get("attempted"))||"uncertain".equals(phase)||"failed".equals(phase)||"consent_changed".equals(phase))return;
        if(read==null||generate==null||now.getEpochSecond()<nextRead)return;
        nextRead=now.getEpochSecond()+900;busy=true;long mine=++epoch;String yesterday=day(now.minus(Duration.ofDays(1)),z);
        read.accept((rows,error)->{if(epoch!=mine)return;busy=false;if(!matches(binding,today))return;
            List<CeLifelog.Row> safe=new ArrayList<>();long excluded=0;
            for(CeLifelog.Row r:rows==null?Collections.<CeLifelog.Row>emptyList():rows){if(r==null||!str(r.text,600))continue;if(SENSITIVE.matcher(r.text).find()){excluded++;continue;}safe.add(r);if(safe.size()>=20000)break;}
            state.put("excluded",excluded);
            int count=(int)num(settings.get("count"));String target=(String)settings.get("target");
            List<Map<String,Object>> due=reviews!=null?reviews.get(today,target,count):Collections.<Map<String,Object>>emptyList();
            if(due==null||(!due.isEmpty()&&!deck(due)))due=new ArrayList<>();if(due.size()>count)due=new ArrayList<>(due.subList(0,count));
            Map<String,Object> selection=null;if(due.size()<count)try{selection=CeCore.prepareDay(safe,yesterday,z,target,count-due.size());}catch(IllegalArgumentException e){selection=null;}
            if(selection==null&&due.isEmpty()){state.put("phase","waiting");state.put("note",error!=null?"官方本机正文暂不可读，稍后再查；不上传摘要。":"昨日暂无合适的本机正文；不编造题目，等待正文缓存。");save();return;}
            state.put("attempted",today);state.put("phase",selection!=null?"generating":"queued");state.put("sources",selection!=null?(long)((List<?>)selection.get("sources")).size():0L);
            state.put("note",selection!=null?"正在按授权范围生成，今天最多一次模型请求。":"已备好到期复习，无需模型请求。");
            if(selection==null){state.put("cards",due);state.put("candidateCount",(long)due.size());save();return;}
            if(!save())return;busy=true;List<Map<String,Object>> reviewCards=due;
            Runnable c2=generate.apply(selection,(cards,failure)->{if(epoch!=mine)return;busy=false;cancel=null;
                if(!matches(binding,today)){state.put("phase","failed");state.put("note","生成期间环境变化，丢弃本次结果。");save();return;}
                List<Map<String,Object>> combined=new ArrayList<>(reviewCards);Set<String> words=new HashSet<>();for(Map<String,Object> r:reviewCards)words.add(String.valueOf(r.get("english")).toLowerCase(Locale.ROOT));
                if(failure==null&&cards!=null)for(Map<String,Object> r:cards){if(r==null||!str(r.get("english"),100))continue;String w=((String)r.get("english")).toLowerCase(Locale.ROOT);if(!words.contains(w)&&combined.size()<count){combined.add(r);words.add(w);}}
                if(!combined.isEmpty()&&deck(combined)){state.put("cards",combined);state.put("candidateCount",(long)combined.size());state.put("phase","queued");state.put("note","题库校验通过，等待空闲发送。");}
                else{state.put("phase","failed");state.put("note","生成失败或无有效题目，今天不自动重传来源；可用手动模式检查。");}save();});
            if(busy&&epoch==mine)cancel=c2;
        });
    }
}
