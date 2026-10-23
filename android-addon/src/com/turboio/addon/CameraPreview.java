package com.turboio.addon;
import android.app.Activity;
import android.app.Application;
import android.view.OrientationEventListener;
import android.content.ContentValues;
import android.content.Context;
import android.graphics.*;
import android.hardware.camera2.*;
import android.media.Image;
import android.media.ImageReader;
import android.net.Uri;
import android.os.*;
import android.provider.MediaStore;
import android.util.Range;
import android.util.Size;
import java.io.OutputStream;
import java.nio.ByteBuffer;
import java.util.*;

/** Phone camera → TVP2 viewfinder (TCM1), shutter from the glasses dial. Back camera, sensor
 * orientation (prop the phone in landscape). Only the lens preview is sent; the photo is saved on
 * the phone under Pictures/TurboIO. Stops on disconnect, link failure or capture timeout; never retakes. */
final class CameraPreview {
    interface Listener{void changed();}
    static final int[] DELAYS=CameraShutter.DELAYS;
    private static final Handler MAIN=new Handler(Looper.getMainLooper());
    private final Activity activity;private final int profile,delay;private final Listener listener;
    private final String owner=UUID.randomUUID().toString();
    private CameraLink link;private HandlerThread thread;private Handler worker;
    private volatile CameraDevice device;private volatile CameraCaptureSession session;private ImageReader preview,still;private CaptureRequest.Builder repeating;
    private volatile boolean wantFrames,released;private volatile double lastSample;private boolean stopped;
    private final CameraShutter shutter;private int phase=CameraCodec.LIVE,remaining,sensorOrientation=90;private volatile int deviceDegrees=-1;private float zoom=1f,minZoom=1f,maxZoom=1f;
    private OrientationEventListener orientation;private Application.ActivityLifecycleCallbacks lifecycle;
    private String failure="";

    CameraPreview(Activity a,int profile,int delay,Listener l){activity=a;this.profile=Math.max(0,Math.min(3,profile));this.delay=Math.max(0,Math.min(3,delay));listener=l;shutter=new CameraShutter(this.delay);}
    private static double now(){return SystemClock.elapsedRealtime()/1000.0;}
    String status(){
        if(link==null)return failure.isEmpty()?"未开启":failure;
        String s=link.note()+"\n取景帧 "+link.frames()+" · 丢弃 "+link.dropped()+(link.lastFrameBytes()>0?" · 上帧 "+link.lastFrameBytes()+" 字节 / "+String.format(Locale.ROOT,"%.1f",link.lastFrameSeconds())+" 秒":"");
        if(phase==CameraCodec.COUNTDOWN)s+="\n倒计时 "+remaining+" 秒";
        return failure.isEmpty()?s:s+"\n"+failure;
    }
    boolean active(){return link!=null&&link.active();}

