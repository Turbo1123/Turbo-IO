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
        // Fit, not fill: a 640x480 luma plane (row stride 704) into 256x144 keeps the whole image (192x144) with black bars.
        int yw=640,yh=480,stride=704;byte[] y=new byte[stride*yh];Arrays.fill(y,(byte)200);for(int r=0;r<yh;r++)for(int x=yw;x<stride;x++)y[r*stride+x]=(byte)255; // padding must never be sampled
        y[240*stride+320]=(byte)17;byte[] fit=CameraCodec.fit(y,yw,yh,stride,256,144);ok(fit.length==256*144);
        boolean bars=true,inside=true,padding=true;for(int r=0;r<144;r++)for(int x=0;x<256;x++){int v=fit[r*256+x]&255;if(x<32||x>=224)bars&=v==0;else{inside&=v==200||v==17;padding&=v!=255;}}
        ok(bars&&inside&&padding);ok((fit[72*256+128]&255)==17);
        // A wider-than-16:9 source gets bars top and bottom instead; nothing is cropped.
        byte[] wide=new byte[1000*100];Arrays.fill(wide,(byte)90);byte[] wf=CameraCodec.fit(wide,1000,100,1000,256,144);boolean tb=true;for(int x=0;x<256;x++){tb&=wf[x]==0&&wf[143*256+x]==0&&(wf[72*256+x]&255)==90;}ok(tb);
        ok(throwsIAE(()->CameraCodec.fit(y,yw,yh,600,256,144))&&throwsIAE(()->CameraCodec.fit(y,yw,yh,stride,300,144)));
        System.out.println("CameraCodecTest: "+n+" checks against C golden bytes");
    }
}
