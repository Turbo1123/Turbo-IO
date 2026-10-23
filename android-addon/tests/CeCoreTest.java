package com.turboio.addon;
import java.nio.charset.StandardCharsets;import java.nio.file.*;import java.time.ZoneId;import java.util.*;

/** Context English core (iOS ContextEnglish.m / ContextEnglishClient.m) and local review history (ContextEnglishHistory.m). */
public final class CeCoreTest {
    static int n;static void ok(boolean b,String why){n++;if(!b)throw new AssertionError("context english "+n+" "+why);}
    static String fails(Runnable r){try{r.run();return "";}catch(IllegalArgumentException e){return e.getMessage();}}
    static Map<String,Object> m(Object...kv){Map<String,Object> r=new LinkedHashMap<>();for(int i=0;i<kv.length;i+=2)r.put((String)kv[i],kv[i+1]);return r;}
    static Object response(String content,String finish){return m("choices",Arrays.asList(m("finish_reason",finish,"message",m("role","assistant","content",content,"refusal",null))));}
    static String card(String id,String quote,String kind,String english){return "{\"sourceId\":\""+id+"\",\"quote\":\""+quote+"\",\"kind\":\""+kind+"\",\"english\":\""+english+"\",\"meaning\":\"推迟\",\"example\":\"Let's postpone it.\",\"exampleMeaning\":\"我们推迟吧。\"}";}
    public static void main(String[] a)throws Exception{
        ZoneId sh=ZoneId.of("Asia/Shanghai");
        List<CeLifelog.Row> rows=Arrays.asList(new CeLifelog.Row("我们把评审 postpone 到明天","2026-10-23T02:00:00Z"),new CeLifelog.Row("我们把评审 postpone 到明天","2026-10-23T03:00:00Z"),
            new CeLifelog.Row("昨天的内容","2026-10-22T03:00:00Z"),new CeLifelog.Row("前一天晚上","2026-10-22T17:00:00Z"),new CeLifelog.Row("坏\u0001字符","2026-10-23T04:00:00Z"));
        Map<String,Object> sel=CeCore.prepareDay(rows,"2026-10-23",sh,"TOEFL",5);List<?> src=(List<?>)sel.get("sources");
        ok(src.size()==2&&((Map<?,?>)src.get(0)).get("sourceId").equals("s0001")&&((Map<?,?>)src.get(1)).get("quote").equals("前一天晚上")&&sel.get("timeBasis").equals("source_timestamp")&&sel.get("count").equals(5L),"local day (UTC+8), dedupe, control dropped");
        ok(fails(()->CeCore.prepareDay(rows,"2026-10-30",sh,"TOEFL",5)).equals("所选日期无可用片段；不补造历史")&&fails(()->CeCore.prepareDay(rows,"2026-02-30",sh,"TOEFL",5)).equals("日期无效")&&fails(()->CeCore.prepareDay(rows,"2026-10-23",sh,"GRE",5)).equals("日期、目标或数量无效")&&fails(()->CeCore.prepareDay(rows,"2026-10-23",sh,"CET4",11)).equals("日期、目标或数量无效"),"prepare errors");
        List<CeLifelog.Row> many=new ArrayList<>();for(int i=0;i<40;i++)many.add(new CeLifelog.Row("片段"+i+new String(new char[200]).replace('\0','字'),"2026-10-23T02:00:00Z"));
        Map<String,Object> big=CeCore.prepareDay(many,"2026-10-23",sh,"CET4",5);int bytes=0;for(Object s:(List<?>)big.get("sources"))bytes+=((String)((Map<?,?>)s).get("quote")).getBytes(StandardCharsets.UTF_8).length;ok(((List<?>)big.get("sources")).size()<=32&&bytes<=12000,"≤32 / 12000 bytes");
        // Request: exact iOS system prompt, canonical selection, no key in the body.
        Map<String,Object> req=CeCore.modelRequest(sel,"deepseek-chat",true);List<?> msgs=(List<?>)req.get("messages");
        ok(((Map<?,?>)msgs.get(0)).get("content").equals(CeCore.SYSTEM)&&CeCore.SYSTEM.startsWith("你生成情境英语学习候选。")&&CeCore.SYSTEM.endsWith("各卡学习表达不能重复；不输出Markdown、额外字段或控制字符。")&&req.get("max_tokens").equals(4096L)&&Boolean.FALSE.equals(req.get("stream")),"system prompt and body");
        ok(((String)((Map<?,?>)msgs.get(1)).get("content")).startsWith("{\"count\":5,\"day\":\"2026-10-23\",\"sources\":[{\"quote\":"),"user content is the sorted-key selection JSON");
        ok(fails(()->CeCore.modelRequest(sel,"m",false)).equals("需要先确认所选片段及云端发送范围"),"approval required");
        ok(CeCore.endpoint("https://api.deepseek.com").equals("https://api.deepseek.com/chat/completions")&&CeCore.endpoint("https://x.example/v1/").equals("https://x.example/v1/chat/completions")&&CeCore.endpoint("https://x.example/v1/chat/completions").equals("https://x.example/v1/chat/completions"),"endpoint normalized");
        for(String bad:new String[]{"http://x.example","https://u:p@x.example","https://x.example/v1?k=1","https://x.example/#f","ftp://x"})ok(fails(()->CeCore.endpoint(bad)).equals("仅允许无账号、查询参数和片段的 HTTPS 模型地址"),"endpoint "+bad);
        byte[] body=CeCore.body(sel,"m",true);ok(new String(body,StandardCharsets.UTF_8).contains("\"thinking\":{\"type\":\"disabled\"}")&&!new String(CeCore.body(sel,"m",false),StandardCharsets.UTF_8).contains("thinking"),"thinking switch");
        // Validation.
        List<Map<String,Object>> good=CeCore.validate(response("{\"cards\":["+card("s0001","评审 postpone","original_english","postpone")+","+card("s0002","前一天","generated_expression","evening")+"]}","stop"),sel);
        ok(good.size()==2&&good.get(0).get("sourceLabel").equals("记录中出现的英文")&&good.get(1).get("sourceLabel").equals("根据记录生成的表达")&&good.get(0).get("receivedAt").equals("2026-10-23T02:00:00Z")&&good.get(0).get("timeBasis").equals("source_timestamp"),"valid cards labelled");
        ok(CeWire.cardValid(CeCore.card(good.get(0)))&&CeCore.card(good.get(1)).generated&&!CeCore.card(good.get(0)).generated,"cards map to wire cards");
        ok(fails(()->CeCore.validate(response("{\"cards\":["+card("s0001","不存在的话","generated_expression","plan")+"]}","stop"),sel)).equals("第 1 张卡片 · quote：不是来源中的逐字片段。未发送到眼镜；可重新生成更短候选。"),"quote must be verbatim");
        ok(fails(()->CeCore.validate(response("{\"cards\":["+card("s0001","我们把评审","original_english","review")+"]}","stop"),sel)).equals("第 1 张卡片 · english：原文中未出现该英文表达。未发送到眼镜；可重新生成更短候选。"),"provenance");
        ok(fails(()->CeCore.validate(response("{\"cards\":["+card("s0001","评审","generated_expression","Plan")+","+card("s0002","前一天","generated_expression","plan")+"]}","stop"),sel)).startsWith("第 2 张卡片 · english：学习表达重复"),"duplicate");
        ok(fails(()->CeCore.validate(response("{\"cards\":["+card("s0001","评审","generated_expression","plan2")+"]}","stop"),sel)).equals("第 1 张卡片 · english：只允许英文字母、空格、半角连字符和半角撇号。未发送到眼镜；可重新生成更短候选。"),"alphabet");
        ok(fails(()->CeCore.validate(response("{\"cards\":["+card("s0001","评审","generated_expression","abcdefghijklmnopqrstuvwxyz")+"]}","stop"),sel)).equals("第 1 张卡片 · english：字符数 26/24。未发送到眼镜；可重新生成更短候选。"),"length detail");
        ok(fails(()->CeCore.validate(response("{\"cards\":[]}","length"),sel)).equals("模型未完整返回候选"),"finish_reason");
        ok(fails(()->CeCore.validate(response("{\"cards\":[{\"sourceId\":\"s0001\"}]}","stop"),sel)).equals("第 1 张卡片 · quote：字段缺失或有额外字段。未发送到眼镜；可重新生成更短候选。"),"schema");
        StringBuilder six=new StringBuilder("{\"cards\":[");for(int i=0;i<6;i++){if(i>0)six.append(',');six.append(card("s0001","评审","generated_expression","w"+"abcdef".charAt(i)));}six.append("]}");
        ok(fails(()->CeCore.validate(response(six.toString(),"stop"),sel)).equals("卡片数量或格式无效"),"more than count");
        ok(CeCore.offlineCards(3).size()==3&&CeCore.offlineCards(9).size()==5&&CeWire.cardValid(CeCore.card(CeCore.offlineCards(1).get(0))),"offline test cards");
        // History.
        Path dir=Files.createTempDirectory("ce-history");CeHistory h=new CeHistory(dir.resolve("reviews.json").toFile());List<CeWire.Card> cards=new ArrayList<>();for(Map<String,Object> c:good)cards.add(CeCore.card(c));
        ok(h.remember(cards,"AA","TOEFL",20750)&&h.reviews("AA","TOEFL",20750,5).isEmpty()&&h.reviews("AA","TOEFL",20751,5).size()==2&&h.reviews("AA","CET4",20751,5).isEmpty()&&h.reviews("BB","TOEFL",20751,5).isEmpty(),"due next day, per peer/target");
        ok(((String)h.reviews("AA","TOEFL",20751,5).get(0).get("sourceLabel")).startsWith("复习 · ")&&h.reviews("AA","TOEFL",20751,0).isEmpty(),"review label, limit 0");
        byte[] prog=progress(20751,1000,new long[]{CeHistory.word("postpone")},new int[]{CeWire.REMEMBERED});ok(h.progress(prog,"BB")&&h.reviews("AA","TOEFL",20752,5).size()==2,"other peer progress ignored");
        ok(h.progress(prog,"AA")&&h.reviews("AA","TOEFL",20752,5).size()==1&&h.reviews("AA","TOEFL",20754,5).size()==2,"remembered → due +3");
        ok(h.progress(progress(20751,1001,new long[]{CeHistory.word("postpone")},new int[]{CeWire.SKIPPED}),"AA")&&h.reviews("AA","TOEFL",20753,5).size()==1,"late reserved report ignored after an answer");
        ok(h.reviews("AA","TOEFL",20800,5).isEmpty(),"30-day window");
        List<CeWire.Card> lots=new ArrayList<>();for(int i=0;i<10;i++)lots.add(new CeWire.Card("word"+"abcdefghij".charAt(i),"q","m","e",true));for(int d=0;d<5;d++){List<CeWire.Card> day=new ArrayList<>();for(CeWire.Card c:lots)day.add(new CeWire.Card(c.english+"abcde".charAt(d),"q","m","e",true));ok(h.remember(day,"AA","CET4",20760),"remember batch "+d);}
        ok(BoundedJson.list(BoundedJson.map(BoundedJson.readLarge(Files.readAllBytes(dir.resolve("reviews.json")),131072,40000)).get("rows")).size()==40,"≤40 rows");
        ok(CeHistory.word("Postpone")==CeHistory.word("postpone")&&CeHistory.word("postpone")!=0,"word hash");
        Files.write(dir.resolve("reviews.json"),"{\"version\":2}".getBytes(StandardCharsets.UTF_8));ok(!h.remember(cards,"AA","TOEFL",20750)&&h.reviews("AA","TOEFL",20751,5).isEmpty(),"corrupt store refused, not overwritten");
        ok(h.clear()&&h.reviews("AA","TOEFL",20751,5).isEmpty(),"clear");
        System.out.println("CeCoreTest: "+n+" checks; selection, prompt, endpoint, validation, history");
    }
    static byte[] progress(long day,long tx,long[] words,int[] results){byte[] p=new byte[72];p[0]='T';p[1]='E';p[2]='P';p[3]='1';p[4]=1;p[5]=5;p[6]=(byte)words.length;w32(p,8,day);w32(p,12,tx);for(int i=0;i<words.length;i++){w32(p,16+4*i,words[i]);p[56+i]=(byte)results[i];}w32(p,68,CeWire.crc32(p,0,68));return p;}
    static void w32(byte[] p,int at,long v){for(int i=0;i<4;i++)p[at+i]=(byte)(v>>(8*i));}
}
