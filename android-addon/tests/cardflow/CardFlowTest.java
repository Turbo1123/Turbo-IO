package com.turboio.addon;
import java.util.*;
import java.nio.charset.StandardCharsets;
import static com.turboio.addon.CardCodec.object;
public class CardFlowTest {
    static int checks;static void yes(boolean b){checks++;if(!b)throw new AssertionError("Flow "+checks+" "+CardTransport.status());}
    static CardEnvelope.Reply request(){byte[] b=NativeTransfer.packets.get(NativeTransfer.packets.size()-1).clone();b[3]=19;b[b.length-1]=2;return CardEnvelope.reply(b);}
    static void reply(Map<String,Object> j){long seq=request().sequence;byte[] b=CardEnvelope.request(seq,j);b[3]=19;b[b.length-1]=2;NativeTransfer.receiver.message(NativeTransfer.peer,b);}
    static void config(Map<String,Object> c){reply(object("cmd","dashboard_config","payload",object("data",new String(BoundedJson.canonical(c),StandardCharsets.UTF_8))));}
    static Map<String,Object> copy(Map<String,Object> c){return BoundedJson.map(BoundedJson.readDevice(BoundedJson.canonical(c)));}
    public static void main(String[] args){CardTransport.init();Map<String,Object> doc=CardCodec.template(5,"turbo_ui_card_test"),weather=object("id","weather","type","native"),todo=object("id","todo","type","native"),baseline=object("widgets_v2",Arrays.asList(weather,todo),"simple_mode",true);
        CardTransport.publish(doc,true);yes(CardTransport.busy());yes(request().json.get("cmd").equals("dashboard_config"));int n=NativeTransfer.packets.size();byte[] wrong=CardEnvelope.request(request().sequence+1,object("code",0));wrong[3]=19;wrong[wrong.length-1]=2;NativeTransfer.receiver.message(NativeTransfer.peer,wrong);yes(NativeTransfer.packets.size()==n&&CardTransport.busy());config(baseline);yes(request().json.get("cmd").equals("widget_install"));Map<String,Object> own=BoundedJson.map(BoundedJson.map(request().json.get("payload")).get("data"));reply(object("code",0));yes(request().json.get("cmd").equals("dashboard_config"));Map<String,Object> after=object("widgets_v2",Arrays.asList(weather,todo,own),"simple_mode",true);config(after);yes(request().json.get("cmd").equals("dashboard_update"));Map<String,Object> sorted=CardCodec.first(after,"turbo_ui_card_test");reply(object("cmd","dashboard_update","payload",object("value",0)));config(sorted);yes(!CardTransport.busy()&&NativeTransfer.lease.isEmpty());yes(CardTransport.status().contains("置顶"));NativeTransfer.MAIN.expire();yes(!CardTransport.busy());
        CardTransport.remove("turbo_ui_card_test");config(sorted);yes(request().json.get("cmd").equals("widget_uninstall"));reply(object("code",0));config(baseline);yes(!CardTransport.busy()&&CardTransport.status().contains("移除"));
        CardTransport.publish(doc,false);config(baseline);reply(object("code",0));Map<String,Object> changed=copy(after);changed.put("simple_mode",false);config(changed);yes(!CardTransport.busy()&&CardTransport.status().contains("不符"));
        CardTransport.publish(doc,true);config(baseline);reply(object("code",3));yes(!CardTransport.busy()&&CardTransport.status().contains("拒绝"));
        CardTransport.publish(doc,true);NativeTransfer.MAIN.expire();yes(!CardTransport.busy()&&CardTransport.status().contains("读取超时"));
        CardTransport.publish(doc,true);config(baseline);NativeTransfer.MAIN.expire();yes(!CardTransport.busy()&&CardTransport.status().contains("结果未知"));
        CardTransport.publish(doc,true);NativeTransfer.fail.run();yes(!CardTransport.busy()&&NativeTransfer.lease.isEmpty());
        Map<String,Object> conflict=object("widgets_v2",Arrays.asList(weather,object("id","turbo_ui_card_test","type","native")));CardTransport.publish(doc,true);n=NativeTransfer.packets.size();config(conflict);yes(!CardTransport.busy()&&NativeTransfer.packets.size()==n);
        CardTransport.publish(doc,false);config(baseline);Map<String,Object> equivalent=copy(own);equivalent.put("extras",((String)equivalent.get("extras")).replace("\":","\": "));reply(object("code",0));config(object("widgets_v2",Arrays.asList(weather,todo,equivalent),"simple_mode",true));yes(!CardTransport.busy()&&CardTransport.status().contains("其他卡片保留"));
        // Firmware may re-encode the stored widget (extras as object, name dropped); iOS TMIG1 accepts this too.
        CardTransport.publish(doc,false);config(baseline);Map<String,Object> reencoded=copy(own);reencoded.put("extras",BoundedJson.read(((String)reencoded.get("extras")).getBytes(StandardCharsets.UTF_8)));reencoded.remove("name");reply(object("code",0));config(object("widgets_v2",Arrays.asList(weather,todo,reencoded),"simple_mode",true));yes(!CardTransport.busy()&&CardTransport.status().contains("其他卡片保留"));
        // A correlated reply without the expected cmd/code is ignored, not treated as a mismatch.
        CardTransport.publish(doc,false);n=NativeTransfer.packets.size();reply(object("cmd","other"));yes(CardTransport.busy()&&NativeTransfer.packets.size()==n);config(baseline);reply(object("cmd","ack"));yes(CardTransport.busy());reply(object("code",0));config(after);yes(!CardTransport.busy()&&CardTransport.status().contains("其他卡片保留"));
        CardTransport.publish(doc,false);config(baseline);reply(object("code",0));config(changed);yes(CardTransport.status().contains("回读安装结果"));
        CardTransport.inspect();int readPackets=NativeTransfer.packets.size();config(baseline);yes(!CardTransport.busy()&&NativeTransfer.packets.size()==readPackets&&CardTransport.status().contains("未修改"));
        // Glasses-owned config as iOS NSJSONSerialization accepts it: decimals, >long ints, duplicate key, non-ASCII type.
        Map<String,Object> real=BoundedJson.map(BoundedJson.readDevice("{\"simple_mode\":true,\"brightness\":0.75,\"widgets_v2\":[{\"id\":\"weather\",\"type\":\"天气/native\",\"temp\":23.50,\"lat\":-31.2e1,\"ts\":18446744073709551616},{\"id\":\"todo\",\"type\":\"native\",\"id\":\"todo\"}]}".getBytes(StandardCharsets.UTF_8)));
        CardTransport.inspect();config(real);yes(!CardTransport.busy()&&CardTransport.status().contains("未修改")&&CardTransport.status().contains("天气"));
        CardTransport.publish(doc,true);config(real);yes(request().json.get("cmd").equals("widget_install"));Map<String,Object> realOwn=BoundedJson.map(BoundedJson.map(request().json.get("payload")).get("data"));reply(object("code",0));Map<String,Object> realAfter=copy(real);List<Object> rr=new ArrayList<>(BoundedJson.list(realAfter.get("widgets_v2")));rr.add(realOwn);realAfter.put("widgets_v2",rr);config(realAfter);yes(request().json.get("cmd").equals("dashboard_update"));
        Map<String,Object> sent=BoundedJson.map(BoundedJson.readDevice(((String)BoundedJson.map(request().json.get("payload")).get("data")).getBytes(StandardCharsets.UTF_8)));yes(sent.get("brightness").equals(new java.math.BigDecimal("0.75")));reply(object("cmd","dashboard_update","payload",object("value",0)));config(sent);yes(!CardTransport.busy()&&CardTransport.status().contains("置顶"));
        // Missing widgets_v2 names the keys the glasses actually sent.
        CardTransport.inspect();config(object("cards",new ArrayList<>()));yes(CardTransport.status().contains("读取原配置")&&CardTransport.status().contains("cards"));
        // Firmware without TVP2 dashboard compat (stock/TMIG1/TMG2 1.0.5.5) has no widgets_v2: stop before sending anything.
        Map<String,Object> legacy=BoundedJson.map(BoundedJson.readDevice("{\"simple_mode\":false,\"widgets\":[1,3,5],\"widgets_data\":{\"weather\":{\"temp\":21.5},\"clock\":{}}}".getBytes(StandardCharsets.UTF_8)));
        for(int op=0;op<3;op++){if(op==0)CardTransport.inspect();else if(op==1)CardTransport.publish(doc,true);else CardTransport.remove("turbo_ui_card_test");
         int packets=NativeTransfer.packets.size();config(legacy);yes(!CardTransport.busy()&&NativeTransfer.packets.size()==packets&&CardTransport.status().contains("需刷 TVP2"));}
        // TDC1 developer card goes through the same read → install → readback → pin flow.
        CardTransport.publishDevcard("TDC1;99;90;85;375;1280;1400;2000;0;1;2",true);config(baseline);yes(request().json.get("cmd").equals("widget_install"));
        Map<String,Object> dev=BoundedJson.map(BoundedJson.map(request().json.get("payload")).get("data"));yes("turbo_ui_devcard_v1".equals(dev.get("id")));reply(object("code",0));
        config(object("widgets_v2",Arrays.asList(weather,todo,dev),"simple_mode",true));yes(request().json.get("cmd").equals("dashboard_update"));
        reply(object("cmd","dashboard_update","payload",object("value",0)));config(CardCodec.first(object("widgets_v2",Arrays.asList(weather,todo,dev),"simple_mode",true),"turbo_ui_devcard_v1"));yes(!CardTransport.busy()&&CardTransport.status().contains("置顶"));
        int devPackets=NativeTransfer.packets.size();CardTransport.publishDevcard("TDC1;101;90;85;375;1280;1400;2000;0;1;2",true);yes(!CardTransport.busy()&&NativeTransfer.packets.size()==devPackets&&CardTransport.status().contains("未发送"));
        CardTransport.remove("turbo_ui_devcard_v1");config(baseline);yes(!CardTransport.busy()&&CardTransport.status().contains("没有这张卡片"));
        System.out.println("CardFlowTest: "+checks+" assertions, targeted install/readback/order/remove and fault paths");
    }
}
