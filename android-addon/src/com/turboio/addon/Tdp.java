package com.turboio.addon;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;

/** TDP1 phone-side codec (port of display_client.c, display_carrier.c, the TDR1 reply codec of display_runtime.c and
 * DisplayDelta.c) for TVP2 display-runtime-v1. Pure: no I/O. Encoders return null wherever the C returns 0. */
final class Tdp {
    static final int WIDTH=512,HEIGHT=128,PIXELS=65536,HEADER=32,MAX_RECT=16384,MAX_PACKET=16424,NATIVE_MAX=512,NATIVE_PIXELS=472,REPLY_BYTES=40;
    static final int QUERY=1,RECT=2,KEEPALIVE=3,CLOSE=4,BEGIN=5,CHUNK=6,COMMIT=7,ABORT=8;
    static final int CAPS=0,UI_SUBMITTED=1,ALIVE=2,CLOSED=3,BAD_PACKET=4,NO_SESSION=5,STALE=6,BUSY=7,RENDER_ERROR=8,STAGED=9,ABORTED=10;
    static final String FILE="turbo-display.tdp";
    static final long U32=0xffffffffL;
    private Tdp(){}

    static long crc(byte[] p,int off,int n){int c=-1;for(int i=off;i<off+n;i++){c^=p[i]&255;for(int b=0;b<8;b++)c=(c>>>1)^(0xedb88320&-(c&1));}return ~c&U32;}
    private static void p16(byte[] p,int at,int v){p[at]=(byte)v;p[at+1]=(byte)(v>>8);}
    private static void p32(byte[] p,int at,long v){for(int i=0;i<4;i++)p[at+i]=(byte)(v>>(8*i));}
    static long u32(byte[] p,int at){return (p[at]&255L)|(p[at+1]&255L)<<8|(p[at+2]&255L)<<16|(p[at+3]&255L)<<24;}
    static int u16(byte[] p,int at){return (p[at]&255)|(p[at+1]&255)<<8;}
    private static boolean u32ok(long v){return v>=0&&v<=U32;}
    private static byte[] header(int op,long sid,long req,long base,int n){
        if(!u32ok(sid)||!u32ok(req)||!u32ok(base)||req==0||n<0||n>MAX_PACKET-HEADER||(op!=QUERY&&sid==0)||(op>=BEGIN&&base==U32)||(op==RECT&&base==U32))return null;
        byte[] p=new byte[HEADER+n];p[0]='T';p[1]='D';p[2]='P';p[3]='1';p[4]=1;p[5]=(byte)op;
        p32(p,8,sid);p32(p,12,req);p32(p,16,base);p32(p,20,(base+((op==RECT||op>=BEGIN)?1:0))&U32);p32(p,24,n);return p;
    }
    private static byte[] seal(byte[] p){if(p!=null)p32(p,28,crc(p,HEADER,p.length-HEADER));return p;}
    static byte[] query(long req){return seal(header(QUERY,0,req,0,0));}
    static byte[] control(int op,long sid,long req,long rev){return op!=KEEPALIVE&&op!=CLOSE?null:seal(header(op,sid,req,rev,0));}
    static byte[] rect(long sid,long req,long base,int x,int y,int w,int h,byte[] px){
        if(px==null||w<=0||h<=0||x<0||y<0||x>=WIDTH||y>=HEIGHT||w>WIDTH-x||h>HEIGHT-y||w*h>MAX_RECT||px.length!=w*h)return null;
        byte[] p=header(RECT,sid,req,base,8+px.length);if(p==null)return null;
        p16(p,32,x);p16(p,34,y);p16(p,36,w);p16(p,38,h);System.arraycopy(px,0,p,40,px.length);return seal(p);
    }
    static byte[] begin(long sid,long req,long base,long tx,long frameCrc){
        if(tx==0||!u32ok(tx)||!u32ok(frameCrc))return null;byte[] p=header(BEGIN,sid,req,base,12);if(p==null)return null;
        p32(p,32,tx);p32(p,36,PIXELS);p32(p,40,frameCrc);return seal(p);
    }
    static byte[] chunk(long sid,long req,long base,long tx,long at,byte[] px,int off,int len){
        if(tx==0||!u32ok(tx)||px==null||len<=0||len>MAX_RECT||off<0||off>px.length-len||at<0||at>PIXELS||len>PIXELS-at)return null;
        byte[] p=header(CHUNK,sid,req,base,8+len);if(p==null)return null;
        p32(p,32,tx);p32(p,36,at);System.arraycopy(px,off,p,40,len);return seal(p);
    }
    static byte[] finish(int op,long sid,long req,long base,long tx){
        if(tx==0||!u32ok(tx)||(op!=COMMIT&&op!=ABORT))return null;byte[] p=header(op,sid,req,base,4);if(p==null)return null;p32(p,32,tx);return seal(p);
    }

