package com.turboio.addon;

import java.io.ByteArrayOutputStream;
import java.util.*;

/** Bounded RNLink protobuf envelope; payload type policy belongs to the caller. */
final class OtaFrame {
 final int type;final Object json;final byte[] binary;
 OtaFrame(int t,Object j,byte[] b){type=t;json=j;binary=b;}
 static byte[] encode(int type,Object json,byte[] binary){
  if(type<1||type>255)throw new IllegalArgumentException("message type");
  byte[] j=BoundedJson.canonical(json==null?Collections.emptyMap():json),b=binary==null?new byte[0]:binary;
  if(j.length>8192||b.length>51200)throw new IllegalArgumentException("message budget");
  ByteArrayOutputStream o=new ByteArrayOutputStream();var(o,8);var(o,1);var(o,16);var(o,type);
  var(o,26);var(o,j.length);o.write(j,0,j.length);if(b.length>0){var(o,34);var(o,b.length);o.write(b,0,b.length);}return o.toByteArray();
 }
 private static void var(ByteArrayOutputStream o,long n){do{int v=(int)(n&127);n>>>=7;o.write(n==0?v:v|128);}while(n!=0);}
 private static long var(byte[] b,int[] p){long v=0;for(int i=0;i<5;i++){if(p[0]>=b.length)throw new IllegalArgumentException("truncated varint");int x=b[p[0]++]&255;if(i==4&&(x&240)!=0)throw new IllegalArgumentException("varint overflow");v|=(long)(x&127)<<(i*7);if((x&128)==0){if(i>0&&x==0)throw new IllegalArgumentException("noncanonical varint");return v;}}throw new IllegalArgumentException("varint");}
 static OtaFrame decode(byte[] b){
  if(b==null||b.length<4||b.length>65536)throw new IllegalArgumentException("frame budget");
  int[] p={0};int seen=0,type=0;long version=0;Object json=Collections.emptyMap();byte[] binary=new byte[0];
  while(p[0]<b.length){long key=var(b,p);int tag=(int)(key>>>3),wire=(int)(key&7);if(tag<1||tag>6||(seen&(1<<tag))!=0)throw new IllegalArgumentException("tag");seen|=1<<tag;
   if(tag==3||tag==4){long n=var(b,p);if(wire!=2||n>b.length-p[0]||n>(tag==3?8192:51200))throw new IllegalArgumentException("field length");byte[] data=Arrays.copyOfRange(b,p[0],p[0]+(int)n);p[0]+=(int)n;if(tag==3){json=n==0?Collections.emptyMap():BoundedJson.read(data);if(!(json instanceof Map||json instanceof List))throw new IllegalArgumentException("JSON type");}else binary=data;}
   else{if(wire!=0)throw new IllegalArgumentException("wire");long n=var(b,p);if(tag==1)version=n;else if(tag==2){if(n<1||n>255)throw new IllegalArgumentException("type");type=(int)n;}else if(n!=0)throw new IllegalArgumentException("unsupported flags");}
  }if(version!=1||type==0)throw new IllegalArgumentException("version/type");return new OtaFrame(type,json,binary);
 }
 static boolean readOnly(byte[] b){try{OtaFrame f=decode(b);return (f.type==1||f.type==2||f.type==11)&&f.json instanceof Map&&((Map<?,?>)f.json).isEmpty()&&f.binary.length==0;}catch(RuntimeException e){return false;}}
 static Map<String,Object> object(Object...pairs){Map<String,Object> m=new LinkedHashMap<>();for(int i=0;i<pairs.length;i+=2)m.put((String)pairs[i],pairs[i+1]);return m;}
}
