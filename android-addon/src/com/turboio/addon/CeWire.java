package com.turboio.addon;
import java.nio.charset.StandardCharsets;
import java.util.*;

/** TEL1 context-English wire (byte-exact port of TVP2 context-english-v1 english_wire.c / english_progress.c and the
 * card rules of english_view.c): CED1 bundle, TEL1 packets, TEA1 acks, TEP1 progress. Invalid content is refused,
 * never truncated. */
final class CeWire {
    static final int QUERY=1,BEGIN=2,CHUNK=3,COMMIT=4,ABORT=5;
    static final int OK=0,BAD_PACKET=1,BUSY=2,STALE=3,BAD_OFFSET=4,INCOMPLETE=5,BAD_CHECKSUM=6,EXPIRED=7,STORE_FAILED=8,CONFLICT=9;
    static final int RX_IDLE=0,RX_RECEIVING=1,RX_COMMITTED=2;
    static final int BUNDLE_MAX=4608,CHUNK_MAX=384,PACKET_MAX=36+CHUNK_MAX,ACK_BYTES=44,PROGRESS_BYTES=72,MAX_CARDS=10;
    static final int UNSEEN=0,REMEMBERED=1,FORGOTTEN=2,SKIPPED=3;
    private CeWire(){}
    static final class Card{
        final String english,quote,meaning,example;final boolean generated;
        Card(String english,String quote,String meaning,String example,boolean generated){this.english=english;this.quote=quote;this.meaning=meaning;this.example=example;this.generated=generated;}
    }
    static final class Ack{int result,state;long tx,seq,next,total,digest,committed,active,highwater;}
    static final class Progress{long day,tx;int limit,used;long[] words=new long[MAX_CARDS];int[] results=new int[MAX_CARDS];}

    static long crc32(byte[] p,int off,int n){int c=~0;for(int i=0;i<n;i++){c^=p[off+i]&255;for(int k=0;k<8;k++)c=(c>>>1)^(-(c&1)&0xedb88320);}return (~c)&0xffffffffL;}
    private static long r32(byte[] p,int at){return (p[at]&255L)|(p[at+1]&255L)<<8|(p[at+2]&255L)<<16|(p[at+3]&255L)<<24;}
    private static int r16(byte[] p,int at){return (p[at]&255)|(p[at+1]&255)<<8;}
    private static void w32(byte[] p,int at,long v){for(int i=0;i<4;i++)p[at+i]=(byte)(v>>(8*i));}
    private static void w16(byte[] p,int at,int v){p[at]=(byte)v;p[at+1]=(byte)(v>>8);}
    private static boolean u32(long v){return v>=0&&v<=0xffffffffL;}

