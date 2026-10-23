package com.turboio.addon;
import java.util.zip.CRC32;

/** TIMG v2 for TVP2's Turbo Image RX (image-upload-test built wide): 512×128 8-bit gray + 32-byte header,
 * file turbo-photo.timg. Byte-identical to a packet the unchanged firmware receiver accepts. */
final class Timg {
    static final int W=512,H=128,PIXELS=W*H,HEADER=32,WIRE=PIXELS+HEADER;static final String FILE="turbo-photo.timg";
    private Timg(){}
    private static void put(byte[] p,int at,long v){for(int i=0;i<4;i++)p[at+i]=(byte)(v>>(8*i));}
    static byte[] packet(byte[] pixels,long session,long frame){
        if(pixels==null||pixels.length!=PIXELS||session<=0||session>0xffffffffL||frame<=0||frame>0xffffffffL)return null;
        byte[] p=new byte[WIRE];byte[] prefix={'T','I','M','G',2,1,32,0,(byte)(W&255),(byte)(W>>8),(byte)(H&255),(byte)(H>>8),(byte)(W&255),(byte)(W>>8),0,0,(byte)(PIXELS&255),(byte)((PIXELS>>8)&255),(byte)((PIXELS>>16)&255),(byte)((PIXELS>>24)&255)};
        System.arraycopy(prefix,0,p,0,20);put(p,20,frame);put(p,24,session);CRC32 c=new CRC32();c.update(pixels);put(p,28,c.getValue());System.arraycopy(pixels,0,p,HEADER,PIXELS);return p;
    }
    /** Aspect-fit rectangle {x,y,w,h} inside 512×128 (black bars around it). */
    static int[] fit(int w,int h){double s=Math.min(W/(double)w,H/(double)h);int dw=Math.max(1,Math.min(W,(int)Math.round(w*s))),dh=Math.max(1,Math.min(H,(int)Math.round(h*s)));return new int[]{(W-dw)/2,(H-dh)/2,dw,dh};}
    /** Gray from a 512×128 ARGB canvas: (299R+587G+114B)/1000. */
    static byte[] luma(int[] argb){
        if(argb==null||argb.length!=PIXELS)return null;byte[] g=new byte[PIXELS];
        for(int i=0;i<PIXELS;i++){int c=argb[i];g[i]=(byte)((299*((c>>16)&255)+587*((c>>8)&255)+114*(c&255))/1000);}return g;
    }
}
