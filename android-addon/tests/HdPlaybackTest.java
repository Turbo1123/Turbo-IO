package com.turboio.addon;

/** Regression: pause/resume must not seek past the paused video content. No Android/device needed. */
public final class HdPlaybackTest {
    private static int checks;
    private static void at(HdPlayback p,double now,double expected){
        checks++;
        if(Math.abs(p.position(now)-expected)>0.000001)throw new AssertionError("position at "+now+": "+p.position(now)+" != "+expected);
    }
    public static void main(String[] args){
        HdPlayback p=new HdPlayback(100);
        at(p,100,0);at(p,110,10);
        p.paused(true,110);at(p,115,10);
        // Repeated PAUSE events and PING state readbacks cannot restart the pause interval.
        p.paused(true,118);at(p,120,10);
        p.paused(false,120);at(p,120,10);at(p,121,11);
        p.paused(false,122);at(p,123,13);
        p.paused(true,125);at(p,200,15);
        p.paused(false,200);at(p,201,16);
        HdPlayback fresh=new HdPlayback(300);at(fresh,300,0);at(fresh,301,1);
        fresh.paused(true,301);at(fresh,10000,1);
        System.out.println("HdPlaybackTest: "+checks+" checks; paused media time, duplicate state, multiple pauses and new session");
    }
}
