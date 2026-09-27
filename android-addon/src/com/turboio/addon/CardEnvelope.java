package com.turboio.addon;
import java.io.*;
import java.util.*;

public final class CardEnvelope {
    public static final class Reply {public final long sequence;public final Map<String,Object> json;private Reply(long s,Map<String,Object> j){sequence=s;json=j;}}
    private static void var(ByteArrayOutputStream out,long n){do{int v=(int)(n&127);n>>>=7;out.write(n==0?v:v|128);}while(n!=0);}
    public static byte[] request(long sequence,Map<String,Object> json){if(sequence<1||sequence>0xffffffffL)throw new IllegalArgumentException();byte[] b=BoundedJson.canonical(json);if(b.length>7500)throw new IllegalArgumentException();ByteArrayOutputStream o=new ByteArrayOutputStream();o.write(8);o.write(1);o.write(16);o.write(18);o.write(26);var(o,b.length);o.write(b,0,b.length);o.write(40);var(o,sequence);o.write(48);o.write(1);return o.toByteArray();}
    private static long var(byte[] b,int[] p){long n=0;for(int i=0;i<5;i++){if(p[0]>=b.length)throw new IllegalArgumentException();int v=b[p[0]++]&255;if(i==4&&(v&240)!=0)throw new IllegalArgumentException();n|=(long)(v&127)<<(7*i);if((v&128)==0)return n;}throw new IllegalArgumentException();}
    public static Reply reply(byte[] b){try{if(b==null||b.length>8192)return null;int[] p={0};int seen=0;long ver=0,type=0,seq=0,mode=0;byte[] json=null;while(p[0]<b.length){long k=var(b,p);int tag=(int)(k>>>3);if(tag<1||tag>6||(seen&(1<<tag))!=0)return null;seen|=1<<tag;if(tag==3||tag==4){if((k&7)!=2)return null;long n=var(b,p);if(n>b.length-p[0]||(tag==4&&n!=0))return null;if(tag==3)json=Arrays.copyOfRange(b,p[0],p[0]+(int)n);p[0]+=(int)n;}else{if((k&7)!=0)return null;long n=var(b,p);if(tag==1)ver=n;if(tag==2)type=n;if(tag==5)seq=n;if(tag==6)mode=n;}}if(ver!=1||type!=19||mode!=2||seq==0||json==null)return null;return new Reply(seq,BoundedJson.map(BoundedJson.read(json)));}catch(RuntimeException e){return null;}}
}
