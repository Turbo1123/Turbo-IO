package com.turboio.addon;
import android.app.*;
import android.os.*;
import android.widget.*;
import java.util.*;

/** 诊断与测试 → 字幕导航 · 常亮与换文 (iOS subtitle HUD lab page, subtitle-hud-v1.1). Leaving the page or the
 * app requests the exit. */
final class SubtitleHudUI {
    private static final Handler MAIN=new Handler(Looper.getMainLooper());
    private final Activity a;private EditorialUI.Screen s;private TextView status,evidence;
    private Application.ActivityLifecycleCallbacks lifecycle;
    private SubtitleHudUI(Activity a){this.a=a;}
    static void show(Activity a){new SubtitleHudUI(a).open();}
    private boolean gone(){return a.isFinishing()||a.isDestroyed()||s==null||!s.dialog.isShowing();}
    private void open(){
        s=new EditorialUI.Screen(a,"字幕导航 · 显示 v1.1");LinearLayout b=s.body;
        b.addView(EditorialUI.text(a,"当前采集状态",15,EditorialUI.INK));status=EditorialUI.text(a,"",13,EditorialUI.LIME);b.addView(status);
        b.addView(EditorialUI.text(a,"字幕配置",15,EditorialUI.INK));
        b.addView(EditorialUI.text(a,"Android 版使用 iOS 已验证的默认临时预览配置；不采集官方字幕配置。",12,EditorialUI.MUTED));
        EditorialUI.button(a,b,"确认眼镜已退出，当前没有任何任务",false,this::confirm);
        b.addView(EditorialUI.text(a,"需要你实际确认首页且没有录音/智记/提词/对话，不以手机发送成功判断退出。",12,EditorialUI.MUTED));
        EditorialUI.button(a,b,"1 · 建立临时预览会话",true,()->{String[] why={""};if(!SubtitleHud.start(why))EditorialUI.notice(a,"未开始："+why[0]);});
        b.addView(EditorialUI.text(a,"只发临时设置，不发字幕录音启动；等待同SID回执后才能发A。4分钟保护；锁屏/离开时请求退出。",12,EditorialUI.MUTED));
        String[] labels={"2 · 发 A：7392／右转80米","3 · 发 B：9264／右转60米","4 · 发 C：3815／右转35米"};
        for(int i=0;i<3;i++){final int row=i;EditorialUI.button(a,b,labels[i],false,()->{SubtitleTrial t=SubtitleHud.trial();if(!t.phase().equals("ready")||t.frame()!=row||!SubtitleHud.next())EditorialUI.notice(a,"现在不能发这一段：需要预览回执、按 A→B→C 顺序且间隔至少3秒。");});}
        b.addView(EditorialUI.text(a,"mode3 / status0：测试同一句文字更新；观察覆盖还是追加、是否闪屏。检测到字幕音频消息立即停止；没有音频包不等于全链路未采音。",12,EditorialUI.MUTED));
        EditorialUI.button(a,b,"停止测试（需要镜片确认退出）",false,()->SubtitleHud.stop("用户停止"));
        b.addView(EditorialUI.text(a,"事件记录（不含文字、音频与设备标识）",15,EditorialUI.INK));evidence=EditorialUI.text(a,"",12,EditorialUI.MUTED);b.addView(evidence);
        lifecycle=new Application.ActivityLifecycleCallbacks(){
            public void onActivityPaused(Activity x){if(x==a){SubtitleHud.invalidateIdle();SubtitleHud.stop("手机离开前台或研究页面关闭");}}
            public void onActivityDestroyed(Activity x){if(x==a){SubtitleHud.invalidateIdle();SubtitleHud.stop("离开字幕测试页");a.getApplication().unregisterActivityLifecycleCallbacks(this);}}
            public void onActivityCreated(Activity x,Bundle b){}public void onActivityStarted(Activity x){}public void onActivityResumed(Activity x){}public void onActivityStopped(Activity x){}public void onActivitySaveInstanceState(Activity x,Bundle b){}};
        a.getApplication().registerActivityLifecycleCallbacks(lifecycle);
        s.dialog.setOnDismissListener(d->{SubtitleHud.invalidateIdle();SubtitleHud.stop("离开字幕测试页");SubtitleHud.changed=null;a.getApplication().unregisterActivityLifecycleCallbacks(lifecycle);});
        SubtitleHud.changed=this::render;
        Runnable refresh=new Runnable(){public void run(){if(gone())return;render();MAIN.postDelayed(this,1000);}};MAIN.post(refresh);
    }
    private void confirm(){
        new AlertDialog.Builder(a).setTitle("请以实际眼镜状态确认").setMessage("眼镜已回首页，且录音、智记、提词、字幕、语音对话均已结束？这不是协议退出回执。")
            .setNegativeButton("还没有",null).setPositiveButton("已实际确认",(d,w)->{if(!SubtitleHud.confirmIdle())EditorialUI.notice(a,"实验仍在进行，请先停止。");}).show();
    }
    private void render(){
        if(gone())return;SubtitleTrial t=SubtitleHud.trial();long elapsed=t.active()?Math.max(0,(long)(SystemClock.elapsedRealtime()/1000.0-t.began())):0;
        status.setText("subtitle-hud-v1.1\n"+t.phase()+" · "+t.note()+"\n预览样本：有 退出格式：有\n已发"+t.frame()+"段 · 字幕音频消息"+t.audioPackets()+"\n建立起计时"+elapsed+"秒（不是镜片亮屏计时）"+(SubtitleHud.confirmedIdle()?"\n已确认空闲（2分钟内可开始）":""));
        List<String> e=SubtitleHud.events();StringBuilder sb=new StringBuilder();for(int i=Math.max(0,e.size()-12);i<e.size();i++)sb.append(e.get(i)).append('\n');evidence.setText(sb.length()==0?"暂无":sb.toString().trim());
    }
}
