package com.turboio.addon;
import java.lang.reflect.*;
import java.util.*;

/** Spoken exit phrases (iOS TIOIsVoiceExitCommand) and the host's own assistant stop. The hooked ASR
 * listener (p8/c$c on 1.0.6, q8/c$c on 1.0.7) keeps its voice controller in field `a`; the controller's
 * s(String,boolean,boolean) is the official stop_assistant path, which the listener itself calls as
 * s(null,false,false). Any shape mismatch disables the feature instead of guessing. */
final class VoiceExit {
    interface Stopper{boolean stop();}
    private static final Set<String> PHRASES=new HashSet<>(Arrays.asList("退下吧","退下","关闭","没事了","关闭窗口","关闭对话","结束对话","退出对话","不用了","就这样吧"));
    private static final String TRIM="，。！？,.!?、：:";
    private VoiceExit(){}
    private static String trim(String s){int a=0,b=s.length();while(a<b&&(Character.isWhitespace(s.charAt(a))||TRIM.indexOf(s.charAt(a))>=0))a++;while(b>a&&(Character.isWhitespace(s.charAt(b-1))||TRIM.indexOf(s.charAt(b-1))>=0))b--;return s.substring(a,b);}
    /** Exact utterances only; chat or task content that merely contains a phrase never matches. */
    static boolean matches(String text){
        if(text==null||text.isEmpty()||text.length()>48)return false;
        String s=trim(text);if(s.startsWith("小雷小雷"))s=trim(s.substring(4));
        StringBuilder b=new StringBuilder();for(int i=0;i<s.length();i++)if(!Character.isWhitespace(s.charAt(i)))b.append(s.charAt(i));
        return PHRASES.contains(b.toString());
    }
    /** Null unless the listener has field `a` whose class declares exactly void s(String,boolean,boolean). */
    static Stopper resolve(Object listener){
        if(listener==null)return null;
        try{Field f=listener.getClass().getDeclaredField("a");f.setAccessible(true);Object outer=f.get(listener);if(outer==null)return null;
            Method m=outer.getClass().getDeclaredMethod("s",String.class,boolean.class,boolean.class);if(m.getReturnType()!=void.class)return null;m.setAccessible(true);
            return ()->{try{m.invoke(outer,null,false,false);return true;}catch(Exception e){return false;}};
        }catch(Exception e){return null;}
    }
}
