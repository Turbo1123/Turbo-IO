package com.turboio.addon;
import java.io.*;
import java.net.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import java.util.function.BiConsumer;

/** One explicit model POST shared by context English and enhanced lifelog (iOS CEGenerationJob / TNLJob transport):
 * no redirects, no caches, HTTP 200 only, bounded response, 15 s connect / 60 s read. Every failure maps to the
 * caller's fixed texts — platform messages may echo request headers (the key). done runs exactly once via deliver. */
final class ModelCall {
    static final class Texts{final String refused,tooLarge,failed,cancelled;Texts(String refused,String tooLarge,String failed,String cancelled){this.refused=refused;this.tooLarge=tooLarge;this.failed=failed;this.cancelled=cancelled;}}
    private static final ExecutorService NET=Executors.newCachedThreadPool(r->{Thread t=new Thread(r,"turboio-model");t.setDaemon(true);return t;});
    private ModelCall(){}
    /** Returns a cancel action; cancelling delivers texts.cancelled (once) and drops the connection. */
    static Runnable post(String url,String key,byte[] body,int cap,Texts texts,Executor deliver,BiConsumer<byte[],String> done){
        AtomicBoolean finished=new AtomicBoolean();AtomicReference<HttpURLConnection> live=new AtomicReference<>();
        BiConsumer<byte[],String> once=(bytes,error)->{if(finished.compareAndSet(false,true))deliver.execute(()->done.accept(bytes,error));};
        NET.execute(()->{byte[] reply=null;String error=null;HttpURLConnection h=null;
            try{h=(HttpURLConnection)new URL(url).openConnection();live.set(h);if(finished.get())return;
                h.setInstanceFollowRedirects(false);h.setUseCaches(false);h.setConnectTimeout(15000);h.setReadTimeout(60000);h.setRequestMethod("POST");h.setDoOutput(true);
                h.setRequestProperty("Content-Type","application/json");h.setRequestProperty("Accept","application/json");h.setRequestProperty("Authorization","Bearer "+key);
                try(OutputStream o=h.getOutputStream()){o.write(body);}
                int code=h.getResponseCode();
                if(code!=200)error=texts.refused;else if(h.getContentLengthLong()>cap)error=texts.tooLarge;
                else try(InputStream in=h.getInputStream()){reply=BoundedHTTP.read(in,cap);}catch(IOException e){error="size limit".equals(e.getMessage())?texts.tooLarge:texts.failed;}
            }catch(Throwable e){error=texts.failed;}
            finally{if(h!=null)h.disconnect();}
            once.accept(error==null?reply:null,error);});
        return ()->{once.accept(null,texts.cancelled);HttpURLConnection h=live.get();if(h!=null)try{h.disconnect();}catch(Throwable ignored){}};
    }
}
