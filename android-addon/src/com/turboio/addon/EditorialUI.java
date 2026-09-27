package com.turboio.addon;
import android.app.*;
import android.graphics.*;
import android.graphics.drawable.*;
import android.view.*;
import android.widget.*;

/** Android-native rendering of the approved plugin design, never changes vendor tabs. */
final class EditorialUI {
    static final int BG=0xff17131b,SURFACE=0xff221d25,INK=0xfff0ede5,MUTED=0xffb1aba9,LIME=0xffdbf67a;
    static int dp(Activity a,int n){return (int)(a.getResources().getDisplayMetrics().density*n+.5f);}
    static LinearLayout column(Activity a){LinearLayout l=new LinearLayout(a);l.setOrientation(1);return l;}
    static GradientDrawable shape(Activity a,int color,int radius){GradientDrawable d=new GradientDrawable();d.setColor(color);d.setCornerRadius(dp(a,radius));d.setStroke(dp(a,1),0x25ffffff);return d;}
    static TextView text(Activity a,String s,int size,int color){TextView t=new TextView(a);t.setText(s);t.setTextSize(size);t.setTextColor(color);t.setLineSpacing(dp(a,3),1);return t;}
    static void gap(Activity a,LinearLayout l,int n){l.addView(new View(a),new LinearLayout.LayoutParams(1,dp(a,n)));}
    static TextView button(Activity a,LinearLayout l,String label,boolean primary,Runnable action){TextView b=text(a,label,16,primary?BG:INK);b.setGravity(Gravity.CENTER);b.setTypeface(null,Typeface.BOLD);b.setBackground(shape(a,primary?LIME:SURFACE,24));b.setPadding(dp(a,14),dp(a,12),dp(a,14),dp(a,12));b.setMinHeight(dp(a,50));LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-1,-2);p.topMargin=dp(a,10);l.addView(b,p);b.setOnClickListener(v->action.run());b.setFocusable(true);return b;}
    static LinearLayout card(Activity a,LinearLayout parent){LinearLayout c=column(a);c.setPadding(dp(a,16),dp(a,16),dp(a,16),dp(a,16));c.setBackground(shape(a,SURFACE,24));LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-1,-2);p.topMargin=dp(a,12);parent.addView(c,p);return c;}
    static Switch toggle(Activity a,LinearLayout parent,String label,boolean on,android.widget.CompoundButton.OnCheckedChangeListener listener){
        LinearLayout row=new LinearLayout(a);row.setGravity(Gravity.CENTER_VERTICAL);row.setPadding(dp(a,8),dp(a,8),dp(a,8),dp(a,8));TextView title=text(a,label,15,INK);row.addView(title,new LinearLayout.LayoutParams(0,-2,1));
        Switch s=new Switch(new ContextThemeWrapper(a,android.R.style.Theme_Material));s.setContentDescription(label);s.setShowText(false);s.setSwitchMinWidth(dp(a,52));
        GradientDrawable thumb=shape(a,INK,20);thumb.setSize(dp(a,24),dp(a,24));s.setThumbDrawable(thumb);
        StateListDrawable tracks=new StateListDrawable();GradientDrawable yes=shape(a,0xff82953b,20),no=shape(a,0xff625a65,20);yes.setSize(dp(a,52),dp(a,28));no.setSize(dp(a,52),dp(a,28));tracks.addState(new int[]{android.R.attr.state_checked},yes);tracks.addState(new int[]{},no);s.setTrackDrawable(tracks);s.setChecked(on);
        LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(dp(a,60),dp(a,48));p.leftMargin=dp(a,16);row.addView(s,p);parent.addView(row,new LinearLayout.LayoutParams(-1,-2));s.setOnCheckedChangeListener(listener);row.setOnClickListener(v->s.setChecked(!s.isChecked()));return s;
    }
    static final class Screen {
        final Dialog dialog;final LinearLayout body,root;final Activity activity;
        Screen(Activity a,String title){
            activity=a;dialog=new Dialog(a,android.R.style.Theme_Material_NoActionBar);dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);
            root=column(a);root.setBackground(new GradientDrawable(GradientDrawable.Orientation.TL_BR,new int[]{0xff31221e,BG,0xff211e18}));
            int side=dp(a,20);root.setPadding(side,0,side,0);
            LinearLayout header=new LinearLayout(a);header.setGravity(Gravity.CENTER_VERTICAL);
            TextView back=text(a,"‹",34,INK);back.setContentDescription("返回");back.setGravity(Gravity.CENTER);
            header.addView(back,new LinearLayout.LayoutParams(dp(a,48),dp(a,56)));
            TextView label=text(a,title,22,INK);label.setTypeface(null,Typeface.BOLD);label.setMaxLines(1);label.setEllipsize(android.text.TextUtils.TruncateAt.END);
            header.addView(label,new LinearLayout.LayoutParams(0,-2,1));root.addView(header);
            body=column(a);body.setPadding(0,dp(a,8),0,dp(a,28));ScrollView scroll=new ScrollView(a);scroll.setFillViewport(true);scroll.addView(body);root.addView(scroll,new LinearLayout.LayoutParams(-1,0,1));
            dialog.setContentView(root);back.setOnClickListener(v->dialog.dismiss());dialog.show();Window w=dialog.getWindow();w.setLayout(-1,-1);
            w.setStatusBarColor(BG);w.setNavigationBarColor(BG);w.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);w.getDecorView().setSystemUiVisibility(0);
            if(android.os.Build.VERSION.SDK_INT>=30){
                w.setDecorFitsSystemWindows(false);
                root.setOnApplyWindowInsetsListener((v,insets)->{
                    android.graphics.Insets safe=insets.getInsets(WindowInsets.Type.systemBars()|WindowInsets.Type.displayCutout());
                    int keyboard=insets.getInsets(WindowInsets.Type.ime()).bottom;
                    v.setPadding(side+safe.left,safe.top,side+safe.right,Math.max(safe.bottom,keyboard));
                    return WindowInsets.CONSUMED;
                });root.requestApplyInsets();
            }
        }
    }
    static void notice(Activity a,String message){new AlertDialog.Builder(a).setTitle("Turbo IO").setMessage(message).setPositiveButton("知道了",null).show();}
    static void confirm(Activity a,String title,String message,Runnable action){new AlertDialog.Builder(a).setTitle(title).setMessage(message).setNegativeButton("取消",null).setPositiveButton("确认",(d,w)->action.run()).show();}
    static void home(Activity a){Screen s=new Screen(a,"turbo io");LinearLayout content=s.body;TextView brand=text(a,"Turbo这个IO",32,INK);brand.setTypeface(null,Typeface.BOLD);content.addView(brand);content.addView(text(a,"声音、阅读与灵感，随你出发。",14,MUTED));EditorialArt hero=new EditorialArt(a,"hero-sequence-v5",true);content.addView(hero,new LinearLayout.LayoutParams(-1,dp(a,190)));
        button(a,content,"模型与对话  ›",false,TurboAddon::showSettings);
        String[] names={"网易云音乐","微信读书","高德导航","番茄时钟","仪表盘","应用广场"},arts={"music","reading","navigation","focus","dashboard-editor","app-gallery"};
        for(int row=0;row<3;row++){LinearLayout pair=new LinearLayout(a);for(int col=0;col<2;col++){int i=row*2+col;FrameLayout card=new FrameLayout(a);card.setBackground(shape(a,SURFACE,24));card.setClipToOutline(true);EditorialArt art=new EditorialArt(a,arts[i],false);card.addView(art,new FrameLayout.LayoutParams(-1,-1));View shade=new View(a);shade.setBackground(new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM,new int[]{0x00000000,0xdd100c12}));card.addView(shade,new FrameLayout.LayoutParams(-1,-1));TextView title=text(a,names[i]+"  ↗",16,INK);title.setTypeface(null,Typeface.BOLD);title.setPadding(dp(a,12),dp(a,10),dp(a,10),dp(a,16));card.addView(title,new FrameLayout.LayoutParams(-1,-2,Gravity.BOTTOM));LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(0,dp(a,164),1);p.topMargin=dp(a,12);if(col==0)p.rightMargin=dp(a,12);pair.addView(card,p);card.setContentDescription(names[i]);card.setFocusable(true);card.setOnClickListener(v->{switch(i){case 0:MusicUI.show(a);break;case 1:ReaderUI.show(a);break;case 2:NavigationUI.show(a);break;case 3:FocusUI.show(a);break;case 4:CardUI.show(a);break;case 5:GalleryUI.show(a);break;default:notice(a,"此模块仍在进行安卓移植，暂不执行眼镜操作。当前可检查仪表盘、番茄时钟、应用广场及原有导航、模型与导出。");}});}content.addView(pair);}
        button(a,content,"实验固件升级 · 默认锁定",false,()->OtaUI.show(a));
        gap(a,content,18);content.addView(text(a,"ANDROID 1.0.5 · INTEGRATION-08 / CALLBACK-01\n安装期禁止立即回查；未知结果保持锁定，不自动重刷。阅读、新闻、云端字幕与后台任务已接入，安卓真实眼镜与服务账号待验收。",12,MUTED));
        LinearLayout tabs=new LinearLayout(a);tabs.setBackground(shape(a,0xe62a252e,32));String[] labels={"首页","翻译","新闻","设置"};for(int i=0;i<4;i++){final int tab=i;TextView t=text(a,labels[i],14,i==0?LIME:MUTED);t.setGravity(Gravity.CENTER);tabs.addView(t,new LinearLayout.LayoutParams(0,dp(a,58),1));t.setOnClickListener(v->{if(tab==1){CaptionUI.show(a);}else if(tab==2){NewsUI.show(a);}else if(tab==3){Screen settings=new Screen(a,"设置");button(a,settings.body,"模型与对话",false,TurboAddon::showSettings);button(a,settings.body,"回答同步朗读",false,()->VoiceSpeech.show(a));button(a,settings.body,"搜索与知识库",false,TurboAddon::showTools);button(a,settings.body,"后台运行",false,()->BackgroundWork.show(a));button(a,settings.body,"诊断",false,()->notice(a,TurboAddon.status()+"\n"+NativeTransfer.diagnostic()));}});}LinearLayout.LayoutParams t=new LinearLayout.LayoutParams(-1,-2);t.bottomMargin=dp(a,12);s.root.addView(tabs,t);
    }
}
