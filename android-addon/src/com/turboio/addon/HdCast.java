package com.turboio.addon;
import android.app.*;
import android.graphics.*;
import android.media.MediaMetadataRetriever;
import android.net.Uri;
import android.os.*;
import java.util.*;

/** TVP2 clear casting glue: holds the NativeTransfer message lease, sends TVP1 HD packets as business-15 messages
 * (≤8 KiB lane), feeds HdLink with the latest encoded frame from a local video or a moving test pattern. Only the
 * newest frame is kept; nothing is queued. Main thread except the single decode worker. */
final class HdCast {
    private static final Handler MAIN=new Handler(Looper.getMainLooper());
    private static HdCast current;private static boolean receiving;
    private static final NativeTransfer.Receiver RECEIVER=(from,bytes)->{HdCast c=current;if(c!=null&&c.link!=null){c.link.consume(from,bytes);c.changed();}};
    /** A cast holds the glasses window: other features and OTA wait. */
    static boolean active(){return current!=null;}
    static HdCast current(){return current;}

    private final Activity activity;private final String owner="hdcast-"+UUID.randomUUID();
    private HdLink link;private String peer="";private Uri video;private HandlerThread thread;private Handler worker;private volatile MediaMetadataRetriever retriever;
    private long durationMs;private double startedAt,nextCapture;private boolean encoding,stopping;private HdEncoder.Frame latest;
    volatile int levels=8,fps=5;volatile boolean fit=true;volatile double zoom=1;
    private int downgraded;private String failure="";Runnable listener;
    private HdCast(Activity a){activity=a;}
    private static double now(){return SystemClock.elapsedRealtime()/1000.0;}
    private void changed(){Runnable r=listener;if(r!=null)try{r.run();}catch(RuntimeException ignored){}}

