package com.turboio.addon;

import android.app.*;
import android.graphics.*;
import android.graphics.drawable.*;
import android.view.*;
import android.widget.*;

final class TurboStyle {
    static final int BG=EditorialUI.BG,INK=EditorialUI.INK,MUTED=EditorialUI.MUTED,LIME=EditorialUI.LIME;
    static int dp(Activity a,int x){return (int)(a.getResources().getDisplayMetrics().density*x+.5f);}
    static GradientDrawable surface(Activity a,int color,int radius){if(color==Color.WHITE||color==0xfff1f4ef||color==0xffe8eee8||color==0xffedf4e8)color=EditorialUI.SURFACE;GradientDrawable d=new GradientDrawable();d.setColor(color);d.setCornerRadius(dp(a,radius));d.setStroke(dp(a,1),0x25ffffff);return d;}
    static LinearLayout column(Activity a){LinearLayout l=new LinearLayout(a);l.setOrientation(1);return l;}
    static TextView text(Activity a,String value,int size,int color){TextView t=new TextView(a);t.setText(value);t.setTextSize(size);t.setTextColor(color);t.setLineSpacing(dp(a,3),1);return t;}
    static TextView title(Activity a,String value,int size){TextView t=text(a,value,size,INK);t.setTypeface(null,Typeface.BOLD);return t;}
    static void field(Activity a,EditText f){f.setTextColor(INK);f.setHintTextColor(MUTED);f.setTextSize(16);f.setPadding(dp(a,14),dp(a,12),dp(a,14),dp(a,12));f.setBackground(surface(a,0xfff1f4ef,14));LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-1,dp(a,52));p.bottomMargin=dp(a,8);f.setLayoutParams(p);}
    static void gap(Activity a,LinearLayout l,int n){View v=new View(a);l.addView(v,new LinearLayout.LayoutParams(1,dp(a,n)));}
    static LinearLayout card(Activity a,LinearLayout parent,int color){LinearLayout l=column(a);l.setPadding(dp(a,20),dp(a,18),dp(a,20),dp(a,18));l.setBackground(surface(a,color,24));LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-1,-2);p.bottomMargin=dp(a,12);parent.addView(l,p);return l;}
    static Button button(Activity a,LinearLayout l,String label,boolean primary,Runnable action){Button b=new Button(a);b.setText(label);b.setAllCaps(false);b.setTextSize(15);b.setTextColor(primary?BG:INK);b.setTypeface(null,Typeface.BOLD);b.setBackground(surface(a,primary?LIME:EditorialUI.SURFACE,24));LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-1,dp(a,56));p.topMargin=dp(a,10);l.addView(b,p);b.setOnClickListener(v->action.run());return b;}
    static void row(Activity a,LinearLayout l,String symbol,String title,String detail,Runnable run){
        LinearLayout c=card(a,l,Color.WHITE);LinearLayout row=new LinearLayout(a);row.setGravity(Gravity.CENTER_VERTICAL);
        TextView icon=text(a,symbol,27,INK);icon.setGravity(Gravity.CENTER);icon.setBackground(surface(a,0xffedf4e8,18));row.addView(icon,new LinearLayout.LayoutParams(dp(a,54),dp(a,54)));
        LinearLayout labels=column(a);labels.setPadding(dp(a,16),0,dp(a,8),0);labels.addView(title(a,title,18));labels.addView(text(a,detail,13,MUTED));row.addView(labels,new LinearLayout.LayoutParams(0,-2,1));row.addView(text(a,"›",26,MUTED));c.addView(row);c.setOnClickListener(v->run.run());c.setContentDescription(title);c.setFocusable(true);
    }
    static Dialog screen(Activity a,String title,LinearLayout content,Runnable back){
        Dialog d=new Dialog(a,android.R.style.Theme_Material_NoActionBar);d.requestWindowFeature(Window.FEATURE_NO_TITLE);
        LinearLayout shell=column(a);shell.setBackgroundColor(BG);shell.setPadding(dp(a,20),dp(a,14),dp(a,20),dp(a,12));
        LinearLayout header=new LinearLayout(a);header.setGravity(Gravity.CENTER_VERTICAL);
        TextView close=text(a,"‹",34,INK);close.setGravity(Gravity.CENTER);header.addView(close,new LinearLayout.LayoutParams(dp(a,48),dp(a,52)));TextView t=title(a,title,24);header.addView(t);shell.addView(header);
        ScrollView scroll=new ScrollView(a);scroll.setFillViewport(true);scroll.setClipToPadding(false);scroll.addView(content);shell.addView(scroll,new LinearLayout.LayoutParams(-1,0,1));
        d.setContentView(shell);close.setOnClickListener(v->{d.dismiss();if(back!=null)back.run();});d.setOnCancelListener(x->{if(back!=null)back.run();});
        d.show();Window w=d.getWindow();w.setBackgroundDrawableResource(android.R.color.transparent);w.setLayout(-1,-1);w.setStatusBarColor(BG);w.setNavigationBarColor(BG);w.getDecorView().setSystemUiVisibility(0);w.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);
        return d;
    }
}
