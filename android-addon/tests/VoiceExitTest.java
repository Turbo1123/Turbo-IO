package com.turboio.addon;

/** Voice exit: exact iOS phrase set, and the official stop reached the way the host listener does it. */
public final class VoiceExitTest {
    static int n;static void ok(boolean b,String why){n++;if(!b)throw new AssertionError("voice exit "+n+" "+why);}
    /** Shapes of the host's ASR listener (q8/c$c) and its outer voice controller (q8/c). */
    static final class Outer{int calls;Object[] args;public final void s(String reason,boolean a,boolean b){calls++;args=new Object[]{reason,a,b};}}
    static final class Listener{public final Outer a;Listener(Outer o){a=o;}}
    static final class WrongOuter{public final void s(String reason,boolean a){}}
    static final class WrongListener{public final WrongOuter a=new WrongOuter();}
    static final class NoField{}
    public static void main(String[] x){
        for(String p:new String[]{"退下吧","退下","关闭","没事了","关闭窗口","关闭对话","结束对话","退出对话","不用了","就这样吧"})ok(VoiceExit.matches(p),p);
        ok(VoiceExit.matches("小雷小雷，退下吧。")&&VoiceExit.matches("  关闭 窗口！ ")&&VoiceExit.matches("小雷小雷 不用了"),"wake word, punctuation, spaces");
        for(String p:new String[]{"帮我关闭空调的提醒","关闭吗","不用了谢谢","","小雷小雷","退下吧退下吧","关闭"+new String(new char[47]).replace('\0','啊')})ok(!VoiceExit.matches(p),"not exit: "+p);
        ok(!VoiceExit.matches(null),"null");
        Outer o=new Outer();VoiceExit.Stopper st=VoiceExit.resolve(new Listener(o));ok(st!=null,"resolves");
        ok(st.stop()&&o.calls==1&&o.args[0]==null&&Boolean.FALSE.equals(o.args[1])&&Boolean.FALSE.equals(o.args[2]),"official stop s(null,false,false) once");
        ok(VoiceExit.resolve(new WrongListener())==null&&VoiceExit.resolve(new NoField())==null&&VoiceExit.resolve(null)==null,"no entry on other shapes");
        System.out.println("VoiceExitTest: "+n+" checks; exact phrases, official stop entry");
    }
}
