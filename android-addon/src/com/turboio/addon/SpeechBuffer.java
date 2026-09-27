package com.turboio.addon;
import java.util.*;

/** Bounded sentence queue. Callers explicitly choose delta vs full-text input. */
final class SpeechBuffer {
    static final int MAX=12000, CHUNK=180;
    private String full="",pending="";private boolean finished;
    void reset(){full="";pending="";finished=false;}
    List<String> append(String text,boolean cumulative,boolean end){
        if(text==null||finished)return Collections.emptyList();
        String delta=text;
        if(cumulative){if(!text.startsWith(full))throw new IllegalArgumentException("Non-prefix response");delta=text.substring(full.length());}
        if(full.length()+delta.length()>MAX)throw new IllegalArgumentException("Speech limit");
        full+=delta;pending+=delta;finished=end;List<String> out=new ArrayList<>();
        while(!pending.isEmpty()){
            int cut=0,limit=Math.min(CHUNK,pending.length());
            for(int i=0;i<limit;i++)if("。！？!?；;\n".indexOf(pending.charAt(i))>=0||(pending.charAt(i)=='.'&&(i+1==pending.length()||Character.isWhitespace(pending.charAt(i+1))))){cut=i+1;break;}
            if(cut==0){if(pending.length()>=CHUNK)cut=CHUNK;else if(end)cut=pending.length();else break;}
            if(cut<pending.length()&&Character.isHighSurrogate(pending.charAt(cut-1)))cut--;
            String part=pending.substring(0,cut).replaceAll("[\\p{Cntrl}&&[^\\n\\t]]","").trim();
            pending=pending.substring(cut);if(!part.isEmpty())out.add(part);
        }return out;
    }
}
