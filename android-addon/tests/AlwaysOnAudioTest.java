package com.turboio.addon;
import java.io.*;import java.nio.file.*;import java.util.*;

/** Always-on audio saving (port of iOS AlwaysOnAudioFiles.m / AlwaysOnOgg.m / AlwaysOnAudioNative.m rules). */
public final class AlwaysOnAudioTest {
    static int n;static void ok(boolean b,String why){n++;if(!b)throw new AssertionError("always-on audio "+n+" "+why);}
    static long crc(byte[] p){long c=0;for(int i=0;i<p.length;i++){c^=((i>=22&&i<26)?0:(p[i]&255L))<<24;for(int b=0;b<8;b++)c=((c<<1)^(((c&0x80000000L)!=0)?0x04c11db7L:0))&0xffffffffL;}return c;}
    static byte[] page(int flags,long granule,int seq,List<byte[]> packets){
        ByteArrayOutputStream lace=new ByteArrayOutputStream(),body=new ByteArrayOutputStream();
        for(byte[] p:packets){int len=p.length;while(len>=255){lace.write(255);len-=255;}lace.write(len);body.write(p,0,p.length);}
        byte[] l=lace.toByteArray(),b=body.toByteArray();byte[] h=new byte[27+l.length+b.length];h[0]='O';h[1]='g';h[2]='g';h[3]='S';h[5]=(byte)flags;
        for(int i=0;i<8;i++)h[6+i]=(byte)(granule>>(8*i));for(int i=0;i<4;i++){h[14+i]=(byte)(0x1234>>(8*i));h[18+i]=(byte)(seq>>(8*i));}h[26]=(byte)l.length;
        System.arraycopy(l,0,h,27,l.length);System.arraycopy(b,0,h,27+l.length,b.length);long c=crc(h);for(int i=0;i<4;i++)h[22+i]=(byte)(c>>(8*i));return h;}
    static byte[] ogg(long audioGranule){
        byte[] head=new byte[19];System.arraycopy("OpusHead".getBytes(),0,head,0,8);head[8]=1;head[9]=1;head[10]=(byte)(312&255);head[11]=(byte)(312>>8);head[12]=(byte)0x80;head[13]=(byte)0xbb;
        byte[] tags=new byte[16];System.arraycopy("OpusTags".getBytes(),0,tags,0,8);
        byte[] f={(byte)0xF8,0,0};ByteArrayOutputStream o=new ByteArrayOutputStream();
        o.write(page(2,0,0,Arrays.asList(head)),0,0);byte[] p0=page(2,0,0,Collections.singletonList(head)),p1=page(0,0,1,Collections.singletonList(tags)),p2=page(4,audioGranule,2,Arrays.asList(f,f,f));
        o.write(p0,0,p0.length);o.write(p1,0,p1.length);o.write(p2,0,p2.length);return o.toByteArray();}
    static File write(Path p,byte[] b)throws IOException{Files.createDirectories(p.getParent());Files.write(p,b);return p.toFile();}
    public static void main(String[] a)throws Exception{
        Path base=Files.createTempDirectory("aoa"),sessions=base.resolve("always_on_debug/sessions");
        write(sessions.resolve("s1/cached_0001.opus"),new byte[]{1});Thread.sleep(20);write(sessions.resolve("s1/realtime_0001.ogg"),new byte[]{1,2});Thread.sleep(20);write(sessions.resolve("s2/dump.pcm"),new byte[]{1,2,3});
        write(sessions.resolve("s1/notes.txt"),new byte[]{1});write(sessions.resolve("s1/deep/deeper/x.opus"),new byte[]{1});write(sessions.resolve("s1/empty.opus"),new byte[0]);
        Path outside=write(base.resolve("secret.opus"),new byte[]{9}).toPath();try{Files.createSymbolicLink(sessions.resolve("s1/link.opus"),outside);}catch(Exception ignored){}
        List<AlwaysOnAudio.Entry> rows=AlwaysOnAudio.list(base.toFile());
        ok(rows.size()==3&&rows.get(0).name.equals("dump.pcm")&&rows.get(0).kind.equals("智记调试音频（来源待核对）")&&rows.get(1).kind.equals("实时音频")&&rows.get(2).kind.equals("缓存音频"),"listing: extension, depth, empty, symlink, newest first");
        ok(AlwaysOnAudio.list(base.resolve("missing").toFile()).isEmpty(),"no dir");
        // Copy: listed only; stable; Ogg validated.
        File exports=base.resolve("exports").toFile();
        boolean refused=false;try{AlwaysOnAudio.copy(base.toFile(),outside.toFile(),exports);}catch(IllegalArgumentException e){refused=true;}ok(refused,"unlisted refused");
        File pcm=AlwaysOnAudio.copy(base.toFile(),rows.get(0).file,exports);ok(pcm.getName().equals("全天智记音频.pcm")&&Arrays.equals(Files.readAllBytes(pcm.toPath()),new byte[]{1,2,3}),"pcm copied, real extension kept");
        File valid=write(sessions.resolve("s3/realtime_ok.ogg"),ogg(2880));File copy=AlwaysOnAudio.copy(base.toFile(),valid,exports);ok(Arrays.equals(Files.readAllBytes(copy.toPath()),ogg(2880)),"valid Ogg Opus copied unchanged");
        File legacy=write(sessions.resolve("s3/realtime_legacy.ogg"),ogg(3*960+312));File fixed=AlwaysOnAudio.copy(base.toFile(),legacy,exports);
        ok(Arrays.equals(Files.readAllBytes(fixed.toPath()),ogg(2880))&&Arrays.equals(Files.readAllBytes(legacy.toPath()),ogg(3*960+312)),"legacy granules repaired in the copy only");
        byte[] broken=ogg(2880);broken[broken.length-1]^=1;File bad=write(sessions.resolve("s3/realtime_bad.ogg"),broken);refused=false;try{AlwaysOnAudio.copy(base.toFile(),bad,exports);}catch(IllegalArgumentException e){refused=true;}ok(refused,"bad CRC refused");
        byte[] cut=Arrays.copyOf(ogg(2880),ogg(2880).length-20);File trunc=write(sessions.resolve("s3/realtime_cut.ogg"),cut);refused=false;try{AlwaysOnAudio.copy(base.toFile(),trunc,exports);}catch(IllegalArgumentException e){refused=true;}ok(refused,"truncated refused");
        File moving=write(sessions.resolve("s3/cached_moving.pcm"),new byte[]{1,2,3,4});AlwaysOnAudio.testHook=()->{try{Files.write(moving.toPath(),new byte[]{1,2,3,4,5});}catch(IOException e){throw new UncheckedIOException(e);}};
        refused=false;try{AlwaysOnAudio.copy(base.toFile(),moving,exports);}catch(IllegalArgumentException e){refused=true;}AlwaysOnAudio.testHook=null;ok(refused,"file changing during copy refused");
        // Status verification after configure (iOS TIOAOSetAudioSaving).
        Map<String,Object> on=new HashMap<>();on.put("dumpEnabled",true);on.put("dumpEvents",false);on.put("dumpRealtimeAudio",true);on.put("dumpCachedAudio",true);
        ok(AlwaysOnAudio.verify(on,true)&&!AlwaysOnAudio.verify(on,false),"enabled verified");Map<String,Object> ev=new HashMap<>(on);ev.put("dumpEvents",true);ok(!AlwaysOnAudio.verify(ev,true),"events must stay off");
        Map<String,Object> off=new HashMap<>();off.put("dumpEnabled",false);ok(AlwaysOnAudio.verify(off,false)&&!AlwaysOnAudio.verify(null,false),"disabled verified");
        System.out.println("AlwaysOnAudioTest: "+n+" checks; listing, copy, Ogg scan/repair, verify");
    }
}
