package com.turboio.addon;
public final class LauncherMetaTest {
 public static void main(String[] args){
  byte[] secret="private-cookie-and-song".getBytes(java.nio.charset.StandardCharsets.UTF_8);
  byte[] b=new byte[8+secret.length];b[0]=8;b[1]=1;b[2]=16;b[3]=6;b[4]=26;b[5]=(byte)secret.length;System.arraycopy(secret,0,b,6,secret.length);b[b.length-2]=48;b[b.length-1]=2;
  String s=LauncherMeta.describe(b);if(!s.equals("v=1 type=6 mode=2 jsonBytes=23 binaryBytes=0")||s.contains("private"))throw new AssertionError(s);
  for(int i=6;i<6+secret.length;i++){byte[] q=b.clone();q[i]=(byte)255;if(!LauncherMeta.describe(q).equals(s))throw new AssertionError("payload inspected");}
  for(byte[] q:new byte[][]{null,new byte[8193],{26,127},{8,(byte)128},{8,1,8,2},{0},{18,0}})if(!LauncherMeta.describe(q).equals("invalid"))throw new AssertionError("bad header accepted");
  System.out.println("LauncherMeta: bounded header and payload non-disclosure verified");
 }
}
