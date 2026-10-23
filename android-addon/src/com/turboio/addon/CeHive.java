package com.turboio.addon;
import java.nio.charset.*;
import java.util.*;
import java.util.zip.CRC32;

/** Read-only, bounded snapshot of Hive (hive_ce) primitive frames (port of iOS CEHiveSnapshot.m). Never opens Hive for
 * writes; unknown value adapters are refused, not guessed. A frame whose body ends after the key deletes that key. */
final class CeHive {
    static final String ERROR="官方缓存正在变化、格式不兼容或校验失败；未修改原文件，请稍后重试。";
    static final int MAX_BYTES=32*1024*1024,MAX_NODES=200000,MAX_FRAMES=100000;
    private final byte[] b;private int p,end,nodes;
    private CeHive(byte[] b,int p,int end){this.b=b;this.p=p;this.end=end;}
    private static IllegalArgumentException bad(){return new IllegalArgumentException(ERROR);}
    private void need(long n){if(n<0||n>end-p)throw bad();}
    private int u8(){need(1);return b[p++]&255;}
    private long u32(){need(4);long v=(b[p]&255L)|(b[p+1]&255L)<<8|(b[p+2]&255L)<<16|(b[p+3]&255L)<<24;p+=4;return v;}
    private String string(long n){if(n>4*1024*1024)throw bad();need(n);try{String s=StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT).decode(java.nio.ByteBuffer.wrap(b,p,(int)n)).toString();p+=(int)n;return s;}catch(CharacterCodingException e){throw bad();}}
    private Object value(int depth){
        if(depth>24||++nodes>MAX_NODES)throw bad();int type=u8();
        if(type==0)return null;
        if(type==1||type==2){need(8);long bits=0;for(int i=0;i<8;i++)bits|=(b[p++]&255L)<<(8*i);double d=Double.longBitsToDouble(bits);if(Double.isNaN(d)||Double.isInfinite(d))throw bad();return d;}
        if(type==3)return u8()!=0;
        if(type==4)return string(u32());
        if(type==5){long n=u32();need(n);byte[] out=Arrays.copyOfRange(b,p,p+(int)n);p+=(int)n;return out;}
        if(type==9||type==10||type==11){long count=u32();if(count>20000)throw bad();
            if(type==11){Map<Object,Object> map=new LinkedHashMap<>();for(long i=0;i<count;i++){Object k=value(depth+1),v=value(depth+1);if(!(k instanceof String||k instanceof Number))throw bad();map.put(k,v);}return map;}
            List<Object> list=new ArrayList<>();for(long i=0;i<count;i++)list.add(type==9?string(u32()):value(depth+1));return list;}
        throw bad();
    }
    /** Key → value of the live entries; IllegalArgumentException(ERROR) on any corruption or unsupported type. */
    static Map<Object,Object> read(byte[] data){
        if(data==null||data.length>MAX_BYTES)throw bad();Map<Object,Object> out=new LinkedHashMap<>();CeHive r=new CeHive(data,0,data.length);int frames=0;long total=0;
        while(r.p<r.end){
            int start=r.p;long length=r.u32();if(length<9||length>r.end-start||++frames>MAX_FRAMES)throw bad();int stop=(int)(start+length-4);
            CRC32 crc=new CRC32();crc.update(data,start,(int)length-4);CeHive tail=new CeHive(data,stop,data.length);if(crc.getValue()!=tail.u32())throw bad();
            CeHive body=new CeHive(data,r.p,stop);int kt=body.u8();Object key;
            if(kt==0)key=body.u32();else if(kt==1)key=body.string(body.u8());else throw bad();
            if(body.p==body.end)out.remove(key);else{Object v=body.value(0);if(body.p!=body.end)throw bad();out.put(key,v);}
            total+=body.nodes;if(total>MAX_NODES)throw bad();r.p=(int)(start+length);
        }
        return out;
    }
}
