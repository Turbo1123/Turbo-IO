package com.turboio.addon;
import android.app.*;
import android.os.*;
import android.text.*;
import android.widget.*;
import java.text.SimpleDateFormat;
import java.util.*;
import java.util.concurrent.*;

/** 设置 → 通知历史 (iOS NotificationUI): opt-in local archive of the notifications the official app's listener sees;
 * search, detail, clear. No model, no upload; status shows counts only. */
final class NotificationHistoryUI {
    private static final ExecutorService READ=Executors.newSingleThreadExecutor();
    private static final Handler MAIN=new Handler(Looper.getMainLooper());
    private static String time(Map<String,Object> r){return new SimpleDateFormat("MM-dd HH:mm:ss",Locale.ROOT).format(new Date((long)(((Number)r.get("receivedAt")).doubleValue()*1000)));}
    private static String name(Map<String,Object> r){String n=(String)r.get("appName");return n==null||n.isEmpty()?(String)r.get("appId"):n;}
    static void show(Activity a){
        NotificationRuntime rt=NotificationTap.runtime(a);EditorialUI.Screen s=new EditorialUI.Screen(a,"通知历史");LinearLayout b=s.body;
        b.addView(EditorialUI.text(a,"来自官方 App 通知监听 · 仅本机",17,EditorialUI.INK));
        b.addView(EditorialUI.text(a,"默认关闭。开启后持续保存至手动关闭；不调用模型、不上传云端，并排除本归档的系统备份。保留最近 30 天，最多 2000 条 / 8 MiB 正文，超过时清理最早记录。\n需要在系统设置中允许雷鸟 App 读取通知。无法补回开启前或 App 被终止期间的通知；常驻/前台服务通知和本 App 自身通知不保存。",13,EditorialUI.MUTED));
        TextView state=EditorialUI.text(a,"",13,EditorialUI.INK);
        Switch[] sw=new Switch[1];boolean[] quiet={false};
        sw[0]=EditorialUI.toggle(a,b,"保存官方 App 收到的通知",rt.enabled(),(v,on)->{
            if(quiet[0])return;
            if(!on){NotificationTap.setEnabled(a,false);return;}
            quiet[0]=true;sw[0].setChecked(false);quiet[0]=false;
            new AlertDialog.Builder(a).setTitle("在本机保存通知？").setMessage("通知可能包含聊天、验证码和财务信息。开启后，官方 App 通知监听收到的普通通知将留在这台手机，直到你清空或超过保留上限。不会自动上传、交给 AI 或改变眼镜通知开关。共享设备前请关闭并清空。")
                .setNegativeButton("取消",null).setPositiveButton("开启本机保存",(d,w)->{NotificationTap.setEnabled(a,true);quiet[0]=true;sw[0].setChecked(true);quiet[0]=false;}).show();
        });
        b.addView(EditorialUI.text(a,"关闭后保留历史；清空需单独确认",13,EditorialUI.MUTED));b.addView(state);
        EditText query=new EditText(a);query.setSingleLine();query.setHint("搜索来源、标题或正文");query.setTextColor(EditorialUI.INK);query.setHintTextColor(EditorialUI.MUTED);b.addView(query);
        TextView header=EditorialUI.text(a,"",14,EditorialUI.INK);b.addView(header);
        LinearLayout list=EditorialUI.column(a);b.addView(list);
        b.addView(EditorialUI.text(a,"记录的是官方 App 收到的通知，不代表镜片一定显示过。相同内容去重；更新和移除事件保留为历史，不删除原文。",13,EditorialUI.MUTED));
        EditorialUI.button(a,b,"清空",false,()->new AlertDialog.Builder(a).setTitle("清空通知历史？").setMessage("删除 TurboIO 保存在本机的通知正文，不影响其他 App 或眼镜原厂通知。此操作不可撤销；若保存开关仍开启，之后的新通知仍会记录。")
            .setNegativeButton("取消",null).setPositiveButton("清空",(d,w)->READ.execute(()->{rt.invalidate();boolean ok=rt.store().clear();MAIN.post(()->{if(!ok)new AlertDialog.Builder(a).setTitle("未能完整清空").setMessage("请解锁手机后重试。").setPositiveButton("知道了",null).show();});})).show());
        final List<Map<String,Object>>[] shown=new List[]{Collections.emptyList()};final boolean[] loading={false};
        Runnable refresh=new Runnable(){public void run(){
            if(loading[0])return;loading[0]=true;String q=query.getText().toString();
            READ.execute(()->{rt.store().prune(System.currentTimeMillis()/1000.0);List<Map<String,Object>> rows=rt.store().search(q,2000);Map<String,Object> st=rt.status();
                MAIN.post(()->{loading[0]=false;if(!s.dialog.isShowing())return;
                    String err=String.valueOf(st.get("error"));
                    state.setText((rt.enabled()?"正在监听官方通知":"未开启 · 不保存正文")+"\n"+(!err.isEmpty()&&!err.equals("null")?err:"本次保存 "+st.get("inserted")+" · 去重 "+st.get("duplicates")+" · 队列丢弃 "+st.get("overflow")+" · 写入失败 "+st.get("writeFailures")+"\nTNA1-ANDROID-01 · 未修改眼镜固件"));
                    header.setText("已保存 "+st.get("count")+" 条 · 匹配 "+rows.size()+" 条");
                    if(rows.equals(shown[0]))return;shown[0]=rows;list.removeAllViews();
                    if(rows.isEmpty()){list.addView(EditorialUI.text(a,"暂无记录\n开启后让另一台设备发来一条测试消息。",13,EditorialUI.MUTED));return;}
                    for(Map<String,Object> r:rows.subList(0,Math.min(rows.size(),300))){String body=(String)r.get("content");if(body==null||body.isEmpty())body=(String)r.get("subtitle");
                        TextView row=EditorialUI.text(a,name(r)+" · "+time(r)+"\n"+r.get("title")+(String.valueOf(r.get("title")).isEmpty()?"":"\n")+(body.length()>160?body.substring(0,160)+"…":body),14,EditorialUI.INK);row.setPadding(0,12,0,12);
                        row.setOnClickListener(v->{String event=new String[]{"新增","更新","移除"}[((Number)r.get("eventId")).intValue()];String ts=(String)r.get("timestamp");
                            String when=ts==null||ts.isEmpty()?"未提供":new SimpleDateFormat("yyyy-MM-dd HH:mm:ss",Locale.ROOT).format(new Date(Long.parseLong(ts)));
                            new AlertDialog.Builder(a).setTitle("通知详情").setMessage(name(r)+"\n"+r.get("appId")+"\n手机接收："+time(r)+" · "+event+"\n原始时间："+when+"\n\n"+r.get("title")+"\n"+r.get("subtitle")+"\n\n"+r.get("content")+"\n\n仅保存通知监听提供的内容；若来源隐藏预览或正文已截断，无法恢复未提供的部分。").setPositiveButton("关闭",null).show();});
                        list.addView(row);}
                    if(rows.size()>300)list.addView(EditorialUI.text(a,"仅显示最近 300 条匹配；请用搜索缩小范围。",13,EditorialUI.MUTED));
                });});
        }};
        query.addTextChangedListener(new TextWatcher(){public void beforeTextChanged(CharSequence c,int x,int y,int z){}public void onTextChanged(CharSequence c,int x,int y,int z){}public void afterTextChanged(Editable e){shown[0]=null;refresh.run();}});
        Runnable tick=new Runnable(){public void run(){if(!s.dialog.isShowing())return;refresh.run();MAIN.postDelayed(this,2000);}};MAIN.post(tick);
    }
}