    static final class Reply{int result;long sid,request,revision,maxRect,lease;int width,height;}
    static byte[] replyEncode(Reply r){
        if(r==null||r.result<CAPS||r.result>ABORTED)return null;byte[] o=new byte[REPLY_BYTES];o[0]='T';o[1]='D';o[2]='R';o[3]='1';o[4]=1;o[5]=(byte)r.result;
        p32(o,8,r.sid);p32(o,12,r.request);p32(o,16,r.revision);p16(o,20,r.width);p16(o,22,r.height);p32(o,24,r.maxRect);p32(o,28,r.lease);p32(o,36,crc(o,0,36));return o;
    }
    static Reply replyDecode(byte[] p){
        if(p==null||p.length!=REPLY_BYTES||p[0]!='T'||p[1]!='D'||p[2]!='R'||p[3]!='1'||p[4]!=1||(p[5]&255)>ABORTED||p[6]!=0||p[7]!=0||u32(p,32)!=0||crc(p,0,36)!=u32(p,36))return null;
        Reply r=new Reply();r.result=p[5]&255;r.sid=u32(p,8);r.request=u32(p,12);r.revision=u32(p,16);r.width=u16(p,20);r.height=u16(p,22);r.maxRect=u32(p,24);r.lease=u32(p,28);return r;
    }
    private static final byte[] PREFIX="{\"cmd\":\"turbo_display_v1\",\"payload\":{\"value\":0,\"mode\":0,\"data\":\"".getBytes(StandardCharsets.US_ASCII),SUFFIX="\"}}".getBytes(StandardCharsets.US_ASCII);
    private static final int JSON=PREFIX.length+REPLY_BYTES*2+SUFFIX.length,PB=JSON+7;
    private static final byte[] HEAD={8,1,16,6,26,(byte)((JSON&127)|128),(byte)(JSON>>7)};
    private static final char[] HEX="0123456789abcdef".toCharArray();
    /** Exact business-15 PB envelope the glasses emit (tdp_carrier_reply). */
    static byte[] carrierEncode(Reply r){
        byte[] raw=replyEncode(r);if(raw==null)return null;byte[] o=new byte[PB];System.arraycopy(HEAD,0,o,0,7);System.arraycopy(PREFIX,0,o,7,PREFIX.length);
        for(int i=0;i<raw.length;i++){o[7+PREFIX.length+2*i]=(byte)HEX[(raw[i]>>4)&15];o[8+PREFIX.length+2*i]=(byte)HEX[raw[i]&15];}
        System.arraycopy(SUFFIX,0,o,PB-SUFFIX.length,SUFFIX.length);return o;
    }
    private static int nibble(byte c){return c>='0'&&c<='9'?c-'0':c>='a'&&c<='f'?c-'a'+10:-1;}
    /** Strict canonical decode of our own encoder only (tdp_carrier_decode); everything else is foreign. */
    static Reply carrierDecode(int business,byte[] p){
        if(p==null||business!=15||p.length!=PB)return null;
        for(int i=0;i<7;i++)if(p[i]!=HEAD[i])return null;for(int i=0;i<PREFIX.length;i++)if(p[7+i]!=PREFIX[i])return null;for(int i=0;i<SUFFIX.length;i++)if(p[PB-SUFFIX.length+i]!=SUFFIX[i])return null;
        byte[] raw=new byte[REPLY_BYTES];for(int i=0;i<raw.length;i++){int a=nibble(p[7+PREFIX.length+2*i]),b=nibble(p[8+PREFIX.length+2*i]);if(a<0||b<0)return null;raw[i]=(byte)(a<<4|b);}
        return replyDecode(raw);
    }
    /** DisplayPhoneTransport Valid: ≤512 B and byte-identical to the canonical rebuild of its own fields. */
    static boolean valid(byte[] d){
        if(d==null||d.length<HEADER||d.length>NATIVE_MAX)return false;long sid=u32(d,8),req=u32(d,12),base=u32(d,16);byte[] b=null;int n=d.length;
        switch(d[5]){
            case QUERY:b=query(req);break;
            case KEEPALIVE:case CLOSE:b=control(d[5],sid,req,base);break;
            case RECT:if(n>=41)b=rect(sid,req,base,u16(d,32),u16(d,34),u16(d,36),u16(d,38),Arrays.copyOfRange(d,40,n));break;
            case BEGIN:if(n==44)b=begin(sid,req,base,u32(d,32),u32(d,40));break;
            case CHUNK:if(n>=41)b=chunk(sid,req,base,u32(d,32),u32(d,36),d,40,n-40);break;
            case COMMIT:case ABORT:if(n==36)b=finish(d[5],sid,req,base,u32(d,32));break;
            default:break;
        }
        return b!=null&&Arrays.equals(b,d);
    }

    static final class Delta{int count;long pixels;final int[][] rects=new int[32][4];}
    /** tdp_delta_batch: fixed 24×16 tiles tightened to the differences. 0 done, 1 more remain (output valid), -1 invalid. */
    static int deltaBatch(byte[] old,byte[] next,int limit,Delta out){
        if(out==null)return -1;out.count=0;out.pixels=0;
        if(old==null||next==null||limit<1||limit>32||old.length!=PIXELS||next.length!=PIXELS)return -1;
        for(int y=0;y<HEIGHT;y+=16)for(int x=0;x<WIDTH;x+=24){
            int right=Math.min(x+24,WIDTH),x0=right,y0=y+16,x1=0,y1=0;boolean changed=false;
            for(int yy=y;yy<y+16;yy++)for(int xx=x;xx<right;xx++){int i=yy*WIDTH+xx;if(old[i]==next[i])continue;changed=true;if(xx<x0)x0=xx;if(yy<y0)y0=yy;if(xx>x1)x1=xx;if(yy>y1)y1=yy;}
            if(!changed)continue;if(out.count==limit)return 1;
            int[] r=out.rects[out.count++];r[0]=x0;r[1]=y0;r[2]=x1-x0+1;r[3]=y1-y0+1;out.pixels+=(long)r[2]*r[3];
        }
        return 0;
    }
    /** tdp_delta_plan: all differences in ≤32 rects, else 1 with an empty plan. */
    static int deltaPlan(byte[] old,byte[] next,Delta out){int r=deltaBatch(old,next,32,out);if(r==1){out.count=0;out.pixels=0;}return r;}
}
