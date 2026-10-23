package com.turboio.addon;
import java.time.*;
import java.util.*;

/** One TEL1 delivery to the pinned glasses (port of iOS ContextEnglishBridge.m): QUERY the runtime, choose a fresh tx
 * above the glasses' highwater, send the CED1 bundle with CeTransfer, then record the delivered cards for local review.
 * The carrier merges file completion and the TEA1 ack (TransferGate), so an unconfirmed file state ends the session and
 * is never resent. Main executor only. */
final class CeSession {
    interface Carrier{
        String peer();boolean otaProtected();
        /** Submit one turbo-english.tel packet; request/session identify the TEA1 ack (QUERY: seq/0, transfer: seq/tx). */
        boolean send(byte[] packet,long request,long session);
        void ack(String peer,long request,long session,int result);
        void note(String text,boolean terminal);
    }
    interface Store{long querySequence();void querySequence(long v);long lastTx();void lastTx(long v);}
    interface History{boolean remember(List<CeWire.Card> cards,String peer,String target,long day);boolean progress(byte[] raw,String peer);}
    static final List<String> TARGETS=Arrays.asList("CET4","CET6","TOEFL","IELTS");

    private final Carrier carrier;private final Store store;private final History history;
    private final CeTransfer transfer=new CeTransfer();
    private String peer="",target="";private List<CeWire.Card> cards=Collections.emptyList();private byte[] bundle,progressPacket;
    private long querySeq,day,unixNow;private boolean active,querying,inFlight,synthetic,delivered,submitted;private CeWire.Ack queryAck;
    CeSession(Carrier carrier,Store store,History history){this.carrier=carrier;this.store=store;this.history=history;}
    boolean active(){return active;}
    boolean lastDeliveryConfirmed(){return delivered&&!active;}
    /** The last session ended before any packet was handed to the carrier: nothing left the phone. */
    boolean lastNotSubmitted(){return !active&&!submitted;}

    private void end(String note){transfer.cancel();active=querying=inFlight=false;bundle=null;cards=Collections.emptyList();queryAck=null;carrier.note(note,true);}

