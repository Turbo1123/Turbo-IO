package com.turboio.addon;
import java.util.*;
import java.nio.charset.StandardCharsets;
import static com.turboio.addon.CardCodec.object;
public class CardFlowTest {
    static int checks;static void yes(boolean b){checks++;if(!b)throw new AssertionError("Flow "+checks+" "+CardTransport.status());}
    static CardEnvelope.Reply request(){byte[] b=NativeTransfer.packets.get(NativeTransfer.packets.size()-1).clone();b[3]=19;b[b.length-1]=2;return CardEnvelope.reply(b);}
    static void reply(Map<String,Object> j){long seq=request().sequence;byte[] b=CardEnvelope.request(seq,j);b[3]=19;b[b.length-1]=2;NativeTransfer.receiver.message(NativeTransfer.peer,b);}
    static void config(Map<String,Object> c){reply(object("cmd","dashboard_config","payload",object("data",new String(BoundedJson.canonical(c),StandardCharsets.UTF_8))));}
    static Map<String,Object> copy(Map<String,Object> c){return BoundedJson.map(BoundedJson.read(BoundedJson.canonical(c)));}
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
        CardTransport.inspect();int readPackets=NativeTransfer.packets.size();config(baseline);yes(!CardTransport.busy()&&NativeTransfer.packets.size()==readPackets&&CardTransport.status().contains("未修改"));
        System.out.println("CardFlowTest: "+checks+" assertions, targeted install/readback/order/remove and fault paths");
    }
}