    /** Start with a picked video (null = test pattern). Returns the started cast or null with a reason in why[0]. */
    static HdCast start(Activity a,Uri video,String[] why){
        if(current!=null){why[0]="已有投屏会话，请先停止";return null;}
        if(Build.VERSION.SDK_INT<27&&video!=null){why[0]="本机系统不支持按时间抽帧，请用测试图案";return null;}
        HdCast c=new HdCast(a);String p=NativeTransfer.connected();
        if(p.isEmpty()||!NativeTransfer.acquireMessages(c.owner)){why[0]="请先连接眼镜、回到眼镜首页并结束其他任务（含升级保护）；未开始投屏。";return null;}
        if(!receiving){receiving=true;NativeTransfer.receive(RECEIVER);}
        c.peer=p;c.video=video;current=c;
        c.link=new HdLink(p,w->{try{NativeTransfer.sendMessage(c.owner,p,w,()->MAIN.post(()->c.fail("发送失败，已停止投屏；不自动重发")));return true;}catch(Exception e){return false;}},HdCast::now);
        c.thread=new HandlerThread("TurboIOHdCast");c.thread.start();c.worker=new Handler(c.thread.getLooper());
        if(video!=null)c.worker.post(c::openVideo);
        c.startedAt=now();c.link.start();MAIN.post(c.ticker);c.changed();return c;
    }
    private void openVideo(){
        MediaMetadataRetriever r=new MediaMetadataRetriever();
        try{r.setDataSource(activity.getApplicationContext(),video);
            String d=r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION),hv=r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO);
            long ms=d==null?0:Long.parseLong(d);if(ms<=0||!"yes".equals(hv)){release(r);MAIN.post(()->abandon("这个文件没有可读取的视频轨道"));return;}
            retriever=r;durationMs=ms;
        }catch(Exception|Error e){release(r);MAIN.post(()->abandon("视频无法读取：请先下载到本机，限常见 MP4/H.264"));}
    }
    private static void release(MediaMetadataRetriever r){try{r.release();}catch(Exception ignored){}}
    /** A source error is not a link error: CLOSE the glasses page before releasing the lease. */
    private void abandon(String why){if(current!=this)return;failure=why;stop();}
    private final Runnable ticker=new Runnable(){public void run(){
        if(current!=HdCast.this)return;
        if(!peer.equals(NativeTransfer.connected())){link.tick();fail("眼镜连接变化，已停止投屏");return;}
        link.tick();
        if(!link.active()){finish();return;}
        if(latest!=null&&link.ready()&&!link.busy()&&!link.paused()&&!stopping){HdEncoder.Frame f=latest;latest=null;link.offer(f);}
        if(!stopping&&link.ready()&&!link.paused()&&!encoding&&latest==null&&now()>=nextCapture&&(video==null||retriever!=null)){encoding=true;nextCapture=now()+1.0/Math.max(1,Math.min(10,fps));double t=now()-startedAt;worker.post(()->capture(t));}
        changed();MAIN.postDelayed(this,50);
    }};
    private void capture(double t){
        HdEncoder.Frame f=null;
        try{Bitmap b=video==null?pattern(t):videoFrame(t);
            if(b!=null){int w=b.getWidth(),h=b.getHeight();int[] argb=new int[w*h];b.getPixels(argb,0,w,0,0,w,h);b.recycle();byte[] luma=new byte[w*h];
                for(int i=0;i<argb.length;i++){int p=argb[i];luma[i]=(byte)((299*((p>>16)&255)+587*((p>>8)&255)+114*(p&255))/1000);}
                f=HdEncoder.encodeForLane(luma,w,h,w,false,levels,fit,zoom,.5,.5);}
        }catch(Exception|Error e){f=null;}
        HdEncoder.Frame done=f;MAIN.post(()->{encoding=false;if(current!=this||done==null)return;if(done.downgraded)downgraded++;latest=done;});
    }
    private Bitmap videoFrame(double t){
        MediaMetadataRetriever r=retriever;if(r==null||durationMs<=0||Build.VERSION.SDK_INT<27)return null;long us=(long)((t*1000)%durationMs)*1000;
        return r.getScaledFrameAtTime(us,MediaMetadataRetriever.OPTION_CLOSEST_SYNC,960,540);
    }
    private static Bitmap pattern(double t){
        Bitmap b=Bitmap.createBitmap(Vp.W,Vp.H,Bitmap.Config.ARGB_8888);Canvas c=new Canvas(b);c.drawColor(Color.BLACK);Paint p=new Paint(Paint.ANTI_ALIAS_FLAG);p.setColor(Color.WHITE);
        float x=(float)((t*120)%(Vp.W+80))-40;c.drawRect(x,0,x+40,Vp.H,p);p.setTextSize(44);p.setTypeface(Typeface.DEFAULT_BOLD);c.drawText(String.format(Locale.ROOT,"TURBO IO · %.1f s",t),24,80,p);
        p.setTextSize(22);p.setTypeface(Typeface.DEFAULT);c.drawText("540×220 原生高清 · 测试图案",24,130,p);for(int i=0;i<16;i++){p.setColor(Color.rgb(i*17,i*17,i*17));c.drawRect(24+i*30,160,24+i*30+28,200,p);}
        return b;
    }
    /** Graceful stop: CLOSE releases the glasses window; the lease is released once the link ends. */
    void stop(){if(current!=this)return;stopping=true;latest=null;if(link.active())link.close();else finish();changed();}
    private void fail(String why){if(current!=this)return;failure=why;finish();}
    private void finish(){
        if(current!=this)return;current=null;MAIN.removeCallbacks(ticker);NativeTransfer.releaseMessages(owner);
        Handler w=worker;HandlerThread th=thread;if(w!=null)w.post(()->{MediaMetadataRetriever r=retriever;retriever=null;if(r!=null)try{r.release();}catch(Exception ignored){}if(th!=null)th.quitSafely();});
        changed();
    }
    String status(){
        HdLink l=link;if(l==null)return failure;
        String s=l.note()+"\n已显示 "+l.frames()+" 帧 · 丢弃 "+l.rejectedFrames()+" · 已确认 "+l.verifiedBytes()/1024+" KiB"+(l.lastFrameSeconds()>0?String.format(Locale.ROOT," · 上帧 %.2f 秒",l.lastFrameSeconds()):"")+(l.paused()?"\n眼镜已暂停（短按继续）":"");
        if(downgraded>0)s+="\n"+downgraded+" 帧超出 8KiB 通道，已降为 4 灰阶";
        return failure.isEmpty()?s:s+"\n"+failure;
    }
    boolean running(){return current==this;}
}
