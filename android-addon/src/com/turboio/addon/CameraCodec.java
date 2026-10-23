package com.turboio.addon;
import java.util.Arrays;

/** TVP2 remote camera (TCM1 phone→glasses, TCA1 glasses→phone). Mirrors camera-v1/camera.c. */
public final class CameraCodec {
    public static final int WIDTH=256,HEIGHT=144,PIXELS=36864,PACKED_MAX=18432,COMP_MAX=18576,RAW_MAX=240,DATA_MAX=208;
    public static final int HELLO=0,OPEN=1,CLOSE=2,STATE=3,BEGIN=4,CHUNK=5,COMMIT=6,ABORT=7,PING=8,SHUTTER=32,ZOOM=33,CANCEL=34,EXIT=35;
    public static final int OK=0,INVALID=1,SESSION=2,BUSY=3,STALE=4,CRC=5,RENDER=6,UNAVAILABLE=7;
    public static final int WAIT=0,LIVE=1,COUNTDOWN=2,CAPTURING=3,SAVED=4,ERROR=5;
    /** {width,height,bits}; the TCM1 receiver accepts exactly these four. */
    public static final int[][] PROFILES={{128,72,2},{192,108,4},{256,144,2},{256,144,4}};
    public static final double[] SAMPLE_SECONDS={.25,.40,.40,.50};
    public static final int DEFAULT_PROFILE=3;
    private CameraCodec(){}
    public static final class Packet {
        public final int op,result;public final long sid,seq,a,b,c;public final int length;
        private Packet(byte[] p){op=p[5]&255;result=p[6]&255;sid=HexCarrier.u32(p,8);seq=HexCarrier.u32(p,12);a=HexCarrier.u32(p,16);b=HexCarrier.u32(p,20);c=HexCarrier.u32(p,24);length=p.length-32;}
    }
    private static boolean opValid(int op){return op>=0&&op<=PING||op>=SHUTTER&&op<=EXIT;}
    private static long crc(byte[] p,int dataLength){return ~HexCarrier.crc(p,32,dataLength,HexCarrier.crc(p,0,28,0xffffffffL))&0xffffffffL;}
    /** Phone→glasses carrier bytes. Glasses-only event ops, seq 0 and data over 208 bytes are refused. */
    public static byte[] packet(int op,long sid,long seq,long a,long b,long c,byte[] data){
        int length=data==null?0:data.length;
        if(!opValid(op)||op>=SHUTTER||seq<=0||seq>0xffffffffL||length>DATA_MAX)throw new IllegalArgumentException("camera packet");
        byte[] p=new byte[32+length];p[0]='T';p[1]='C';p[2]='M';p[3]='1';p[4]=1;p[5]=(byte)op;
        HexCarrier.w32(p,8,sid);HexCarrier.w32(p,12,seq);HexCarrier.w32(p,16,a);HexCarrier.w32(p,20,b);HexCarrier.w32(p,24,c);
        if(length>0)System.arraycopy(data,0,p,32,length);HexCarrier.w32(p,28,crc(p,length));
        return HexCarrier.wrap("TCM:",p);
    }
    /** Glasses→phone packet, or null. Replies never carry a data region. */
    public static Packet reply(byte[] wire){
        byte[] p=HexCarrier.unwrap(wire,"TCA:",32,RAW_MAX);
        if(p==null||p.length!=32||p[0]!='T'||p[1]!='C'||p[2]!='A'||p[3]!='1'||p[4]!=1||!opValid(p[5]&255)||(p[6]&255)>UNAVAILABLE||p[7]!=0||HexCarrier.u32(p,12)==0||HexCarrier.u32(p,28)!=crc(p,0))return null;
        return new Packet(p);
    }
    /** MSB-first packed levels, as tc_quantize: q=(v*max+127)/255. */
    public static byte[] quantize(byte[] gray,int bits){
        int per=bits==2||bits==4?8/bits:0;
        if(gray==null||per==0||gray.length==0||gray.length>PIXELS||gray.length%per!=0)throw new IllegalArgumentException("quantize");
        int max=(1<<bits)-1;byte[] out=new byte[gray.length*bits/8];
        for(int i=0;i<gray.length;i++){int q=((gray[i]&255)*max+127)/255;out[i/per]|=(byte)(q<<(8-bits-bits*(i%per)));}
        return out;
    }
    /** PackBits exactly as tc_compress; null when empty, over 18432 bytes, or not representable. */
    public static byte[] compress(byte[] p){
        if(p==null||p.length==0||p.length>PACKED_MAX)return null;
        byte[] out=new byte[COMP_MAX];int i=0,k=0,n=p.length;
        while(i<n){int run=1;while(run<128&&i+run<n&&p[i+run]==p[i])run++;
            if(run>=3){if(k+2>COMP_MAX)return null;out[k++]=(byte)(257-run);out[k++]=p[i];i+=run;}
            else{int first=i;i+=run;while(i<n&&i-first<128){run=1;while(run<3&&i+run<n&&p[i+run]==p[i])run++;if(run==3)break;i++;}
                int count=i-first;if(k+1+count>COMP_MAX)return null;out[k++]=(byte)(count-1);System.arraycopy(p,first,out,k,count);k+=count;}
        }
        return Arrays.copyOf(out,k);
    }
    /** Whole source, letterboxed (fit, not fill) into one of the profile sizes; bars are black.
     * Nearest sample with integer mapping; row padding beyond {@code width} is never read. Mirrors TCEncodeImage. */
    public static byte[] fit(byte[] y,int width,int height,int rowStride,int w,int h){
        if(y==null||width<=0||height<=0||rowStride<width||(long)rowStride*(height-1)+width>y.length||budget(w,h,2)==0)throw new IllegalArgumentException("fit");
        int dw,dh;if((long)width*h>=(long)height*w){dw=w;dh=Math.max(1,(int)((long)height*w/width));}else{dh=h;dw=Math.max(1,(int)((long)width*h/height));}
        int ox=(w-dw)/2,oy=(h-dh)/2;byte[] out=new byte[w*h];
        for(int r=0;r<dh;r++){int sy=(int)((long)r*height/dh);int src=sy*rowStride,dst=(oy+r)*w+ox;for(int x=0;x<dw;x++)out[dst+x]=y[src+(int)((long)x*width/dw)];}
        return out;
    }
    /** Seconds a frame may take before it is aborted (tc_preview_frame_budget); 0 = unsupported geometry. */
    public static double budget(int w,int h,int bits){
        if(bits!=2&&bits!=4)return 0;if(w==128&&h==72)return 2.5;if(w==192&&h==108)return 5.5;if(w==256&&h==144)return bits==2?6.5:8.0;return 0;
    }
}
