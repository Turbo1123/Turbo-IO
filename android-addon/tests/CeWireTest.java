package com.turboio.addon;
import java.nio.charset.StandardCharsets;import java.nio.file.*;import java.util.*;

/** TEL1 wire parity with the unchanged TVP2 context-english-v1 C sources (golden vectors from english_golden.c). */
public final class CeWireTest {
    static int n;static void ok(boolean b,String why){n++;if(!b)throw new AssertionError("TEL1 wire "+n+" "+why);}
    static byte[] hex(String s){byte[] b=new byte[s.length()/2];for(int i=0;i<b.length;i++)b[i]=(byte)Integer.parseInt(s.substring(2*i,2*i+2),16);return b;}
    static String text(String h){try{return StandardCharsets.UTF_8.newDecoder().decode(java.nio.ByteBuffer.wrap(hex(h))).toString();}catch(java.nio.charset.CharacterCodingException e){return null;}}
    public static void main(String[] a)throws Exception{
        Path g=Paths.get(a[0]);
        String[][] rows={{"clarify","澄清；讲清楚","Could you clarify the plan?"},{"postpone","推迟","Let's postpone the meeting."},{"compare","比较","Let's compare the two options."},{"budget","预算","We need to check the budget."},{"deadline","截止日期","Please confirm the deadline."}};
        List<CeWire.Card> cards=new ArrayList<>();for(String[] r:rows)cards.add(new CeWire.Card(r[0],"合成测试场景：讨论明天的工作安排。",r[1],r[2],true));
        byte[] bundle=CeWire.bundle(cards,2,20750,1793000000L,1200,true);ok(Arrays.equals(bundle,Files.readAllBytes(g.resolve("bundle.bin"))),"CED1 bundle");
        long digest=CeWire.crc32(bundle,0,bundle.length),total=bundle.length;
        ok(Arrays.equals(CeWire.packet(CeWire.QUERY,0,7,0,0,0,null,0,0),Files.readAllBytes(g.resolve("query.bin"))),"QUERY");
        ok(Arrays.equals(CeWire.packet(CeWire.BEGIN,1000,1,0,total,digest,null,0,0),Files.readAllBytes(g.resolve("begin.bin"))),"BEGIN");
        ok(Arrays.equals(CeWire.packet(CeWire.CHUNK,1000,2,0,total,digest,bundle,0,384),Files.readAllBytes(g.resolve("chunk.bin"))),"CHUNK");
        ok(Arrays.equals(CeWire.packet(CeWire.COMMIT,1000,9,total,total,digest,null,0,0),Files.readAllBytes(g.resolve("commit.bin"))),"COMMIT");
        ok(Arrays.equals(CeWire.packet(CeWire.ABORT,1000,3,384,total,digest,null,0,0),Files.readAllBytes(g.resolve("abort.bin"))),"ABORT");
        ok(CeWire.packet(CeWire.BEGIN,1000,2,0,total,digest,null,0,0)==null&&CeWire.packet(CeWire.CHUNK,1000,2,0,total,digest,bundle,0,385)==null&&CeWire.packet(CeWire.QUERY,1,7,0,0,0,null,0,0)==null&&CeWire.packet(CeWire.COMMIT,1000,1,total,total,digest,null,0,0)==null,"packet rules");
        byte[] ack=Files.readAllBytes(g.resolve("ack.bin"));CeWire.Ack k=CeWire.ack(ack);
        ok(k!=null&&k.result==0&&k.state==CeWire.RX_RECEIVING&&k.tx==1000&&k.seq==2&&k.next==384&&k.total==total&&k.digest==digest&&k.committed==999&&k.active==1000&&k.highwater==1000,"TEA1 fields");
        for(int i=0;i<ack.length*8;i++){byte[] b=ack.clone();b[i/8]^=1<<(i%8);ok(CeWire.ack(b)==null,"ack flip "+i);}ok(CeWire.ack(Arrays.copyOf(ack,43))==null,"ack length");
        byte[] prog=Files.readAllBytes(g.resolve("progress.bin"));CeWire.Progress p=CeWire.progress(prog);
        ok(p!=null&&p.day==20750&&p.limit==5&&p.used==3&&p.tx==1000&&p.words[1]==22&&p.results[2]==3&&p.words[3]==0,"TEP1 fields");
        for(int i=0;i<prog.length*8;i++){byte[] b=prog.clone();b[i/8]^=1<<(i%8);ok(CeWire.progress(b)==null,"progress flip "+i);}
        int cases=0;for(String line:Files.readAllLines(g.resolve("cards.txt"))){String[] f=line.split("\t",-1);String e=text(f[1]),q=text(f[2]),m=text(f[3]),x=text(f[4]);cases++;
            if(e==null||q==null||m==null||x==null){ok(f[0].equals("0"),"malformed UTF-8 invalid in C too");continue;}
            ok(CeWire.cardValid(new CeWire.Card(e,q,m,x,true))==f[0].equals("1"),"card rule "+line);}
        ok(!CeWire.cardValid(new CeWire.Card("ok","\ud800","m","e",true)),"lone surrogate");
        ok(cases==17,"card cases");
        List<CeWire.Card> bad=new ArrayList<>(cards);bad.set(1,new CeWire.Card("123","q","m","e",false));ok(CeWire.bundle(bad,2,20750,1793000000L,1200,true)==null,"invalid card refused, not cut");
        ok(CeWire.bundle(cards,4,20750,1793000000L,1200,true)==null&&CeWire.bundle(cards,2,0,1793000000L,1200,true)==null&&CeWire.bundle(cards,2,20750,1793000000L,1440,true)==null&&CeWire.bundle(new ArrayList<>(),2,20750,1793000000L,1200,true)==null,"bundle bounds");
        List<CeWire.Card> eleven=new ArrayList<>();for(int i=0;i<11;i++)eleven.add(cards.get(0));ok(CeWire.bundle(eleven,2,20750,1793000000L,1200,true)==null,"≤10 cards");
        System.out.println("CeWireTest: "+n+" checks; CED1/TEL1/TEA1/TEP1 golden, card rules");
    }
}
