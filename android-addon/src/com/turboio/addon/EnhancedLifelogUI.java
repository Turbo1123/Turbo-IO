package com.turboio.addon;
import android.app.*;
import android.content.DialogInterface;
import android.os.*;
import android.widget.*;
import java.io.File;
import java.net.URI;
import java.time.*;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.concurrent.*;

/** 设置 → 增强智记 (iOS enhanced-lifelog-v1 TNLUI): read one day of the official cached transcript plus explicitly
 * ticked local notifications, show the full preview, approve one model call, save the cited summary locally.
 * Nothing runs automatically; synthetic examples are never saved. */
final class EnhancedLifelogUI {
    private static final ExecutorService READ=Executors.newSingleThreadExecutor();
    private static final Handler MAIN=new Handler(Looper.getMainLooper());
    private static final ModelCall.Texts TEXTS=new ModelCall.Texts("模型服务拒绝请求或响应过大；没有保存。","模型响应超过 128 KiB；没有保存。","连接失败或超时；不会自动重传原文。","已取消；已发往模型的内容无法撤回。");
    private final Activity a;private EditorialUI.Screen s;private TextView note,selectedLabel;private LinearLayout candidateBox,historyBox;
    private LocalDate day=LocalDate.now();private boolean includeSpeech=true,loading;private int generation;
    private List<CeLifelog.Row> speech=new ArrayList<>();private List<Map<String,Object>> archive=new ArrayList<>(),candidates=new ArrayList<>();private final Set<String> selected=new LinkedHashSet<>();
    private Instant start,end;private String zone,scope;private Runnable job;
    private EnhancedLifelogUI(Activity a){this.a=a;}
    static void show(Activity a){CeBridge.init(a);new EnhancedLifelogUI(a).open();}
    private static TnlStore store(Activity a){return new TnlStore(new File(a.getNoBackupFilesDir(),"turboio/enhanced-lifelog"));}
    private void open(){
        s=new EditorialUI.Screen(a,"增强智记");LinearLayout b=s.body;
        b.addView(EditorialUI.text(a,"选择本机内容",17,EditorialUI.INK));
        b.addView(EditorialUI.text(a,"按日期读取本机记录，通知默认不选中。不会开启录音、拉取云端历史或改写官方数据。官方详情未加载过时，本机可能没有正文；需先在官方全天智记打开原文。",13,EditorialUI.MUTED));
        TextView dayLabel=EditorialUI.text(a,"日期 · "+day,14,EditorialUI.INK);b.addView(dayLabel);
        EditorialUI.button(a,b,"日期",false,()->new DatePickerDialog(a,(v,y,m,d)->{day=LocalDate.of(y,m+1,d);dayLabel.setText("日期 · "+day);invalidate();},day.getYear(),day.getMonthValue()-1,day.getDayOfMonth()).show());
        EditorialUI.toggle(a,b,"包含本机智记原文",true,(v,on)->{includeSpeech=on;invalidate();});
        EditorialUI.button(a,b,"读取这一天",true,this::load);
        EditorialUI.button(a,b,"通知归档与保存开关",false,()->NotificationHistoryUI.show(a));
        note=EditorialUI.text(a,"请选择日期，点“读取这一天”。",14,EditorialUI.LIME);b.addView(note);
        b.addView(EditorialUI.text(a,"检查后再发送",17,EditorialUI.INK));
        b.addView(EditorialUI.text(a,"仅向“模型与对话”中你配置的服务发送，逐次预览授权；默认不自动运行。最多 64 段智记、64 条通知 / 32 KiB，未纳入片段会明确计数。",13,EditorialUI.MUTED));
        EditorialUI.button(a,b,"预览合并内容",true,this::preview);
        EditorialUI.button(a,b,"取消全部通知选择",false,()->{selected.clear();renderCandidates();});
        EditorialUI.button(a,b,"示例（合成内容，不读取真实记录）",false,this::demo);
        selectedLabel=EditorialUI.text(a,"",14,EditorialUI.INK);b.addView(selectedLabel);
        b.addView(EditorialUI.text(a,"通知按手机接收时间归入日期，不能证明用户已读或已行动。更新取最新内容；明显验证码和超长通知不纳入。过滤不完整，请自行取消不适合分享的内容。通知来自本机，不与雷鸟账号绑定。",13,EditorialUI.MUTED));
        candidateBox=EditorialUI.column(a);b.addView(candidateBox);
        b.addView(EditorialUI.text(a,"单独保存的总结",17,EditorialUI.INK));
        b.addView(EditorialUI.text(a,"结果是 AI 生成，可能有误。只保留本机最近 30 天 / 30 份 / 512 KiB，不存原始输入副本和密钥；存放在不参与系统备份的目录。清空总结不删除通知归档或官方智记。",13,EditorialUI.MUTED));
        historyBox=EditorialUI.column(a);b.addView(historyBox);
        EditorialUI.button(a,b,"清空增强智记结果",false,()->new AlertDialog.Builder(a).setTitle("清空增强智记？").setMessage("仅删除这台手机单独保存的增强总结，不能撤回已发给模型的内容。不删除官方日记或通知历史。")
            .setNegativeButton("取消",null).setPositiveButton("清空",(d,w)->READ.execute(()->{boolean ok;try{ok=store(a).clear();}catch(Throwable t){ok=false;}boolean r=ok;MAIN.post(()->{if(!r)EditorialUI.notice(a,"未能清空");renderHistory();});})).show());
        renderCandidates();renderHistory();
        // Leaving the screen cancels a running request (iOS cancels on disappear); late callbacks are ignored.
        s.dialog.setOnDismissListener(d->{generation++;Runnable j=job;job=null;if(j!=null)j.run();});
    }
    private boolean gone(){return a.isFinishing()||a.isDestroyed()||!s.dialog.isShowing();}
    private void invalidate(){generation++;loading=false;archive=new ArrayList<>();candidates=new ArrayList<>();speech=new ArrayList<>();selected.clear();scope=null;note.setText("内容已清除，请重新读取。");renderCandidates();}
    private void load(){
        if(loading)return;invalidate();loading=true;int token=generation;note.setText("仅读本机，不联网…");
        ZoneId z=ZoneId.systemDefault();Instant from=day.atStartOfDay(z).toInstant(),to=day.plusDays(1).atStartOfDay(z).toInstant();boolean withSpeech=includeSpeech;NotificationRuntime rt=NotificationTap.runtime(a);
        READ.execute(()->{try{String before=CeLifelog.scope(CeBridge.dirs()),error=null;List<Map<String,Object>> notes;List<CeLifelog.Row> rows=new ArrayList<>();
            try{notes=rt.store().search("",2000);}catch(Throwable t){notes=new ArrayList<>();error="通知归档暂不可读；请稍后重试。";}
            if(withSpeech)try{rows=CeLifelog.read(CeBridge.dirs(),z);}catch(IllegalArgumentException e){error=e.getMessage();}catch(Throwable t){error=CeHive.ERROR;}
            List<Map<String,Object>> cands=TnlCore.candidates(notes,from,to);String after=CeLifelog.scope(CeBridge.dirs());
            List<Map<String,Object>> n=notes;List<CeLifelog.Row> r=rows;String err=error;
            MAIN.post(()->{if(token!=generation||gone())return;loading=false;
                if(!before.equals(after)){note.setText("账号缓存变化，请重新读取。");return;}
                archive=n;speech=r;candidates=cands;start=from;end=to;zone=z.getId();scope=before;
                note.setText(err!=null&&!err.isEmpty()&&!"null".equals(err)?err:"已在本机读取，请勾选需要补充的通知。未上传任何内容。");renderCandidates();renderHistory();});
            }catch(Throwable t){MAIN.post(()->{if(token==generation)loading=false;});}});
    }
    private void renderCandidates(){
        candidateBox.removeAllViews();selectedLabel.setText("通知 · 已选 "+selected.size()+" / "+candidates.size());
        if(candidates.isEmpty()){candidateBox.addView(EditorialUI.text(a,"暂无可选通知\n先读取；没有通知时可先用“示例”验证总结流程。",13,EditorialUI.MUTED));return;}
        DateTimeFormatter f=DateTimeFormatter.ofPattern("HH:mm:ss");
        for(Map<String,Object> c:candidates){String id=(String)c.get("id"),t=(String)c.get("text");CheckBox box=new CheckBox(a);box.setTextColor(EditorialUI.INK);
            box.setText(c.get("app")+" · "+Instant.parse((String)c.get("at")).atZone(ZoneId.systemDefault()).format(f)+"\n"+(t.length()>120?t.substring(0,120)+"…":t));box.setChecked(selected.contains(id));
            box.setOnCheckedChangeListener((v,on)->{if(!on){selected.remove(id);}else if(selected.size()>=64){v.setChecked(false);EditorialUI.notice(a,"一次最多选择 64 条通知。");return;}else selected.add(id);selectedLabel.setText("通知 · 已选 "+selected.size()+" / "+candidates.size());});
            candidateBox.addView(box);}
    }
    private void renderHistory(){
        READ.execute(()->{List<Map<String,Object>> rows;try{rows=store(a).read(System.currentTimeMillis()/1000.0);}catch(Throwable t){rows=null;}List<Map<String,Object>> r=rows;
            MAIN.post(()->{if(gone())return;historyBox.removeAllViews();if(r==null){historyBox.addView(EditorialUI.text(a,"增强智记本机文件不可用；未覆盖既有记录。",13,EditorialUI.MUTED));return;}
                if(r.isEmpty()){historyBox.addView(EditorialUI.text(a,"暂无保存的总结",13,EditorialUI.MUTED));return;}
                for(Map<String,Object> h:r){String when=Instant.ofEpochMilli((long)(((Number)h.get("createdAt")).doubleValue()*1000)).atZone(ZoneId.systemDefault()).format(DateTimeFormatter.ofPattern("MM-dd HH:mm"));
                    TextView row=EditorialUI.text(a,"智记 "+h.get("speechCount")+" 段 · 通知 "+h.get("notificationCount")+" 条\n"+when+" · "+h.get("model"),14,EditorialUI.INK);row.setPadding(0,10,0,10);
                    row.setOnClickListener(v->text("增强智记 · 历史",(String)h.get("text")));historyBox.addView(row);}});});
    }
    private void text(String title,String body){ScrollView sv=new ScrollView(a);TextView t=new TextView(a);t.setText(body);t.setTextIsSelectable(true);t.setPadding(40,20,40,20);sv.addView(t);new AlertDialog.Builder(a).setTitle(title).setView(sv).setPositiveButton("关闭",null).show();}
    private void preview(){
        if(loading)return;if(scope==null){EditorialUI.notice(a,"请选择日期，点“读取这一天”。");return;}
        if(!scope.equals(CeLifelog.scope(CeBridge.dirs()))){invalidate();EditorialUI.notice(a,"账号缓存变化，请重新读取和选择。");return;}
        Map<String,Object> ctx;try{ctx=TnlCore.context(speech,archive,new HashSet<>(selected),start,end,zone);}catch(IllegalArgumentException e){EditorialUI.notice(a,e.getMessage());return;}
        review(ctx,false);
    }
    private void demo(){
        ZoneId z=ZoneId.systemDefault();Instant from=LocalDate.now().atStartOfDay(z).toInstant(),to=from.plus(Duration.ofDays(1));
        List<CeLifelog.Row> rows=Collections.singletonList(new CeLifelog.Row("这是一条合成智记：今天计划下午三点讨论界面设计，尚未确认完成。",from.plusSeconds(9*3600).toString()));
        Map<String,Object> n=NotificationArchive.record("synthetic-1","test.synthetic","合成日程通知","讨论时间调整","","界面讨论改为16:00。请确认是否能参加。",0,0,"synthetic",from.getEpochSecond()+10*3600);
        List<Map<String,Object>> notes=Collections.singletonList(n);Set<String> ids=new HashSet<>();for(Map<String,Object> c:TnlCore.candidates(notes,from,to))ids.add((String)c.get("id"));
        try{review(TnlCore.context(rows,notes,ids,from,to,z.getId()),true);}catch(IllegalArgumentException e){EditorialUI.notice(a,e.getMessage());}
    }
    /** Full preview, then a separate approval naming the destination and model; the scope and config must not change. */
    private void review(Map<String,Object> ctx,boolean synthetic){
        String content=TnlCore.preview(ctx);ScrollView sv=new ScrollView(a);TextView t=new TextView(a);t.setText(content);t.setTextIsSelectable(true);t.setPadding(40,20,40,20);sv.addView(t);
        new AlertDialog.Builder(a).setTitle(synthetic?"合成示例 · 无私人内容":"发送前完整预览").setView(sv).setNegativeButton("返回",null).setPositiveButton("生成",(d,w)->approve(ctx,synthetic)).show();
    }
    private void approve(Map<String,Object> ctx,boolean synthetic){
        CeBridge.Config c=CeBridge.config();byte[] body;
        try{if(c.error!=null)throw new IllegalArgumentException(c.error);Map<String,Object> payload=TnlCore.body(ctx,c.model);
            if(c.disableThinking){Map<String,Object> th=new LinkedHashMap<>();th.put("type","disabled");payload.put("thinking",th);}
            body=BoundedJson.canonical(payload);if(body.length>65536)throw new IllegalArgumentException("请求无效或超过 64 KiB。");}
        catch(IllegalArgumentException e){EditorialUI.notice(a,"无法生成："+e.getMessage());return;}
        String host;try{host=new URI(c.endpoint).getHost();}catch(Exception e){host="";}String scopeNow=scope,provider=host;byte[] request=body;
        String message="将发送当前预览中的"+(synthetic?"合成测试":"")+"智记 "+ctx.get("speechCount")+" 段、通知 "+ctx.get("notificationCount")+" 条到：\n"+c.endpoint+"\n模型："+c.model+"\n\n"
            +(synthetic?"示例完全虚构，不读取或上传真实记录。":"包含原文，可能涉及你及他人的隐私。请确认有权发送并已阅读全部预览。")+"\n不会修改官方日记。结果可能有误，请核对来源；敏感过滤不保证完整。";
        new AlertDialog.Builder(a).setTitle("确认本次总结").setMessage(message).setNegativeButton("取消",null).setPositiveButton("同意并生成一次",(d,w)->{
            CeBridge.Config now=CeBridge.config();
            if(!now.endpoint.equals(c.endpoint)||!now.model.equals(c.model)||!now.key.equals(c.key)||(!synthetic&&(scopeNow==null||!scopeNow.equals(CeLifelog.scope(CeBridge.dirs()))))){EditorialUI.notice(a,"输入、账号或模型配置已变化，本次未发送。");return;}
            ProgressDialog wait=new ProgressDialog(a);wait.setMessage("正在生成…");wait.setCancelable(false);
            Runnable cancel=ModelCall.post(c.endpoint,c.key,request,131072,TEXTS,MAIN::post,(reply,error)->{job=null;try{wait.dismiss();}catch(Throwable ignored){}if(gone())return;
                if(error!=null){EditorialUI.notice(a,"未保存总结："+error);return;}
                List<Map<String,Object>> items;try{items=TnlCore.validate(reply,ctx);}catch(IllegalArgumentException e){EditorialUI.notice(a,"未保存总结："+e.getMessage());return;}
                String result=TnlCore.render(items,ctx);
                if(synthetic){text("示例总结","合成示例结果 · 未写入真实历史\n\n"+result);return;}
                READ.execute(()->{boolean saved;try{saved=store(a).save(result,provider,c.model,ctx,System.currentTimeMillis()/1000.0);}catch(Throwable x){saved=false;}boolean ok=saved;
                    MAIN.post(()->{if(gone())return;text("增强智记",(ok?"已单独保存到本机 · 官方日记未改动":"保存失败，结果仅在当前页；请勿离开")+"\n\n"+result);renderHistory();});});});
            job=cancel;wait.setButton(DialogInterface.BUTTON_NEGATIVE,"取消",(x,y)->cancel.run());wait.show();
        }).show();
    }
}
