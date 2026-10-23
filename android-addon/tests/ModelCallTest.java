package com.turboio.addon;
import com.sun.net.httpserver.*;import java.io.*;import java.net.InetSocketAddress;import java.nio.charset.StandardCharsets;import java.util.*;import java.util.concurrent.*;

/** Shared explicit model POST: one request, no redirects, 200 only, bounded body, fixed error texts (never platform
 * messages, which may echo the key), cancel delivers once. */
public final class ModelCallTest {
    static int n;static void ok(boolean b,String why){n++;if(!b)throw new AssertionError("model call "+n+" "+why);}
    static final ModelCall.Texts T=new ModelCall.Texts("拒绝","过大","失败","已取消");
    static String[] call(String url,int cap)throws Exception{CountDownLatch done=new CountDownLatch(1);String[] out=new String[2];
        ModelCall.post(url,"sk-test",("{\"a\":1}").getBytes(StandardCharsets.UTF_8),cap,T,Runnable::run,(bytes,error)->{out[0]=bytes==null?null:new String(bytes,StandardCharsets.UTF_8);out[1]=error;done.countDown();});
        ok(done.await(10,TimeUnit.SECONDS),"delivered");return out;}
    public static void main(String[] a)throws Exception{
        HttpServer s=HttpServer.create(new InetSocketAddress("127.0.0.1",0),0);List<String> auth=new ArrayList<>();int[] hits={0};
        s.createContext("/ok",x->{hits[0]++;auth.add(x.getRequestHeaders().getFirst("Authorization"));byte[] in=readAll(x.getRequestBody());byte[] b=("{\"echo\":"+new String(in,StandardCharsets.UTF_8)+"}").getBytes(StandardCharsets.UTF_8);x.sendResponseHeaders(200,b.length);x.getResponseBody().write(b);x.close();});
        s.createContext("/fail",x->{x.sendResponseHeaders(500,-1);x.close();});
        s.createContext("/redirect",x->{x.getResponseHeaders().add("Location","/ok");x.sendResponseHeaders(302,-1);x.close();});
        s.createContext("/big",x->{byte[] b=new byte[5000];Arrays.fill(b,(byte)'x');x.sendResponseHeaders(200,0);x.getResponseBody().write(b);x.close();});
        s.createContext("/slow",x->{try{Thread.sleep(3000);}catch(InterruptedException e){}x.sendResponseHeaders(200,-1);x.close();});
        s.start();String base="http://127.0.0.1:"+s.getAddress().getPort();
        String[] r=call(base+"/ok",65536);ok(r[1]==null&&r[0].equals("{\"echo\":{\"a\":1}}")&&auth.get(0).equals("Bearer sk-test"),"200 body, bearer header");
        r=call(base+"/fail",65536);ok(r[0]==null&&r[1].equals("拒绝"),"non-200 refused");
        int before=hits[0];r=call(base+"/redirect",65536);ok(r[1].equals("拒绝")&&hits[0]==before,"redirect not followed");
        r=call(base+"/big",4096);ok(r[1].equals("过大"),"response cap");
        r=call("http://127.0.0.1:1/none",65536);ok(r[1].equals("失败"),"connection failure fixed text");
        CountDownLatch once=new CountDownLatch(1);int[] calls={0};String[] got=new String[1];
        Runnable cancel=ModelCall.post(base+"/slow","k","{}".getBytes(StandardCharsets.UTF_8),100,T,Runnable::run,(bytes,error)->{calls[0]++;got[0]=error;once.countDown();});
        cancel.run();ok(once.await(5,TimeUnit.SECONDS)&&got[0].equals("已取消"),"cancel delivers");Thread.sleep(3500);ok(calls[0]==1,"delivered exactly once");
        s.stop(0);System.out.println("ModelCallTest: "+n+" checks; body, header, refusals, redirect, cap, cancel");
        System.exit(0);
    }
    static byte[] readAll(InputStream in)throws IOException{ByteArrayOutputStream o=new ByteArrayOutputStream();byte[] b=new byte[4096];int k;while((k=in.read(b))>0)o.write(b,0,k);return o.toByteArray();}
}
