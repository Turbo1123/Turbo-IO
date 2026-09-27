import com.turboio.addon.*;
import java.nio.file.*;
import java.nio.*;
import java.util.*;
import java.util.zip.CRC32;
public class NativeNavTest {
    static int checks;static void yes(boolean b){checks++;if(!b)throw new AssertionError("TNV1 #"+checks);}static void bad(Runnable r){boolean thrown=false;try{r.run();}catch(IllegalArgumentException e){thrown=true;}yes(thrown);}
    static NativeNavCodec.Scene scene(){NativeNavCodec.Scene s=new NativeNavCodec.Scene();s.icon=3;s.mode=1;s.heading=90;s.distance=80;s.remaining=2048;s.seconds=420;s.x=512;s.y=800;s.points=new int[][]{{512,800},{700,200},{1023,0}};s.road="模拟 · 测试道路";s.turn="前方右转";return s;}
    static NativeNavCodec.Reply response(long seq,boolean active){byte[] b=reply.clone();ByteBuffer q=ByteBuffer.wrap(b).order(ByteOrder.LITTLE_ENDIAN);q.putInt(12,(int)seq);b[6]=(byte)(active?3:0);CRC32 crc=new CRC32();crc.update(b,0,28);q.putInt(28,(int)crc.getValue());return NativeNavCodec.reply(b);}
    static byte[] reply;public static void main(String[] args)throws Exception{Path path=Paths.get(args[0]);for(int op=1;op<=6;op++){byte[] b=NativeNavCodec.packet(op,123,42,scene());yes(Arrays.equals(b,Files.readAllBytes(path.resolve("command-"+op+".bin"))));}reply=Files.readAllBytes(path.resolve("reply.bin"));yes(NativeNavCodec.reply(reply).active);for(int i=0;i<32;i++){byte[] b=reply.clone();b[i]^=1;yes(NativeNavCodec.reply(b)==null);}for(int n=0;n<32;n++)yes(NativeNavCodec.reply(Arrays.copyOf(reply,n))==null);
        bad(()->NativeNavCodec.packet(1,0,1,scene()));bad(()->NativeNavCodec.packet(1,1,0,scene()));bad(()->{NativeNavCodec.Scene s=scene();s.points=new int[33][2];NativeNavCodec.scene(s);});bad(()->{NativeNavCodec.Scene s=scene();s.road="x\n";NativeNavCodec.scene(s);});bad(()->{NativeNavCodec.Scene s=scene();s.turn="\ud800";NativeNavCodec.scene(s);});bad(()->{NativeNavCodec.Scene s=scene();s.x=1024;NativeNavCodec.scene(s);});yes(NativeNavCodec.clip("a\n你好",4).equals("a你"));
        List<byte[]> sent=new ArrayList<>();NativeNavSession s=new NativeNavSession("peer",123,(b,id,seq)->{sent.add(b);return true;});yes(s.start(scene(),100));yes(s.state()==NativeNavSession.State.STARTING);s.offer(scene(),200);s.pump("peer",300);yes(sent.size()==1);s.complete(1,true,0,response(1,true),400);yes(s.state()==NativeNavSession.State.RUNNING);NativeNavCodec.Scene next=scene();next.distance=79;s.offer(next,450);next.distance=70;s.offer(next,500);s.pump("peer",1399);yes(sent.size()==1);s.pump("peer",1400);yes(sent.size()==2);yes(ByteBuffer.wrap(sent.get(1)).order(ByteOrder.LITTLE_ENDIAN).getInt(36)==70);s.stop(1500);yes(s.state()==NativeNavSession.State.STOPPING);s.complete(2,true,0,response(2,true),1600);s.pump("peer",2600);yes(sent.get(2)[5]==4);s.complete(3,true,0,response(3,false),2700);yes(s.state()==NativeNavSession.State.STOPPED);
        s=new NativeNavSession("peer",123,(b,id,seq)->true);s.start(scene(),0);s.pump("peer",8000);yes(s.state()==NativeNavSession.State.UNCERTAIN);s.complete(1,true,0,response(1,true),8100);yes(s.state()==NativeNavSession.State.UNCERTAIN);
        s=new NativeNavSession("peer",123,(b,id,seq)->true);s.start(scene(),0);s.pump("another",100);yes(s.state()==NativeNavSession.State.UNCERTAIN);
        sent.clear();s=new NativeNavSession("peer",123,(b,id,seq)->{sent.add(b);return true;});s.start(scene(),0);s.complete(1,true,0,response(1,true),100);s.pump("peer",20000);yes(sent.get(1)[5]==3); // stale UI frames never refresh the screen lease
        List<NavCore.Step> route=Arrays.asList(new NavCore.Step("向右前方行驶",Arrays.asList(new NavCore.Point(30,120),new NavCore.Point(30.01,120.01))));NativeNavCodec.Scene r=NativeNavRoute.scene(route,0,route.get(0).points.get(0),800,1000,true,false,false);yes(r.points.length<=32);yes(r.road.contains("模拟"));yes(r.icon==5);yes(NativeNavCodec.packet(1,123,42,r).length<=512);yes(NativeNavRoute.icon("turn left")==2);
        StringBuilder hex=new StringBuilder();for(byte value:reply)hex.append(String.format("%02x",value&255));
        byte[] wire=CustomEnvelopeTest.envelope("{\"cmd\":\"turbo_nav_v1\",\"payload\":{\"value\":0,\"mode\":0,\"data\":\""+hex+"\"}}");
        NativeNavCodec.Reply decoded=NativeNavCodec.reply(CustomEnvelope.decode(wire,"turbo_nav_v1",32));
        yes(decoded!=null&&decoded.active&&decoded.sid==123&&decoded.seq==42);
        System.out.println("NativeNavTest: "+checks+" assertions, C golden packets, native JSON wrapper, backpressure, timeout, stale-source and route bounds");
    }
}
