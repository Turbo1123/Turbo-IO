package com.turboio.addon;

/** TVP1 video-player wire codec (port of TVP2 video-player-v1 player.c, phone side): "TVP1" requests / "VPA1"
 * replies with a 32-byte header and a whole-packet CRC that skips its own field, PackBits-style compression and the
 * displayed-pixel CRC. Pure. Encoders return null wherever the C returns 0. */
final class Vp {
    static final int W=540,H=220,STRIDE_MAX=544,PACKED_MAX=14850,COMP_MAX=14967,HEADER=32,WIRE_MAX=14999,HD_FLAG=1,HD_ROWS=55;
    static final long HD_CAP=0x32445056L,U32=0xffffffffL;
    /** NativeTransfer.sendMessage budget on Android. */
    static final int LANE=8192;
    static final int HELLO=1,OPEN=2,FRAME=3,PING=4,CLOSE=5,HD_BEGIN=6,HD_STRIP=7,HD_COMMIT=8,PAUSE=32,EXIT=33;
    static final int OK=0,INVALID=1,BUSY=2,STALE=3,CRC=4,SESSION=5,RENDER=6;
    private Vp(){}
    static final class Packet{int op,result;long sid,seq,a,b,c;byte[] data;int length(){return data==null?0:data.length;}}

    private static int step(int c,int b){c^=b&255;for(int k=0;k<8;k++)c=(c>>>1)^(0xedb88320&-(c&1));return c;}
    static long crc(byte[] p,int off,int n){int c=-1;for(int i=off;i<off+n;i++)c=step(c,p[i]);return ~c&U32;}
    private static long wireCrc(byte[] p,int n){int c=-1;for(int i=0;i<n;i++)if(i<28||i>=32)c=step(c,p[i]);return ~c&U32;}
    static long u32(byte[] p,int at){return (p[at]&255L)|(p[at+1]&255L)<<8|(p[at+2]&255L)<<16|(p[at+3]&255L)<<24;}
    private static void w32(byte[] p,int at,long v){for(int i=0;i<4;i++)p[at+i]=(byte)(v>>(8*i));}
    private static boolean u32ok(long v){return v>=0&&v<=U32;}
    private static boolean valid(Packet q,boolean reply){
        if(q==null||q.sid==0||q.seq==0||!u32ok(q.sid)||!u32ok(q.seq)||!u32ok(q.a)||!u32ok(q.b)||!u32ok(q.c)||q.result<0||q.result>RENDER||q.length()>COMP_MAX)return false;
        if(reply)return((q.op>=HELLO&&q.op<=HD_COMMIT)||q.op==PAUSE||q.op==EXIT)&&q.length()==0;
        if(q.result!=0||q.op<HELLO||q.op>HD_COMMIT)return false;
        if(q.op==FRAME)return q.a==(270|(110L<<16))&&(q.b==2||q.b==4)&&q.length()>0;
        if(q.op==HD_BEGIN)return q.a!=0&&(q.b==2||q.b==4)&&q.length()==0;
        if(q.op==HD_STRIP){long y=q.a&65535,h=q.a>>>16;return y<H&&h!=0&&h<=HD_ROWS&&h<=H-y&&(q.b==2||q.b==4)&&q.length()>0;}
        if(q.op==HD_COMMIT)return q.a!=0&&q.b==0&&q.length()==0;
        return q.length()==0;
    }
    static byte[] encode(Packet q,boolean reply){
        if(!valid(q,reply))return null;int n=q.length();byte[] p=new byte[HEADER+n];
        byte[] magic=(reply?"VPA1":"TVP1").getBytes(java.nio.charset.StandardCharsets.US_ASCII);System.arraycopy(magic,0,p,0,4);
        p[4]=1;p[5]=(byte)q.op;p[6]=(byte)q.result;w32(p,8,q.sid);w32(p,12,q.seq);w32(p,16,q.a);w32(p,20,q.b);w32(p,24,q.c);
        if(n>0)System.arraycopy(q.data,0,p,HEADER,n);w32(p,28,wireCrc(p,p.length));return p;
    }
    static Packet decode(byte[] p,boolean reply){
        if(p==null||p.length<HEADER||p.length>WIRE_MAX)return null;String magic=reply?"VPA1":"TVP1";
        for(int i=0;i<4;i++)if(p[i]!=magic.charAt(i))return null;
        if(p[4]!=1||p[7]!=0||u32(p,28)!=wireCrc(p,p.length))return null;
        Packet q=new Packet();q.op=p[5]&255;q.result=p[6]&255;q.sid=u32(p,8);q.seq=u32(p,12);q.a=u32(p,16);q.b=u32(p,20);q.c=u32(p,24);
        q.data=p.length>HEADER?java.util.Arrays.copyOfRange(p,HEADER,p.length):null;return valid(q,reply)?q:null;
    }
    /** vp_compress: runs ≥3 as (257−run, byte), literals as (count−1, bytes…). null if over cap or input invalid. */
    static byte[] compress(byte[] p,int off,int n,int cap){
        if(p==null||n<=0||n>PACKED_MAX||off<0||off>p.length-n||cap<=0)return null;cap=Math.min(cap,COMP_MAX);byte[] out=new byte[cap];int i=0,k=0;
        while(i<n){int run=1;while(run<128&&i+run<n&&p[off+i+run]==p[off+i])run++;
            if(run>=3){if(k+2>cap)return null;out[k++]=(byte)(257-run);out[k++]=p[off+i];i+=run;}
            else{int first=i;i+=run;while(i<n&&i-first<128){run=1;while(run<3&&i+run<n&&p[off+i+run]==p[off+i])run++;if(run==3)break;i++;}
                int count=i-first;if(k+1+count>cap)return null;out[k++]=(byte)(count-1);System.arraycopy(p,off+first,out,k,count);k+=count;}}
        return java.util.Arrays.copyOf(out,k);
    }
    static boolean decompress(byte[] p,byte[] out,int wanted){
        if(p==null||out==null||p.length==0||p.length>COMP_MAX||wanted<=0||wanted>PACKED_MAX||wanted>out.length)return false;int i=0,k=0,n=p.length;
        while(i<n){int v=p[i++]&255;if(v==128)return false;int count=v<128?v+1:257-v;if(count>wanted-k)return false;
            if(v<128){if(count>n-i)return false;System.arraycopy(p,i,out,k,count);i+=count;}else{if(i>=n)return false;java.util.Arrays.fill(out,k,k+count,p[i++]);}k+=count;}
        return k==wanted;
    }
    static long pixelsCrc(byte[] p,int stride){
        if(p==null||stride<W||stride>STRIDE_MAX||p.length<(H-1)*stride+W)return 0;int c=-1;
        for(int y=0;y<H;y++)for(int x=0;x<W;x++)c=step(c,p[y*stride+x]);return ~c&U32;
    }
}
