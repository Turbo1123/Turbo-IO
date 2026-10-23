package com.turboio.addon;
import android.app.*;
import android.os.*;
import android.widget.*;

/** 设置 → 清晰投屏 · 实验: TVP2 native 540×220 HD window fed from a local video or a test pattern. Foreground
 * only: leaving the page or backgrounding the app stops the cast and releases the glasses. */
final class HdCastUI {
    private static final Handler MAIN=new Handler(Looper.getMainLooper());
    private final Activity a;private EditorialUI.Screen s;private TextView status,settings;private HdCast cast;
    private int levels=8,fps=5;private boolean fit=true;private double zoom=1;
    private Application.ActivityLifecycleCallbacks lifecycle;
    private HdCastUI(Activity a){this.a=a;}
    static void show(Activity a){new HdCastUI(a).open();}
    private boolean gone(){return a.isFinishing()||a.isDestroyed()||s==null||!s.dialog.isShowing();}
    private void open(){
        s=new EditorialUI.Screen(a,"清晰投屏 · 实验");LinearLayout b=s.body;
        b.addView(EditorialUI.text(a,"需要眼镜已刷 TVP2，并停在眼镜首页。手机把画面缩放成 540×220 灰度，四块收齐并校验后才换帧；眼镜短按暂停/继续，长按退出。仅前台运行，不上传云端。",13,EditorialUI.MUTED));
        EditorialUI.button(a,b,"选择本机视频并开始",true,this::pickVideo);
        EditorialUI.button(a,b,"用测试图案开始",false,()->begin(null));
        EditorialUI.button(a,b,"停止并释放眼镜",false,this::stop);
        b.addView(EditorialUI.text(a,"画面设置（下一帧生效）",15,EditorialUI.INK));
        settings=EditorialUI.text(a,"",13,EditorialUI.MUTED);b.addView(settings);
        EditorialUI.button(a,b,"切换灰阶 2 / 4 / 8 / 16",false,()->{levels=levels==16?2:levels*2;apply();});
        EditorialUI.button(a,b,"切换 完整画面 / 裁切放大",false,()->{fit=!fit;apply();});
        EditorialUI.button(a,b,"放大倍数 1 / 2 / 3 / 4（裁切模式）",false,()->{zoom=zoom>=4?1:zoom+1;apply();});
        EditorialUI.button(a,b,"目标帧率 2 / 5 / 10",false,()->{fps=fps==2?5:fps==5?10:2;apply();});
        b.addView(EditorialUI.text(a,"投屏状态",15,EditorialUI.INK));status=EditorialUI.text(a,"尚未开始",14,EditorialUI.LIME);b.addView(status);
        b.addView(EditorialUI.text(a,"高清像素是旧版的4倍，实际帧率受蓝牙带宽限制；目标帧率不等于实际帧率。16/8 灰阶超出手机 8KiB 消息通道的帧会自动降为 4 灰阶。",12,EditorialUI.MUTED));
        lifecycle=new Application.ActivityLifecycleCallbacks(){
            public void onActivityStopped(Activity x){if(x==a&&!x.isChangingConfigurations())stop();}
            public void onActivityDestroyed(Activity x){if(x==a){stop();a.getApplication().unregisterActivityLifecycleCallbacks(this);}}
            public void onActivityCreated(Activity x,Bundle b){}public void onActivityStarted(Activity x){}public void onActivityResumed(Activity x){}public void onActivityPaused(Activity x){}public void onActivitySaveInstanceState(Activity x,Bundle b){}};
        a.getApplication().registerActivityLifecycleCallbacks(lifecycle);
        s.dialog.setOnDismissListener(d->{stop();a.getApplication().unregisterActivityLifecycleCallbacks(lifecycle);});
        apply();Runnable refresh=new Runnable(){public void run(){if(gone())return;render();MAIN.postDelayed(this,500);}};MAIN.post(refresh);
    }
    private void apply(){
        settings.setText(levels+" 灰阶 · "+(fit?"完整画面":"裁切放大 "+(int)zoom+"×")+" · 目标 "+fps+" 帧/秒");
        HdCast c=cast;if(c!=null){c.levels=levels;c.fit=fit;c.zoom=zoom;c.fps=fps;}
    }
    private void render(){HdCast c=cast;if(c==null)return;status.setText(c.status());if(!c.running())cast=null;}
    private void pickVideo(){
        if(HdCast.active()){EditorialUI.notice(a,"已有投屏会话，请先停止");return;}
        // The system picker stops this page; the cast starts only after a file is chosen and the page is back.
        DocumentPicker.pickUri(a,"video/*",uri->MAIN.post(()->{if(!gone())begin(uri);}));
    }
    private void begin(android.net.Uri video){
        String[] why={""};HdCast c=HdCast.start(a,video,why);
        if(c==null){status.setText(why[0]);return;}
        cast=c;apply();render();
    }
    private void stop(){HdCast c=cast;if(c!=null)c.stop();}
}
