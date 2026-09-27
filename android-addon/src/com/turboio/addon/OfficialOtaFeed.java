package com.turboio.addon;

import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.*;
import java.util.function.BooleanSupplier;
import java.util.function.LongSupplier;

/** Local source for the Android OFFICIAL downloader. No Bluetooth APIs. */
final class OfficialOtaFeed implements Closeable {
 static final String[] PATHS={"/g/xxxxxxxA78p2M","/g/xxxxxxxxxxCCXhB"};
 private final LongSupplier clock;private final BooleanSupplier protectedMode;
 private ServerSocket listener;private volatile boolean closed;private byte[] archive;
 private String token="",md5="";private long deadline;private int queries,firmwareQueries,downloads,rejected;
 private String queryShape="尚无查询";
 private String lastReject="无";
 private final boolean guarded;
 OfficialOtaFeed(LongSupplier clock,BooleanSupplier protectedMode){this(clock,protectedMode,false);}
 OfficialOtaFeed(LongSupplier clock,BooleanSupplier protectedMode,boolean guarded){this.clock=clock;this.protectedMode=protectedMode;this.guarded=guarded;}
 synchronized int start(int port)throws IOException{
  if(listener!=null)throw new IOException("already started");
  ServerSocket socket=new ServerSocket();try{socket.bind(new InetSocketAddress(InetAddress.getByName("127.0.0.1"),port),4);}catch(IOException e){socket.close();throw e;}listener=socket;
  Thread t=new Thread(()->{while(!closed){try(Socket s=listener.accept()){s.setSoTimeout(2000);if(s.getInetAddress().equals(InetAddress.getLoopbackAddress())||s.getInetAddress().getHostAddress().equals("127.0.0.1"))serve(s);}catch(Exception ignored){}}},"TurboIO-official-ota-source");t.setDaemon(true);t.start();return listener.getLocalPort();
 }
 synchronized void arm(byte[] zip)throws IOException{
  if(listener==null||!protectedMode.getAsBoolean())throw new IOException("preparation guard unavailable");
  // Immutable private snapshot, verified in full before publication to downloader.
  byte[] frozen=zip.clone();OtaPackage.verify(frozen);
  byte[] random=new byte[24];new SecureRandom().nextBytes(random);
  token=OtaPackage.hash("SHA-256",random);md5=OtaPackage.hash("MD5",frozen);
  archive=frozen;deadline=clock.getAsLong()+900000;
 }
 synchronized void disarm(){archive=null;token="";md5="";deadline=0;}
 private synchronized void expire(){if(archive!=null&&(clock.getAsLong()>=deadline||!protectedMode.getAsBoolean()))disarm();}
 synchronized String status(){expire();return "本机更新源："+(listener==null?"未启动":"运行中")+" · "+(archive==null?"无更新":"15 分钟只下载")+"\n来源查询："+queries+" · 匹配固件："+firmwareQueries+" · 下载请求："+downloads+" · 拒绝："+rejected+"（"+lastReject+"）\n查询形状："+queryShape;}
 public synchronized void close()throws IOException{closed=true;disarm();if(listener!=null)listener.close();}
 static Map<String,String> query(String target)throws IOException{
  Map<String,String> out=new HashMap<>();int at=target.indexOf('?');if(at<0)return out;
  for(String pair:target.substring(at+1).split("&",-1)){
   int eq=pair.indexOf('=');if(eq<1)throw new IOException("query");
   String k=URLDecoder.decode(pair.substring(0,eq),"UTF-8"),v=URLDecoder.decode(pair.substring(eq+1),"UTF-8");
   if(out.put(k,v)!=null)throw new IOException("duplicate query");
  }return out;
 }
 static boolean firmware(Map<String,String> q){return "firmware".equals(q.get("packageType"))&&"strix OS".equals(q.get("packageName"))&&"S3".equals(q.get("glassesType"))&&"android".equals(q.get("deviceType"))&&"01.00.04.0012".equals(q.get("versionCode"));}
 static final class Reply {int code=200;byte[] body=new byte[0];String type="application/json",range="";boolean head;}
 synchronized Reply reply(String request){
  Reply r=new Reply();try{
   expire();if(request.length()>16384||!request.endsWith("\r\n\r\n"))throw new IOException("headers");
   String[] lines=request.substring(0,request.length()-4).split("\r\n",-1),first=lines[0].split(" ",-1);
   if(first.length!=3||!"HTTP/1.1".equals(first[2]))throw new IOException("request line");
   String target=first[1];r.head="HEAD".equals(first[0]);
   if(!r.head&&!"GET".equals(first[0])){lastReject="method";r.code=405;return r;}
   Map<String,String> h=new HashMap<>();for(int i=1;i<lines.length;i++){int n=lines[i].indexOf(':');if(n<=0)throw new IOException("header");String k=lines[i].substring(0,n).toLowerCase(Locale.ROOT);if(!k.matches("[a-z0-9!#$%&'*+.^_`|~-]+")||h.put(k,lines[i].substring(n+1).trim())!=null)throw new IOException("header");}
   if(listener==null||!("127.0.0.1:"+listener.getLocalPort()).equals(h.get("host")))throw new IOException("host");
   if(h.containsKey("transfer-encoding")||h.containsKey("content-length")&&!"0".equals(h.get("content-length")))throw new IOException("body");
   String path=target.split("\\?",2)[0];
   if(Arrays.asList(PATHS).contains(path)){
    Map<String,String> q=query(target);queries++;boolean match=firmware(q);if(match)firmwareQueries++;
    // Values are never retained: these booleans cannot expose IDs, tokens or headers.
    queryShape="firmware="+"firmware".equals(q.get("packageType"))+", app="+"app".equals(q.get("packageType"))+", S3="+"S3".equals(q.get("glassesType"))+", android="+"android".equals(q.get("deviceType"))+", name="+"strix OS".equals(q.get("packageName"))+", version="+"01.00.04.0012".equals(q.get("versionCode"));
    Object data=null;if(match&&archive!=null)data=OtaFrame.object("taskName",guarded?"TAP1-TEST-01 GUARDED":"TAP1-TEST-01 PREPARATION ONLY","appName","Strix OS","packageName","Strix OS","versionName","0100040012","versionCode",100040012,"upgradeType",1,"userScope",0,"updateDesc",guarded?"TAP1-TEST-01 experimental firmware. AP-only; requires separate one-time authorization. Risk of device failure. Do not install without confirmation.":"TEST: download and verify on phone only. Glasses upgrade sending is disabled.","appIcon","","apkSize",archive.length,"apkMd5",md5,"downloadUrl","http://127.0.0.1:"+listener.getLocalPort()+"/p/"+token+"/Strix_OS_1.0.4.12.zip");
    r.body=BoundedJson.canonical(OtaFrame.object("error_code",1000,"error_msg","success","data",data));
   }else if(archive!=null&&target.equals("/p/"+token+"/Strix_OS_1.0.4.12.zip")){
    r.type="application/zip";r.body=archive;
    if(h.containsKey("range")){
     String v=h.get("range");if(!v.matches("bytes=[0-9]{1,10}-[0-9]{0,10}")){r.code=416;r.body=new byte[0];return r;}
     String[] ends=v.substring(6).split("-",-1);long from=Long.parseLong(ends[0]),to=ends[1].isEmpty()?archive.length-1:Long.parseLong(ends[1]);
     if(from>=archive.length||to<from){r.code=416;r.body=new byte[0];return r;}to=Math.min(to,archive.length-1);
     r.code=206;r.range="bytes "+from+"-"+to+"/"+archive.length;r.body=Arrays.copyOfRange(archive,(int)from,(int)to+1);
    }downloads++;
   }else r.code=404;
  }catch(Exception e){String reason=e.getMessage();lastReject=Arrays.asList("headers","request line","query","duplicate query","header","host","body").contains(reason)?reason:"parse";r.code=400;r.body=new byte[0];}finally{if(r.code>=400)rejected++;}return r;
 }
 private void serve(Socket s)throws IOException{
  InputStream in=s.getInputStream();ByteArrayOutputStream b=new ByteArrayOutputStream();int tail=0;long until=System.nanoTime()+2000000000L;
  while(b.size()<16384&&System.nanoTime()<until){int c=in.read();if(c<0)break;b.write(c);tail=(tail<<8)|c;if(tail==0x0d0a0d0a)break;}
  Reply r=reply(b.toString("UTF-8"));String headers="HTTP/1.1 "+r.code+" "+(r.code==200?"OK":r.code==206?"Partial Content":"Rejected")+"\r\nContent-Length: "+r.body.length+"\r\nContent-Type: "+r.type+"\r\nCache-Control: no-store\r\nConnection: close\r\nX-Content-Type-Options: nosniff\r\nAccept-Ranges: bytes\r\n"+(r.range.isEmpty()?"":"Content-Range: "+r.range+"\r\n")+"\r\n";
  // Watchdog bounds blocked response writes as well as header reads.
  Timer timer=new Timer(true);timer.schedule(new TimerTask(){public void run(){try{s.close();}catch(IOException ignored){}}},10000);
  try{OutputStream out=s.getOutputStream();out.write(headers.getBytes(StandardCharsets.US_ASCII));if(!r.head)out.write(r.body);out.flush();}finally{timer.cancel();}
 }
}
