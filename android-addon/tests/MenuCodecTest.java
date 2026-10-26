package com.turboio.addon;
import java.nio.file.*;import java.util.*;

/** TMG2/TMA2 menu-layout codec against wire bytes from the iOS/firmware C source. */
public final class MenuCodecTest {
 static int n;static void ok(boolean b){n++;if(!b)throw new AssertionError("menu codec "+n);}
 public static void main(String[] a)throws Exception{Path d=Paths.get(a[0]);
  byte[] query=Files.readAllBytes(d.resolve("query.bin")),set=Files.readAllBytes(d.resolve("set3.bin")),reply=Files.readAllBytes(d.resolve("reply-ok.bin")),session=Files.readAllBytes(d.resolve("reply-session.bin"));
  ok(Arrays.equals(HexCarrier.wrap("TML:",MenuCodec.command(MenuCodec.QUERY,0,0x11223344L,0,0,0x55667788L)),query));
  ok(Arrays.equals(HexCarrier.wrap("TML:",MenuCodec.command(MenuCodec.SET,3,0x0a0b0c0dL,7,2,0x55667788L)),set));
  MenuCodec.Reply r=MenuCodec.reply(reply);ok(r!=null&&r.op==MenuCodec.QUERY&&r.rows==2&&r.result==MenuCodec.OK&&r.token==9&&r.generation==5&&r.request==0x11223344L&&r.client==0x55667788L);
  MenuCodec.Reply s=MenuCodec.reply(session);ok(s!=null&&s.op==MenuCodec.SET&&s.result==MenuCodec.SESSION&&s.token==0&&s.rows==3);
  // Every mutation of a valid reply is rejected.
  for(int i=0;i<reply.length;i++){byte[] bad=reply.clone();bad[i]^=1;MenuCodec.Reply x=MenuCodec.reply(bad);ok(x==null);}
  ok(MenuCodec.reply(Arrays.copyOf(reply,73))==null);
  ok(MenuCodec.reply(query)==null);                       // phone-side tag TML: is not a reply
  byte[] upper=reply.clone();for(int i=10;i<74;i++)if(upper[i]>='a'&&upper[i]<='f')upper[i]-=32;ok(MenuCodec.reply(upper)==null);
  ok(HexCarrier.unwrap(query,"TML:",32,32)!=null&&HexCarrier.unwrap(query,"TMA:",32,32)==null&&HexCarrier.unwrap(query,"TML:",33,40)==null);
  // Commands the glasses would refuse are refused here first.
  for(int rows:new int[]{0,1,4})try{MenuCodec.command(MenuCodec.SET,rows,1,7,0,1);ok(false);}catch(IllegalArgumentException expected){ok(true);}
  try{MenuCodec.command(MenuCodec.SET,3,1,0,0,1);ok(false);}catch(IllegalArgumentException expected){ok(true);}  // SET needs a token
  try{MenuCodec.command(MenuCodec.QUERY,0,0,0,0,1);ok(false);}catch(IllegalArgumentException expected){ok(true);} // request 0
  System.out.println("MenuCodecTest: "+n+" checks against C golden wire bytes");
 }
}
