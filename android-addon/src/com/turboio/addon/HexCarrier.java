package com.turboio.addon;
import java.util.Arrays;

/** Business-15 type-127 carrier shared by the TVP2 native modules (menu TML/TMA, camera TCM/TCA):
 * 08 01 10 7f 1a, varint string length, 4-char tag such as "TML:", then lowercase hex of the raw frame. */
public final class HexCarrier {
    private static final byte[] PREFIX={8,1,16,127,26};
    private static final char[] HEX="0123456789abcdef".toCharArray();
    private HexCarrier(){}
    public static byte[] wrap(String tag,byte[] raw){
        if(tag==null||tag.length()!=4||raw==null||raw.length==0)throw new IllegalArgumentException("carrier");
        int str=4+raw.length*2;if(str>=16384)throw new IllegalArgumentException("carrier length");
        int head=str<128?6:7;byte[] out=new byte[head+str];System.arraycopy(PREFIX,0,out,0,5);int at=5;
        if(str<128)out[at++]=(byte)str;else{out[at++]=(byte)((str&127)|128);out[at++]=(byte)(str>>>7);}
        for(int i=0;i<4;i++)out[at++]=(byte)tag.charAt(i);
        for(byte b:raw){out[at++]=(byte)HEX[(b>>4)&15];out[at++]=(byte)HEX[b&15];}
        return out;
    }
    /** null unless prefix, minimal length encoding, tag and lowercase hex are exact and the raw size is in range. */
    public static byte[] unwrap(byte[] wire,String tag,int minRaw,int maxRaw){
        if(wire==null||tag==null||tag.length()!=4||wire.length<6||!Arrays.equals(Arrays.copyOf(wire,5),PREFIX))return null;
        int at=5,str=wire[at++]&255;
        if((str&128)!=0){if(at>=wire.length||(wire[at]&128)!=0)return null;str=(str&127)|((wire[at++]&255)<<7);if(str<128)return null;}
        if(str!=wire.length-at||str<4||(str-4)%2!=0)return null;
        for(int i=0;i<4;i++)if(wire[at+i]!=(byte)tag.charAt(i))return null;at+=4;
        int bytes=(str-4)/2;if(bytes<minRaw||bytes>maxRaw)return null;byte[] raw=new byte[bytes];
        for(int i=0;i<bytes;i++){int h=nibble(wire[at++]),l=nibble(wire[at++]);if(h<0||l<0)return null;raw[i]=(byte)(h<<4|l);}
        return raw;
    }
    private static int nibble(byte c){return c>='0'&&c<='9'?c-'0':c>='a'&&c<='f'?c-'a'+10:-1;}
    static long u32(byte[] p,int at){return (p[at]&255L)|(p[at+1]&255L)<<8|(p[at+2]&255L)<<16|(p[at+3]&255L)<<24;}
    static void w32(byte[] p,int at,long v){for(int i=0;i<4;i++)p[at+i]=(byte)(v>>>(8*i));}
    /** CRC-32/ISO-HDLC, as tml_crc / tc_crc. */
    static long crc(byte[] p,int off,int n,long state){long c=state;for(int i=0;i<n;i++){c^=p[off+i]&255;for(int b=0;b<8;b++)c=(c>>>1)^(0xedb88320L&-(c&1));}return c;}
    static long crc(byte[] p,int n){return ~crc(p,0,n,0xffffffffL)&0xffffffffL;}
}
