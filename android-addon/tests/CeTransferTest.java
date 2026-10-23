package com.turboio.addon;
import java.nio.file.*;import java.util.*;

/** TEL1 sender (english_transfer.c port, golden against the C receiver) and the phone session (ContextEnglishBridge.m). */
public final class CeTransferTest {
    static int n;static void ok(boolean b,String why){n++;if(!b)throw new AssertionError("TEL1 transfer "+n+" "+why);}
    static byte[] hex(String s){byte[] b=new byte[s.length()/2];for(int i=0;i<b.length;i++)b[i]=(byte)Integer.parseInt(s.substring(2*i,2*i+2),16);return b;}
    static long r32(byte[] p,int at){return (p[at]&255L)|(p[at+1]&255L)<<8|(p[at+2]&255L)<<16|(p[at+3]&255L)<<24;}
    static void w32(byte[] p,int at,long v){for(int i=0;i<4;i++)p[at+i]=(byte)(v>>(8*i));}
    /** TEA1 encoder for the fake glasses. */
    static byte[] ack(int result,int state,long tx,long seq,long next,long total,long digest,long committed,long active,long high){
        byte[] a=new byte[44];a[0]='T';a[1]='E';a[2]='A';a[3]='1';a[4]=1;a[5]=(byte)result;a[6]=(byte)state;long[] v={tx,seq,next,total,digest,committed,active,high};for(int i=0;i<8;i++)w32(a,8+4*i,v[i]);w32(a,40,CeWire.crc32(a,0,40));return a;}
    /** Well-behaved receiver reply for a sender packet. */
    static byte[] reply(byte[] p){int op=p[5];long tx=r32(p,8),seq=r32(p,12),off=r32(p,16),total=r32(p,20),digest=r32(p,24);int len=(p[28]&255)|(p[29]&255)<<8;
        if(op==CeWire.QUERY)return ack(0,0,0,seq,0,0,0,4999,0,5000);
        if(op==CeWire.COMMIT)return ack(0,2,tx,seq,total,total,digest,tx,tx,tx);return ack(0,1,tx,seq,off+len,total,digest,0,tx,tx);}
    static List<CeWire.Card> cards(int k){List<CeWire.Card> c=new ArrayList<>();String[] w={"clarify","postpone","compare","budget","deadline"};for(int i=0;i<k;i++)c.add(new CeWire.Card(w[i],"合成测试场景：讨论明天的工作安排。","释义","Let's check it.",true));return c;}
    public static void main(String[] a)throws Exception{
        Path g=Paths.get(a[0]);byte[] bundle=Files.readAllBytes(g.resolve("bundle.bin"));
        // Golden: identical packets to the C sender, advancing on the C receiver's acks.
        CeTransfer t=new CeTransfer();ok(t.start(bundle,1000,0),"start");long now=0;int lines=0;
        for(String line:Files.readAllLines(g.resolve("transfer.txt"))){String[] f=line.split(" ");byte[] out=t.outgoing(now);ok(out!=null&&Arrays.equals(out,hex(f[0])),"packet "+lines);
            t.fileDone(t.attempt(),true);ok(t.ack(hex(f[1])),"ack "+lines);now+=10;lines++;}
        ok(t.state()==CeTransfer.COMPLETE&&lines==4,"complete");
        // Lost COMMIT ack: one retry after definitive file completion.
        t=new CeTransfer();t.start(bundle,1000,0);now=0;byte[] last=null;
        while(t.state()==CeTransfer.SENDING){byte[] out=t.outgoing(now);if(out==null){now+=100;t.tick(now);continue;}
            t.fileDone(t.attempt(),true);if(out[5]==CeWire.COMMIT&&last==null){last=out;now+=12001;t.tick(now);continue;}
            if(out[5]==CeWire.COMMIT)ok(Arrays.equals(out,last),"same COMMIT retried");ok(t.ack(reply(out)),"ack");now+=10;}
        ok(t.state()==CeTransfer.COMPLETE&&last!=null,"recovered after lost ack");
        // Unknown file state: no retry.
        t=new CeTransfer();t.start(bundle,1000,0);t.outgoing(0);t.tick(12000);ok(t.state()==CeTransfer.FAILED&&t.error()==CeWire.INCOMPLETE&&t.outgoing(12001)==null,"unknown file state fails, no resend");
        // Overall 110 s.
        t=new CeTransfer();t.start(bundle,1000,0);t.tick(110000);ok(t.state()==CeTransfer.FAILED&&t.error()==CeWire.EXPIRED,"110 s");
        // Rejected ack.
        t=new CeTransfer();t.start(bundle,1000,0);byte[] b0=t.outgoing(0);ok(t.ack(ack(CeWire.BUSY,0,1000,1,0,0,0,0,0,999))&&t.state()==CeTransfer.FAILED&&t.error()==CeWire.BUSY,"busy ack fails");
        t=new CeTransfer();t.start(bundle,1000,0);b0=t.outgoing(0);ok(!t.ack(ack(0,1,1000,1,5,(int)r32(b0,20),r32(b0,24),0,1000,1000))&&t.state()==CeTransfer.SENDING,"inconsistent ack ignored");
        // Session (ContextEnglishBridge): QUERY → tx → BEGIN/CHUNK/COMMIT → history.
        Fake f=new Fake();CeSession s=new CeSession(f,f,f);
        f.peer="";s.start(cards(5),"TOEFL",5,1200,true,false,0,1792990000L,java.time.ZoneOffset.UTC);ok(f.last.equals("眼镜未连接。")&&f.terminal,"no peer");
        f.peer="AA";f.querySeq=41;f.lastTx=1792990005L;s.start(cards(5),"TOEFL",5,1200,true,false,0,1792990000L,java.time.ZoneOffset.UTC);
        ok(s.active()&&f.sent.size()==1&&f.sent.get(0)[5]==CeWire.QUERY&&r32(f.sent.get(0),12)==42&&f.requests.get(0)==42&&f.sessions.get(0)==0&&f.querySeq==42,"QUERY with persisted sequence");
        drive(s,f,0);ok(f.sent.get(1)[5]==CeWire.BEGIN&&r32(f.sent.get(1),8)==1792990006L&&f.lastTx==1792990006L&&f.sessions.get(1)==1792990006L,"tx = max(last+1, highwater+1, now)");
        ok(f.last.equals("眼镜已确认保存题库；可进入「情境英语」。复习记录仅保存在本机。")&&f.terminal&&f.remembered==5&&f.rememberedTarget.equals("TOEFL")&&f.rememberedDay==20752&&!s.active(),"delivered and remembered");
        ok(f.sent.get(1)[0]=='T'&&f.acked.size()==f.sent.size(),"every TEA1 forwarded to the carrier gate");
        Fake h=new Fake();h.peer="AA";CeSession syn=new CeSession(h,h,h);syn.start(cards(2),"CET4",5,480,false,true,0,1792990000L,java.time.ZoneOffset.UTC);drive(syn,h,0);
        ok(h.remembered==0&&h.last.startsWith("眼镜已确认保存合成测试题"),"synthetic never touches history");
        syn.progress("AA",Files.readAllBytes(g.resolve("progress.bin")));ok(h.progressPeers.isEmpty(),"synthetic progress not recorded");
        // Busy glasses.
        Fake b=new Fake();b.peer="AA";CeSession busy=new CeSession(b,b,b);busy.start(cards(2),"CET4",5,480,false,false,0,1792990000L,java.time.ZoneOffset.UTC);
        byte[] q=b.sent.get(0);busy.reply("AA",ack(0,1,0,r32(q,12),10,100,7,0,9,9));busy.completed(TransferGate.State.CONFIRMED,10);ok(b.last.equals("眼镜当前忙碌或存在未完成传输，请稍后再试。")&&b.sent.size()==1,"busy refused");
        // Peer change mid-transfer, uncertain file state, config errors, reentry.
        Fake c=new Fake();c.peer="AA";CeSession mid=new CeSession(c,c,c);mid.start(cards(5),"CET4",5,480,false,false,0,1792990000L,java.time.ZoneOffset.UTC);
        byte[] p0=c.sent.get(0);mid.reply("AA",reply(p0));mid.completed(TransferGate.State.CONFIRMED,10);c.peer="BB";mid.pump(20);ok(c.last.equals("连接变化，传输已取消；不自动续传。")&&!mid.active(),"peer change");
        Fake u=new Fake();u.peer="AA";CeSession unk=new CeSession(u,u,u);unk.start(cards(5),"CET4",5,480,false,false,0,1792990000L,java.time.ZoneOffset.UTC);unk.reply("AA",reply(u.sent.get(0)));unk.completed(TransferGate.State.CONFIRMED,10);
        int sent=u.sent.size();unk.completed(TransferGate.State.UNCERTAIN,13000);unk.pump(14000);ok(u.last.equals("文件状态不明，停止重试。")&&u.sent.size()==sent&&!unk.active(),"uncertain: no resend");
        Fake e=new Fake();e.peer="AA";CeSession bad=new CeSession(e,e,e);bad.start(cards(5),"GRE",5,480,false,false,0,1792990000L,java.time.ZoneOffset.UTC);ok(e.last.equals("学习配置无效。"),"bad target");
        bad.start(cards(5),"CET4",4,480,false,false,0,1792990000L,java.time.ZoneOffset.UTC);ok(e.last.equals("学习配置无效。"),"more cards than count");
        List<CeWire.Card> longCard=cards(1);longCard.set(0,new CeWire.Card("abcdefghijklmnopqrstuvwxyz","q","m","e",true));bad.start(longCard,"CET4",5,480,false,false,0,1792990000L,java.time.ZoneOffset.UTC);ok(e.last.equals("候选超出眼镜显示预算或格式无效，未截断；请重新生成更短表达。"),"invalid card refused");
        e.ota=true;bad.start(cards(1),"CET4",5,480,false,false,0,1792990000L,java.time.ZoneOffset.UTC);ok(e.last.equals("固件升级保护中，不发送学习数据。"),"OTA protection");e.ota=false;
        bad.start(cards(1),"CET4",5,480,false,false,0,1792990000L,java.time.ZoneOffset.UTC);String before=e.last;bad.start(cards(1),"CET4",5,480,false,false,0,1792990000L,java.time.ZoneOffset.UTC);ok(e.last.equals("上一轮传输尚未释放；请等待完成或重新连接后查询。"),"one at a time "+before);
        // Channel refused before anything left the phone: reported as not submitted, not as an unknown outcome.
        Fake z=new Fake(){public boolean send(byte[] p,long request,long session){return false;}};z.peer="AA";CeSession ns=new CeSession(z,z,z);ns.start(cards(1),"CET4",5,480,false,false,0,1792990000L,java.time.ZoneOffset.UTC);
        ok(!ns.active()&&ns.lastNotSubmitted()&&!ns.lastDeliveryConfirmed(),"not submitted");
        ok(!syn.lastNotSubmitted()&&!unk.lastNotSubmitted(),"submitted sessions are not 'not submitted'");
        // Progress: only the current peer's progress is kept for history.
        Fake pr=new Fake();pr.peer="AA";CeSession ps=new CeSession(pr,pr,pr);byte[] prog=Files.readAllBytes(g.resolve("progress.bin"));ps.progress("BB",prog);ok(pr.progressPeers.isEmpty(),"other peer ignored");ps.progress("AA",prog);ok(pr.progressPeers.equals(Collections.singletonList("AA")),"current peer recorded");
        System.out.println("CeTransferTest: "+n+" checks; golden sender, retry, failures, session, history hooks");
    }
    static void drive(CeSession s,Fake f,long now){for(int guard=0;guard<40&&s.active();guard++){byte[] p=f.sent.get(f.sent.size()-1);int before=f.sent.size();s.reply(f.peer,reply(p));s.completed(TransferGate.State.CONFIRMED,now+=10);s.pump(now+=10);if(f.sent.size()==before&&s.active())s.pump(now+=10);}}
    static class Fake implements CeSession.Carrier,CeSession.Store,CeSession.History{
        String peer="",last="",rememberedTarget="";boolean terminal,ota;long querySeq,lastTx,rememberedDay;int remembered;
        List<byte[]> sent=new ArrayList<>();List<Long> requests=new ArrayList<>(),sessions=new ArrayList<>();List<long[]> acked=new ArrayList<>();List<String> progressPeers=new ArrayList<>();
        public String peer(){return peer;}public boolean otaProtected(){return ota;}
        public boolean send(byte[] p,long request,long session){sent.add(p);requests.add(request);sessions.add(session);return true;}
        public void ack(String peer,long request,long session,int result){acked.add(new long[]{request,session,result});}
        public void note(String text,boolean terminal){last=text;this.terminal=terminal;}
        public long querySequence(){return querySeq;}public void querySequence(long v){querySeq=v;}public long lastTx(){return lastTx;}public void lastTx(long v){lastTx=v;}
        public boolean remember(List<CeWire.Card> cards,String peer,String target,long day){remembered=cards.size();rememberedTarget=target;rememberedDay=day;return true;}
        public boolean progress(byte[] raw,String peer){progressPeers.add(peer);return true;}
    }
}
