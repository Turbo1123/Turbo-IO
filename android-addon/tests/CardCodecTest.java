import com.turboio.addon.*;
import java.nio.file.*;
import java.util.*;
public class CardCodecTest {
    static int checks;static void yes(boolean b){checks++;if(!b)throw new AssertionError("Card check "+checks);}
    static void rejected(Runnable r){boolean failed=false;try{r.run();}catch(IllegalArgumentException e){failed=true;}yes(failed);}
    static Map<String,Object> copy(Map<String,Object> d){return BoundedJson.map(BoundedJson.read(BoundedJson.canonical(d)));}
    public static void main(String[] args)throws Exception{CardCodec.Icons icons=(i,s)->{byte[] b=new byte[s*s/8];Arrays.fill(b,(byte)(0xaa^i));return b;};Path out=Paths.get(args[0]);Files.createDirectories(out);
        for(int i=0;i<6;i++){Map<String,Object> d=CardCodec.template(i,"turbo_ui_card_test"+i);byte[] b=CardCodec.encode(d,icons);yes(b.length<=2048);yes((b[6]&255)+((b[7]&255)<<8)==b.length);Files.write(out.resolve("template"+i+".tce"),b);Files.write(out.resolve("template"+i+".json"),BoundedJson.canonical(d));Map<String,Object> bad=copy(d);bad.put("unknown",1);rejected(()->CardCodec.encode(bad,icons));for(String key:new String[]{"x","y","w","h"}){Map<String,Object> wrong=copy(d);BoundedJson.map(BoundedJson.list(wrong.get("components")).get(0)).put(key,7);rejected(()->CardCodec.encode(wrong,icons));}}
        Map<String,Object> d=CardCodec.template(5,"turbo_ui_card_test");for(Object v:new Object[]{true,14.0,15,30}){Map<String,Object> wrong=copy(d);BoundedJson.map(BoundedJson.list(wrong.get("components")).get(0)).put("font",v);rejected(()->CardCodec.encode(wrong,icons));}
        Map<String,Object> weather=CardCodec.object("id","weather","type","native"),todo=CardCodec.object("id","todo","type","native"),own=CardCodec.object("id","turbo_ui_card_test","type","a2ui"),before=CardCodec.object("widgets_v2",Arrays.asList(weather,todo),"simple_mode",true),after=CardCodec.object("widgets_v2",Arrays.asList(weather,own,todo),"simple_mode",true);yes(CardCodec.preserves(before,after,"turbo_ui_card_test"));Map<String,Object> ordered=CardCodec.first(after,"turbo_ui_card_test");yes(BoundedJson.list(ordered.get("widgets_v2")).get(0).equals(own));yes(CardCodec.preserves(before,ordered,"turbo_ui_card_test"));ordered.put("simple_mode",false);yes(!CardCodec.preserves(before,ordered,"turbo_ui_card_test"));
        byte[] packet=CardEnvelope.request(7392,CardCodec.install(d,icons));yes(packet.length<8192);yes(CardEnvelope.reply(packet)==null);packet[3]=19;packet[packet.length-1]=2;CardEnvelope.Reply r=CardEnvelope.reply(packet);yes(r!=null&&r.sequence==7392&&r.json.get("cmd").equals("widget_install"));for(int at:new int[]{0,1,2,3,4,packet.length-2,packet.length-1}){byte[] bad=packet.clone();bad[at]=(byte)255;yes(CardEnvelope.reply(bad)==null);}
        System.out.println("CardCodecTest: "+checks+" assertions; six native decoder fixtures generated");
    }
}
