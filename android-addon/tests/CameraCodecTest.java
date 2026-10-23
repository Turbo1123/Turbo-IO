package com.turboio.addon;
import java.nio.file.*;import java.util.*;

/** TCM1/TCA1 camera codec against wire bytes, quantized planes and PackBits from the C source. */
public final class CameraCodecTest {
    static int n;static void ok(boolean b){n++;if(!b)throw new AssertionError("camera codec "+n);}
    static byte[] f(Path d,String name)throws Exception{return Files.readAllBytes(d.resolve(name));}
    static boolean throwsIAE(Runnable r){try{r.run();return false;}catch(IllegalArgumentException e){return true;}}
    public static void main(String[] a)throws Exception{Path d=Paths.get(a[0]);long sid=0xa1b2c3d4L;
        ok(Arrays.equals(CameraCodec.packet(CameraCodec.HELLO,sid,1,0,0,0,null),f(d,"hello.bin")));
        ok(Arrays.equals(CameraCodec.packet(CameraCodec.BEGIN,sid,7,256|(144<<16),1234|(4L<<24),0xdeadbeefL,null),f(d,"begin.bin")));
        byte[] data=new byte[CameraCodec.DATA_MAX];for(int i=0;i<data.length;i++)data[i]=(byte)(i*37+5);
        ok(Arrays.equals(CameraCodec.packet(CameraCodec.CHUNK,sid,7,416,0,0,data),f(d,"chunk.bin")));
        CameraCodec.Packet s=CameraCodec.reply(f(d,"shutter-reply.bin"));ok(s!=null&&s.op==CameraCodec.SHUTTER&&s.result==CameraCodec.OK&&s.sid==sid&&s.seq==9&&s.b==123456);
        CameraCodec.Packet h=CameraCodec.reply(f(d,"hello-reply.bin"));ok(h!=null&&h.op==CameraCodec.HELLO&&h.a==256&&h.b==144&&h.c==5000);
        ok(CameraCodec.reply(f(d,"hello.bin"))==null);                                  // phone tag is not a reply
        byte[] good=f(d,"hello-reply.bin");for(int i=0;i<good.length;i++){byte[] bad=good.clone();bad[i]^=1;ok(CameraCodec.reply(bad)==null);}
        ok(CameraCodec.reply(Arrays.copyOf(f(d,"chunk.bin"),f(d,"chunk.bin").length))==null);  // replies never carry data (and wrong tag)
        byte[] gray=f(d,"gray.bin");
        ok(Arrays.equals(CameraCodec.quantize(gray,2),f(d,"quant2.bin"))&&Arrays.equals(CameraCodec.quantize(gray,4),f(d,"quant4.bin")));
        ok(Arrays.equals(CameraCodec.compress(f(d,"mixed.bin")),f(d,"packbits.bin")));
        ok(Arrays.equals(CameraCodec.compress(f(d,"quant4.bin")),f(d,"quant4-packbits.bin")));
        // Oversized or invalid inputs never reach the wire.
        ok(CameraCodec.compress(new byte[CameraCodec.PACKED_MAX+1])==null&&CameraCodec.compress(new byte[0])==null);
        ok(throwsIAE(()->CameraCodec.packet(CameraCodec.CHUNK,sid,7,0,0,0,new byte[CameraCodec.DATA_MAX+1])));
        ok(throwsIAE(()->CameraCodec.packet(CameraCodec.PING,sid,0,0,0,0,null)));                 // seq 0
        ok(throwsIAE(()->CameraCodec.packet(CameraCodec.SHUTTER,sid,1,0,0,0,null)));              // phone never sends glasses events
        ok(throwsIAE(()->CameraCodec.quantize(new byte[CameraCodec.PIXELS+4],2))&&throwsIAE(()->CameraCodec.quantize(new byte[16],3)));
        ok(CameraCodec.budget(128,72,2)==2.5&&CameraCodec.budget(192,108,4)==5.5&&CameraCodec.budget(256,144,2)==6.5&&CameraCodec.budget(256,144,4)==8.0&&CameraCodec.budget(256,144,8)==0&&CameraCodec.budget(320,180,4)==0);
        ok(CameraCodec.PROFILES.length==4&&Arrays.equals(CameraCodec.PROFILES[3],new int[]{256,144,4})&&CameraCodec.DEFAULT_PROFILE==3);
        System.out.println("CameraCodecTest: "+n+" checks against C golden bytes");
    }
}
