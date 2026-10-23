package com.turboio.addon;
import java.nio.charset.StandardCharsets;
import java.util.*;

/** RNLink A2UI envelope (port of iOS A2UIProtocol TIOA2UIPacket/Decode): field1 version 1, field2 type, field3 JSON
 * object (sorted keys), field4 empty binary, field5 sequence, field6 mode. Pure. */
final class A2uiFrame {
    private A2uiFrame(){}
    static final class Frame{long type,sequence,mode;Map<String,Object> json;}
    private static void var(java.io.ByteArrayOutputStream o,long v){while((v&~127L)!=0){o.write((int)((v&127)|128));v>>>=7;}o.write((int)v);}
    static byte[] packet(long type,long sequence,Map<String,Object> json){
        if(type<=0||type>0xffffffffL||sequence<0||sequence>0xffffffffL||json==null)return null;
        byte[] j=BoundedJson.canonical(json);if(j.length>7500)return null;
        java.io.ByteArrayOutputStream o=new java.io.ByteArrayOutputStream();o.write(8);var(o,1);o.write(16);var(o,type);o.write(26);var(o,j.length);o.write(j,0,j.length);
        if(sequence!=0){o.write(40);var(o,sequence);}byte[] out=o.toByteArray();return out.length>8192?null:out;
    }
    private static long var(byte[] b,int[] p){long v=0;for(int i=0;i<10;i++){if(p[0]>=b.length)throw new IllegalArgumentException();int c=b[p[0]++]&255;if(i==9&&(c&254)!=0)throw new IllegalArgumentException();v|=(long)(c&127)<<(7*i);if((c&128)==0)return v;}throw new IllegalArgumentException();}
    static Frame decode(byte[] b){
        try{
            if(b==null||b.length<1||b.length>8192)return null;int[] p={0};Set<Integer> seen=new HashSet<>();long version=-1,type=0,seq=0,mode=0;byte[] json=null;
            while(p[0]<b.length){long key=var(b,p);int field=(int)(key>>>3),wire=(int)(key&7);if(field<1||field>6||!seen.add(field))return null;
                if(field==3||field==4){if(wire!=2)return null;long len=var(b,p);if(len>b.length-p[0])return null;if(field==4&&len!=0)return null;if(field==3)json=Arrays.copyOfRange(b,p[0],p[0]+(int)len);p[0]+=(int)len;}
                else{if(wire!=0)return null;long v=var(b,p);if(v<0||v>0xffffffffL)return null;if(field==1)version=v;else if(field==2)type=v;else if(field==5)seq=v;else mode=v;}}
            if(version!=1||type==0||json==null||json.length==0)return null;
            Object o=BoundedJson.read(json);if(!(o instanceof Map))return null;
            Frame f=new Frame();f.type=type;f.sequence=seq;f.mode=mode;f.json=BoundedJson.map(o);return f;
        }catch(RuntimeException e){return null;}
    }
}
