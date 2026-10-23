package com.turboio.addon;
import android.app.*;
import android.os.*;
import android.widget.*;

/** 诊断与测试 → 待办协议验收 (iOS TodoRuntime page). */
final class TodoUI {
    private static final Handler MAIN=new Handler(Looper.getMainLooper());
    private final Activity a;private EditorialUI.Screen s;private TextView state,detail;
    private TodoUI(Activity a){this.a=a;}
    static void show(Activity a){new TodoUI(a).open();}
    private boolean gone(){return a.isFinishing()||a.isDestroyed()||s==null||!s.dialog.isShowing();}
    private void open(){
        s=new EditorialUI.Screen(a,"待办协议验收");LinearLayout b=s.body;
        state=EditorialUI.text(a,"",15,EditorialUI.INK);b.addView(state);detail=EditorialUI.text(a,"",13,EditorialUI.MUTED);b.addView(detail);
        EditorialUI.button(a,b,"刷新",false,this::render);
        EditorialUI.button(a,b,"创建一条桥接测试待办",true,this::confirm);
        b.addView(EditorialUI.text(a,"通过真实官方模板；不会调用未验证的Dart地址",12,EditorialUI.MUTED));
        b.addView(EditorialUI.text(a,"只测试官方持久化创建入口；不发送网页业务待办、不覆盖眼镜列表。一次创建后不自动重试。列表基线仅保留进程内存，文件只记录命名测试项和计数。",12,EditorialUI.MUTED));
        TodoRuntime.changed=()->MAIN.post(this::render);s.dialog.setOnDismissListener(d->TodoRuntime.changed=null);render();
        Runnable refresh=new Runnable(){public void run(){if(gone())return;render();MAIN.postDelayed(this,1000);}};MAIN.postDelayed(refresh,1000);
    }
    private void confirm(){
        new AlertDialog.Builder(a).setTitle("创建专用测试项？").setMessage("将通过官方待办流程尝试新增一条随机编号测试项，不动其他待办。即使超时也不自动重发。")
            .setNegativeButton("取消",null).setPositiveButton("创建测试项",(d,w)->new AlertDialog.Builder(a).setTitle("提交状态").setMessage(TodoRuntime.createTestTask()).setPositiveButton("知道了",null).show()).show();
    }
    private void render(){if(gone())return;state.setText(TodoRuntime.state());detail.setText(TodoRuntime.counts());}
}
