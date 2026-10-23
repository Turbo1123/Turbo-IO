package com.turboio.addon;
import android.app.Activity;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.*;
import android.widget.*;
import java.io.*;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.*;
import org.json.*;

/** Settings → 诊断: adapter status, TDG1 glasses runtime status (TVP2), and one-tap model/search tests.
 * Nothing here runs by itself; every request is one explicit tap. */
final class DiagnosticsUI {
    private static final Handler MAIN=new Handler(Looper.getMainLooper());
    static void show(Activity a){
        EditorialUI.Screen s=new EditorialUI.Screen(a,"诊断与测试");LinearLayout b=s.body;
        b.addView(EditorialUI.text(a,TurboAddon.status()+"\n"+NativeTransfer.diagnostic(),13,EditorialUI.MUTED));
        // TDG1 glasses runtime status
        b.addView(EditorialUI.text(a,"眼镜运行状态 · TDG1",17,EditorialUI.INK));
        b.addView(EditorialUI.text(a,"需 TVP2。开启后自动记录 10 分钟，可返回音乐/导航正常使用。每 5 秒本机存盘；不保存歌词、对话或密钥，报告不含设备标识。不自动重连或续期。",13,EditorialUI.MUTED));
        DiagnosticsRun run=DiagnosticsRun.current(new File(a.getFilesDir(),"turboio/diagnostics"));
        TextView state=EditorialUI.text(a,"",14,EditorialUI.LIME);b.addView(state);
        TextView metrics=EditorialUI.text(a,"",13,EditorialUI.INK);b.addView(metrics);
        EditorialUI.button(a,b,"开始记录 10 分钟",true,()->{if(!run.start())EditorialUI.notice(a,"未开始："+run.status()+"\n请先连接眼镜、结束其他传输任务并退出升级保护。");});
        EditorialUI.button(a,b,"结束记录",false,()->run.stop("user_stop"));
        EditorialUI.button(a,b,"分享报告（Markdown）",false,()->share(a,run.reportMarkdown(),"text/markdown","Turbo IO 眼镜诊断.md"));
        EditorialUI.button(a,b,"分享报告（JSON）",false,()->share(a,new String(run.reportJSON(),StandardCharsets.UTF_8),"application/json","Turbo IO 眼镜诊断.json"));
        Runnable tick=new Runnable(){public void run(){if(!s.dialog.isShowing())return;run.poll();state.setText(run.status()+(run.active()?" · 剩余 "+(int)run.remaining()+" 秒":"")+" · 采样 "+run.count()+"\n"+run.saveStatus());metrics.setText(table(run.latest()));MAIN.postDelayed(this,1000);}};
        MAIN.post(tick);
        // One-tap tests
        b.addView(EditorialUI.text(a,"测试",17,EditorialUI.INK));
        TextView result=EditorialUI.text(a,"只在点击时发送一次请求。",13,EditorialUI.MUTED);b.addView(result);
        EditorialUI.button(a,b,"测试模型接口",false,()->{result.setText("正在请求模型接口…");new Thread(()->{String r=modelTest(a);MAIN.post(()->result.setText(r));}).start();});
        EditorialUI.button(a,b,"测试联网搜索",false,()->{result.setText("正在请求联网搜索…");new Thread(()->{String r=searchTest(a);MAIN.post(()->result.setText(r));}).start();});
        s.dialog.setOnDismissListener(d->MAIN.removeCallbacks(tick));
    }
    private static String cut(String v,int n){return v.length()<=n?v:v.substring(0,n)+"…";}
    private static String table(Map<String,Object> latest){
        if(latest==null)return "尚无采样";Map<?,?> m=(Map<?,?>)latest.get("metrics");StringBuilder t=new StringBuilder("序号 ").append(latest.get("sequence")).append(" · 采样耗时 ").append(latest.get("probe_ms")).append(" ms\n");
        for(String name:TdgCodec.NAMES){Object v=m.get(name);t.append(DiagnosticsRun.label(name)).append("：").append(v==null?"未测":v).append('\n');}
        return t.toString();
    }
    private static void share(Activity a,String text,String mime,String subject){
        try{a.startActivity(Intent.createChooser(new Intent(Intent.ACTION_SEND).setType(mime).putExtra(Intent.EXTRA_TEXT,text).putExtra(Intent.EXTRA_SUBJECT,subject),"分享诊断报告"));}catch(RuntimeException e){EditorialUI.notice(a,"无法打开分享面板");}
    }
    /** One short completion against the configured endpoint; same settings and endpoint policy as chat. */
    private static String modelTest(Activity a){
        SharedPreferences p=a.getSharedPreferences("turboio_settings",0);String endpoint=p.getString("endpoint","https://api.deepseek.com/chat/completions"),model=p.getString("model","deepseek-flash"),key;
        try{key=SecretStore.get(a);}catch(Exception e){return "未测试：无法读取本机保存的 Key（"+e.getClass().getSimpleName()+"）。";}
        if(!ChatPolicy.endpoint(endpoint)||key.isEmpty())return "未测试：请先在模型与对话中配置 HTTPS 接口、模型和 Key。";
        long started=SystemClock.elapsedRealtime();HttpURLConnection c=null;
        try{JSONObject body=new JSONObject().put("model",model).put("stream",false).put("max_tokens",32).put("messages",new JSONArray().put(new JSONObject().put("role","user").put("content","请只回复：连接正常")));
            c=(HttpURLConnection)new URL(endpoint).openConnection();c.setInstanceFollowRedirects(false);c.setConnectTimeout(15000);c.setReadTimeout(30000);c.setRequestMethod("POST");c.setRequestProperty("Authorization","Bearer "+key);c.setRequestProperty("Content-Type","application/json");c.setDoOutput(true);
            byte[] data=body.toString().getBytes(StandardCharsets.UTF_8);c.setFixedLengthStreamingMode(data.length);try(OutputStream out=c.getOutputStream()){out.write(data);}
            int code=c.getResponseCode();long ms=SystemClock.elapsedRealtime()-started;if(code!=200)return "模型接口返回 HTTP "+code+" · "+ms+" ms（模型 "+model+"）";
            String text;try(InputStream in=c.getInputStream();ByteArrayOutputStream o=new ByteArrayOutputStream()){byte[] buf=new byte[4096];int n;while((n=in.read(buf))!=-1){if(o.size()+n>65536)throw new IOException("回复过大");o.write(buf,0,n);}text=o.toString("UTF-8");}
            String reply=new JSONObject(text).getJSONArray("choices").getJSONObject(0).getJSONObject("message").optString("content","");
            return "模型接口正常 · "+ms+" ms（模型 "+model+"）\n回复："+cut(reply.trim(),80);
        }catch(Exception e){return "模型接口失败："+e.getClass().getSimpleName()+(e.getMessage()==null?"":" "+cut(e.getMessage(),80));}
        finally{if(c!=null)c.disconnect();}
    }
    /** One TinyFish query through the same tool path chat uses (respects its enable switch and key checks). */
    private static String searchTest(Activity a){
        long started=SystemClock.elapsedRealtime();
        try{JSONObject r=new ToolClient(a).call("web_search",new JSONObject().put("query","Turbo IO 联网搜索测试"),SecretStore.get(a));long ms=SystemClock.elapsedRealtime()-started;
            JSONArray list=r.optJSONArray("results");return "联网搜索正常 · "+ms+" ms · 结果 "+(list==null?0:list.length())+" 条";
        }catch(IllegalArgumentException e){return "未测试：请先在模型与对话中开启联网搜索并配置搜索 Key。";}
        catch(Exception e){return "联网搜索失败："+e.getClass().getSimpleName()+(e.getMessage()==null?"":" "+cut(e.getMessage(),80));}
    }
}
