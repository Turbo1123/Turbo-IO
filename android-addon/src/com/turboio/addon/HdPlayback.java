package com.turboio.addon;

/** Main-thread media timeline. Link deadlines keep using the unpaused monotonic clock. */
final class HdPlayback {
    private final double startedAt;
    private double pausedAt,totalPaused;
    private boolean paused;

    HdPlayback(double now){startedAt=now;}
    void paused(boolean value,double now){
        if(value==paused)return;
        if(value)pausedAt=now;else totalPaused+=now-pausedAt;
        paused=value;
    }
    double position(double now){return Math.max(0,(paused?pausedAt:now)-startedAt-totalPaused);}
}
