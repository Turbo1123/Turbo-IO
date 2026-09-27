package com.turboio.addon;

import java.nio.*;
import java.nio.charset.*;
import java.util.*;
import java.util.zip.CRC32;

/** Byte-exact TNV1/TNA1 counterpart to the existing application-only firmware. */
public final class NativeNavCodec {
    public static final int START=1,UPDATE=2,HEARTBEAT=3,STOP=4,MODE=5,QUERY=6;
    public static final class Scene {
        public int icon,mode,heading,x,y;
        public long distance,remaining,seconds;
        public String road="",turn="";
        public int[][] points=new int[0][2];
    }
    public static final class Reply {
        public final int result,mode;public final long sid,seq;public final boolean active,awake,stale;
        Reply(byte[] b){ByteBuffer q=ByteBuffer.wrap(b).order(ByteOrder.LITTLE_ENDIAN);result=b[5]&255;mode=b[7]&255;active=(b[6]&1)!=0;awake=(b[6]&2)!=0;stale=(b[6]&4)!=0;sid=u32(q,8);seq=u32(q,12);}
    }
    private static void range(long n,long max){if(n<0||n>max)throw new IllegalArgumentException("TNV1 bounds");}
    private static long u32(ByteBuffer b,int offset){return Integer.toUnsignedLong(b.getInt(offset));}
    private static byte[] text(String s,int max){try{if(s==null)throw new IllegalArgumentException();for(int i=0;i<s.length();i++){char c=s.charAt(i);if(c<32||c==127)throw new IllegalArgumentException();}ByteBuffer encoded=StandardCharsets.UTF_8.newEncoder().onMalformedInput(CodingErrorAction.REPORT).encode(CharBuffer.wrap(s));if(encoded.remaining()>max)throw new IllegalArgumentException();byte[] bytes=new byte[encoded.remaining()];encoded.get(bytes);return bytes;}catch(CharacterCodingException e){throw new IllegalArgumentException(e);}}
    public static String clip(String s,int max){if(s==null)return "";StringBuilder out=new StringBuilder();int n=0;for(int i=0;i<s.length();){int cp=s.codePointAt(i);i+=Character.charCount(cp);if(cp<32||cp==127||(cp>=0xd800&&cp<=0xdfff))continue;String c=new String(Character.toChars(cp));int count=c.getBytes(StandardCharsets.UTF_8).length;if(n+count>max)break;out.append(c);n+=count;}return out.toString();}
    public static byte[] scene(Scene s){if(s==null)throw new IllegalArgumentException();range(s.icon,10);range(s.mode,1);range(s.heading,359);range(s.x,1023);range(s.y,1023);range(s.distance,1000000);range(s.remaining,10000000);range(s.seconds,604800);if(s.points==null||s.points.length>32)throw new IllegalArgumentException();byte[] a=text(s.road,96),b=text(s.turn,48);ByteBuffer q=ByteBuffer.allocate(24+a.length+b.length+4*s.points.length).order(ByteOrder.LITTLE_ENDIAN);q.put((byte)s.icon).put((byte)s.points.length).put((byte)s.mode).put((byte)0).putInt((int)s.distance).putInt((int)s.remaining).putInt((int)s.seconds).putShort((short)s.heading).putShort((short)s.x).putShort((short)s.y).put((byte)a.length).put((byte)b.length).put(a).put(b);for(int[] p:s.points){if(p==null||p.length!=2)throw new IllegalArgumentException();range(p[0],1023);range(p[1],1023);q.putShort((short)p[0]).putShort((short)p[1]);}return q.array();}
    public static byte[] packet(int op,long sid,long seq,Scene s){if(op==MODE){if(s==null)throw new IllegalArgumentException();range(s.mode,1);}return packetBytes(op,sid,seq,op==START||op==UPDATE?scene(s):op==MODE?new byte[]{(byte)s.mode}:null);}
    static byte[] packetBytes(int op,long sid,long seq,byte[] body){range(sid,0xffffffffL);range(seq,0xffffffffL);if(sid==0||seq==0||op<1||op>6)throw new IllegalArgumentException();if(op==START||op==UPDATE){if(body==null||body.length<24||body.length>296)throw new IllegalArgumentException();}else if(op==MODE){if(body==null||body.length!=1||(body[0]&255)>1)throw new IllegalArgumentException();}else if(body!=null&&body.length!=0)throw new IllegalArgumentException();int n=body==null?0:body.length;ByteBuffer q=ByteBuffer.allocate(32+n).order(ByteOrder.LITTLE_ENDIAN);q.put(new byte[]{'T','N','V','1',1,(byte)op,0,0}).putInt((int)sid).putInt((int)seq).putInt(n).putInt(0).putLong(0);if(n>0)q.put(body);CRC32 crc=new CRC32();crc.update(q.array());q.putInt(20,(int)crc.getValue());return q.array();}
    public static Reply reply(byte[] b){if(b==null||b.length!=32||b[0]!='T'||b[1]!='N'||b[2]!='A'||b[3]!='1'||b[4]!=1||(b[5]&255)>6||(b[6]&~7)!=0||(b[7]&255)>1)return null;ByteBuffer q=ByteBuffer.wrap(b).order(ByteOrder.LITTLE_ENDIAN);CRC32 crc=new CRC32();crc.update(b,0,28);if(u32(q,16)!=60000||u32(q,20)!=32||u32(q,24)!=0||crc.getValue()!=u32(q,28))return null;return new Reply(b);}
}
