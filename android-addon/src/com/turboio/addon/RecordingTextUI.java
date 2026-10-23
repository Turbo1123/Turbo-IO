package com.turboio.addon;
import android.app.*;
import android.content.DialogInterface;
import android.os.*;
import android.text.InputType;
import android.widget.*;
import java.io.*;
import java.net.URI;
import java.nio.charset.*;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;

/** 录音与智记 · 转写文字 → 自有模型整理 (iOS RecordingTextUI) and 全天智记导出. Text is sent only after one confirmation,
 * chunk by chunk; a cancelled or failed run never produces a success file. Results stay in the no-backup dir and
 * leave the phone only through the system share sheet. */
final class RecordingTextUI {
    private static final ExecutorService IO=Executors.newSingleThreadExecutor();
    private static final Handler MAIN=new Handler(Looper.getMainLooper());
    private static final ModelCall.Texts TEXTS=new ModelCall.Texts("服务拒绝请求或返回无效内容；未保存错误正文；原转写未改。","模型响应超过大小限制。","连接失败或超时，本次整理未完成。原转写保留，可手动重试。","本次已取消，原录音、转写及之前已保存的整理结果不变。");
    private final Activity a;private EditText editor;private TextView info;private Runnable job;private int run;private File result;
    private RecordingTextUI(Activity a){this.a=a;}
    static void show(Activity a){CeBridge.init(a);new RecordingTextUI(a).open();}
    private void open(){
        EditorialUI.Screen s=new EditorialUI.Screen(a,"文字整理");LinearLayout b=s.body;
        info=EditorialUI.text(a,"保留官方 ASR。导入或粘贴完整转写，确认后仅上传文字；不覆盖官方内容。",14,EditorialUI.LIME);b.addView(info);
        b.addView(EditorialUI.text(a,"完整转写文字",15,EditorialUI.INK));
        editor=new EditText(a);editor.setMinLines(8);editor.setGravity(android.view.Gravity.TOP);editor.setInputType(InputType.TYPE_CLASS_TEXT|InputType.TYPE_TEXT_FLAG_MULTI_LINE);editor.setTextColor(EditorialUI.INK);editor.setHint("粘贴完整转写，最多 30 万字符");editor.setHintTextColor(EditorialUI.MUTED);b.addView(editor);
        EditorialUI.button(a,b,"导入文本",false,this::importText);
        EditorialUI.button(a,b,"用当前自有模型整理",true,this::confirm);
        EditorialUI.button(a,b,"取消本次整理",false,this::cancel);
        EditorialUI.button(a,b,"分享整理结果 Markdown",false,()->{if(result==null){EditorialUI.notice(a,"暂无本次完整整理结果。取消、超时或截断不会生成成功文件。");return;}RecordingExports.share(a,result,"text/markdown");});
        s.dialog.setOnDismissListener(d->cancel());
    }
    private void importText(){
        if(job!=null)return;
        DocumentPicker.pick(a,2*1024*1024,bytes->{String text=null;
            if(bytes!=null)try{text=StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT).decode(java.nio.ByteBuffer.wrap(bytes)).toString();}catch(CharacterCodingException e){text=null;}
            if(text==null||text.trim().isEmpty()||text.length()>300000){EditorialUI.notice(a,"需要非空 UTF-8 TXT/MD，最多 30 万字符 / 2 MB；不会悄悄截断全文。");return;}
            editor.setText(text);info.setText("已导入本机文本，尚未上传。请核对是否为完整转写。");});
    }
    private void cancel(){if(job==null)return;Runnable j=job;job=null;run++;j.run();editor.setEnabled(true);info.setText("本次已取消，原录音、转写及之前已保存的整理结果不变。");}
    private void confirm(){
        if(job!=null)return;String text=editor.getText().toString();List<String> chunks=RecordingText.chunks(text);
        if(chunks==null){EditorialUI.notice(a,"先导入或粘贴完整转写，最多 30 万字符。不自动读取剪贴板或把屏幕几段当作全文。");return;}
        CeBridge.Config c=CeBridge.config();if(c.error!=null){EditorialUI.notice(a,"请先在研究菜单配置有效的自有模型接口。");return;}
        String host;try{host=new URI(c.endpoint).getHost();}catch(Exception e){host=c.endpoint;}
        new AlertDialog.Builder(a).setTitle("发送转写文字？").setMessage("服务："+host+"\n模型："+c.model+"\n"+text.length()+" 字符，"+chunks.size()+" 段顺序处理，可能产生费用。仅发这份文字，不发音频、聊天历史或官方凭据。原文保留，生成独立 Markdown。")
            .setNegativeButton("取消",null).setPositiveButton("确认整理",(d,w)->{CeBridge.Config now=CeBridge.config();
                if(now.error!=null||!now.endpoint.equals(c.endpoint)||!now.model.equals(c.model)||!now.key.equals(c.key)){EditorialUI.notice(a,"当前服务没有可用的自有 Key，未发送文字。");return;}
                result=null;editor.setEnabled(false);int mine=++run;next(mine,c,chunks,new ArrayList<>(),text);}).show();
    }
    private void next(int mine,CeBridge.Config c,List<String> chunks,List<String> answers,String input){
        if(mine!=run)return;
        if(answers.size()==chunks.size()){job=null;editor.setEnabled(true);String md=RecordingText.markdown(c.model,answers,input);
            IO.execute(()->{File f=null;try{File dir=new File(a.getNoBackupFilesDir(),"turboio/recording-text");if(!dir.isDirectory()&&!dir.mkdirs())throw new IOException();f=new File(dir,"录音整理.md");try(FileOutputStream o=new FileOutputStream(f)){o.write(md.getBytes(StandardCharsets.UTF_8));o.getFD().sync();}}catch(Throwable t){f=null;}
                File saved=f;MAIN.post(()->{if(a.isDestroyed())return;result=saved;info.setText(saved!=null?"全部分段已整理，已另存本机 Markdown（含输入原文）。点击分享可发送到其他应用。":"模型整理完成，但本机保存失败。内容保留在下方，请复制保存。");if(saved==null)editor.setText(md);});});
            return;}
        int index=answers.size();info.setText("正在整理第 "+(index+1)+" / "+chunks.size()+" 段… 可取消；离开此页会停止。");
        Map<String,Object> payload=RecordingText.payload(c.model,chunks.get(index),c.disableThinking);
        if(payload==null){job=null;editor.setEnabled(true);info.setText("文字分段或模型配置无效，未继续发送。");return;}
        job=ModelCall.post(c.endpoint,c.key,BoundedJson.canonical(payload),262144,TEXTS,MAIN::post,(reply,error)->{
            if(mine!=run)return;
            if(error!=null){job=null;editor.setEnabled(true);info.setText(error);return;}
            Object json;try{json=BoundedJson.readLarge(reply,262144,20000);}catch(RuntimeException e){json=null;}
            String answer=RecordingText.answer(json);
            if(answer==null){job=null;editor.setEnabled(true);info.setText("模型没有完整结束、返回空内容或非文字结果；未把半截摘要保存为成功。");return;}
            answers.add(answer);next(mine,c,chunks,answers,input);});
    }
    /** 全天智记导出: one day of the official cached transcript as Markdown, shared via the system sheet only. */
    static void exportLifelog(Activity a){
        CeBridge.init(a);LocalDate today=LocalDate.now();
        new DatePickerDialog(a,(v,y,m,d)->{LocalDate day=LocalDate.of(y,m+1,d);ZoneId z=ZoneId.systemDefault();
            IO.execute(()->{String error=null;File file=null;
                try{List<CeLifelog.Row> rows=new ArrayList<>();for(CeLifelog.Row r:CeLifelog.read(CeBridge.dirs(),z)){Instant at;try{at=Instant.parse(r.at);}catch(RuntimeException e){continue;}if(at.atZone(z).toLocalDate().equals(day))rows.add(r);}
                    if(rows.isEmpty())error="所选日期尚无本机正文。请先在官方智记打开该记录的原文，再回来导出；不用重新录音。";
                    else{File dir=new File(a.getNoBackupFilesDir(),"turboio/lifelog-export");if(!dir.isDirectory()&&!dir.mkdirs())throw new IOException();file=new File(dir,"全天智记.md");try(FileOutputStream o=new FileOutputStream(file)){o.write(RecordingText.lifelogMarkdown(rows,z).getBytes(StandardCharsets.UTF_8));}}}
                catch(IllegalArgumentException e){error=e.getMessage();}catch(Throwable t){error="无法写入独立文件，原记录未改。";}
                String err=error;File f=file;MAIN.post(()->{if(a.isFinishing()||a.isDestroyed())return;if(err!=null)EditorialUI.notice(a,err);else RecordingExports.share(a,f,"text/markdown");});});
        },today.getYear(),today.getMonthValue()-1,today.getDayOfMonth()).show();
    }
}
