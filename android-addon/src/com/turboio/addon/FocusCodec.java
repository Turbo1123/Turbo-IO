package com.turboio.addon;

import java.util.zip.CRC32;

/** Byte-identical TFP1/TFA1 codec. No Android, UI, network or firmware dependency. */
public final class FocusCodec {
    public static final int QUERY=1,START=2,PAUSE=3,RESUME=4,STOP=5,PEEK=6,ACK_DONE=7;
    public static final int IDLE=0,RUNNING=1,PAUSED=2,DONE=3,STOPPED=4;
    private FocusCodec() {}
    private static void uint32(long n) { if(n<0||n>0xffffffffL)throw new IllegalArgumentException("uint32"); }
    public static long u32(byte[] b,int at) {return (b[at]&255L)|((b[at+1]&255L)<<8)|((b[at+2]&255L)<<16)|((b[at+3]&255L)<<24);}
    private static void put(byte[] b,int at,long n){uint32(n);for(int i=0;i<4;i++)b[at+i]=(byte)(n>>>(i*8));}
    public static long crc(byte[] b,int length){CRC32 crc=new CRC32();crc.update(b,0,length);return crc.getValue();}
    public static byte[] command(int op,long sid,long seq,long revision,int seconds,int phase){
        uint32(sid);uint32(seq);uint32(revision);
        if(op<QUERY||op>ACK_DONE||seq==0)throw new IllegalArgumentException("operation/sequence");
        if(op==QUERY){if(seconds!=0||phase!=0||revision!=0)throw new IllegalArgumentException("query fields");}
        else if(sid==0)throw new IllegalArgumentException("session");
        if(op==START){if(seconds<10||seconds>7200||phase<0||phase>2)throw new IllegalArgumentException("duration/phase");}
        else if(seconds!=0||phase!=0)throw new IllegalArgumentException("reserved fields");
        byte[] b=new byte[64];b[0]='T';b[1]='F';b[2]='P';b[3]='1';b[4]=1;b[5]=(byte)op;
        put(b,8,sid);put(b,12,seq);put(b,16,revision);put(b,20,seconds);put(b,24,phase);put(b,60,crc(b,60));return b;
    }
    public static final class Reply {
        public final int result,status;public final boolean pending,peek;
        public final long sid,seq,revision,remainingMS,duration,phase,completed,completion,requestSID,notified;
        private Reply(byte[] b){result=b[5];status=b[6];pending=(b[7]&1)!=0;peek=(b[7]&2)!=0;
            sid=u32(b,8);seq=u32(b,12);revision=u32(b,16);remainingMS=u32(b,20);duration=u32(b,24);
            phase=u32(b,28);completed=u32(b,32);completion=u32(b,36);requestSID=u32(b,40);notified=u32(b,44);}
    }
    public static Reply reply(byte[] b){
        if(b==null||b.length!=64||b[0]!='T'||b[1]!='F'||b[2]!='A'||b[3]!='1'||b[4]!=1||(b[5]&255)>4||(b[6]&255)>4||(b[7]&~3)!=0||u32(b,60)!=crc(b,60))return null;
        for(int i=48;i<60;i++)if(b[i]!=0)return null;
        if(u32(b,20)>7200000||u32(b,24)>7200||u32(b,28)>2)return null;
        return new Reply(b);
    }
    public static byte[] hex(String text){
        if(text==null||text.length()!=128)return null;byte[] b=new byte[64];
        for(int i=0;i<64;i++){char a=text.charAt(i*2),c=text.charAt(i*2+1);int x=digit(a),y=digit(c);if(x<0||y<0)return null;b[i]=(byte)((x<<4)|y);}return b;
    }
    private static int digit(char c){return c>='0'&&c<='9'?c-'0':c>='a'&&c<='f'?c-'a'+10:-1;}
}
