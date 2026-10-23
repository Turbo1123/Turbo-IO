package com.turboio.addon;
import android.app.*;
import android.os.*;
import android.widget.*;

/** 诊断与测试 → 眼镜日志 · 仅本机 (iOS GlassesLogProbe page, log-local-v3). */
final class GlassesLogUI {
    private static final Handler MAIN=new Handler(Looper.getMainLooper());
    private final Activity a;private EditorialUI.Screen s;private TextView status,request;
    private GlassesLogUI(Activity a){this.a=a;}
    static void show(Activity a){new GlassesLogUI(a).open();}
    private boolean gone(){return a.isFinishing()||a.isDestroyed()||s==null||!s.dialog.isShowing();}
    private void open(){
        s=new EditorialUI.Screen(a,"眼镜日志 · 仅本机");LinearLayout b=s.body;
        b.addView(EditorialUI.text(a,"当前状态 · "+GlassesLog.VERSION,15,EditorialUI.INK));status=EditorialUI.text(a,"",13,EditorialUI.LIME);b.addView(status);
        EditorialUI.button(a,b,"刷新状态",false,this::render);
        request=EditorialUI.button(a,b,"请求一次眼镜日志",true,this::confirm);
        EditorialUI.button(a,b,"分享已保存副本",false,()->{java.io.File f=GlassesLog.archive();if(f==null)GlassesLog.restore();else RecordingExports.share(a,f,"application/octet-stream");});
        b.addView(EditorialUI.text(a,"仅研究日志路径。测试前关闭手机互联网但保留蓝牙，结束其他眼镜任务；不要同时操作官方反馈。已保存且校验通过后，可手动请求新一轮，保留旧归档与隔离记录；不会自动重试。超时或结果未知仍禁止重发。最多保留32轮任务隔离，达到上限由Mac检查。隔离不是全App网络防火墙。",12,EditorialUI.MUTED));
        GlassesLog.listen(()->MAIN.post(this::render));s.dialog.setOnDismissListener(d->GlassesLog.listen(null));
        GlassesLog.restore();render();
        Runnable refresh=new Runnable(){public void run(){if(gone())return;render();MAIN.postDelayed(this,1000);}};MAIN.postDelayed(refresh,1000);
    }
    private void confirm(){
        new AlertDialog.Builder(a).setTitle("仅本机日志验收？").setMessage("先关闭手机互联网、保留蓝牙，并结束其他眼镜任务。此操作会让眼镜生成日志归档；可能包含私人信息。扩展接收本次任务，不调用上传、不自动解压、不删除原件。未恢复前请勿操作官方日志反馈。")
            .setNegativeButton("取消",null).setPositiveButton("已断互联网，开始一次",(d,w)->GlassesLog.start()).show();
    }
    private void render(){
        if(gone())return;
        status.setText(GlassesLog.note()+"\n发送上下文："+(GlassesLog.ready()?"可用":"不可用")+"\n任务记录："+(GlassesLog.hasRecord()?"已建立（跨重启保留）":"未建立"));
        request.setText(GlassesLog.archive()!=null?"开始新一轮日志（保留旧副本）":"请求一次眼镜日志");
    }
}
