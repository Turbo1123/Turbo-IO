package com.turboio.addon;

/** Diagnostic header only. Never decodes/logs JSON, text, audio or identifiers. */
final class LauncherMeta {
 private static long var(byte[] b,int[] p){long n=0;for(int i=0;i<5;i++){if(p[0]>=b.length)throw new IllegalArgumentException();int v=b[p[0]++]&255;if(i==4&&(v&240)!=0)throw new IllegalArgumentException();n|=(long)(v&127)<<(7*i);if((v&128)==0)return n;}throw new IllegalArgumentException();}
 static String describe(byte[] b){try{
  if(b==null||b.length>8192)return "invalid";int[] p={0};int seen=0;long version=-1,type=-1,mode=-1;int json=0,binary=0;
  while(p[0]<b.length){long k=var(b,p);int tag=(int)(k>>>3);if(tag<1||tag>6||(seen&(1<<tag))!=0)return "invalid";seen|=1<<tag;
   if(tag==3||tag==4){if((k&7)!=2)return "invalid";long n=var(b,p);if(n>b.length-p[0])return "invalid";if(tag==3)json=(int)n;else binary=(int)n;p[0]+=(int)n;}
   else {if((k&7)!=0)return "invalid";long n=var(b,p);if(tag==1)version=n;if(tag==2)type=n;if(tag==6)mode=n;}
  }
  return "v="+version+" type="+type+" mode="+mode+" jsonBytes="+json+" binaryBytes="+binary;
 }catch(RuntimeException e){return "invalid";}}
}
