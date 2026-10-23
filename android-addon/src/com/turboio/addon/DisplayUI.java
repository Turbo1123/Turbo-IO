package com.turboio.addon;
import android.app.*;
import android.graphics.*;
import android.os.*;
import android.widget.*;
import java.util.concurrent.*;

/** 设置 → 灵活显示 · 实验 (iOS DisplayPhoneUI "灵活显示 · PHONE 06", TVP2 display-runtime-v1 Turbo Display SID page):
 * query the SID, local 512×128 navigation sample or picked image, full canvas (139 chunks), delta updates, test mark,
 * close. Sends and lease renewal only while this page is visible and the app is in the foreground. */
final class DisplayUI {
    private static final ExecutorService IO=Executors.newSingleThreadExecutor();
    private static final Handler MAIN=new Handler(Looper.getMainLooper());
    private final Activity a;private EditorialUI.Screen s;private ImageView preview;private TextView note,rectState,baseline,pickInfo;
    private byte[] pixels;private boolean left,loading,resumed=true,refreshPending;private int meters=80;private long lastRefresh;
    private Application.ActivityLifecycleCallbacks lifecycle;
    private DisplayUI(Activity a){this.a=a;}
    static void show(Activity a){new DisplayUI(a).open();}
    private boolean gone(){return a.isFinishing()||a.isDestroyed()||s==null||!s.dialog.isShowing();}
    private void open(){
        s=new EditorialUI.Screen(a,"灵活显示 · 实验");LinearLayout b=s.body;
        b.addView(EditorialUI.text(a,"连接与能力 · 必须真实回执",15,EditorialUI.INK));
        note=EditorialUI.text(a,"保留TDP1传图测试。先在眼镜进入Turbo Display SID页面，再查询。原生导航请从导航页开启。",13,EditorialUI.LIME);b.addView(note);
        EditorialUI.button(a,b,"1 · 查询眼镜 SID",true,this::query);
        b.addView(EditorialUI.text(a,"先在眼镜进入 Turbo Display SID 页面。只查询一次，5秒无匹配回执停止；不根据旧提示猜测固件版本。",12,EditorialUI.MUTED));
        b.addView(EditorialUI.text(a,"手机绘图 · 不改变眼镜固件",15,EditorialUI.INK));
        preview=new ImageView(a);preview.setAdjustViewBounds(true);preview.setBackgroundColor(0xff000000);b.addView(preview,new LinearLayout.LayoutParams(-1,EditorialUI.dp(a,90)));
        b.addView(EditorialUI.text(a,"512×128 灰度 · 手机布局预览\n箭头 / 距离 / 路名 / 示意小地图\n不是实时导航，也不是眼镜截图",12,EditorialUI.MUTED));
        EditorialUI.button(a,b,"切换左转 / 右转示例",false,()->{left=!left;setImage(navigation(left,meters));});
        EditorialUI.button(a,b,"从文件选择 PNG / JPEG / HEIC",false,this::pick);
        pickInfo=EditorialUI.text(a,"只修改手机预览，不自动发送",12,EditorialUI.MUTED);b.addView(pickInfo);
        EditorialUI.button(a,b,"2 · 发送完整画布（64 KiB）",true,this::sendFrame);
        b.addView(EditorialUI.text(a,"单帧139块；此前真机约20秒。完整校验后才换画面，25秒未完成停止。首次发送后建立局部更新基线。",12,EditorialUI.MUTED));
        b.addView(EditorialUI.text(a,"测试与退出",15,EditorialUI.INK));
        EditorialUI.button(a,b,"3 · 发送 20×20 测试标记",false,()->result(DisplayBridge.session()!=null&&DisplayBridge.session().sendTestRect()));
        rectState=EditorialUI.text(a,"尚未查询",12,EditorialUI.MUTED);b.addView(rectState);
        EditorialUI.button(a,b,"关闭眼镜测试页",false,()->result(DisplayBridge.session()!=null&&DisplayBridge.session().closePage()));
        b.addView(EditorialUI.text(a,"需要会话有效且无在途任务；退出手机页会停止续租，不保证镜片立即关闭",12,EditorialUI.MUTED));
        EditorialUI.button(a,b,"返回 N8W 旧版传图",false,()->ImageUploadUI.show(a));
        b.addView(EditorialUI.text(a,"低延迟实验 · 只传变化区域",15,EditorialUI.INK));
        EditorialUI.button(a,b,"4 · 距离 80 / 60 米切换并局部发送",false,()->delta(0));
        EditorialUI.button(a,b,"5 · 左右转切换并局部发送",false,()->delta(1));
        EditorialUI.button(a,b,"6 · 重发同图（应为零传输）",false,()->delta(2));
        b.addView(EditorialUI.text(a,"先成功发送一次完整导航示例图，再点本项。只发送差异，最多32块；不是实时导航，不自动连续发送。",12,EditorialUI.MUTED));
        baseline=EditorialUI.text(a,"",12,EditorialUI.MUTED);b.addView(baseline);
        setImage(navigation(false,meters));
        DisplayBridge.changed=()->{refreshPending=true;refresh();};
        lifecycle=new Application.ActivityLifecycleCallbacks(){
            public void onActivityResumed(Activity x){if(x==a){resumed=true;resume();}}
            public void onActivityPaused(Activity x){if(x==a){resumed=false;DisplayBridge.foreground(false);}}
            public void onActivityCreated(Activity x,Bundle b){}public void onActivityStarted(Activity x){}public void onActivityStopped(Activity x){}
            public void onActivitySaveInstanceState(Activity x,Bundle b){}public void onActivityDestroyed(Activity x){}};
        a.getApplication().registerActivityLifecycleCallbacks(lifecycle);
        s.dialog.setOnDismissListener(d->{a.getApplication().unregisterActivityLifecycleCallbacks(lifecycle);DisplayBridge.foreground(false);DisplayBridge.changed=null;});
        Runnable tick=new Runnable(){public void run(){if(gone())return;try{DisplayBridge.tick();}catch(RuntimeException ignored){}refresh();MAIN.postDelayed(this,50);}};MAIN.postDelayed(tick,50);
        resume();refreshPending=true;refresh();
    }
    private void resume(){if(!gone()&&resumed)DisplayBridge.foreground(true);}
    private void refresh(){
        if(!refreshPending||gone())return;TdpSession t=DisplayBridge.session();long now=SystemClock.elapsedRealtime();
        if(t!=null&&t.busy()&&now-lastRefresh<250)return;refreshPending=false;lastRefresh=now;
        if(t!=null)note.setText(t.state());rectState.setText(t==null?"尚未查询":t.state());
        baseline.setText(t==null?"基线无效 · 0/0块 · 0.00秒\n未查询":String.format(java.util.Locale.ROOT,"基线%s · %d/%d块 · %.2f秒\n%s",t.hasPixelBaseline()?"已确认":"无效",t.completedRects(),t.deltaTotal(),t.deltaElapsed(),t.state()));
    }
    private void result(boolean ok){if(!ok){TdpSession t=DisplayBridge.session();note.setText(t!=null?t.state():"未发送：请先连接并进入眼镜 Turbo Display 页面，再查询 SID。");}}
    private void query(){
        if(loading)return;
        if(!DisplayBridge.setup()){note.setText("没有当前官方连接，或旧任务结果未知。请在官方设备页确认连接，不会创建第二个蓝牙连接。");return;}
        DisplayBridge.changed=()->{refreshPending=true;refresh();};resume();result(DisplayBridge.session().query());
    }
    private void sendFrame(){
        TdpSession t=DisplayBridge.session();if(loading)return;if(t==null||!t.ready()||t.busy()||pixels==null){result(false);return;}
        new AlertDialog.Builder(a).setTitle("发送本机画布？").setMessage("只发给当前配对眼镜，不上传云端、不刷固件。真实文件吞吐待验，超时后不会盲目重发。")
            .setNegativeButton("取消",null).setPositiveButton("发送",(d,w)->{TdpSession now=DisplayBridge.session();result(now!=null&&now.sendFrame(pixels));}).show();
    }
    private void delta(int row){
        TdpSession t=DisplayBridge.session();if(loading)return;if(t==null){result(false);return;}
        boolean l=row==1?!left:left;int m=row==0?(meters==80?60:80):meters;byte[] next=row==2?pixels:gray(navigation(l,m));
        boolean ok=next!=null&&t.sendChangedPixels(next);if(ok){left=l;meters=m;if(row!=2)setImage(navigation(l,m));}result(ok);
    }
    private void setImage(Bitmap bmp){pixels=gray(bmp);showGray(pixels);bmp.recycle();}
    private void showGray(byte[] g){if(g==null)return;int[] px=new int[Tdp.PIXELS];for(int i=0;i<px.length;i++){int v=g[i]&255;px[i]=0xff000000|v<<16|v<<8|v;}preview.setImageBitmap(Bitmap.createBitmap(px,Tdp.WIDTH,Tdp.HEIGHT,Bitmap.Config.ARGB_8888));}
    private static byte[] gray(Bitmap bmp){int[] argb=new int[Tdp.PIXELS];bmp.getPixels(argb,0,Tdp.WIDTH,0,0,Tdp.WIDTH,Tdp.HEIGHT);return Timg.luma(argb);}
    private static void text(Canvas c,String s,float x,float top,float size,boolean bold,int color){Paint p=new Paint(Paint.ANTI_ALIAS_FLAG);p.setColor(color);p.setTextSize(size);if(bold)p.setTypeface(Typeface.DEFAULT_BOLD);c.drawText(s,x,top-p.getFontMetrics().ascent,p);}
    /** The iOS NavigationImage sample layout: arrow, distance, road text, footer and a schematic mini map. */
    static Bitmap navigation(boolean left,int meters){
        Bitmap bmp=Bitmap.createBitmap(Tdp.WIDTH,Tdp.HEIGHT,Bitmap.Config.ARGB_8888);Canvas c=new Canvas(bmp);c.drawColor(Color.BLACK);
        Paint stroke=new Paint(Paint.ANTI_ALIAS_FLAG);stroke.setStyle(Paint.Style.STROKE);stroke.setColor(Color.WHITE);stroke.setStrokeWidth(7);stroke.setStrokeJoin(Paint.Join.ROUND);
        Path arrow=new Path();arrow.moveTo(45,100);arrow.lineTo(45,46);arrow.lineTo(left?14:82,46);arrow.moveTo(left?30:66,30);arrow.lineTo(left?14:82,46);arrow.lineTo(left?30:66,62);c.drawPath(arrow,stroke);
        text(c,meters+" 米",102,5,42,true,Color.WHITE);
        text(c,left?"前方左转 · 测试道路":"前方右转 · 测试道路",103,59,23,false,Color.WHITE);
        text(c,"TURBO IO · 本机布局示例 7392",103,100,13,false,Color.LTGRAY);
        stroke.setColor(Color.rgb(77,77,77));stroke.setStrokeWidth(2);c.drawRoundRect(new RectF(396,8,504,120),8,8,stroke);
        stroke.setStrokeWidth(1);for(int i=0;i<3;i++){c.drawLine(404,30+i*30,496,30+i*30,stroke);c.drawLine(414+i*32,16,414+i*32,111,stroke);}
        stroke.setColor(Color.WHITE);stroke.setStrokeWidth(4);Path route=new Path();route.moveTo(445,106);route.lineTo(445,60);route.lineTo(left?407:491,60);c.drawPath(route,stroke);
        return bmp;
    }
    private void pick(){
        if(loading)return;
        DocumentPicker.pick(a,20*1024*1024,bytes->{loading=true;pickInfo.setText("正在本机解码…");IO.execute(()->{byte[] g=null;
            try{BitmapFactory.Options o=new BitmapFactory.Options();o.inJustDecodeBounds=true;BitmapFactory.decodeByteArray(bytes,0,bytes.length,o);
                String mime=o.outMimeType==null?"":o.outMimeType;
                if(o.outWidth<=0||o.outHeight<=0||(long)o.outWidth*o.outHeight>16_000_000L||!(mime.equals("image/png")||mime.equals("image/jpeg")||mime.equals("image/heif")||mime.equals("image/heic")))throw new IllegalArgumentException();
                int sample=1;while(o.outWidth/(sample*2)>=Tdp.WIDTH&&o.outHeight/(sample*2)>=Tdp.HEIGHT)sample*=2;
                BitmapFactory.Options d=new BitmapFactory.Options();d.inSampleSize=sample;Bitmap src=BitmapFactory.decodeByteArray(bytes,0,bytes.length,d);if(src==null)throw new IllegalArgumentException();
                Bitmap canvas=Bitmap.createBitmap(Tdp.WIDTH,Tdp.HEIGHT,Bitmap.Config.ARGB_8888);Canvas c=new Canvas(canvas);c.drawColor(Color.BLACK);int[] r=Timg.fit(src.getWidth(),src.getHeight());
                c.drawBitmap(src,null,new Rect(r[0],r[1],r[0]+r[2],r[1]+r[3]),new Paint(Paint.FILTER_BITMAP_FLAG));src.recycle();g=gray(canvas);canvas.recycle();
            }catch(Throwable t){g=null;}
            byte[] out=g;MAIN.post(()->{loading=false;if(gone())return;
                if(out!=null){pixels=out;showGray(out);note.setText("已本机缩图，没有发送。");}else note.setText("文件不可用或超限：请先下载到本机，限单帧 PNG/JPEG/HEIC、16MP/20MiB。");
                pickInfo.setText("只修改手机预览，不自动发送");});});});
    }
}
