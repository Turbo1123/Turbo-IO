package com.turboio.addon;
import java.nio.file.*;import java.util.*;

/** TVP1/VPA1 HD codec byte-identical to TVP2 video-player-v1, and the FrameEncoder port. */
public final class HdTest {
    static int n;static void ok(boolean b,String why){n++;if(!b)throw new AssertionError("hd "+n+" "+why);}
    static byte[] g(String dir,String f)throws Exception{return Files.readAllBytes(Paths.get(dir).resolve(f));}
    static Vp.Packet p(int op,long sid,long seq,long a,long b,long c,byte[] data){Vp.Packet q=new Vp.Packet();q.op=op;q.sid=sid;q.seq=seq;q.a=a;q.b=b;q.c=c;q.data=data;return q;}
    /** Re-seal the whole-packet CRC (skipping bytes 28..31) after a deliberate field change. */
    static void reseal(byte[] p){int c=-1;for(int i=0;i<p.length;i++){if(i>=28&&i<32)continue;c^=p[i]&255;for(int k=0;k<8;k++)c=(c>>>1)^(0xedb88320&-(c&1));}long v=~c&0xffffffffL;for(int i=0;i<4;i++)p[28+i]=(byte)(v>>(8*i));}
    static byte[] plane(int w,int h){byte[] b=new byte[w*h];for(int y=0;y<h;y++)for(int x=0;x<w;x++)b[y*w+x]=(byte)(x*17+y*31+(x%13)*19);return b;}
    /** What the player puts on screen for our strips (vp_hd decompress + expand). */
    static byte[] shown(HdEncoder.Frame f){byte[] out=new byte[Vp.W*Vp.H];int per=8/f.bits,max=(1<<f.bits)-1;
        for(int s=0;s<4;s++){int rows=55,count=Vp.W*rows;byte[] packed=new byte[count*f.bits/8];if(!Vp.decompress(f.strips[s],packed,packed.length))return null;
            for(int i=0;i<count;i++){int v=((packed[i/per]&255)>>(8-f.bits-f.bits*(i%per)))&max;out[s*55*Vp.W+i]=(byte)(v*255/max);}}return out;}
    public static void main(String[] a)throws Exception{
        String dir=a[0];
        ok(Arrays.equals(Vp.encode(p(Vp.HELLO,7,1,Vp.HD_CAP,0,0,null),false),g(dir,"hello.bin")),"hello");
        byte[] data=new byte[100];for(int i=0;i<100;i++)data[i]=(byte)(i*7);
        ok(Arrays.equals(Vp.encode(p(Vp.HD_STRIP,7,3,55|(55L<<16),4,Vp.crc(data,0,100),data),false),g(dir,"strip.bin")),"strip");
        ok(Arrays.equals(Vp.encode(p(Vp.HD_COMMIT,7,9,2,0,0x12345678L,null),false),g(dir,"commit.bin")),"commit");
        ok(Arrays.equals(Vp.encode(p(Vp.PING,7,4,1,3,999,null),true),g(dir,"ping_reply.bin")),"ping reply");
        Vp.Packet r=Vp.decode(g(dir,"ping_reply.bin"),true);ok(r!=null&&r.op==Vp.PING&&r.sid==7&&r.seq==4&&r.a==1&&r.b==3&&r.c==999&&r.result==0,"decode reply");
        ok(Vp.decode(g(dir,"ping_reply.bin"),false)==null&&Vp.decode(g(dir,"strip.bin"),true)==null,"direction pinned");
        byte[] bad=g(dir,"strip.bin");bad[60]^=1;ok(Vp.decode(bad,false)==null,"crc flip");
        bad=g(dir,"hello.bin");reseal(bad);ok(Vp.decode(bad,false)!=null,"reseal helper");bad[7]=1;reseal(bad);ok(Vp.decode(bad,false)==null,"re-sealed byte 7");bad=g(dir,"hello.bin");bad[4]=2;reseal(bad);ok(Vp.decode(bad,false)==null,"re-sealed version");
        ok(Vp.encode(p(9,7,1,0,0,0,null),false)==null&&Vp.encode(p(Vp.PING,0,1,0,0,0,null),false)==null&&Vp.encode(p(Vp.PING,7,1,0,0,0,new byte[1]),true)==null,"invalid refused");
        ok(Vp.encode(p(Vp.HD_STRIP,7,3,(56L<<16),4,0,data),false)==null&&Vp.encode(p(Vp.HD_STRIP,7,3,200|(55L<<16),4,0,data),false)==null&&Vp.encode(p(Vp.HD_BEGIN,7,3,1,3,0,null),false)==null,"strip geometry");
        byte[] d=new byte[302];int k=130;Arrays.fill(d,k,k+3,(byte)5);k+=3;d[k++]=1;d[k++]=2;Arrays.fill(d,k,k+167,(byte)9);
        ok(Arrays.equals(Vp.compress(d,0,302,Vp.COMP_MAX),g(dir,"comp1.bin")),"compress runs");
        d=new byte[200];for(int i=0;i<200;i++)d[i]=(byte)(i*37);ok(Arrays.equals(Vp.compress(d,0,200,Vp.COMP_MAX),g(dir,"comp2.bin")),"compress literals");
        d=new byte[Vp.PACKED_MAX];for(int i=0;i<d.length;i++)d[i]=(byte)((i/7)%5*(i%3!=0?1:40));byte[] c3=Vp.compress(d,0,d.length,Vp.COMP_MAX);ok(Arrays.equals(c3,g(dir,"comp3.bin")),"compress mixed");
        byte[] back=new byte[d.length];ok(Vp.decompress(c3,back,back.length)&&Arrays.equals(back,d),"round trip");ok(!Vp.decompress(new byte[]{(byte)128},back,10),"128 refused");
        String[] crc=Files.readAllLines(Paths.get(dir).resolve("pixcrc.txt")).get(0).split(" ");
        byte[] gs=new byte[544*220];for(int y=0;y<220;y++)for(int x=0;x<544;x++)gs[y*544+x]=(byte)(x<540?x+y:0xee);
        ok(Vp.pixelsCrc(gs,544)==Long.parseLong(crc[0])&&Vp.crc(d,0,d.length)==Long.parseLong(crc[1])&&Vp.pixelsCrc(gs,539)==Long.parseLong(crc[2]),"pixel crc");
        // Encoder (FrameEncoder port).
        for(int levels:new int[]{2,4,8,16}){HdEncoder.Frame f=HdEncoder.encode(plane(540,220),540,220,540,false,levels,true,1,.5,.5);
            ok(f!=null&&f.strips.length==4&&f.bits==(levels<=4?2:4),"levels "+levels);ok(Arrays.equals(shown(f),f.gray),"player shows exactly gray at "+levels);
            ok(f.pixelCrc==Vp.pixelsCrc(f.gray,540),"pixel crc "+levels);long sum=0;for(byte[] s:f.strips)sum+=s.length;ok(sum==f.compressedBytes,"bytes");
            int top=0;for(byte v:f.gray)top=Math.max(top,v&255);ok(top==255,"white reaches 255 at "+levels);
            java.util.Set<Integer> values=new java.util.HashSet<>();for(byte v:f.gray)values.add(v&255);ok(values.size()<=levels,"at most "+levels+" gray values");}
        byte[] portrait=plane(400,1000);HdEncoder.Frame fit=HdEncoder.encode(portrait,400,1000,400,false,8,true,1,.5,.5),crop=HdEncoder.encode(portrait,400,1000,400,false,8,false,2,.5,.5),edge=HdEncoder.encode(portrait,400,1000,400,false,8,false,4,0,1);
        ok(fit.contentWidth==88&&fit.contentHeight==220&&crop.contentWidth==540&&edge.contentWidth==540&&HdEncoder.encode(portrait,400,1000,400,false,3,true,1,.5,.5)==null,"fit/crop/edge");
        ok((fit.gray[0]&255)==0&&(fit.gray[100*540+5]&255)==0,"black bars");
        byte[] video=new byte[540*220];Arrays.fill(video,(byte)16);HdEncoder.Frame vr=HdEncoder.encode(video,540,220,540,true,16,true,1,.5,.5);ok((vr.gray[1000]&255)==0,"video range black is 0");
        Arrays.fill(video,(byte)23);ok((HdEncoder.encode(video,540,220,540,true,16,true,1,.5,.5).gray[1000]&255)==0,"video 23 → 0");Arrays.fill(video,(byte)24);ok((HdEncoder.encode(video,540,220,540,true,16,true,1,.5,.5).gray[1000]&255)==17,"video 24 → 17");
        { java.util.Set<Integer> want=new java.util.HashSet<>(Arrays.asList(0,34,68,102,153,187,221,255)),got=new java.util.HashSet<>();byte[] ramp=new byte[540*220];for(int i=0;i<ramp.length;i++)ramp[i]=(byte)((i%540)*255/539);for(byte v:HdEncoder.encode(ramp,540,220,540,false,8,true,1,.5,.5).gray)got.add(v&255);ok(got.equals(want),"8 levels map to the 16-step palette "+got); }
        ok(HdEncoder.encode(plane(10,10),10,10,9,false,16,true,1,.5,.5)==null&&HdEncoder.encode(new byte[5000*10],5000,10,5000,false,16,true,1,.5,.5)==null,"bad geometry");
        // Android lane: a 16-level frame with a strip over 8160 B is re-encoded at 4 levels.
        byte[] noise=new byte[540*220];long s=1;for(int i=0;i<noise.length;i++){s=s*6364136223846793005L+1442695040888963407L;noise[i]=(byte)(s>>>56);}
        HdEncoder.Frame big=HdEncoder.encode(noise,540,220,540,false,16,true,1,.5,.5);int largest=0;for(byte[] st:big.strips)largest=Math.max(largest,st.length);ok(largest>8160,"noise strip exceeds the lane ("+largest+")");
        HdEncoder.Frame lane=HdEncoder.encodeForLane(noise,540,220,540,false,16,true,1,.5,.5);ok(lane.bits==2&&lane.downgraded,"downgraded to 4 levels");for(byte[] st:lane.strips)ok(st.length+Vp.HEADER<=Vp.LANE,"strip fits the lane");
        byte[] smooth=new byte[540*220];for(int i=0;i<smooth.length;i++)smooth[i]=(byte)((i%540)*255/539);HdEncoder.Frame keep=HdEncoder.encodeForLane(smooth,540,220,540,false,16,true,1,.5,.5);ok(keep.bits==4&&!keep.downgraded,"small frames keep 16 levels");
        System.out.println("HdTest: "+n+" checks; TVP1/VPA1 packets, compression and pixel CRC match player.c; encoder geometry, levels and lane fallback");
    }
}
