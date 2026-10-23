package com.turboio.addon;
import android.app.*;
import android.os.*;
import android.widget.*;
import java.util.*;
import java.util.concurrent.*;
import org.json.*;

/** 设置 → 知识库 (iOS KnowledgeUI): executor Agent, connection and sources status, a manual read-only query polled
 * every 3 s for up to 80 s, the last result and its cited sources. The token is never shown. */
final class KnowledgeUI {
    private static final ExecutorService NET=Executors.newSingleThreadExecutor();
    private static final Handler MAIN=new Handler(Looper.getMainLooper());
    private final Activity a;private final ToolClient client;private EditorialUI.Screen s;private TextView status,agentLabel,jobText;private LinearLayout sourceBox,citeBox;private int poll;
    private KnowledgeUI(Activity a){this.a=a;client=new ToolClient(a.getApplicationContext());}
    static void show(Activity a){new KnowledgeUI(a).open();}
    private boolean gone(){return a.isFinishing()||a.isDestroyed()||!s.dialog.isShowing();}
    private static Map<String,Object> map(JSONObject o){Map<String,Object> m=new LinkedHashMap<>();if(o==null)return m;for(Iterator<String> i=o.keys();i.hasNext();){String k=i.next();Object v=o.opt(k);m.put(k,v==JSONObject.NULL?null:v);}return m;}
    private static String failure(Throwable e){
        if(e instanceof IllegalStateException&&e.getMessage()!=null)return e.getMessage();
        String m=String.valueOf(e.getMessage());int code=m.matches("HTTP \\d{3}")?Integer.parseInt(m.substring(5)):0;
        return e instanceof IllegalArgumentException?"请先配置知识库连接。":"知识库连接失败（HTTP "+code+"）。请检查 Mac 服务、网络与令牌。";
    }
    private void open(){
        s=new EditorialUI.Screen(a,"知识库");LinearLayout b=s.body;
        b.addView(EditorialUI.text(a,"连接你的知识",17,EditorialUI.INK));b.addView(EditorialUI.text(a,"从眼镜提问，让 Agent 查证来源。",14,EditorialUI.MUTED));
        b.addView(EditorialUI.text(a,"连接与权限",17,EditorialUI.INK));
        agentLabel=EditorialUI.text(a,"",14,EditorialUI.INK);b.addView(agentLabel);
        EditorialUI.button(a,b,"执行 Agent",false,()->{String[] names=KnowledgeView.AGENTS.toArray(new String[0]);new AlertDialog.Builder(a).setTitle("选择 Agent").setSingleChoiceItems(names,KnowledgeView.AGENTS.indexOf(client.agent()),(d,w)->{client.agent(names[w]);d.dismiss();render();}).show();});
        EditorialUI.button(a,b,"连接配置（知识库工具开关、地址与令牌）",false,()->{s.dialog.dismiss();TurboAddon.showTools();});
        EditorialUI.button(a,b,"刷新连接状态",false,this::refreshSources);
        status=EditorialUI.text(a,"",13,EditorialUI.LIME);b.addView(status);
        b.addView(EditorialUI.text(a,"仅 Codex 已接执行器；其他 Agent 可选择但尚未连接。令牌存本机加密存储。",13,EditorialUI.MUTED));
        b.addView(EditorialUI.text(a,"数据来源",17,EditorialUI.INK));sourceBox=EditorialUI.column(a);b.addView(sourceBox);
        b.addView(EditorialUI.text(a,"只查询 Mac 已归档数据，不刷新微信、不读实时数据库。命中片段经 Codex 处理，答案会交给当前自有模型。",13,EditorialUI.MUTED));
        b.addView(EditorialUI.text(a,"查询与结果",17,EditorialUI.INK));
        EditorialUI.button(a,b,"发起查询",true,this::ask);EditorialUI.button(a,b,"刷新最近结果",false,()->{String id=client.lastJob();if(id.isEmpty()){EditorialUI.notice(a,"还没有知识库查询。");return;}track(id,0,true);});
        jobText=EditorialUI.text(a,KnowledgeView.job(null),14,EditorialUI.INK);b.addView(jobText);
        b.addView(EditorialUI.text(a,"长查询保留在 Mac；刷新结果可继续查看。退出后不保证主动通知。",13,EditorialUI.MUTED));
        b.addView(EditorialUI.text(a,"本次引用来源",17,EditorialUI.INK));citeBox=EditorialUI.column(a);b.addView(citeBox);
        s.dialog.setOnDismissListener(d->poll++);
        render();refreshSources();showJob(null);
    }
    private void render(){
        boolean ready;try{ready=client.knowledgeReady();}catch(Exception e){ready=false;}
        agentLabel.setText("执行 Agent："+client.agent()+"\n"+("Codex".equals(client.agent())?"Codex App Server · Mac 执行":"未连接执行器")+"\n知识库工具："+(ready?"已开启 · 允许语音调用只读知识库":"未开启或未配置"));
    }
    private void refreshSources(){
        status.setText("连接中…");
        NET.execute(()->{JSONObject j=null;String error=null;try{j=client.sources();}catch(Throwable e){error=failure(e);}JSONObject r=j;String err=error;
            MAIN.post(()->{if(gone())return;status.setText(err!=null?err:"Mac 服务已连接 · Codex 按查询启动");sourceBox.removeAllViews();
                JSONArray list=r==null?null:r.optJSONArray("sources");if(list==null||list.length()==0){sourceBox.addView(EditorialUI.text(a,"暂无来源信息",13,EditorialUI.MUTED));return;}
                for(int i=0;i<list.length();i++){JSONObject src=list.optJSONObject(i);if(src==null)continue;sourceBox.addView(EditorialUI.text(a,src.optString("name","")+"\n"+KnowledgeView.source(map(src)),14,EditorialUI.INK));}});});
    }
    private void ask(){
        EditText q=new EditText(a);q.setHint("输入想查询的问题");q.setSingleLine();
        new AlertDialog.Builder(a).setTitle("让 Codex 查知识库").setMessage("仅检索已归档资料，不执行写入。").setView(q).setNegativeButton("取消",null).setPositiveButton("查询",(d,w)->{
            String text=q.getText().toString();if(!KnowledgeView.validQuery(text)){EditorialUI.notice(a,"请输入2至200字。");return;}
            int mine=++poll;jobText.setText("查询中…");long started=SystemClock.elapsedRealtime();
            NET.execute(()->{String id=null,error=null;JSONObject first=null;try{first=client.query(text);id=first.optString("id");}catch(Throwable e){error=failure(e);}
                String jid=id,err=error;JSONObject f=first;MAIN.post(()->{if(gone()||mine!=poll)return;if(err!=null){EditorialUI.notice(a,err);showJob(null);return;}showJob(f);track(jid,started,false);});});
        }).show();
    }
    /** Poll /jobs/<id> every 3 s until a final state or 80 s after the query; a refresh polls once. */
    private void track(String id,long started,boolean once){
        int mine=once?++poll:poll;
        NET.execute(()->{JSONObject j=null;String error=null;try{j=client.job(id);}catch(Throwable e){error=failure(e);}JSONObject r=j;String err=error;
            MAIN.post(()->{if(gone()||mine!=poll)return;if(err!=null){EditorialUI.notice(a,err);return;}showJob(r);
                if(!once&&!KnowledgeView.terminal(r.optString("status"),started,SystemClock.elapsedRealtime()))MAIN.postDelayed(()->{if(!gone()&&mine==poll)track(id,started,false);},3000);});});
    }
    private void showJob(JSONObject j){
        jobText.setText(KnowledgeView.job(j==null?null:map(j)));citeBox.removeAllViews();JSONArray r=j==null?null:j.optJSONArray("results");
        if(r==null||r.length()==0){citeBox.addView(EditorialUI.text(a,"暂无引用\n完成查询后显示实际来源。",13,EditorialUI.MUTED));return;}
        for(int i=0;i<r.length();i++){JSONObject e=r.optJSONObject(i);if(e!=null)citeBox.addView(EditorialUI.text(a,e.optString("title","")+"\n"+KnowledgeView.citation(map(e)),14,EditorialUI.INK));}
    }
}