    /** Starts a delivery; every refusal ends with a terminal note. unixNow seconds; zone selects the learning day. */
    void start(List<CeWire.Card> list,String targetCode,int count,int minute,boolean reminder,boolean syntheticTest,long now,long unixNow,ZoneId zone){
        if(active){carrier.note("上一轮传输尚未释放；请等待完成或重新连接后查询。",true);return;}
        delivered=false;submitted=false;synthetic=syntheticTest;progressPacket=null;
        if(carrier.otaProtected()){end("固件升级保护中，不发送学习数据。");return;}
        String current=carrier.peer();if(current==null||current.isEmpty()){end("眼镜未连接。");return;}
        int t=TARGETS.indexOf(targetCode);
        if(t<0||minute<0||minute>1439||count<1||count>10||list==null||list.size()>count){end("学习配置无效。");return;}
        LocalDate today=Instant.ofEpochSecond(unixNow).atZone(zone).toLocalDate();long d=today.toEpochDay(),expires=today.plusDays(1).atStartOfDay(zone).toEpochSecond();
        if(d<=0||d>0xffffffffL||expires<=0||expires>0xffffffffL){end("当前日期不可用。");return;}
        byte[] encoded=CeWire.bundle(list,t,d,expires,minute,reminder);
        if(encoded==null){end("候选超出眼镜显示预算或格式无效，未截断；请重新生成更短表达。");return;}
        long sequence=store.querySequence()+1;if(sequence>0xffffffffL){end("查询编号已耗尽。");return;}store.querySequence(sequence);
        bundle=encoded;cards=new ArrayList<>(list);target=targetCode;day=d;this.unixNow=unixNow;querySeq=sequence;peer=current;active=querying=true;queryAck=null;
        issue(CeWire.packet(CeWire.QUERY,0,sequence,0,0,0,null,0,0),sequence,0);
    }
    private void issue(byte[] packet,long request,long session){
        if(carrier.otaProtected()||!peer.equals(carrier.peer())){end("升级保护或设备连接变化，已停止发送。");return;}
        if(!carrier.send(packet,request,session)){end("传输通道忙或未连接，未发送；不会自动重发。");return;}inFlight=true;submitted=true;
        if(querying)carrier.note("正在回查 TEL1 能力与题库编号…",false);
        else carrier.note(String.format(Locale.ROOT,"发送题库 · 第 %d / %d 包 · %d / %d 字节",transfer.seq(),2+(transfer.total()+CeWire.CHUNK_MAX-1)/CeWire.CHUNK_MAX,transfer.next(),transfer.total()),false);
    }
    /** TEA1 from the pinned peer: forwarded to the carrier gate when it belongs to the packet in flight. */
    void reply(String from,byte[] raw){
        CeWire.Ack a=CeWire.ack(raw);if(!active||!inFlight||a==null||!peer.equals(from)||!peer.equals(carrier.peer()))return;
        if(querying){if(a.tx!=0||a.seq!=querySeq)return;queryAck=a;carrier.ack(from,a.seq,0,a.result);return;}
        if(a.tx!=transfer.tx()||a.seq!=transfer.seq())return;transfer.ack(raw);carrier.ack(from,a.seq,a.tx,a.result);
    }
    /** TEP1 progress from the glasses; only the currently connected peer's record reaches history. */
    void progress(String from,byte[] raw){
        String current=carrier.peer();if(CeWire.progress(raw)==null||current==null||current.isEmpty()||!current.equals(from))return;
        if(active&&peer.equals(from))progressPacket=raw.clone();
        if(!synthetic)history.progress(raw,from);
    }
    /** Carrier result for the packet in flight. */
    void completed(TransferGate.State state,long now){
        if(!active||!inFlight)return;inFlight=false;
        if(querying){
            if(state==TransferGate.State.CONFIRMED&&queryAck!=null){
                if(queryAck.result!=CeWire.OK||queryAck.state==CeWire.RX_RECEIVING){end("眼镜当前忙碌或存在未完成传输，请稍后再试。");return;}
                long fresh=Math.max(Math.max(store.lastTx()+1,queryAck.highwater+1),unixNow);
                if(fresh>0xffffffffL||!transfer.start(bundle,fresh,now)){end("无法创建有界题库传输。");return;}
                store.lastTx(fresh);bundle=null;querying=false;pump(now);return;
            }
            if(state==TransferGate.State.REJECTED){end("眼镜当前忙碌或存在未完成传输，请稍后再试。");return;}
            if(state==TransferGate.State.FAILED){end("文件传输失败，已释放本次发送。");return;}
            end("TEL1 查询超时，文件传输尚未确认完成；暂不能判断固件是否支持，不继续发送题库。");return;
        }
        if(state==TransferGate.State.CONFIRMED||state==TransferGate.State.REJECTED){transfer.fileDone(transfer.attempt(),true);pump(now);return;}
        if(state==TransferGate.State.FAILED){end("文件传输失败，已释放本次发送。");return;}
        end("文件状态不明，停止重试。");
    }
    void pump(long now){
        if(!active)return;
        if(!peer.equals(carrier.peer())){end("连接变化，传输已取消；不自动续传。");return;}
        if(carrier.otaProtected()){end("升级保护已开启，学习传输停止。");return;}
        if(querying||inFlight)return;
        transfer.tick(now);
        if(transfer.state()==CeTransfer.FAILED){end("题库未完成（"+transfer.error()+"），没有自动重开传输。");return;}
        if(transfer.state()==CeTransfer.COMPLETE){delivered=true;boolean saved=synthetic||history.remember(cards,peer,target,day);
            if(!synthetic&&saved&&progressPacket!=null)history.progress(progressPacket,peer);
            end(synthetic?"眼镜已确认保存合成测试题；请进入「情境英语」。未加入本机复习记录。":saved?"眼镜已确认保存题库；可进入「情境英语」。复习记录仅保存在本机。":"眼镜已保存题库，但本机复习记录保存失败；不会重发题库。");return;}
        byte[] p=transfer.outgoing(now);if(p!=null)issue(p,transfer.seq(),transfer.tx());
    }
    /** Explicit cancel (page closed): no further packets; the carrier keeps any in-flight file. */
    void cancel(){if(active)end("已取消发送；在途文件由传输通道收尾。");}
}