    /** Starts only with the camera permission granted and the message link free. */
    void start(){
        String peer=NativeTransfer.connected();
        if(peer.isEmpty()||!NativeTransfer.acquireMessages(owner)){failure="请先连接眼镜、结束其他任务并退出升级保护；未启动相机。";changed();return;}
        link=new CameraLink(peer,w->{try{NativeTransfer.sendMessage(owner,peer,w,()->MAIN.post(()->{if(link!=null)link.invalidate("发送失败，已停止预览；没有重试快门");}));return true;}catch(Exception e){return false;}},CameraPreview::now);
        link.action=(op,arg)->MAIN.post(()->event(op,arg));CURRENT=this;
        thread=new HandlerThread("TurboIOCamera");thread.start();worker=new Handler(thread.getLooper());
        try{openCamera();}catch(Exception e){fail("此设备的相机配置不可用。");return;}
        orientation=new OrientationEventListener(activity){public void onOrientationChanged(int o){deviceDegrees=o;}};if(orientation.canDetectOrientation())orientation.enable();
        // Backgrounding the host stops the session: no preview over BLE while the app is not visible.
        lifecycle=new Application.ActivityLifecycleCallbacks(){
            public void onActivityStopped(Activity x){if(x==activity&&!x.isChangingConfigurations())fail("手机进入后台，已停止相机；请重新开启。");}
            public void onActivityCreated(Activity x,Bundle b){}public void onActivityStarted(Activity x){}public void onActivityResumed(Activity x){}public void onActivityPaused(Activity x){}public void onActivitySaveInstanceState(Activity x,Bundle b){}public void onActivityDestroyed(Activity x){if(x==activity)fail("页面已关闭，已停止相机。");}};
        activity.getApplication().registerActivityLifecycleCallbacks(lifecycle);
        link.start();MAIN.post(ticker);changed();
    }
    private void openCamera()throws Exception{
        CameraManager m=(CameraManager)activity.getSystemService(Context.CAMERA_SERVICE);String id=null;CameraCharacteristics chosen=null;
        for(String c:m.getCameraIdList()){CameraCharacteristics ch=m.getCameraCharacteristics(c);Integer f=ch.get(CameraCharacteristics.LENS_FACING);if(f!=null&&f==CameraCharacteristics.LENS_FACING_BACK){id=c;chosen=ch;break;}}
        if(id==null)throw new IllegalStateException("no back camera");
        android.hardware.camera2.params.StreamConfigurationMap map=chosen.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP);
        Size small=null;for(Size s:map.getOutputSizes(ImageFormat.YUV_420_888))if(s.getWidth()>=640&&s.getHeight()>=360&&(small==null||s.getWidth()*s.getHeight()<small.getWidth()*small.getHeight()))small=s;
        Size big=null;for(Size s:map.getOutputSizes(ImageFormat.JPEG))if(big==null||s.getWidth()*s.getHeight()>big.getWidth()*big.getHeight())big=s;
        if(small==null||big==null)throw new IllegalStateException("sizes");
        Integer so=chosen.get(CameraCharacteristics.SENSOR_ORIENTATION);if(so!=null)sensorOrientation=so;
        if(Build.VERSION.SDK_INT>=30){Range<Float> r=chosen.get(CameraCharacteristics.CONTROL_ZOOM_RATIO_RANGE);if(r!=null){minZoom=Math.max(1f,r.getLower());maxZoom=Math.min(6f,r.getUpper());}}
        preview=ImageReader.newInstance(small.getWidth(),small.getHeight(),ImageFormat.YUV_420_888,2);preview.setOnImageAvailableListener(this::sample,worker);
        still=ImageReader.newInstance(big.getWidth(),big.getHeight(),ImageFormat.JPEG,1);still.setOnImageAvailableListener(this::saved,worker);
        m.openCamera(id,new CameraDevice.StateCallback(){
            public void onOpened(CameraDevice d){if(released){d.close();return;}device=d;try{repeating=d.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW);repeating.addTarget(preview.getSurface());
                d.createCaptureSession(Arrays.asList(preview.getSurface(),still.getSurface()),new CameraCaptureSession.StateCallback(){
                    public void onConfigured(CameraCaptureSession s){if(released){s.close();return;}session=s;wantFrames=true;applyRepeating();}
                    public void onConfigureFailed(CameraCaptureSession s){MAIN.post(()->fail("相机会话配置失败，未开启取景。"));}},worker);}catch(Exception e){MAIN.post(()->fail("相机会话配置失败，未开启取景。"));}}
            public void onDisconnected(CameraDevice d){d.close();MAIN.post(()->fail("相机被中断或手机进入后台，已停止；请重新开启。"));}
            public void onError(CameraDevice d,int e){d.close();MAIN.post(()->fail("相机错误（"+e+"），已停止。"));}},worker);
    }
    private void applyRepeating(){try{if(session==null||released)return;if(Build.VERSION.SDK_INT>=30)repeating.set(CaptureRequest.CONTROL_ZOOM_RATIO,zoom);session.setRepeatingRequest(repeating.build(),null,worker);}catch(Exception e){MAIN.post(()->fail("相机预览失败，已停止。"));}}
    /** Worker thread: luma → fit → quantize → PackBits; only the latest frame survives in the link. */
    private void sample(ImageReader r){
        if(released)return;Image img;try{img=r.acquireLatestImage();}catch(RuntimeException e){return;}if(img==null)return;
        try{if(released||!wantFrames||now()-lastSample<CameraCodec.SAMPLE_SECONDS[profile])return;lastSample=now();
            Image.Plane p=img.getPlanes()[0];if(p.getPixelStride()!=1)return;ByteBuffer b=p.getBuffer();byte[] y=new byte[b.remaining()];b.get(y);
            int[] g=CameraCodec.PROFILES[profile];byte[] packed=CameraCodec.quantize(CameraCodec.fit(y,img.getWidth(),img.getHeight(),p.getRowStride(),g[0],g[1]),g[2]);
            byte[] comp=CameraCodec.compress(packed);if(comp!=null)MAIN.post(()->{if(link!=null&&wantFrames)link.offer(comp,g[0],g[1],g[2],false);});
        }catch(RuntimeException ignored){}finally{img.close();}
    }
    private void event(int op,long arg){
        if(link==null||stopped)return;
        // A press before the capture session exists is dropped, never replayed later.
        if(op==CameraCodec.SHUTTER){if(shutter.press(now(),session!=null&&!released))takePhoto();phase=shutter.phase();}
        else if(op==CameraCodec.ZOOM){zoom=Math.max(minZoom,Math.min(maxZoom,zoom+(arg!=0?.1f:-.1f)));applyRepeating();}
        else if(op==CameraCodec.CANCEL){shutter.cancel();phase=shutter.phase();}
        else if(op==CameraCodec.EXIT)stop();
        changed();
    }
    private void takePhoto(){
        CameraDevice d=device;CameraCaptureSession cs=session;if(d==null||cs==null||released){captureFailed("相机会话已停止，本次没有拍照。");return;}phase=shutter.phase();wantFrames=false;
        try{CaptureRequest.Builder b=d.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE);b.addTarget(still.getSurface());b.set(CaptureRequest.JPEG_ORIENTATION,CameraShutter.jpegOrientation(sensorOrientation,deviceDegrees));if(Build.VERSION.SDK_INT>=30)b.set(CaptureRequest.CONTROL_ZOOM_RATIO,zoom);
            cs.capture(b.build(),new CameraCaptureSession.CaptureCallback(){public void onCaptureFailed(CameraCaptureSession x,CaptureRequest q,CaptureFailure f){MAIN.post(()->captureFailed("拍照失败，未生成照片。"));}},worker);}
        catch(Exception e){captureFailed("拍照失败，未生成照片。");}
    }
    /** Worker thread: save the original, then send a 256x144 4-bit thumbnail as the review frame. */
    private void saved(ImageReader r){
        if(released)return;byte[] jpeg;
        try{Image img=r.acquireLatestImage();if(img==null)return;try{ByteBuffer b=img.getPlanes()[0].getBuffer();jpeg=new byte[b.remaining()];b.get(jpeg);}finally{img.close();}}
        catch(RuntimeException e){MAIN.post(()->captureFailed("拍照失败，未生成照片。"));return;}
        boolean ok=save(jpeg);byte[] thumb=ok?thumbnail(jpeg):null;
        MAIN.post(()->{if(stopped)return;wantFrames=true;
            if(!ok){captureFailed("保存照片失败，请检查存储空间。");return;}
            shutter.saved(now(),true);phase=shutter.phase();failure="";if(thumb!=null&&link!=null)link.offer(thumb,256,144,4,true);else failure="原片已保存，缩略图生成失败。";changed();});
    }
    private boolean save(byte[] jpeg){
        if(Build.VERSION.SDK_INT<29)return false;
        try{ContentValues v=new ContentValues();v.put(MediaStore.Images.Media.DISPLAY_NAME,"TurboIO_"+System.currentTimeMillis()+".jpg");v.put(MediaStore.Images.Media.MIME_TYPE,"image/jpeg");
            v.put(MediaStore.Images.Media.RELATIVE_PATH,Environment.DIRECTORY_PICTURES+"/TurboIO");v.put(MediaStore.Images.Media.IS_PENDING,1);
            Uri u=activity.getContentResolver().insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI,v);if(u==null)return false;
            try{try(OutputStream out=activity.getContentResolver().openOutputStream(u)){if(out==null)throw new java.io.IOException("no stream");out.write(jpeg);}
                v.clear();v.put(MediaStore.Images.Media.IS_PENDING,0);activity.getContentResolver().update(u,v,null,null);return true;}
            catch(Exception e){try{activity.getContentResolver().delete(u,null,null);}catch(Exception ignored){}return false;}  // no orphaned pending row
        }catch(Exception e){return false;}
    }
    private static byte[] thumbnail(byte[] jpeg){
        try{BitmapFactory.Options o=new BitmapFactory.Options();o.inJustDecodeBounds=true;BitmapFactory.decodeByteArray(jpeg,0,jpeg.length,o);
            int sample=1;while(o.outWidth/(sample*2)>=512&&o.outHeight/(sample*2)>=288)sample*=2;o=new BitmapFactory.Options();o.inSampleSize=sample;
            Bitmap bmp=BitmapFactory.decodeByteArray(jpeg,0,jpeg.length,o);if(bmp==null)return null;int w=bmp.getWidth(),h=bmp.getHeight();int[] px=new int[w*h];bmp.getPixels(px,0,w,0,0,w,h);bmp.recycle();
            byte[] y=new byte[w*h];for(int i=0;i<px.length;i++){int c=px[i];y[i]=(byte)((((c>>16)&255)*77+((c>>8)&255)*150+(c&255)*29)>>8);}
            return CameraCodec.compress(CameraCodec.quantize(CameraCodec.fit(y,w,h,w,256,144),4));
        }catch(RuntimeException e){return null;}
    }
    private void captureFailed(String why){if(stopped)return;shutter.saved(now(),false);phase=shutter.phase();wantFrames=true;failure=why;changed();}
    private final Runnable ticker=new Runnable(){public void run(){
        if(stopped||link==null)return;double t=now();
        if(!NativeTransfer.connected().equals(link.peer())){fail("蓝牙连接中断，已停止相机，不自动续拍");return;}
        CameraShutter.Step step=shutter.tick(t,session!=null&&!released,link.reviewBusy());phase=step.phase;remaining=step.remaining;
        if(step.capture)takePhoto();
        if(step.timedOut){fail("拍摄或保存超时，已停止取景；照片仍可能完成保存，不会自动补拍。");return;}
        link.state(phase,Math.round(zoom*100),remaining);
        link.tick();
        if(!link.active()){finishRelease();return;}
        changed();MAIN.postDelayed(this,50);
    }};
    private void fail(String why){failure=why;stop();}
    /** Sends CLOSE once while the link is up; releases the camera on its ack or after 3 s. */
    void stop(){
        if(stopped)return;stopped=true;wantFrames=false;
        if(link!=null&&link.active()){link.close();MAIN.postDelayed(this::finishRelease,3000);MAIN.post(closeTicker);}else finishRelease();
        changed();
    }
    private final Runnable closeTicker=new Runnable(){public void run(){if(link==null||!link.active()){finishRelease();return;}link.tick();MAIN.postDelayed(this,50);}};
    private void finishRelease(){
        if(released)return;released=true;stopped=true;wantFrames=false;MAIN.removeCallbacks(ticker);MAIN.removeCallbacks(closeTicker);
        if(orientation!=null)orientation.disable();if(lifecycle!=null)activity.getApplication().unregisterActivityLifecycleCallbacks(lifecycle);
        // Camera objects are closed on the camera thread, serialized with its callbacks; the thread lives
        // a little longer so a late onOpened/onConfigured still sees `released` and closes itself.
        if(worker!=null){worker.post(()->{
            try{if(session!=null)session.close();}catch(Exception ignored){}try{if(device!=null)device.close();}catch(Exception ignored){}
            try{if(preview!=null)preview.close();}catch(Exception ignored){}try{if(still!=null)still.close();}catch(Exception ignored){}});
            HandlerThread t=thread;worker.postDelayed(t::quitSafely,5000);}
        if(link!=null&&link.active())link.invalidate("已停止");NativeTransfer.releaseMessages(owner);if(CURRENT==this)CURRENT=null;changed();
    }
    private void changed(){if(listener!=null)MAIN.post(listener::changed);}

    private static CameraPreview CURRENT;private static boolean receiving;
    /** One receiver for the process; packets go to the session that is open now, if any. */
    static void init(){if(receiving)return;receiving=true;NativeTransfer.receive((d,b)->{CameraPreview c=CURRENT;if(c!=null&&c.link!=null)c.link.consume(d,b);});}
}
