package com.turboio.addon;
import java.nio.file.*;import java.util.*;

/** TDQ1/TDG1 diagnostics codec against bytes from the iOS/firmware C source. */
public final class TdgCodecTest {
    static int n;static void ok(boolean b,String why){n++;if(!b)throw new AssertionError("tdg "+n+" "+why);}
    static boolean throwsIAE(Runnable r){try{r.run();return false;}catch(IllegalArgumentException e){return true;}}
    static byte[] fix(byte[] p){HexCarrier.w32(p,124,HexCarrier.crc(p,124));return p;}
    public static void main(String[] a)throws Exception{Path d=Paths.get(a[0]);
        ok(Arrays.equals(TdgCodec.command(TdgCodec.START,0x12345678L,1,600000),Files.readAllBytes(d.resolve("start.bin"))),"start");
        ok(Arrays.equals(TdgCodec.command(TdgCodec.STOP,0x12345678L,2,0),Files.readAllBytes(d.resolve("stop.bin"))),"stop");
        byte[] full=Files.readAllBytes(d.resolve("sample.bin"));TdgCodec.Sample s=TdgCodec.sample(full);
        ok(s!=null&&s.session==0x12345678L&&s.sequence==5&&s.tickMs==123456&&s.probeMs==3&&s.valid==0x7FFFF&&s.build==0x01000001L&&s.eventCount==3&&s.eventsLost==1&&s.flags==0,"full fields");
        for(int i=0;i<19;i++)ok(s.values[i]==i*1000+7,"metric "+i);
        TdgCodec.Sample p=TdgCodec.sample(Files.readAllBytes(d.resolve("sample-partial.bin")));ok(p!=null&&p.valid==5&&p.values[0]==7&&p.values[1]==0&&p.values[2]==2007&&p.flags==1,"partial");
        for(int i=0;i<full.length;i++)for(int b=0;b<8;b++){byte[] x=full.clone();x[i]^=(byte)(1<<b);ok(TdgCodec.sample(x)==null,"flip "+i+":"+b);}
        byte[] hidden=full.clone();HexCarrier.w32(hidden,24,0x7FFFE);ok(TdgCodec.sample(fix(hidden))==null,"value with clear valid bit");
        byte[] flags=full.clone();HexCarrier.w32(flags,120,2);ok(TdgCodec.sample(fix(flags))==null,"flags 2");
        byte[] events=full.clone();HexCarrier.w32(events,112,65);ok(TdgCodec.sample(fix(events))==null,"event_count 65");
        byte[] reserved=full.clone();HexCarrier.w32(reserved,24,0x7FFFF|(1<<19));ok(TdgCodec.sample(fix(reserved))==null,"reserved valid bit");
        ok(TdgCodec.sample(Arrays.copyOf(full,127))==null,"length");
        ok(throwsIAE(()->TdgCodec.command(TdgCodec.START,1,1,600001))&&throwsIAE(()->TdgCodec.command(TdgCodec.START,1,1,0))&&throwsIAE(()->TdgCodec.command(TdgCodec.STOP,1,2,5))&&throwsIAE(()->TdgCodec.command(TdgCodec.START,0,1,1000))&&throwsIAE(()->TdgCodec.command(TdgCodec.START,1,0,1000))&&throwsIAE(()->TdgCodec.command(3,1,1,0)),"invalid commands");
        ok(TdgCodec.NAMES.length==19&&"lv_configured_bytes".equals(TdgCodec.NAMES[0])&&"errors".equals(TdgCodec.NAMES[18]),"names");
        System.out.println("TdgCodecTest: "+n+" checks against C golden bytes");
    }
}
