package com.turboio.addon;
import java.nio.charset.StandardCharsets;import java.nio.file.*;import java.util.*;

/** Didi sandbox wire/text/tool (golden vs TVP2 didi-v1 ride.c; iOS RideStatus.m / RideTool.m). */
public final class DrCoreTest {
    static int n;static void ok(boolean b,String why){n++;if(!b)throw new AssertionError("didi core "+n+" "+why);}
    static DrWire.Scene scene(){DrWire.Scene s=new DrWire.Scene();s.phase=DrWire.QUOTE;s.flags=DrWire.SHOW|DrWire.CONFIRM;s.ttl=60;s.nonce=0xA1B2C3D4L;s.metric="32元";s.title="快车 · 预估";s.line1="起：测试上车点";s.line2="终：测试目的地";s.footer="旋钮选确认，再短按提交";return s;}
    public static void main(String[] a)throws Exception{
        Path g=Paths.get(a[0]);
        ok(Arrays.equals(DrWire.encode(DrWire.SNAPSHOT,1792990000L,7,scene()),Files.readAllBytes(g.resolve("snapshot.bin"))),"snapshot golden");
        ok(Arrays.equals(DrWire.encode(DrWire.CLOSE,1792990000L,8,null),Files.readAllBytes(g.resolve("close.bin")))&&Arrays.equals(DrWire.encode(DrWire.QUERY,1792990000L,9,null),Files.readAllBytes(g.resolve("query.bin"))),"close/query golden");
        byte[] r=Files.readAllBytes(g.resolve("reply.bin"));DrWire.Reply q=DrWire.reply(r);
        ok(q!=null&&q.result==DrWire.OK&&q.event==DrWire.CONFIRMED&&q.sid==1792990000L&&q.seq==7&&q.nonce==0xA1B2C3D4L&&q.phase==DrWire.QUOTE&&q.consumed,"DRA1 fields");
        for(int i=0;i<r.length*8;i++){byte[] b=r.clone();b[i/8]^=1<<(i%8);ok(DrWire.reply(b)==null,"reply flip "+i);}
        String[] lines=new String(Files.readAllBytes(g.resolve("scenes.txt")),StandardCharsets.UTF_8).trim().split("\n");
        for(String line:lines){int k=Integer.parseInt(line.split(" ")[0]);boolean want=line.endsWith(" 1");DrWire.Scene s=scene();
            switch(k){case 1:s.ttl=14;break;case 2:s.ttl=121;break;case 3:s.nonce=0;break;case 4:s.phase=DrWire.TRIP;break;case 5:s.flags=4;break;case 6:s.title="\u0001"+s.title.substring(1);break;case 7:s.flags=DrWire.SHOW;s.phase=DrWire.TRIP;s.nonce=0;break;default:}
            ok((DrWire.encode(DrWire.SNAPSHOT,1,1,s)!=null)==want,"scene rule "+k);}
        DrWire.Scene big=scene();big.title=new String(new char[64]).replace('\0','a');ok(DrWire.encode(DrWire.SNAPSHOT,1,1,big)==null,"field must leave a NUL");
        // Bounded display text: whole characters, under cap-1 bytes, controls become spaces.
        String t=DrText.text("出行出行出行出行出行出行出行",32);ok(t.getBytes(StandardCharsets.UTF_8).length<32&&t.equals("出行出行出行出行出行"),"text cap "+t);
        ok(DrText.text("a\u0001b",32).equals("a b")&&DrText.text("😀😀😀😀😀😀😀😀",32).equals("😀😀😀😀😀😀😀"),"controls and surrogates");
        // SafeMessage via normalizeOrder.
        Map<String,Object> m=new HashMap<>();m.put("serverMessage","司机：张师傅\n手机号 13800000000\n订单号 ABC\n查看 https://x.example/a?b\n联系 13912345678 尽快\n\u0007结束");
        Map<String,Object> norm=DrText.normalizeOrder(m);String shown=(String)norm.get("displayText");
        ok(norm.get("sourceFormat").equals("sandbox-text")&&shown.equals("司机：张师傅\n查看 [已隐藏]\n联系 [已隐藏] 尽快\n 结束"),"safe message "+shown);
        Map<String,Object> code=new HashMap<>();code.put("statusCode",1L);ok(DrText.normalizeOrder(code)==code,"structured passes");
        ok(DrText.normalizeOrder(new HashMap<>())==null,"no message");
        String[] ml=DrText.messageLines("一二三四五六七八九十一二三四五六七八九十一二三四五六七八九十一二三四五六七八九十");
        ok(ml[0].equals("一二三四五六七八九十一二三四五六七八")&&ml[1].equals("九十一二三四五六七八九十一二三四五…"),"message lines "+ml[1]);
        ok(DrText.messageLines("短 消息\n第二")[0].equals("短 消息 第二")&&DrText.messageLines("短")[1].isEmpty(),"short lines");
        // Tool.
        ok(DrTool.SPEC.contains("\"name\":\"didi_ride\"")&&DrTool.SPEC.contains("滴滴出行沙箱（非真实订单）"),"spec");BoundedJson.readDevice(DrTool.SPEC.getBytes(StandardCharsets.UTF_8));
        ok(DrTool.arguments("{\"action\":\"search\",\"city\":\"北京市\",\"query\":\"国贸\"}")!=null&&DrTool.arguments("{\"action\":\"status\"}")!=null,"valid args");
        ok(DrTool.arguments("{\"action\":\"search\",\"city\":\"北京市\"}")==null&&DrTool.arguments("{\"action\":\"status\",\"x\":\"1\"}")==null&&DrTool.arguments("{\"action\":\"book\"}")==null&&DrTool.arguments("{\"action\":\"prepare\",\"product_id\":\"\"}")==null&&DrTool.arguments("{\"action\":\"prepare\",\"product_id\":\"a\\nb\"}")==null,"invalid args");
        System.out.println("DrCoreTest: "+n+" checks; TDR1/DRA1 golden, scene rules, text, tool");
    }
}
