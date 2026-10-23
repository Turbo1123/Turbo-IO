package com.turboio.addon;
import java.util.Arrays;

/** TEL1 sender state machine (port of TVP2 context-english-v1 english_transfer.c): BEGIN → CHUNK… → COMMIT, one
 * packet in flight, advance only on definitive file completion plus a matching TEA1 ack, 12 s per packet, at most
 * two retries and only after the file completed, 110 s overall. Times are monotonic milliseconds. */
final class CeTransfer {
    static final int IDLE=0,SENDING=1,COMPLETE=2,FAILED=3,CANCELLED=4;
    private byte[] bytes=new byte[0],packet;private long tx,seq,total,digest,next,deadline,started,attempt;
    private int op,state=IDLE,retries,error;private boolean fileDone,acked,issued;
    int state(){return state;}int error(){return error;}long attempt(){return attempt;}long seq(){return seq;}long next(){return next;}long total(){return total;}long tx(){return tx;}
    private void finish(int s,int e){state=s;error=e;Arrays.fill(bytes,(byte)0);if(packet!=null)Arrays.fill(packet,(byte)0);packet=null;issued=false;}
    private boolean prepare(){
        int length=op==CeWire.CHUNK?(int)Math.min(CeWire.CHUNK_MAX,total-next):0;
        packet=CeWire.packet(op,tx,seq,next,total,digest,bytes,(int)next,length);issued=fileDone=acked=false;retries=0;return packet!=null;
    }
    /** Starts a transfer of an encoded CED1 bundle with a caller-chosen tx (after QUERY). */
    boolean start(byte[] bundle,long tx,long now){
        if(state==SENDING||tx<=0||tx>0xffffffffL)return false;long keep=attempt;
        bytes=new byte[0];packet=null;seq=total=digest=next=deadline=started=0;op=retries=error=0;fileDone=acked=issued=false;attempt=keep;
        if(bundle==null||bundle.length<20||bundle.length>CeWire.BUNDLE_MAX){finish(FAILED,CeWire.BAD_PACKET);return false;}
        bytes=bundle.clone();total=bytes.length;digest=CeWire.crc32(bytes,0,bytes.length);this.tx=tx;seq=1;op=CeWire.BEGIN;state=SENDING;started=now;
        if(!prepare()){finish(FAILED,CeWire.BAD_PACKET);return false;}return true;
    }
    /** Next packet to submit (a copy), or null while one is in flight or the transfer has ended; attempt() tags it. */
    byte[] outgoing(long now){
        tick(now);if(state!=SENDING||issued)return null;
        if(attempt==0xffffffffL){finish(FAILED,CeWire.STALE);return null;}
        issued=true;deadline=now+12000;attempt++;return packet.clone();
    }
    private void advance(){
        if(state!=SENDING||!issued||!fileDone||!acked)return;
        if(op==CeWire.COMMIT){finish(COMPLETE,CeWire.OK);return;}
        if(op==CeWire.CHUNK)next+=packet.length-36;
        op=next==total?CeWire.COMMIT:CeWire.CHUNK;seq++;
        if(!prepare())finish(FAILED,CeWire.BAD_PACKET);
    }
    void fileDone(long attemptId,boolean success){
        if(state!=SENDING||!issued||attemptId!=attempt)return;
        if(!success){finish(FAILED,CeWire.BAD_PACKET);return;}fileDone=true;advance();
    }
    /** True when the ack belongs to the packet in flight (consumed); a result ≠ OK fails the transfer. */
    boolean ack(byte[] raw){
        CeWire.Ack a=CeWire.ack(raw);if(state!=SENDING||!issued||a==null||a.tx!=tx||a.seq!=seq)return false;
        if(a.result!=CeWire.OK){finish(FAILED,a.result);return true;}
        long expected=next+(op==CeWire.CHUNK?packet.length-36:0);
        if(a.active!=tx||a.highwater!=tx||a.total!=total||a.digest!=digest||a.next!=expected||a.state!=(op==CeWire.COMMIT?CeWire.RX_COMMITTED:CeWire.RX_RECEIVING)||(op==CeWire.COMMIT&&a.committed!=tx))return false;
        acked=true;advance();return true;
    }
    void tick(long now){
        if(state!=SENDING)return;
        if(now-started>=110000){finish(FAILED,CeWire.EXPIRED);return;}
        if(issued&&now-deadline>=0){
            // Retry only after definitive file completion; an unknown native operation never gets a second submission.
            if(!fileDone||retries>=2){finish(FAILED,CeWire.INCOMPLETE);return;}
            retries++;issued=false;fileDone=acked=false;
        }
    }
    void cancel(){finish(CANCELLED,CeWire.OK);}
}
