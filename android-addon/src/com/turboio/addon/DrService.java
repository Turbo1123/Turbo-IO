package com.turboio.addon;
import java.security.SecureRandom;
import java.util.*;
import java.util.function.*;

/** Didi sandbox ride state machine (port of iOS RideService.m). Places and products only come from the sandbox;
 * an order is created or cancelled at most once per glasses/phone confirmation (fresh nonce, 60 s, bound to the
 * glasses peer and key); an unknown result is persisted and blocks new orders. Status prose is display-only.
 * Main executor only; time is monotonic seconds. */
final class DrService {
    interface Rpc{void call(String tool,Map<String,Object> args,BiConsumer<Map<String,Object>,String> done);}
    interface Bridge{boolean busy();void send(DrWire.Scene scene,Consumer<Boolean> done);int lastResult();String note();}
    interface Env{String peer();String key();double now();String order();void order(String id);boolean unknown();void unknown(boolean v);}
    private static final SecureRandom RANDOM=new SecureRandom();
    private final Rpc rpc;private final Bridge bridge;private final Env env;
    private final Map<String,Map<String,Object>> lookup=new HashMap<>();
    private List<Map<String,Object>> places=new ArrayList<>(),products=new ArrayList<>();private Map<String,Object> quote,from,to,order,commit;
    private String orderId,note,peer,credential;private long nonce;private boolean busy,pending,unknown,used,queued,queueShow;
    private double quoteAt,consentAt,polled,statusAt,pollDelay,retryAt,retryUntil,queryAt;private int step;
    private final DrWire.Scene scene=new DrWire.Scene();
    DrService(Rpc rpc,Bridge bridge,Env env){
        this.rpc=rpc;this.bridge=bridge;this.env=env;scene.ttl=60;scene.phase=DrWire.IDLE;scene.title="想去哪里？";scene.metric="出行";scene.line1="说出起点和目的地";scene.line2="也可从手机发起";scene.footer="长按退出";
        orderId=env.order();unknown=env.unknown();
    }
    String note(){return note!=null?note:(unknown?"上次提交结果未知；禁止重复下单，请到沙箱控制台核对":"仅沙箱 · 不会产生真实行程。先搜索并选定地点，再获取报价。");}
    List<Map<String,Object>> places(){return places;}List<Map<String,Object>> products(){return products;}Map<String,Object> order(){return order;}
    boolean busy(){return busy;}DrWire.Scene scene(){return scene.copy();}
    boolean pending(){return pending&&!used&&env.now()-consentAt<60;}
    private static String str(Object x){return x instanceof String?(String)x:x instanceof Number?DrText.clean(x,64):"";}
    private void field(String which,Object v){int cap=which.equals("metric")?32:which.equals("title")||which.equals("footer")?64:96;String t=DrText.text(v,cap);
        switch(which){case "metric":scene.metric=t;break;case "title":scene.title=t;break;case "line1":scene.line1=t;break;case "line2":scene.line2=t;break;default:scene.footer=t;}}
    void invalidateConsent(){pending=false;used=true;queued=false;queueShow=false;retryUntil=0;commit=null;nonce=0;scene.flags&=~DrWire.CONFIRM;scene.nonce=0;field("footer","确认已失效，请重新获取报价");}
    void tick(){
        double now=env.now();
        if(pending&&(now-consentAt>=60||!Objects.equals(peer,env.peer())||!Objects.equals(credential,env.key()))){invalidateConsent();note="确认已过期或连接/配置变化，请重新确认";queued=true;queueShow=false;}
        if(queued&&!bridge.busy()&&now>=retryAt){queued=false;display(queueShow);}
        if(queryAt>0&&now>=queryAt&&!busy){queryAt=0;query(r->{});return;}
        int phase=scene.phase;
        if(!busy&&!pending&&orderId!=null&&!orderId.isEmpty()&&phase>=DrWire.MATCHING&&phase<=DrWire.TRIP&&now-polled>=Math.max(pollDelay,(phase==DrWire.MATCHING||phase==DrWire.PICKUP)?30:60))query(r->{});
    }
    private void display(boolean show){
        if(show)scene.flags|=DrWire.SHOW;else scene.flags&=~DrWire.SHOW;
        if(bridge.busy()){queued=true;queueShow=show;return;}
        bridge.send(scene.copy(),ok->{if(!ok){note=bridge.note();if(show&&bridge.lastResult()==DrWire.BUSY&&env.now()<retryUntil){queued=true;queueShow=true;retryAt=env.now()+2;}}});
    }
    void previewNext(){
        if(busy||pending||(orderId!=null&&!orderId.isEmpty())||unknown){note="有待确认、进行中或结果未知的订单，先核对后再预览";return;}
        int[] phases={DrWire.IDLE,DrWire.QUOTE,DrWire.MATCHING,DrWire.PICKUP,DrWire.ARRIVED,DrWire.TRIP,DrWire.DONE};int i=step++%7;
        scene.phase=phases[i];scene.flags=0;scene.nonce=0;scene.ttl=60;
        field("metric",new String[]{"出行","32元","匹配中","8分钟","已到达","12分钟","已完成"}[i]);field("title",new String[]{"想去哪里？","快车 · 示例报价","正在匹配司机","司机正在赶来","请前往上车点","行程进行中","本机演示结束"}[i]);
        field("line1",i<3?"起：测试上车点":"体验模式司机 · 黑色轿车");field("line2",i==5?"剩余 5.2 公里":i<3?"终：测试目的地":"测A·12345");field("footer","本机演示 · 非API结果 · 长按退出");
        note="仅发送显示示例，不查询接口、不创建订单";showOnGlasses();
    }
    void showOnGlasses(){retryUntil=env.now()+20;display(true);}
    void glassesEvent(DrWire.Reply q){
        if(q.event==DrWire.CLOSED){invalidateConsent();return;}
        if(q.event==DrWire.OPENED){if(orderId!=null&&!orderId.isEmpty()&&!busy&&!pending)query(r->{});else display(false);return;}
        if(q.event==DrWire.CONFIRMED&&q.nonce==nonce&&q.phase==scene.phase)commit();
    }
    void confirmOnPhone(){commit();}
    private void request(String tool,Map<String,Object> args,BiConsumer<Map<String,Object>,String> done){busy=true;rpc.call(tool,args,(r,e)->{busy=false;done.accept(r,e);});}
    private Map<String,Object> result(String status,String message){Map<String,Object> r=new LinkedHashMap<>();r.put("status",status);r.put("sandbox",true);r.put("real_order",false);r.put("message",message==null?"":message);r.put("retry_order_allowed",false);return r;}
    private static Map<String,Object> m(Object...kv){Map<String,Object> r=new LinkedHashMap<>();for(int i=0;i<kv.length;i+=2)r.put((String)kv[i],kv[i+1]);return r;}
    private static double coordinate(String s){try{return s.trim().equals(s)&&!s.isEmpty()?Double.parseDouble(s):Double.NaN;}catch(NumberFormatException e){return Double.NaN;}}
    void tool(Map<String,Object> args,Consumer<Map<String,Object>> done){
        if(busy){done.accept(result("busy","接口忙碌，未重复调用"));return;}
        Object action=args.get("action");
        if("status".equals(action)){query(done);return;}
        if("prepare_cancel".equals(action)){
            if(orderId==null||orderId.isEmpty()||unknown||scene.phase==DrWire.TRIP){done.accept(result("not_ready","没有可确认的订单，或上次结果未知"));return;}
            prepare(m("order_id",orderId,"reason","用户确认取消沙箱测试订单"),true);done.accept(result("awaiting_confirmation",note()));return;
        }
        if("search".equals(action)){
            if(pending){invalidateConsent();display(false);}
            request("maps_textsearch",m("city",args.get("city"),"keywords",args.get("query")),(r,err)->{
                if(err!=null){note=err;done.accept(result("failed",err));return;}
                Object rows=r==null?null:r.get("rows");if(lookup.size()>48)lookup.clear();List<Map<String,Object>> safe=new ArrayList<>();
                if(rows instanceof List)for(Object row:(List<?>)rows){if(!(row instanceof Map)||!(((Map<?,?>)row).get("location") instanceof Map))continue;Map<?,?> loc=(Map<?,?>)((Map<?,?>)row).get("location");
                    String name=DrText.clean(((Map<?,?>)row).get("display_name"),120),lng=str(loc.get("lng")),lat=str(loc.get("lat"));double x=coordinate(lng),y=coordinate(lat);
                    if(name.isEmpty()||Double.isNaN(x)||Double.isNaN(y)||Double.isInfinite(x)||Double.isInfinite(y)||Math.abs(x)>180||Math.abs(y)>90)continue;
                    String pid=UUID.randomUUID().toString();lookup.put(pid,m("id",pid,"name",name,"lng",lng,"lat",lat));safe.add(m("id",pid,"name",name));if(safe.size()==8)break;}
                places=safe;note="沙箱地点可能是固定测试数据，请选择返回的地点，不代表真实搜索命中";
                Map<String,Object> out=m("status","choose_place","sandbox",true,"places",safe,"message",note());done.accept(out);});
            return;
        }
        if("estimate".equals(action)){
            Map<String,Object> a=lookup.get(args.get("from_id")),b=lookup.get(args.get("to_id"));
            if(a==null||b==null||a.get("id").equals(b.get("id"))||unknown||(orderId!=null&&!orderId.isEmpty())){done.accept(result("not_ready","请选不同的有效地点，并先结束或核对上一订单"));return;}
            invalidateConsent();from=a;to=b;products=new ArrayList<>();quote=null;
            request("taxi_estimate",m("from_name",a.get("name"),"from_lng",a.get("lng"),"from_lat",a.get("lat"),"to_name",b.get("name"),"to_lng",b.get("lng"),"to_lat",b.get("lat")),(r,err)->{
                List<Map<String,Object>> items=new ArrayList<>();
                if(err==null&&r!=null&&!str(r.get("traceId")).isEmpty()&&r.get("items") instanceof List)for(Object v:(List<?>)r.get("items")){if(!(v instanceof Map))continue;Map<?,?> x=(Map<?,?>)v;
                    String pid=str(x.get("productCategory")),name=DrText.clean(x.get("productName"),40),price=DrText.clean(x.get("priceText"),40);if(price.isEmpty())price=DrText.clean(x.get("priceDiscounted"),40);
                    if(!pid.isEmpty()&&!name.isEmpty()&&!price.isEmpty())items.add(m("id",pid,"name",name,"price",price));if(items.size()==8)break;}
                products=items;quote=r;quoteAt=env.now();note=!items.isEmpty()?"请选择车型，然后在眼镜或手机确认沙箱叫车":(err!=null?err:"报价为空，不能叫车");
                done.accept(m("status",items.isEmpty()?"failed":"choose_product","sandbox",true,"products",items,"message",note()));});
            return;
        }
        if("prepare".equals(action)){
            if(unknown||(orderId!=null&&!orderId.isEmpty())||env.now()-quoteAt>60){done.accept(result("expired","报价已过期或已有订单，请核对后重新预估"));return;}
            Map<String,Object> chosen=null;for(Map<String,Object> p:products)if(p.get("id").equals(args.get("product_id")))chosen=p;
            if(chosen==null){done.accept(result("invalid","请选择实际报价中的车型"));return;}
            field("title",chosen.get("name")+" · 预估");field("metric",chosen.get("price"));field("line1","起："+from.get("name"));field("line2","终："+to.get("name"));
            prepare(m("estimate_trace_id",str(quote.get("traceId")),"product_category",chosen.get("id")),false);done.accept(result("awaiting_confirmation",note()));return;
        }
        done.accept(result("invalid","无效动作"));
    }
    private void prepare(Map<String,Object> args,boolean cancel){
        invalidateConsent();commit=new LinkedHashMap<>(args);nonce=1+(RANDOM.nextInt()&0x7fffffffL)%0xfffffffeL;peer=env.peer();credential=env.key();pending=true;used=false;consentAt=env.now();retryUntil=consentAt+20;
        scene.phase=cancel?DrWire.CANCEL_CONFIRM:DrWire.QUOTE;scene.flags=DrWire.CONFIRM;scene.ttl=60;scene.nonce=nonce;
        if(cancel){field("title","确认取消沙箱订单？");field("metric","取消？");field("line1","取消后不能恢复该订单");field("line2","返回不会取消行程");}
        field("footer","旋钮选确认，再短按提交");note="等待确认：眼镜默认选返回，旋钮选确认后短按；60 秒有效。不会真实叫车。";display(true);
    }
    private void commit(){
        double now=env.now();
        if(busy||!pending()||(scene.phase==DrWire.QUOTE&&now-quoteAt>=120)||!Objects.equals(credential,env.key())||!Objects.equals(peer,env.peer())){note="确认已失效或连接变化，未提交";return;}
        Map<String,Object> args=commit;boolean cancel=scene.phase==DrWire.CANCEL_CONFIRM;used=true;pending=false;commit=null;unknown=true;env.unknown(true);
        scene.flags=0;scene.nonce=0;field("footer","正在提交 · 请勿重复操作");display(false);
        request(cancel?"taxi_cancel_order":"taxi_create_order",args,(r,err)->{
            String oid=r==null?"":str(r.get("orderId"));boolean ok=cancel?(r!=null&&Boolean.TRUE.equals(r.get("success"))):!oid.isEmpty();
            if(err!=null||!ok){note="提交结果未知，禁止重复下单；请核对沙箱订单";field("footer","结果未知 · 请在手机核对");display(false);return;}
            unknown=false;env.unknown(false);
            if(cancel){orderId=null;env.order(null);scene.phase=DrWire.CANCELLED;note="沙箱返回取消结果，请刷新核对";}
            else{orderId=oid;polled=0;env.order(oid);scene.phase=DrWire.MATCHING;note="沙箱已创建测试订单，等待查询状态；不是实际叫车";}
            order=r;field("title",cancel?"沙箱订单已取消":"正在匹配测试司机");field("metric",cancel?"已取消":"匹配中");field("footer","短按刷新 · 长按退出");display(true);
            if(!cancel)queryAt=env.now()+2;});
    }
    Map<String,Object> statusResult(){
        Map<?,?> d=order!=null&&order.get("driver") instanceof Map?(Map<?,?>)order.get("driver"):Collections.emptyMap(),mp=order!=null&&order.get("map") instanceof Map?(Map<?,?>)order.get("map"):Collections.emptyMap();
        return m("status","sandbox_status","sandbox",true,"real_order",false,"statusCode",order!=null&&order.get("statusCode")!=null?order.get("statusCode"):-1L,"driver",DrText.clean(d.get("name"),30),"car",DrText.clean(d.get("carModel"),50),
            "plate",DrText.clean(d.get("carPlate"),30),"etaMinutes",DrText.clean(mp.get("eta"),20),"distanceKm",DrText.clean(mp.get("distanceKm"),20),"message",note(),"ageSeconds",(long)Math.max(0,env.now()-statusAt));
    }
    void query(Consumer<Map<String,Object>> done){
        if(pending){done.accept(result("awaiting_confirmation",note()));return;}if(busy){done.accept(result("busy",note()));return;}
        if(orderId==null||orderId.isEmpty()){done.accept(result(unknown?"unknown":"no_order",note()));return;}
        double interval=Math.max(pollDelay,(order==null||!"sandbox-text".equals(order.get("sourceFormat")))&&(scene.phase==DrWire.MATCHING||scene.phase==DrWire.PICKUP)?30:60);
        if(polled>0&&env.now()-polled<interval){done.accept(statusResult());return;}
        polled=env.now();
        request("taxi_query_order",m("order_id",orderId),(r,err)->{
            if(err!=null){pollDelay=Math.min(300,Math.max(60,pollDelay*2));note=err;done.accept(result("unavailable",err));return;}
            pollDelay=0;Map<String,Object> norm=DrText.normalizeOrder(r);order=norm;Object raw=norm==null?null:norm.get("statusCode");
            if(!(raw instanceof Number)){String message=norm==null?null:(String)norm.get("displayText");
                if(message==null||message.isEmpty()){note="没有收到可显示的订单消息";done.accept(result("unavailable",note()));return;}
                statusAt=env.now();String[] lines=DrText.messageLines(message);if(scene.phase<DrWire.MATCHING||scene.phase>DrWire.TRIP)scene.phase=DrWire.MATCHING;
                scene.flags=0;scene.nonce=0;scene.ttl=90;field("title","订单消息");field("metric","沙箱");field("line1",lines[0]);field("line2",lines[1]);field("footer","摘要 · 手机查看全文 · 长按退出");
                note="沙箱接口文字（不据此改变订单状态）：\n"+message;display(false);done.accept(statusResult());return;}
            statusAt=env.now();long state=((Number)raw).longValue();int old=scene.phase;
            Map<?,?> driver=norm.get("driver") instanceof Map?(Map<?,?>)norm.get("driver"):Collections.emptyMap(),map=norm.get("map") instanceof Map?(Map<?,?>)norm.get("map"):Collections.emptyMap();
            scene.phase=state==0?DrWire.MATCHING:state==1?DrWire.PICKUP:state==2?DrWire.ARRIVED:state==4?DrWire.TRIP:state==5?DrWire.DONE:DrWire.ERROR;scene.flags=0;scene.nonce=0;scene.ttl=90;
            field("title",state==0?"正在匹配司机":state==1?"司机正在赶来":state==2?"司机已到达":state==4?"行程进行中":state==5?"行程已结束":"订单状态需核对");
            field("metric",!str(map.get("eta")).isEmpty()?str(map.get("eta"))+"分钟":"沙箱");field("line1",DrText.clean(driver.get("name"),16)+" "+DrText.clean(driver.get("carModel"),30));
            field("line2",state==4?"剩余 "+DrText.clean(map.get("distanceKm"),20)+" 公里":DrText.clean(driver.get("carPlate"),30));field("footer","短按刷新 · 长按退出");
            note="沙箱状态已刷新；返回眼镜菜单不会取消订单";if(state==5){orderId=null;env.order(null);}
            display(old!=scene.phase);done.accept(statusResult());});
    }
}
