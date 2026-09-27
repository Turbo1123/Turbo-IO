package com.turboio.addon;
import java.nio.file.*;import java.util.*;import java.util.concurrent.atomic.*;import java.net.*;import java.io.*;
public final class OfficialOtaFeedTest {
 static int n;static void ok(boolean b){n++;if(!b)throw new AssertionError("check "+n);}
 static String request(int port,String target,String extra){return "GET "+target+" HTTP/1.1\r\nHost: 127.0.0.1:"+port+"\r\n"+extra+"\r\n";}
 static Object data(OfficialOtaFeed.Reply r){ok(r.code==200);return BoundedJson.map(BoundedJson.read(r.body)).get("data");}
 public static void main(String[] args)throws Exception{
  byte[] zip=Files.readAllBytes(Paths.get(args[0]));AtomicLong clock=new AtomicLong(1000);AtomicBoolean guard=new AtomicBoolean(true);
  try(OfficialOtaFeed f=new OfficialOtaFeed(clock::get,guard::get)){
   int port=f.start(0);String query=OfficialOtaFeed.PATHS[1]+"?packageType=firmware&packageName=strix+OS&glassesType=S3&deviceType=android&versionCode=01.00.04.0012";
   ok(data(f.reply(request(port,query,"")))==null);f.arm(zip);
   Map<String,Object> meta=BoundedJson.map(data(f.reply(request(port,query,""))));ok(meta.get("apkMd5").equals(OtaPackage.hash("MD5",zip)));ok(((Number)meta.get("apkSize")).intValue()==zip.length);
   String path=new URI((String)meta.get("downloadUrl")).getRawPath();ok(Arrays.equals(zip,f.reply(request(port,path,"" )).body));
   ok(Arrays.equals(Arrays.copyOfRange(zip,100,201),f.reply(request(port,path,"Range: bytes=100-200\r\n")).body));
   ok(f.reply(request(port,path,"Range: bytes=0-9999999999\r\n")).body.length==zip.length);
   ok(f.reply(request(port,path,"Range: bytes=9999999999-\r\n")).code==416);
   ok(f.reply(request(port,path,"Range: bytes=9-2\r\n")).code==416);
   ok(f.reply(request(port,path,"Range: bytes=1-2,4-5\r\n")).code==416);
   ok(f.reply(request(port,path,"Range: bytes=-10\r\n")).code==416);
   ok(f.reply(request(port,path,"Host: evil\r\n")).code==400);
   ok(f.reply(request(port,path,"Transfer-Encoding: chunked\r\n")).code==400);
   ok(f.reply(request(port,path,"Content-Length: 1\r\n")).code==400);
   ok(f.reply(request(port,path,"Content-Length: 0\r\n")).code==200);
   ok(f.reply(request(port,path,"x_client_type: Android\r\n")).code==200);
   ok(f.reply(request(port,path,"x bad: forbidden\r\n")).code==400);
   ok(f.reply(request(port,query+"&packageType=firmware","" )).code==400);
   ok(data(f.reply(request(port,query.replace("android","iOS"),"")))==null);
   ok(data(f.reply(request(port,query.replace("packageType=firmware","packageType=app"),"")))==null);
   ok(data(f.reply(request(port,query.replace("0012","9999"),"")))==null);
   ok(f.reply(request(port,path,"" ).replace("GET ","POST ")).code==405);
   ok(f.reply(request(port,path,"" ).replace("127.0.0.1:","localhost:")).code==400);
   ok(f.reply(request(port,path+"?anything=1","" )).code==404);
   ok(f.reply(request(port,path,"" ).replace("GET ","HEAD ")).head);
   try(Socket s=new Socket("127.0.0.1",port)){s.setSoTimeout(2000);s.getOutputStream().write(request(port,query,"" ).getBytes("UTF-8"));ByteArrayOutputStream all=new ByteArrayOutputStream();byte[] b=new byte[4096];int k;while((k=s.getInputStream().read(b))!=-1)all.write(b,0,k);ok(all.toString("UTF-8").contains("HTTP/1.1 200 OK"));}
   byte[] bad=zip.clone();bad[0]^=1;try{f.arm(bad);throw new AssertionError();}catch(IOException expected){n++;}
   clock.set(901000);ok(data(f.reply(request(port,query,"")))==null);ok(f.reply(request(port,path,"" )).code==404);
   f.arm(zip);guard.set(false);ok(data(f.reply(request(port,query,"")))==null);try{f.arm(zip);throw new AssertionError();}catch(IOException expected){n++;}
   guard.set(true);f.arm(zip);f.disarm();ok(data(f.reply(request(port,query,"")))==null);
  }
  for(int type=1;type<=255;type++)ok(OtaFrame.readOnly(OtaFrame.encode(type,null,null))==(type==1||type==2||type==11));
  for(int type:new int[]{1,2,11}){ok(!OtaFrame.readOnly(OtaFrame.encode(type,OtaFrame.object("Mode",2),null)));ok(!OtaFrame.readOnly(OtaFrame.encode(type,null,new byte[]{1})));}
  ok(!OtaFrame.readOnly(new byte[]{8,1,16,4}));
  System.out.println("Official OTA preparation source/guard: "+n+" assertions passed; no device I/O");
 }
}
