import com.turboio.addon.FocusCodec;
import java.nio.file.*;
import java.util.*;
public class FocusCodecTest {
    static int count;
    static void check(boolean value){count++;if(!value)throw new AssertionError(count);}
    static void reject(Runnable run){boolean failed=false;try{run.run();}catch(IllegalArgumentException e){failed=true;}check(failed);}
    public static void main(String[] args)throws Exception{
        for(int op=1;op<=7;op++){
            byte[] b=FocusCodec.command(op,op==1?0:123,42,op==1?0:7,op==2?1500:0,0);
            check(Arrays.equals(b,Files.readAllBytes(Paths.get(args[0],"command-"+op+".bin"))));
        }
        byte[] b=Files.readAllBytes(Paths.get(args[0],"reply.bin"));FocusCodec.Reply r=FocusCodec.reply(b);
        check(r!=null&&r.sid==123&&r.seq==42&&r.status==1&&r.remainingMS==1500000&&r.requestSID==123);
        for(int i=0;i<64;i++){byte[] bad=b.clone();bad[i]^=1;check(FocusCodec.reply(bad)==null);}
        check(FocusCodec.reply(new byte[63])==null);check(FocusCodec.reply(null)==null);
        reject(()->FocusCodec.command(0,0,1,0,0,0));reject(()->FocusCodec.command(8,1,1,0,0,0));
        reject(()->FocusCodec.command(2,0,1,0,10,0));reject(()->FocusCodec.command(2,1,0,0,10,0));
        reject(()->FocusCodec.command(2,1,1,0,9,0));reject(()->FocusCodec.command(2,1,1,0,7201,0));
        reject(()->FocusCodec.command(2,1,1,0,10,3));reject(()->FocusCodec.command(1,0,1,1,0,0));
        reject(()->FocusCodec.command(3,1,1,0,10,0));reject(()->FocusCodec.command(2,0x100000000L,1,0,10,0));
        check(FocusCodec.command(2,0xffffffffL,0xffffffffL,0xffffffffL,7200,2).length==64);
        check(FocusCodec.hex("X".repeat(128))==null);check(FocusCodec.hex("0".repeat(126))==null);
        check(FocusCodec.hex("0".repeat(128)).length==64);
        System.out.println("Focus codec: "+count+" assertions, C firmware golden parity passed");
    }
}
