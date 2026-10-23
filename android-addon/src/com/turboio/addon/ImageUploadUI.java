package com.turboio.addon;
import android.app.*;
import android.graphics.*;
import android.os.*;
import android.text.InputType;
import android.widget.*;
import java.util.concurrent.*;

/** 设置 → 图片传输 · 实验 (iOS ImageUploadUI lab, TVP2 wide receiver): pick a PNG/JPEG, preview the 512×128 gray
 * frame, open Turbo Image RX on the glasses, enter its session ID, send one frame within 30 s. File delivery is
 * not display confirmation; nothing is retried. */
final class ImageUploadUI {
    private static final ExecutorService IO=Executors.newSingleThreadExecutor();
    private static final Handler MAIN=new Handler(Looper.getMainLooper());
    private final Activity a;private EditorialUI.Screen s;private ImageView preview;private TextView state,info;private byte[] pixels;private ImageUpload upload;
    private ImageUploadUI(Activity a){this.a=a;}
    static void show(Activity a){new ImageUploadUI(a).open();}
    private boolean gone(){return a.isFinishing()||a.isDestroyed()||!s.dialog.isShowing();}
    private static double now(){return SystemClock.elapsedRealtime()/1000.0;}
    private void open(){
        s=new EditorialUI.Screen(a,"图片传输 · 实验");LinearLayout b=s.body;
        b.addView(EditorialUI.text(a,"TVP2 大区域版：眼镜页面540×180，图片512×128、64KiB。先选图，再在眼镜打开 Turbo Image RX，输入页面上的 SID。原厂固件不支持；没有自动显示 ACK，最终看镜片 #1 和图片。",13,EditorialUI.MUTED));
        EditorialUI.button(a,b,"1 · 选择 PNG / JPEG",false,this::pick);
        b.addView(EditorialUI.text(a,"2 · 传输预览（512×128）",15,EditorialUI.INK));
        preview=new ImageView(a);preview.setAdjustViewBounds(true);preview.setBackgroundColor(0xff000000);b.addView(preview,new LinearLayout.LayoutParams(-1,EditorialUI.dp(a,90)));
        info=EditorialUI.text(a,"尚未选图",13,EditorialUI.MUTED);b.addView(info);
        EditorialUI.button(a,b,"输入眼镜 SID，开启本轮（30 秒内发送）",false,this::authorize);
        EditorialUI.button(a,b,"3 · 发送到眼镜",true,this::send);
        b.addView(EditorialUI.text(a,"接收与显示状态",15,EditorialUI.INK));state=EditorialUI.text(a,"",14,EditorialUI.LIME);b.addView(state);
        b.addView(EditorialUI.text(a,"本实验每轮仅提交一张。已有任务不自动重发；先确认结束并退出眼镜页面，再开启下一轮。仅发送当前图片，不启动 OTA，不上传云端。",13,EditorialUI.MUTED));
        upload=new ImageUpload((packet,device,task,submitted)->{
            long frame=readU32(packet,20),sid=readU32(packet,24);
            boolean sent=NativeTransfer.send(Timg.FILE,packet,frame,sid,15000,(st,result)->{if(upload!=null)upload.fileOutcome(device,task,st);render();});
            // The receiver has no app-level ACK: settle the shared gate on file delivery only.
            if(sent)NativeTransfer.ack(device,frame,sid,0);submitted.accept(sent);});
        upload.changed=this::render;render();
        Runnable tick=new Runnable(){public void run(){if(gone())return;upload.tick(now());MAIN.postDelayed(this,1000);}};MAIN.postDelayed(tick,1000);
        s.dialog.setOnDismissListener(d->{if(upload!=null&&upload.pending())upload.disconnect();});
    }
    private static long readU32(byte[] p,int at){return (p[at]&255L)|(p[at+1]&255L)<<8|(p[at+2]&255L)<<16|(p[at+3]&255L)<<24;}
    private void render(){if(state==null)return;String t;switch(upload.state()){
        case "ready":t="人工 SID 已开启，请在 30 秒内点发送。";break;case "submitting":t="已提交本图，等待文件回执；没有回执不会显示成功";break;case "transferring":t="正在传输文件…";break;
        case "file_received_waiting_renderer":t="文件成功回执已收到；没有自动显示 ACK，请检查镜片图片和 #1。";break;case "submission_failed":t="手机提交失败，未确认眼镜收到。请勿重复点发送。";break;
        case "file_failed":t="官方文件通道返回失败，未确认显示。请勿重复发送。";break;case "timeout_result_unknown":t="等待回执超时，结果未知；查看镜片 #1 和图片，不自动重发。";break;
        case "session_expired":t="30 秒窗口已过，请在眼镜重新打开接收页并输入新 SID。";break;case "disconnected_result_unknown":t="连接中断，结果未知；不自动重发。";break;
        default:t="等待已验证的接收会话；当前不会盲发";}state.setText(t);}
    private void pick(){
        DocumentPicker.pick(a,20*1024*1024,bytes->IO.execute(()->{byte[] g=null;String err=null;
            try{BitmapFactory.Options o=new BitmapFactory.Options();o.inJustDecodeBounds=true;BitmapFactory.decodeByteArray(bytes,0,bytes.length,o);
                if(o.outWidth<=0||o.outHeight<=0||(long)o.outWidth*o.outHeight>16_000_000L)throw new IllegalArgumentException();
                int sample=1;while(o.outWidth/(sample*2)>=Timg.W&&o.outHeight/(sample*2)>=Timg.H)sample*=2;
                BitmapFactory.Options d=new BitmapFactory.Options();d.inSampleSize=sample;Bitmap src=BitmapFactory.decodeByteArray(bytes,0,bytes.length,d);if(src==null)throw new IllegalArgumentException();
                Bitmap canvas=Bitmap.createBitmap(Timg.W,Timg.H,Bitmap.Config.ARGB_8888);Canvas c=new Canvas(canvas);c.drawColor(Color.BLACK);int[] r=Timg.fit(src.getWidth(),src.getHeight());
                c.drawBitmap(src,null,new Rect(r[0],r[1],r[0]+r[2],r[1]+r[3]),new Paint(Paint.FILTER_BITMAP_FLAG));src.recycle();
                int[] argb=new int[Timg.PIXELS];canvas.getPixels(argb,0,Timg.W,0,0,Timg.W,Timg.H);canvas.recycle();g=Timg.luma(argb);
            }catch(Throwable t){err="选图失败：只支持单帧 PNG/JPEG，最多 16MP、20 MiB。";}
            byte[] gray=g;String e=err;MAIN.post(()->{if(gone())return;if(e!=null){EditorialUI.notice(a,e);return;}pixels=gray;
                int[] px=new int[Timg.PIXELS];for(int i=0;i<px.length;i++){int v=gray[i]&255;px[i]=0xff000000|v<<16|v<<8|v;}preview.setImageBitmap(Bitmap.createBitmap(px,Timg.W,Timg.H,Bitmap.Config.ARGB_8888));
                info.setText("64 KiB 灰度像素；等比缩小留黑边。协议 v2，需匹配 TVP2 接收页。已在手机生成像素，无云上传。");});}));
    }
    private void authorize(){
        if(pixels==null){EditorialUI.notice(a,"请先选图，再打开眼镜 Turbo Image RX；这样不会浪费眼镜的接收窗口。");return;}
        String peer=NativeTransfer.connected();if(peer==null||peer.isEmpty()){EditorialUI.notice(a,"没有当前官方协议对象。请先在官方设备页确认连接；不会创建第二个蓝牙连接。");return;}
        EditText sid=new EditText(a);sid.setInputType(InputType.TYPE_CLASS_NUMBER);sid.setHint("眼镜显示的十进制 SID");
        new AlertDialog.Builder(a).setTitle("Turbo Image RX · 人工会话").setMessage("必须亲眼看到眼镜接收页上的 SID。输入后 30 秒内点发送；本轮最多一张，SDK 收到文件不代表镜片显示，需人工验收。不会触发 OTA。").setView(sid)
            .setNegativeButton("取消",null).setPositiveButton("已看到 SID，开启本轮",(d,w)->{long v;try{v=Long.parseLong(sid.getText().toString().trim());}catch(NumberFormatException e){v=0;}
                if(!peer.equals(NativeTransfer.connected())||!upload.authorize(peer,v,now()))EditorialUI.notice(a,"SID 无效或设备已改变，未开启。");}).show();
    }
    private void send(){
        if(pixels==null){EditorialUI.notice(a,"尚未选图");return;}
        if(!upload.send(pixels,now()))EditorialUI.notice(a,"未发送：未验证接收会话、会话已过期或已有任务。");
    }
}
