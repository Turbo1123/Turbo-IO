package com.turboio.addon;
import android.app.*;
import android.content.*;
import android.os.*;
import android.widget.*;
import java.time.*;
import java.time.format.DateTimeFormatter;
import java.util.*;

/** 设置 → 学习研究 · 情境英语 (iOS ContextEnglishPanel.m + CEAutoRuntime panel): load cached excerpts, tick what may
 * be sent, approve one model request, review the cards, send them to the glasses; plus the opt-in daily automation. */
final class ContextEnglishUI {
    private static final String[] TARGET_NAMES={"四级","六级","托福","雅思"};
    private final Activity a;private final SharedPreferences prefs;private EditorialUI.Screen s;
    private TextView status,countLabel,dayLabel,timeLabel,autoState;private LinearLayout sourceBox,cardBox;
    private LocalDate day=LocalDate.now().minusDays(1);private boolean initialLoad=true,loading;private int revision;
    private List<Map<String,Object>> sources=new ArrayList<>(),cards=new ArrayList<>();private final Set<Integer> selected=new TreeSet<>();private Runnable job;
    private ContextEnglishUI(Activity a){this.a=a;prefs=a.getSharedPreferences("turboio_english_ui",0);}
    static void show(Activity a){CeBridge.init(a);new ContextEnglishUI(a).open();}
    private String target(){int t=prefs.getInt("target",0);return CeSession.TARGETS.get(t>=0&&t<4?t:0);}
    private int count(){return Math.max(1,Math.min(10,prefs.getInt("count",5)));}
    private int minute(){return Math.max(0,Math.min(1439,prefs.getInt("minute",1200)));}
    private boolean busy(){return job!=null||loading||CeBridge.sending();}
    private void setStatus(String t){status.setText(t);}
    private void open(){
        s=new EditorialUI.Screen(a,"情境英语");LinearLayout b=s.body;
        b.addView(EditorialUI.text(a,"每天一点，从生活里学英语",17,EditorialUI.INK));
        b.addView(EditorialUI.text(a,"默认每天 5 个，含复习；题库与每日进度在眼镜端保存。本机保留最多 40 个已发送表达供复习，不自动上传旧片段。",13,EditorialUI.MUTED));
        LinearLayout setup=EditorialUI.card(a,b);
        setup.addView(EditorialUI.text(a,"学习目标",14,EditorialUI.INK));RadioGroup g=new RadioGroup(a);g.setOrientation(0);
        for(int i=0;i<4;i++){RadioButton r=new RadioButton(a);r.setText(TARGET_NAMES[i]);r.setTextColor(EditorialUI.INK);r.setId(1000+i);g.addView(r);}
        g.check(1000+CeSession.TARGETS.indexOf(target()));g.setOnCheckedChangeListener((v,id)->{prefs.edit().putInt("target",id-1000).apply();invalidate();});setup.addView(g);
        countLabel=EditorialUI.text(a,"",14,EditorialUI.INK);setup.addView(countLabel);LinearLayout steps=new LinearLayout(a);
        EditorialUI.button(a,steps,"−",false,()->{prefs.edit().putInt("count",Math.max(1,count()-1)).apply();invalidate();refresh();});
        EditorialUI.button(a,steps,"+",false,()->{prefs.edit().putInt("count",Math.min(10,count()+1)).apply();invalidate();refresh();});setup.addView(steps);
        dayLabel=EditorialUI.text(a,"",14,EditorialUI.INK);setup.addView(dayLabel);
        EditorialUI.button(a,setup,"来源记录日期",false,()->new DatePickerDialog(a,(v,y,m,d)->{day=LocalDate.of(y,m+1,d);initialLoad=false;loadArchive();},day.getYear(),day.getMonthValue()-1,day.getDayOfMonth()).show());
        timeLabel=EditorialUI.text(a,"",14,EditorialUI.INK);setup.addView(timeLabel);
        EditorialUI.button(a,setup,"眼镜提醒时间",false,()->new TimePickerDialog(a,(v,h,m)->{prefs.edit().putInt("minute",h*60+m).apply();refresh();},minute()/60,minute()%60,true).show());
        EditorialUI.toggle(a,setup,"轻量复习提醒",prefs.getBoolean("reminder",false),(v,on)->prefs.edit().putBoolean("reminder",on).apply());
        status=EditorialUI.text(a,"正在读取本机已有智记正文，不需要开启文字保存。未确认前不会上传。",14,EditorialUI.LIME);b.addView(status);
        b.addView(EditorialUI.text(a,"1 · 载入片段",17,EditorialUI.INK));
        b.addView(EditorialUI.text(a,"直接读取官方 App 已缓存的逐句正文，不依赖“保存最终文字”。只有列表或摘要时，请先在官方智记打开对应记录的原文，再回来刷新。不读取位置、不自动上传。合成测试题不读取个人记录。",13,EditorialUI.MUTED));
        EditorialUI.button(a,b,"刷新已有智记片段",false,()->{if(!busy())loadArchive();});
        EditorialUI.button(a,b,"载入合成测试题（无需智记 / Key）",false,()->{if(busy())return;invalidate();sources=new ArrayList<>();selected.clear();cards=CeCore.offlineCards(count());
            setStatus("已载入合成测试题；检查下面的候选，再点“发送今日题库到眼镜”。未读取智记、未调用模型、未发送。");render();});
        b.addView(EditorialUI.text(a,"2 · 选择可发送的内容",17,EditorialUI.INK));
        b.addView(EditorialUI.text(a,"最多 32 个完整片段、合计 12 KB。请排除账号、密钥及不愿分享的第三方内容。关闭页面后清除未发送的来源快照。",13,EditorialUI.MUTED));
        sourceBox=EditorialUI.column(a);b.addView(sourceBox);
        b.addView(EditorialUI.text(a,"3 · 检查候选",17,EditorialUI.INK));
        b.addView(EditorialUI.text(a,"AI 候选未经过考试词表或语言学核验。不把教学改写冒充原话；少量候选不足时不凑题。",13,EditorialUI.MUTED));
        cardBox=EditorialUI.column(a);b.addView(cardBox);
        b.addView(EditorialUI.text(a,"4 · 发送到眼镜",17,EditorialUI.INK));
        EditorialUI.button(a,b,"生成今日练习（优先到期复习）",true,this::generate);
        EditorialUI.button(a,b,"取消生成",false,()->{if(job!=null){Runnable j=job;job=null;revision++;j.run();setStatus("生成已取消；不会自动重传片段。");}});
        EditorialUI.button(a,b,"发送今日题库到眼镜",true,this::send);
        EditorialUI.button(a,b,"清除本页候选与片段",false,()->{if(busy())return;resign();cards=new ArrayList<>();setStatus("本页内容已清除；不删除官方记录或眼镜中已有题库。");render();});
        EditorialUI.button(a,b,"清除本机复习记录",false,()->new AlertDialog.Builder(a).setTitle("清除本机复习记录？").setMessage("删除本插件保存的学习表达，不删除官方智记记录，也不会重置眼镜的每日额度。")
            .setNegativeButton("取消",null).setPositiveButton("清除",(d,w)->{if(busy())return;setStatus(CeBridge.history().clear()?"本机复习记录已清除。":"清除失败，未重置眼镜。");}).show());
        buildAuto(b);
        CeBridge.listen((text,terminal)->{if(s.dialog.isShowing())setStatus(text);});
        s.dialog.setOnDismissListener(d->{resign();CeBridge.listen(null);});
        refresh();loadArchive();
    }
    private void refresh(){countLabel.setText("每天 "+count()+" 个（含复习）");dayLabel.setText("来源记录日期 · "+day);timeLabel.setText(String.format(Locale.ROOT,"眼镜提醒时间 · %02d:%02d",minute()/60,minute()%60));}
    private void invalidate(){revision++;cards=new ArrayList<>();if(cardBox!=null)render();}
    /** Page left: unsent source snapshot and any generation are dropped (iOS resign). */
    private void resign(){revision++;if(job!=null){Runnable j=job;job=null;j.run();}loading=false;sources=new ArrayList<>();selected.clear();}
    private void loadArchive(){
        invalidate();sources=new ArrayList<>();selected.clear();int mine=revision;loading=true;setStatus("正在读取本机已有智记…不会联网或上传。");render();
        CeBridge.readArchive((rows,error)->{if(mine!=revision)return;loading=false;ZoneId zone=ZoneId.systemDefault();Map<String,Object> snapshot=null;String e=error;
            if(error==null)try{snapshot=CeCore.prepareDay(rows,day.toString(),zone,target(),count());}catch(IllegalArgumentException x){e=null;}
            TreeSet<String> days=new TreeSet<>(Comparator.reverseOrder());Instant newest=null;
            if(rows!=null)for(CeLifelog.Row r:rows){Instant at;try{at=Instant.parse(r.at);}catch(RuntimeException x){continue;}if(at.isAfter(Instant.now()))continue;days.add(at.atZone(zone).toLocalDate().toString());if(newest==null||at.isAfter(newest))newest=at;}
            boolean switched=false;if(error==null&&snapshot==null&&initialLoad&&newest!=null){day=newest.atZone(zone).toLocalDate();try{snapshot=CeCore.prepareDay(rows,day.toString(),zone,target(),count());switched=true;}catch(IllegalArgumentException x){snapshot=null;}}
            initialLoad=false;sources=new ArrayList<>();if(snapshot!=null)for(Object o:(List<?>)snapshot.get("sources"))sources.add(BoundedJson.map(o));selected.clear();
            String text=snapshot!=null?(switched?"已切到最近有正文的日期：":"")+day+" · 已载入 "+sources.size()+" 个片段，请勾选后生成。":e!=null?e:"所选日期尚无本机正文。请先在官方智记打开该记录的原文，再回来刷新；不用重新录音。";
            if(!days.isEmpty()){List<String> d=new ArrayList<>(days);text+="\n有正文的日期："+String.join("、",d.subList(0,Math.min(7,d.size())));}
            setStatus(text);refresh();render();});
    }
    private void render(){
        sourceBox.removeAllViews();DateTimeFormatter f=DateTimeFormatter.ofPattern("MM-dd HH:mm");
        for(int i=0;i<sources.size();i++){final int index=i;Map<String,Object> src=sources.get(i);String when;try{when=Instant.parse((String)src.get("receivedAt")).atZone(ZoneId.systemDefault()).format(f);}catch(RuntimeException e){when="";}
            CheckBox c=new CheckBox(a);c.setText("来源时间 · "+when+"\n"+src.get("quote"));c.setTextColor(EditorialUI.INK);c.setChecked(selected.contains(i));
            c.setOnCheckedChangeListener((v,on)->{if(on)selected.add(index);else selected.remove(index);revision++;cards=new ArrayList<>();renderCards();});sourceBox.addView(c);}
        renderCards();
    }
    private void renderCards(){
        cardBox.removeAllViews();
        for(Map<String,Object> c:cards)cardBox.addView(EditorialUI.text(a,c.get("english")+" · "+c.get("meaning")+"\n"+c.get("example")+"\n记录："+c.get("quote")+"\n"+(c.get("sourceLabel")==null?"":c.get("sourceLabel")),14,EditorialUI.INK));
        if(cards.isEmpty())cardBox.addView(EditorialUI.text(a,"暂无候选",13,EditorialUI.MUTED));
    }
    private void generate(){
        if(busy())return;if(CeBridge.auto().enabled()){setStatus("请先关闭自动备题，再使用手动生成，避免重复。");return;}
        List<Map<String,Object>> reviews=CeBridge.history().reviews(NativeTransfer.connected(),target(),LocalDate.now().toEpochDay(),count());
        if(reviews.size()>=count()||(selected.isEmpty()&&!reviews.isEmpty())){cards=reviews;setStatus("已载入到期复习，不调用模型；检查后可发送。");renderCards();return;}
        if(selected.isEmpty()){setStatus("暂无到期复习，请先勾选愿意发送的片段。");return;}
        List<CeLifelog.Row> rows=new ArrayList<>();for(int i:selected){Map<String,Object> src=sources.get(i);rows.add(new CeLifelog.Row((String)src.get("quote"),(String)src.get("receivedAt")));}
        Map<String,Object> selection;CeBridge.Config c=CeBridge.config();
        try{selection=CeCore.prepareDay(rows,day.toString(),ZoneId.systemDefault(),target(),count()-reviews.size());if(c.error!=null)throw new IllegalArgumentException(c.error);CeCore.body(selection,c.model,c.disableThinking);}
        catch(IllegalArgumentException e){setStatus(e.getMessage()!=null?e.getMessage():"请先配置自定义模型。");return;}
        int mine=revision;String host;try{host=new java.net.URI(c.endpoint).getHost();}catch(Exception e){host=c.endpoint;}
        new AlertDialog.Builder(a).setTitle("确认向模型发送片段").setMessage("将选中的 "+selected.size()+" 个片段发送给 "+host+"\n模型："+c.model+"\n未勾选内容不会发送。生成后仍需你检查并手动发送到眼镜。")
            .setNegativeButton("取消",null).setPositiveButton("同意并生成",(d,w)->{if(mine!=revision||busy())return;setStatus("正在生成；不会自动重试或发送到眼镜。");
                job=CeBridge.generate(selection,(generated,error)->{job=null;if(mine!=revision)return;
                    List<Map<String,Object>> combined=new ArrayList<>(reviews);Set<String> words=new HashSet<>();for(Map<String,Object> r:reviews)words.add(String.valueOf(r.get("english")).toLowerCase(Locale.ROOT));
                    if(generated!=null)for(Map<String,Object> g:generated){String word=String.valueOf(g.get("english")).toLowerCase(Locale.ROOT);if(!words.contains(word)&&combined.size()<count()){combined.add(g);words.add(word);}}
                    cards=combined;setStatus(error!=null?error:"共 "+combined.size()+" 个候选（复习 "+reviews.size()+" 个），请检查。");renderCards();});}).show();
    }
    private void send(){
        if(busy())return;if(CeBridge.auto().enabled()){setStatus("请先关闭自动备题，再手动发送，避免重复。");return;}
        if(cards.isEmpty()){setStatus("请先生成并检查候选。");return;}
        boolean synthetic=Boolean.TRUE.equals(cards.get(0).get("syntheticTest"));setStatus("等待眼镜能力和题库状态回查…");
        CeBridge.send(cards,target(),count(),minute(),!synthetic&&prefs.getBoolean("reminder",false),synthetic,(text,terminal)->{if(s.dialog.isShowing())setStatus(text);});
    }
    private void buildAuto(LinearLayout b){
        b.addView(EditorialUI.text(a,"自动备题与提醒",17,EditorialUI.INK));
        b.addView(EditorialUI.text(a,"默认关闭。授权后读取昨日本机正文，不启动录音、不拉云端全量历史。每天最多一次模型请求，最多32段／12KB；敏感内容过滤并不完美。关闭清除本机待发题库，但不能撤回已经上传或发往眼镜的内容。只在 App 获得运行时间时备题与发送，不能保证后台准点执行。题库提前存在眼镜，到点由固件邀请。",13,EditorialUI.MUTED));
        autoState=EditorialUI.text(a,"",13,EditorialUI.INK);b.addView(autoState);
        EditorialUI.button(a,b,"开启自动备题并发送",false,()->{
            if(CeBridge.auto().enabled()){renderAuto();return;}
            Map<String,Object> ctx=CeBridge.context();Map<String,Object> settings=new LinkedHashMap<>();settings.put("target",target());settings.put("count",(long)count());settings.put("minute",(long)minute());
            String message="允许每天自动选取昨日本机智记正文（最多32段／12KB）发送到：\n"+ctx.get("destination")+"\n模型："+ctx.get("model")+"\n生成后自动推送给当前眼镜。\n请确保谈话内容及相关人员已获适当授权。过滤无法保证排除全部隐私。\n账号、模型地址、模型、设备或时区变化需重新授权。随时可关闭。";
            new AlertDialog.Builder(a).setTitle("授权每日自动学习").setMessage(message).setNegativeButton("取消",null).setPositiveButton("同意并开启",(d,w)->{
                Map<String,Object> now=CeBridge.context();boolean same=Boolean.TRUE.equals(now.get("ready"));for(String k:new String[]{"destination","model","scope","peer","zone"})same=same&&Objects.equals(now.get(k),ctx.get(k));
                if(!same){EditorialUI.notice(a,"连接或配置已变化，请重新确认。");return;}
                String error=CeBridge.auto().enable(settings);if(error!=null)EditorialUI.notice(a,error);else CeBridge.auto().tick();renderAuto();}).show();
        });
        EditorialUI.button(a,b,"关闭自动备题",false,()->{CeBridge.auto().disable();renderAuto();});
        EditorialUI.button(a,b,"检查一次执行条件",false,()->{CeBridge.auto().tick();renderAuto();});
        Handler h=new Handler(Looper.getMainLooper());Runnable tick=new Runnable(){public void run(){if(!s.dialog.isShowing())return;renderAuto();h.postDelayed(this,2000);}};h.post(tick);
    }
    private void renderAuto(){Map<String,Object> st=CeBridge.auto().snapshot();Object note=st.get("note");
        autoState.setText((note==null?"尚未开启":note)+"\n候选 "+(st.get("candidateCount")==null?0:st.get("candidateCount"))+" 个 · 已发送日期 "+(st.get("delivered")==null?"—":st.get("delivered"))+"\n修改配置请先关闭自动化。");}
}
