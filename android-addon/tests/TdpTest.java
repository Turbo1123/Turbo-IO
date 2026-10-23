package com.turboio.addon;
import java.nio.file.*;import java.util.*;

/** TDP1 client packets, TDR1 carrier and delta planning byte-identical to the TVP2 display-runtime-v1 / iOS C. */
public final class TdpTest {
    static int n;static void ok(boolean b,String why){n++;if(!b)throw new AssertionError("tdp "+n+" "+why);}
    static byte[] g(String dir,String f)throws Exception{return Files.readAllBytes(Paths.get(dir).resolve(f));}
    static String plan(String tag,int r,Tdp.Delta d){StringBuilder s=new StringBuilder(tag+" "+r+" "+d.count+" "+d.pixels);for(int i=0;i<d.count;i++)for(int k=0;k<4;k++)s.append(' ').append(d.rects[i][k]);return s.toString();}
    public static void main(String[] a)throws Exception{
        String dir=a[0];byte[] px=new byte[Tdp.PIXELS];for(int i=0;i<px.length;i++)px[i]=(byte)(i%251);
        ok(Arrays.equals(Tdp.query(7),g(dir,"query.bin")),"query");
        ok(Arrays.equals(Tdp.control(Tdp.KEEPALIVE,7392,9,3),g(dir,"keepalive.bin")),"keepalive");
        ok(Arrays.equals(Tdp.control(Tdp.CLOSE,7392,10,3),g(dir,"close.bin")),"close");
        byte[] x=new byte[400];for(int y=0;y<20;y++)for(int i=0;i<20;i++)x[y*20+i]=(byte)((i==y||i+y==19)?255:60);
        ok(Arrays.equals(Tdp.rect(7392,11,3,4,4,20,20,x),g(dir,"rect.bin")),"rect");
        ok(Arrays.equals(Tdp.begin(7392,12,3,5,Tdp.crc(px,0,px.length)),g(dir,"begin.bin")),"begin");
        ok(Arrays.equals(Tdp.chunk(7392,13,3,5,472,px,472,472),g(dir,"chunk.bin")),"chunk");
        ok(Arrays.equals(Tdp.finish(Tdp.COMMIT,7392,14,3,5),g(dir,"commit.bin")),"commit");
        ok(Arrays.equals(Tdp.finish(Tdp.ABORT,7392,15,3,5),g(dir,"abort.bin")),"abort");
        // Encoders refuse what the C refuses.
        ok(Tdp.query(0)==null&&Tdp.control(Tdp.RECT,7392,9,3)==null&&Tdp.control(Tdp.CLOSE,0,9,3)==null,"bad control");
        ok(Tdp.rect(7392,11,3,500,4,20,20,x)==null&&Tdp.rect(7392,11,3,4,4,20,21,x)==null&&Tdp.rect(7392,11,0xffffffffL,4,4,20,20,x)==null,"bad rect");
        ok(Tdp.chunk(7392,13,3,5,65536-10,px,0,11)==null&&Tdp.chunk(7392,13,3,0,0,px,0,10)==null&&Tdp.begin(7392,12,3,0,1)==null,"bad chunk/begin");
        // Carrier: exact canonical envelope only.
        byte[] env=g(dir,"carrier.bin");Tdp.Reply r=Tdp.carrierDecode(15,env);
        ok(r!=null&&r.result==Tdp.STAGED&&r.sid==7392&&r.request==13&&r.revision==3&&r.width==512&&r.height==128&&r.maxRect==16384&&r.lease==120000,"carrier decode");
        ok(Arrays.equals(Tdp.carrierEncode(r),env),"carrier encode");
        ok(Tdp.carrierDecode(11,env)==null,"wrong business");
        boolean all=true;for(int i=0;i<env.length;i++){byte[] m=env.clone();m[i]^=(byte)(m[i]>='a'&&m[i]<='f'?0x20:1);if(Tdp.carrierDecode(15,m)!=null)all=false;}ok(all,"every envelope byte change rejected");
        ok(Tdp.carrierDecode(15,Arrays.copyOf(env,env.length-1))==null,"truncated envelope");
        // Canonical packet validation (DisplayPhoneTransport Valid).
        byte[] q=Tdp.query(7);ok(Tdp.valid(q)&&Tdp.valid(g(dir,"chunk.bin"))&&Tdp.valid(g(dir,"rect.bin")),"valid");
        byte[] bad=q.clone();bad[6]=1;ok(!Tdp.valid(bad),"reserved byte");
        bad=g(dir,"chunk.bin");bad[100]^=1;ok(!Tdp.valid(bad),"payload/CRC flip");
        ok(!Tdp.valid(Tdp.rect(7392,11,3,0,0,128,128,new byte[16384])),"over 512 B refused for the native file");
        // Delta plans.
        byte[] A=px.clone(),B=px.clone();
        for(int t=0;t<10;t++){int xx=(t*53)%512,yy=(t*29)%128;A[yy*512+xx]^=0x55;A[yy*512+(xx+1)%512]^=0x0f;}
        for(int t=0;t<40;t++){int xx=(t*24)%512,yy=((t*24)/512)*16+3;B[yy*512+xx+2]^=1;}
        List<String> want=Files.readAllLines(Paths.get(dir).resolve("delta.txt"));Tdp.Delta d=new Tdp.Delta();
        ok(plan("plan",Tdp.deltaPlan(px,A,d),d).equals(want.get(0)),"plan "+want.get(0));
        ok(plan("batch8",Tdp.deltaBatch(px,A,8,d),d).equals(want.get(1)),"batch8 "+want.get(1));
        ok(plan("many",Tdp.deltaPlan(px,B,d),d).equals(want.get(2)),"many "+want.get(2));
        ok(plan("same",Tdp.deltaPlan(px,px,d),d).equals(want.get(3)),"same "+want.get(3));
        ok(Tdp.deltaBatch(px,new byte[10],8,d)==-1&&Tdp.deltaBatch(px,A,33,d)==-1,"invalid delta");
        System.out.println("TdpTest: "+n+" checks; TDP1 packets, TDR1 carrier, canonical validation and delta plans match the C");
    }
}
