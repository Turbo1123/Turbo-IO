package com.turboio.addon;
import java.util.*;

public final class RayneoToolTurnTest {
    static int checks;
    static final String R="rayneo_context_query";
    static void check(boolean value){checks++;if(!value)throw new AssertionError("check "+checks);}
    static ToolTurn enabled(){return new ToolTurn(true,true,true,true,true);}
    public static void main(String[] args){
        ToolTurn noSearch=new ToolTurn(false,true,true,true,true);
        check(noSearch.validate(Arrays.asList(R))==null);
        check(new ToolTurn(true,true,true,true,false).validate(Arrays.asList(R))!=null);
        check(new ToolTurn(true,true,true,true).validate(Arrays.asList(R))!=null);
        check("auto".equals(noSearch.toolChoice()));
        noSearch.attempt(R);
        check("none".equals(noSearch.toolChoice()));
        check(noSearch.validate(Arrays.asList(R))!=null);
        check(enabled().validate(Arrays.asList(R,R))!=null);
        for(String other:Arrays.asList("web_search","didi_ride","create_todo","knowledge_query","knowledge_query_status")){
            ToolTurn t=enabled();
            check(t.validate(Arrays.asList(R,other))!=null);
            check(t.validate(Arrays.asList(other,R))!=null);
            check(t.validate(Arrays.asList(other))==null);
            t.attempt(other);
            check(t.validate(Arrays.asList(R))!=null);
            ToolTurn r=enabled();r.attempt(R);
            check(r.validate(Arrays.asList(other))!=null);
        }
        check(!RayneoCaptureSupport.available());
        System.out.println("PASS "+checks+" Rayneo private-tool isolation/capture-disabled checks");
    }
}
