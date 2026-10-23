package com.turboio.addon;

/** TVP2 menu layout (2 or 3 rows): TMG2 commands out, TMA2 replies in. Mirrors menu_config.c. */
public final class MenuCodec {
    public static final int QUERY=0,SET=1,OK=0,BLOCKED=1,SESSION=2,STORAGE=3,UNAVAILABLE=4;
    private MenuCodec(){}
    public static final class Reply {
        public final int op,rows,result;public final long request,token,generation,client;
        private Reply(byte[] p){op=p[5];rows=p[6];result=p[7];request=HexCarrier.u32(p,8);token=HexCarrier.u32(p,12);generation=HexCarrier.u32(p,16);client=HexCarrier.u32(p,20);}
    }
    /** Raw 32-byte TMG2 command; refuses anything tml_decode on the glasses would reject. */
    public static byte[] command(int op,int rows,long request,long token,long generation,long client){
        boolean ok=request>0&&request<=0xffffffffL&&client>0&&client<=0xffffffffL&&token>=0&&token<=0xffffffffL&&generation>=0&&generation<=0xffffffffL
            &&(op==QUERY?rows==0&&token==0&&generation==0:op==SET&&(rows==2||rows==3)&&token!=0);
        if(!ok)throw new IllegalArgumentException("menu command");
        byte[] p=new byte[32];p[0]='T';p[1]='M';p[2]='G';p[3]='2';p[4]=1;p[5]=(byte)op;p[6]=(byte)rows;
        HexCarrier.w32(p,8,request);HexCarrier.w32(p,12,token);HexCarrier.w32(p,16,generation);HexCarrier.w32(p,20,client);HexCarrier.w32(p,28,HexCarrier.crc(p,28));return p;
    }
    /** Carrier bytes from the glasses → reply, or null unless every TMA2 field check passes. */
    public static Reply reply(byte[] wire){
        byte[] p=HexCarrier.unwrap(wire,"TMA:",32,32);
        if(p==null||p[0]!='T'||p[1]!='M'||p[2]!='A'||p[3]!='2'||p[4]!=1||(p[5]&255)>1||(p[6]!=2&&p[6]!=3)||(p[7]&255)>UNAVAILABLE)return null;
        if(HexCarrier.u32(p,8)==0||HexCarrier.u32(p,20)==0||(p[24]&255)!=28||p[25]!=2||(p[26]&255)!=220||p[27]!=0||HexCarrier.u32(p,28)!=HexCarrier.crc(p,28))return null;
        return new Reply(p);
    }
}
