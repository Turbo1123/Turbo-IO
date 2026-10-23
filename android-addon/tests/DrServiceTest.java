package com.turboio.addon;
import java.nio.charset.StandardCharsets;import java.util.*;import java.util.function.*;

/** Didi sandbox RPC parsing (iOS RideRPC.m) and the ride state machine (RideService.m). */
public final class DrServiceTest {
    static int n;static void ok(boolean b,String why){n++;if(!b)throw new AssertionError("didi service "+n+" "+why);}
    static Map<String,Object> m(Object...kv){Map<String,Object> r=new LinkedHashMap<>();for(int i=0;i<kv.length;i+=2)r.put((String)kv[i],kv[i+1]);return r;}
    static final class Fake implements DrService.Rpc,DrService.Bridge,DrService.Env{
        double now=1000;String peer="AA",key="k1",order;boolean unknown,busy;int last=DrWire.OK;List<DrWire.Scene> sent=new ArrayList<>();List<Object[]> calls=new ArrayList<>();
        public void call(String tool,Map<String,Object> args,BiConsumer<Map<String,Object>,String> done){calls.add(new Object[]{tool,args,done});}
        public boolean busy(){return busy;}public void send(DrWire.Scene s,Consumer<Boolean> done){sent.add(s.copy());done.accept(true);}public int lastResult(){return last;}public String note(){return "bridge";}
        public String peer(){return peer;}public String key(){return key;}public double now(){return now;}
        public String order(){return order;}public void order(String v){order=v;}public boolean unknown(){return unknown;}public void unknown(boolean v){unknown=v;}
        @SuppressWarnings("unchecked") void reply(Map<String,Object> r,String err){Object[] c=calls.get(calls.size()-1);((BiConsumer<Map<String,Object>,String>)c[2]).accept(r,err);}
        String tool(){return (String)calls.get(calls.size()-1)[0];}
    }
    public static void main(String[] a){
        // RPC parsing.
        String id="abc";
        ok(DrRpc.parse(("{\"jsonrpc\":\"2.0\",\"id\":\"abc\",\"result\":{\"structuredContent\":{\"orderId\":\"o1\"}}}").getBytes(StandardCharsets.UTF_8),id).result.get("orderId").equals("o1"),"JSON structured");
        ok(DrRpc.parse(("event: message\ndata: {\"id\":\"zzz\",\"result\":{}}\ndata: {\"jsonrpc\":\"2.0\",\"id\":\"abc\",\"result\":{\"content\":[{\"type\":\"text\",\"text\":\"[1,2]\"}]}}\n").getBytes(StandardCharsets.UTF_8),id).result.get("rows") instanceof List,"SSE, array → rows");
        ok(DrRpc.parse("{\"id\":\"abc\",\"result\":{\"content\":[{\"text\":\"司机已出发\"}]}}".getBytes(StandardCharsets.UTF_8),id).result.get("serverMessage").equals("司机已出发"),"prose → serverMessage");
        ok(DrRpc.parse("{\"id\":\"abc\",\"error\":{\"code\":-32001}}".getBytes(StandardCharsets.UTF_8),id).error.equals("沙箱接口错误（-32001）：限流，查询稍后再试；订单操作不自动重试"),"rate limit");
        ok(DrRpc.parse("{\"id\":\"abc\",\"error\":{\"code\":5}}".getBytes(StandardCharsets.UTF_8),id).error.equals("沙箱接口错误（5）：未自动重试"),"error code");
        ok(DrRpc.parse("{\"id\":\"other\",\"result\":{}}".getBytes(StandardCharsets.UTF_8),id).error.equals("沙箱 RPC 返回异常，未重试")&&DrRpc.parse("{\"id\":\"abc\",\"result\":{\"isError\":true}}".getBytes(StandardCharsets.UTF_8),id).error.equals("沙箱返回业务错误，未重试"),"mismatch / business error");
        String body=new String(DrRpc.body("abc","taxi_estimate",m("from_name","甲")),StandardCharsets.UTF_8);ok(body.contains("\"method\":\"tools/call\"")&&body.contains("\"name\":\"taxi_estimate\"")&&!DrRpc.allowed("taxi_pay"),"body / tool allow-list");
        // Service flow.
        Fake f=new Fake();DrService s=new DrService(f,f,f);List<Map<String,Object>> out=new ArrayList<>();Consumer<Map<String,Object>> done=out::add;
        s.tool(m("action","search","city","北京市","query","国贸"),done);ok(f.tool().equals("maps_textsearch"),"search rpc");
        List<Object> rows=new ArrayList<>();for(int i=0;i<10;i++)rows.add(m("display_name","地点"+i,"location",m("lng","116."+i,"lat","39.9")));rows.add(m("display_name","坏点","location",m("lng","abc","lat","1")));
        f.reply(m("rows",rows),null);List<?> places=(List<?>)out.get(0).get("places");ok(places.size()==8&&out.get(0).get("status").equals("choose_place"),"≤8 valid places");
        String p0=(String)((Map<?,?>)places.get(0)).get("id"),p1=(String)((Map<?,?>)places.get(1)).get("id");
        s.tool(m("action","estimate","from_id",p0,"to_id",p0),done);ok(out.get(1).get("status").equals("not_ready"),"same place refused");
        s.tool(m("action","estimate","from_id",p0,"to_id",p1),done);ok(f.tool().equals("taxi_estimate"),"estimate rpc");
        f.reply(m("traceId","t9","items",Arrays.asList(m("productCategory",201L,"productName","快车","priceText","32元"),m("productCategory","x"))),null);
        List<?> prods=(List<?>)out.get(2).get("products");ok(prods.size()==1&&((Map<?,?>)prods.get(0)).get("id").equals("201"),"products");
        int sends=f.sent.size();s.tool(m("action","prepare","product_id","201"),done);DrWire.Scene card=f.sent.get(f.sent.size()-1);
        ok(out.get(3).get("status").equals("awaiting_confirmation")&&card.phase==DrWire.QUOTE&&(card.flags&DrWire.CONFIRM)!=0&&card.nonce!=0&&card.metric.equals("32元")&&card.line1.equals("起：地点0")&&f.sent.size()==sends+1&&s.pending(),"confirm card on glasses");
        int calls=f.calls.size();DrWire.Reply wrong=new DrWire.Reply();wrong.event=DrWire.CONFIRMED;wrong.nonce=card.nonce+1;wrong.phase=DrWire.QUOTE;s.glassesEvent(wrong);ok(f.calls.size()==calls,"wrong nonce ignored");
        DrWire.Reply right=new DrWire.Reply();right.event=DrWire.CONFIRMED;right.nonce=card.nonce;right.phase=DrWire.QUOTE;s.glassesEvent(right);
        ok(f.calls.size()==calls+1&&f.tool().equals("taxi_create_order")&&f.unknown&&((Map<?,?>)f.calls.get(calls)[1]).get("estimate_trace_id").equals("t9"),"right nonce commits, unknown persisted first");
        s.glassesEvent(right);s.confirmOnPhone();ok(f.calls.size()==calls+1,"commits once");
        f.reply(m("orderId","o-1"),null);ok(!f.unknown&&"o-1".equals(f.order)&&f.sent.get(f.sent.size()-1).phase==DrWire.MATCHING,"created");
        f.now+=2.5;s.tick();ok(f.tool().equals("taxi_query_order"),"status query 2 s after creation");
        f.reply(m("statusCode",1L,"driver",m("name","张师傅","carModel","黑色轿车","carPlate","测A12345"),"map",m("eta","8","distanceKm","2.1")),null);
        DrWire.Scene st=f.sent.get(f.sent.size()-1);ok(st.phase==DrWire.PICKUP&&st.metric.equals("8分钟")&&st.title.equals("司机正在赶来")&&st.line2.equals("测A12345"),"status code → phase");
        int c2=f.calls.size();out.clear();s.tool(m("action","status"),done);ok(f.calls.size()==c2&&out.get(0).get("status").equals("sandbox_status"),"poll interval respected");
        f.now+=31;s.tick();f.reply(m("serverMessage","司机已到达上车点"),null);ok(f.sent.get(f.sent.size()-1).phase==DrWire.PICKUP&&s.note().startsWith("沙箱接口文字（不据此改变订单状态）"),"prose keeps phase");
        f.now+=61;s.tick();f.reply(m("statusCode",5L),null);ok(f.order==null&&f.sent.get(f.sent.size()-1).phase==DrWire.DONE,"done clears order");
        // Failure: unknown blocks new orders.
        Fake g=new Fake();DrService t=new DrService(g,g,g);List<Map<String,Object>> o2=new ArrayList<>();t.tool(m("action","search","city","c","query","q"),o2::add);g.reply(m("rows",rows.subList(0,2)),null);
        String a0=(String)((Map<?,?>)((List<?>)o2.get(0).get("places")).get(0)).get("id"),a1=(String)((Map<?,?>)((List<?>)o2.get(0).get("places")).get(1)).get("id");
        t.tool(m("action","estimate","from_id",a0,"to_id",a1),o2::add);g.reply(m("traceId","t","items",Arrays.asList(m("productCategory","1","productName","快车","priceText","9元"))),null);
        t.tool(m("action","prepare","product_id","1"),o2::add);t.confirmOnPhone();g.reply(null,"沙箱网络失败（-1）；未自动重试");
        ok(g.unknown&&t.note().equals("提交结果未知，禁止重复下单；请核对沙箱订单"),"failed create stays unknown");
        t.tool(m("action","estimate","from_id",a0,"to_id",a1),o2::add);ok(o2.get(o2.size()-1).get("status").equals("not_ready"),"unknown blocks the next estimate");
        // Consent invalidation: peer change, expiry, quote age.
        Fake h=new Fake();DrService u=new DrService(h,h,h);List<Map<String,Object>> o3=new ArrayList<>();u.tool(m("action","search","city","c","query","q"),o3::add);h.reply(m("rows",rows.subList(0,2)),null);
        String b0=(String)((Map<?,?>)((List<?>)o3.get(0).get("places")).get(0)).get("id"),b1=(String)((Map<?,?>)((List<?>)o3.get(0).get("places")).get(1)).get("id");
        u.tool(m("action","estimate","from_id",b0,"to_id",b1),o3::add);h.reply(m("traceId","t","items",Arrays.asList(m("productCategory","1","productName","快车","priceText","9元"))),null);
        u.tool(m("action","prepare","product_id","1"),o3::add);h.peer="BB";u.tick();int c3=h.calls.size();u.confirmOnPhone();ok(!u.pending()&&h.calls.size()==c3,"peer change invalidates consent");
        h.peer="AA";h.now+=61;u.tool(m("action","prepare","product_id","1"),o3::add);ok(o3.get(o3.size()-1).get("status").equals("expired"),"quote older than 60 s");
        // Demo cards never call the API.
        Fake d=new Fake();DrService demo=new DrService(d,d,d);demo.previewNext();demo.previewNext();ok(d.calls.isEmpty()&&d.sent.size()==2&&d.sent.get(1).phase==DrWire.QUOTE&&(d.sent.get(1).flags&DrWire.CONFIRM)==0,"demo cards");
        System.out.println("DrServiceTest: "+n+" checks; RPC parse, flow, once-only commit, unknown, consent, demo");
    }
}
