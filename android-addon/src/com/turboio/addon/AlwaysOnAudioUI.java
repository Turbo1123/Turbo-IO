package com.turboio.addon;
import android.app.*;
import android.os.*;
import android.widget.*;
import java.io.File;
import java.text.SimpleDateFormat;
import java.util.*;
import java.util.concurrent.*;

/** 设置 → 全天智记音频 (iOS AlwaysOnAudioUI): explicitly turn on the official always-on audio dump (no event text),
 * check the official status, list saved session audio and share stable, validated copies. Never starts always-on. */
final class AlwaysOnAudioUI {
    private static final ExecutorService IO=Executors.newSingleThreadExecutor();
    private static final Handler MAIN=new Handler(Looper.getMainLooper());
    private final Activity a;private EditorialUI.Screen s;private TextView state,saving;private LinearLayout list;private Map<?,?> status;private boolean busy;
    private AlwaysOnAudioUI(Activity a){this.a=a;}
    static void show(Activity a){new AlwaysOnAudioUI(a).open();}
    private boolean gone(){return a.isFinishing()||a.isDestroyed()||!s.dialog.isShowing();}
    private void open(){
        s=new EditorialUI.Screen(a,"全天智记音频");LinearLayout b=s.body;
        b.addView(EditorialUI.text(a,"声音档案",17,EditorialUI.INK));b.addView(EditorialUI.text(a,"明确开启后才保存，分享前先停止录制。",14,EditorialUI.MUTED));
        b.addView(EditorialUI.text(a,"官方本地音频保存",17,EditorialUI.INK));
        saving=EditorialUI.text(a,"",14,EditorialUI.INK);b.addView(saving);
        EditorialUI.button(a,b,"开启：保存之后的智记音频",false,this::enable);
        EditorialUI.button(a,b,"关闭音频保存",false,()->set(false));
        state=EditorialUI.text(a,"",13,EditorialUI.LIME);b.addView(state);
        b.addView(EditorialUI.text(a,"只保存开启之后官方全天智记收到的音频，不启动麦克风/智记，不恢复历史未保存音频。仅本机，关闭附加事件正文日志。持续开启会占用存储，用完请关闭；不会自动删除文件。App重开后需重新核对开关。",13,EditorialUI.MUTED));
        b.addView(EditorialUI.text(a,"已保存音频副本",17,EditorialUI.INK));
        EditorialUI.button(a,b,"刷新",false,this::refresh);
        list=EditorialUI.column(a);b.addView(list);
        b.addView(EditorialUI.text(a,"先在官方App停止本次全天智记，再刷新并选文件分享。仅列出官方智记调试sessions目录，不含mock输入或字幕音频。实时/缓存可能是不同分段，不自动拼接、不承诺无缺包。PCM是原始格式，不能直接当WAV播放。",13,EditorialUI.MUTED));
        refresh();
    }
    private void renderStatus(){
        boolean on=status!=null&&Boolean.TRUE.equals(status.get("dumpEnabled"));
        saving.setText("保存之后的智记音频："+(status==null?"当前官方版本或音频接口尚未就绪":on?"已开启":"未开启")+"\n不改变官方ASR/模型，不自动上传");
        Object rt=status==null?null:status.get("realtimePackets"),ca=status==null?null:status.get("cachedPackets");
        state.setText((status!=null&&Boolean.TRUE.equals(status.get("alwaysOnRunning"))?"全天智记正在运行，请先停止再分享":"当前未运行全天智记")+"\n实时包 "+(rt==null?0:rt)+" / 缓存包 "+(ca==null?0:ca)+"；"+(status!=null?"读取官方状态":"接口不可用"));
    }
    private void refresh(){
        if(busy)return;busy=true;status=AlwaysOnHost.status();renderStatus();list.removeAllViews();list.addView(EditorialUI.text(a,"正在读取…",13,EditorialUI.MUTED));File base=AlwaysOnHost.base(a);
        IO.execute(()->{List<AlwaysOnAudio.Entry> rows;try{rows=AlwaysOnAudio.list(base);}catch(Throwable t){rows=new ArrayList<>();}List<AlwaysOnAudio.Entry> r=rows;
            MAIN.post(()->{busy=false;if(gone())return;list.removeAllViews();
                if(r.isEmpty()){list.addView(EditorialUI.text(a,"暂无已保存音频\n开启保存后使用一次官方全天智记，停止后刷新。",13,EditorialUI.MUTED));return;}
                SimpleDateFormat f=new SimpleDateFormat("MM-dd HH:mm:ss",Locale.ROOT);
                for(AlwaysOnAudio.Entry e:r){String ext=e.name.substring(e.name.lastIndexOf('.')+1);TextView row=EditorialUI.text(a,e.kind+" · "+f.format(new Date(e.date))+"\n"+ext+" · "+(e.bytes/1024)+" KB",14,EditorialUI.INK);row.setPadding(0,10,0,10);row.setOnClickListener(v->share(e));list.addView(row);}});});
    }
    private void enable(){
        if(status==null){EditorialUI.notice(a,"当前官方版本或音频接口尚未就绪");return;}
        new AlertDialog.Builder(a).setTitle("保存之后的智记音频？").setMessage("之后使用官方全天智记时，额外在本机保存真实谈话音频，请确保已获相关人员同意。可能占用较大空间，不上传、不自动删除，不恢复过去的录音。此操作本身不启动智记。")
            .setNegativeButton("取消",null).setPositiveButton("开启本机音频保存",(d,w)->set(true)).show();
    }
    private void set(boolean on){
        boolean ok=AlwaysOnHost.setSaving(on);status=AlwaysOnHost.status();renderStatus();
        if(on)EditorialUI.notice(a,ok?"音频保存已开启。请用官方界面开启一次短智记，停止后回这里刷新。之前未保存的历史音频不会出现。":"设置未完全通过回读验证，请查看实际开关；可手动关闭。未启动智记。");
        else if(!ok)EditorialUI.notice(a,"关闭未通过回读验证，请核对开关状态；没有删除音频。停止官方全天智记可停止新音频输入。");
    }
    private void share(AlwaysOnAudio.Entry e){
        status=AlwaysOnHost.status();renderStatus();
        if(status!=null&&Boolean.TRUE.equals(status.get("alwaysOnRunning"))){EditorialUI.notice(a,"请先停止官方全天智记，等音频落盘后刷新再分享。");return;}
        if(status!=null&&Boolean.TRUE.equals(status.get("dumpEnabled"))){EditorialUI.notice(a,"请先关闭上方音频保存开关，让官方写完文件尾，再刷新分享。不会删除原件。");return;}
        // The validated copy is written once, directly under the share provider root; the previous export is removed first.
        File base=AlwaysOnHost.base(a),exports=new File(new File(a.getCacheDir(),"share_plus"),"always-on");
        IO.execute(()->{try{NotificationTap.delete(new File(a.getNoBackupFilesDir(),"turboio/always-on-exports"));}catch(Throwable ignored){}File copy=null;String error=null;try{NotificationTap.delete(exports);copy=AlwaysOnAudio.copy(base,e.file,exports);}catch(IllegalArgumentException x){error=x.getMessage();}catch(Throwable t){error=AlwaysOnAudio.COPY_ERROR;}
            File c=copy;String err=error;MAIN.post(()->{if(gone())return;if(err!=null)EditorialUI.notice(a,err);else RecordingExports.shareInPlace(a,c,c.getName().endsWith(".pcm")?"application/octet-stream":"audio/ogg");});});
    }
}
