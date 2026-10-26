package com.turboio.addon;
import java.nio.charset.StandardCharsets;
import java.util.zip.CRC32;

/** TDR1 Didi card wire (byte-exact port of TVP2 didi-v1 ride.c): 392-byte SNAPSHOT/CLOSE/QUERY commands, sandbox
 * flag mandatory, and the 32-byte DRA1 glasses reply. */
final class DrWire {
    static final int PACKET=392,SHOW=1,CONFIRM=2;
    static final int IDLE=0,QUOTE=1,CANCEL_CONFIRM=2,MATCHING=3,PICKUP=4,ARRIVED=5,TRIP=6,DONE=7,CANCELLED=8,ERROR=9;
    static final int SNAPSHOT=1,CLOSE=2,QUERY=3;
    static final int OK=0,BAD=1,OLD=2,BUSY=3,NO_SESSION=4;
    static final int ACK=0,OPENED=1,CONFIRMED=2,CLOSED=3;
    private DrWire(){}
    static final class Scene{int phase,flags,ttl;long nonce;String metric="",title="",line1="",line2="",footer="";
        Scene copy(){Scene s=new Scene();s.phase=phase;s.flags=flags;s.ttl=ttl;s.nonce=nonce;s.metric=metric;s.title=title;s.line1=line1;s.line2=line2;s.footer=footer;return s;}}
    static final class Reply{int result,event,phase;long sid,seq,nonce;boolean consumed;}
    private static long crc(byte[] p,int n){CRC32 c=new CRC32();c.update(p,0,n);return c.getValue();}
    private static void put(byte[] p,int at,long v){for(int i=0;i<4;i++)p[at+i]=(byte)(v>>(8*i));}
    private static long u32(byte[] p,int at){return (p[at]&255L)|(p[at+1]&255L)<<8|(p[at+2]&255L)<<16|(p[at+3]&255L)<<24;}
    /** NUL-terminated strict UTF-8 without controls, < cap bytes. */
    private static byte[] text(String s,int cap){
        if(s==null)return null;for(int i=0;i<s.length();i++){char c=s.charAt(i);if(c<0x20||c==0x7f)return null;if(Character.isHighSurrogate(c)){if(i+1>=s.length()||!Character.isLowSurrogate(s.charAt(i+1)))return null;i++;}else if(Character.isLowSurrogate(c))return null;}
        byte[] b=s.getBytes(StandardCharsets.UTF_8);return b.length<cap?b:null;
    }
    static boolean sceneOk(Scene s){
        return s!=null&&s.phase>=0&&s.phase<=ERROR&&(s.flags&~3)==0&&s.ttl>=15&&s.ttl<=120&&s.nonce>=0&&s.nonce<=0xffffffffL&&((s.flags&CONFIRM)==0||(s.nonce!=0&&(s.phase==QUOTE||s.phase==CANCEL_CONFIRM)))
            &&text(s.metric,32)!=null&&text(s.title,64)!=null&&text(s.line1,96)!=null&&text(s.line2,96)!=null&&text(s.footer,64)!=null;
    }
    /** 392-byte command; null when ids, op or scene are invalid. */
    static byte[] encode(int op,long sid,long seq,Scene s){
        if(sid<=0||sid>0xffffffffL||seq<=0||seq>0xffffffffL||op<1||op>3||(op==SNAPSHOT&&!sceneOk(s)))return null;
        byte[] p=new byte[PACKET];p[0]='T';p[1]='D';p[2]='R';p[3]='1';p[4]=1;p[5]=(byte)op;p[6]=1;put(p,8,sid);put(p,12,seq);put(p,16,PACKET-32);
        if(op==SNAPSHOT){p[32]=(byte)s.phase;p[33]=(byte)s.flags;p[34]=(byte)s.ttl;p[35]=(byte)(s.ttl>>8);put(p,36,s.nonce);
            int[][] at={{40,32},{72,64},{136,96},{232,96},{328,64}};String[] f={s.metric,s.title,s.line1,s.line2,s.footer};
            for(int i=0;i<5;i++){byte[] b=text(f[i],at[i][1]);System.arraycopy(b,0,p,at[i][0],b.length);}}
        put(p,20,crc(p,PACKET));return p;
    }
    /** DRA1 reply (32 bytes, CRC at 28); null when malformed. */
    static Reply reply(byte[] b){
        if(b==null||b.length!=32||b[0]!='D'||b[1]!='R'||b[2]!='A'||b[3]!='1'||b[4]!=1||(b[5]&255)>NO_SESSION||(b[6]&255)>CLOSED||b[7]!=1||(b[20]&255)>ERROR||(b[21]&255)>1||u32(b,28)!=crc(b,28))return null;
        for(int i=22;i<28;i++)if(b[i]!=0)return null;
        Reply r=new Reply();r.result=b[5]&255;r.event=b[6]&255;r.sid=u32(b,8);r.seq=u32(b,12);r.nonce=u32(b,16);r.phase=b[20]&255;r.consumed=b[21]==1;return r;
    }
}
