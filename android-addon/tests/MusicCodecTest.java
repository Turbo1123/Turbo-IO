package com.turboio.addon;
import java.util.*;import java.nio.file.*;import java.nio.charset.StandardCharsets;
public class MusicCodecTest {
 static int n;static void ok(boolean v){n++;if(!v)throw new AssertionError("case "+n);}static void bad(Runnable r){try{r.run();throw new AssertionError("expected reject");}catch(IllegalArgumentException e){n++;}}
 public static void main(String[] args)throws Exception{
 byte[] state=MusicCodec.state(12345,230000,true,2,17,"Turbo Song","Turbo Artist"),cover=new byte[96];Arrays.fill(cover,(byte)127);byte[] lyrics=MusicCodec.lyrics(Arrays.asList(new MusicCodec.Line(1000,"hello!")));
 for(int op=1;op<=6;op++){byte[] payload=op<=2?state:op==3?cover:op==4?lyrics:null;ok(Arrays.equals(MusicCodec.command(op,7392,3,8642,0,op==4,payload),Files.readAllBytes(Paths.get(args[0],"op"+op+".bin"))));}
 bad(()->MusicCodec.command(1,0,1,1,0,false,state));bad(()->MusicCodec.command(1,1,1,0,0,false,state));bad(()->MusicCodec.command(7,1,1,1,0,false,null));bad(()->MusicCodec.command(3,1,1,1,0,true,cover));bad(()->MusicCodec.command(4,1,1,1,24575,false,cover));bad(()->MusicCodec.state(86400001,0,false,0,0,"",""));
 byte[] huge=MusicCodec.clip("abc😀中文",7);ok(new String(huge,StandardCharsets.UTF_8).equals("abc😀"));ok(Arrays.equals(MusicCodec.clip("x\n\0y",10),"x  y".getBytes(StandardCharsets.UTF_8)));
 List<MusicCodec.Line> l=MusicCodec.lrc("[offset:-100]\n[00:01.20][00:02]hello\n[00:60]bad\n[00:00.4]first\n[00:03.001]尾");ok(l.size()==4);ok(l.get(0).ms==300);ok(l.get(1).ms==1100);ok(l.get(2).ms==1900);ok(l.get(3).ms==2901);ok(MusicCodec.line(l,1100)==1);ok(MusicCodec.line(l,0)==-1);ok(MusicCodec.line(l,999999)==3);bad(()->MusicCodec.lyrics(Arrays.asList(new MusicCodec.Line(20,"a"),new MusicCodec.Line(10,"b"))));
 StringBuilder longLrc=new StringBuilder();for(int i=0;i<250;i++)longLrc.append("[00:01]行\n");ok(MusicCodec.lrc(longLrc.toString()).size()==192);ok(MusicCodec.lrc("[00:59.999]a").get(0).ms==59999);
 byte[] reply=new byte[32];System.arraycopy("TMA1".getBytes(StandardCharsets.US_ASCII),0,reply,0,4);reply[4]=1;MusicCodec.put(reply,8,7392);MusicCodec.put(reply,28,FocusCodec.crc(reply,28));ok(MusicCodec.reply(reply)!=null);for(int i=0;i<reply.length;i++){byte[] broken=reply.clone();broken[i]^=1;ok(MusicCodec.reply(broken)==null);}for(int i=0;i<32;i++)ok(MusicCodec.reply(Arrays.copyOf(reply,i))==null);
 byte[] invalid=state.clone();invalid[16]=(byte)0xff;bad(()->MusicCodec.command(1,1,1,1,0,false,invalid));ok(MusicCodec.clip("bad\ud800ok",20).length==5);
 System.out.println("MusicCodec: "+n+" checks; six packets match C firmware encoder");}
}