    /** english_view.c valid(): strict scalars, no controls/bidi/separators, ≤max scalars, some non-space, < cap bytes. */
    private static boolean field(String s,int cap,int max){
        if(s==null||s.isEmpty())return false;
        for(int i=0;i<s.length();i++){char c=s.charAt(i);if(Character.isHighSurrogate(c)){if(i+1>=s.length()||!Character.isLowSurrogate(s.charAt(i+1)))return false;i++;}else if(Character.isLowSurrogate(c))return false;}
        if(s.getBytes(StandardCharsets.UTF_8).length>=cap)return false;
        int count=0;boolean nonspace=false;
        for(int i=0;i<s.length();){int cp=s.codePointAt(i);i+=Character.charCount(cp);
            if(cp<32||(cp>=127&&cp<=159)||cp==0x2028||cp==0x2029||(cp>=0x202a&&cp<=0x202e)||(cp>=0x2066&&cp<=0x2069))return false;
            if(++count>max)return false;if(cp!=' ')nonspace=true;}
        return nonspace;
    }
    static boolean cardValid(Card c){
        if(c==null||!field(c.english,32,24)||!field(c.quote,160,49)||!field(c.meaning,72,22)||!field(c.example,192,60))return false;
        boolean letter=false;for(int i=0;i<c.english.length();i++){char a=c.english.charAt(i);if((a>='a'&&a<='z')||(a>='A'&&a<='Z'))letter=true;else if(a!=' '&&a!='-'&&a!='\'')return false;}
        return letter;
    }
    /** CED1 bundle; null when any card, the target (0..3), day/expiry (non-zero u32) or minute (<1440) is invalid. */
    static byte[] bundle(List<Card> cards,int target,long day,long expires,int minute,boolean reminder){
        if(cards==null||cards.isEmpty()||cards.size()>MAX_CARDS||target<0||target>3||day<=0||!u32(day)||expires<=0||!u32(expires)||minute<0||minute>=1440)return null;
        java.io.ByteArrayOutputStream out=new java.io.ByteArrayOutputStream();byte[] head=new byte[20];head[0]='C';head[1]='E';head[2]='D';head[3]='1';head[4]=1;head[5]=(byte)cards.size();head[6]=(byte)target;head[7]=(byte)(reminder?1:0);
        w32(head,8,day);w32(head,12,expires);w16(head,16,minute);out.write(head,0,20);
        for(Card c:cards){if(!cardValid(c))return null;out.write(c.generated?1:0);
            for(String f:new String[]{c.english,c.quote,c.meaning,c.example}){byte[] b=f.getBytes(StandardCharsets.UTF_8);out.write(b.length&255);out.write(b.length>>8);out.write(b,0,b.length);}}
        return out.size()<=BUNDLE_MAX?out.toByteArray():null;
    }
    private static boolean packetValid(int op,long tx,long seq,long offset,long total,long digest,int length){
        if(seq<=0||!u32(seq)||!u32(tx)||!u32(offset)||!u32(total)||!u32(digest)||length<0||length>CHUNK_MAX)return false;
        if(op==QUERY)return tx==0&&offset==0&&total==0&&digest==0&&length==0;
        if(op<BEGIN||op>ABORT||tx==0||total<20||total>BUNDLE_MAX||offset>total)return false;
        if(op==BEGIN)return seq==1&&offset==0&&length==0;
        if(seq<2)return false;
        if(op==CHUNK)return length>0&&length<=total-offset;
        if(op==COMMIT)return offset==total&&length==0;
        return length==0;
    }
    /** TEL1 packet (36 + length bytes, CRC over all but the last 4); null when the fields break english_wire rules. */
    static byte[] packet(int op,long tx,long seq,long offset,long total,long digest,byte[] payload,int from,int length){
        if(!packetValid(op,tx,seq,offset,total,digest,length)||(length>0&&(payload==null||from<0||from+length>payload.length)))return null;
        byte[] out=new byte[36+length];out[0]='T';out[1]='E';out[2]='L';out[3]='1';out[4]=1;out[5]=(byte)op;
        w32(out,8,tx);w32(out,12,seq);w32(out,16,offset);w32(out,20,total);w32(out,24,digest);w16(out,28,length);
        if(length>0)System.arraycopy(payload,from,out,32,length);w32(out,out.length-4,crc32(out,0,out.length-4));return out;
    }
    /** TEA1 ack (44 bytes); null when malformed or inconsistent (ack_valid). */
    static Ack ack(byte[] p){
        if(p==null||p.length!=ACK_BYTES||p[0]!='T'||p[1]!='E'||p[2]!='A'||p[3]!='1'||p[4]!=1||p[7]!=0||r32(p,40)!=crc32(p,0,40))return null;
        Ack a=new Ack();a.result=p[5]&255;a.state=p[6]&255;a.tx=r32(p,8);a.seq=r32(p,12);a.next=r32(p,16);a.total=r32(p,20);a.digest=r32(p,24);a.committed=r32(p,28);a.active=r32(p,32);a.highwater=r32(p,36);
        if(a.seq==0||a.result>CONFLICT||a.state>RX_COMMITTED||a.total>BUNDLE_MAX||a.next>a.total||a.committed>a.highwater||a.active>a.highwater)return null;
        if(a.state==RX_IDLE)return a.active==0&&a.next==0&&a.total==0&&a.digest==0?a:null;
        if(a.active==0||a.total<20)return null;
        return a.state!=RX_COMMITTED||(a.active==a.committed&&a.next==a.total)?a:null;
    }
    /** TEP1 progress (72 bytes); null when malformed (english_progress ce_progress_decode). */
    static Progress progress(byte[] p){
        if(p==null||p.length!=PROGRESS_BYTES||p[0]!='T'||p[1]!='E'||p[2]!='P'||p[3]!='1'||p[4]!=1||(p[5]&255)>10||(p[6]&255)>10||p[7]!=0||p[66]!=0||p[67]!=0||r32(p,68)!=crc32(p,0,68))return null;
        Progress g=new Progress();g.day=r32(p,8);g.limit=p[5]&255;g.used=p[6]&255;g.tx=r32(p,12);
        if(g.day==0&&(g.used!=0||g.limit!=0))return null;
        for(int i=0;i<MAX_CARDS;i++){g.words[i]=r32(p,16+i*4);g.results[i]=p[56+i]&255;
            if(i<g.used){if(g.words[i]==0||g.results[i]<1||g.results[i]>3)return null;for(int j=0;j<i;j++)if(g.words[j]==g.words[i])return null;}
            else if(g.words[i]!=0||g.results[i]!=0)return null;}
        return g;
    }
}
