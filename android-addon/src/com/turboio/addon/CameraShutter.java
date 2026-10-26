package com.turboio.addon;

/** Shutter timing for the TCM1 camera, free of Camera2 so it can be tested: a press only counts
 * while the capture session exists (never replayed later), countdown, cancel, 3 s review,
 * 1 s error, 20 s capture timeout without retake. Times are seconds on a monotonic clock. */
final class CameraShutter {
    static final int[] DELAYS={0,3,5,10};
    static final class Step{boolean capture,timedOut;int phase,remaining;}
    private final int delay;private int phase=CameraCodec.LIVE;private boolean capturing;
    private double countdown,startedAt,reviewUntil,errorUntil;
    CameraShutter(int delayIndex){delay=DELAYS[Math.max(0,Math.min(DELAYS.length-1,delayIndex))];}
    int phase(){return phase;}boolean capturing(){return capturing;}
    /** True when the photo must be taken now. */
    boolean press(double now,boolean sessionReady){
        if(!sessionReady||capturing||phase==CameraCodec.COUNTDOWN)return false;
        if(delay==0)return begin(now);
        countdown=now+delay;phase=CameraCodec.COUNTDOWN;return false;
    }
    void cancel(){if(!capturing){countdown=0;phase=CameraCodec.LIVE;}}
    private boolean begin(double now){countdown=0;capturing=true;startedAt=now;phase=CameraCodec.CAPTURING;return true;}
    Step tick(double now,boolean sessionReady,boolean reviewBusy){
        Step s=new Step();
        if(phase==CameraCodec.COUNTDOWN){if(!sessionReady)cancel();else if(now>=countdown)s.capture=begin(now);}
        if(capturing&&now-startedAt>20)s.timedOut=true;
        if(phase==CameraCodec.SAVED&&!reviewBusy){if(reviewUntil==0)reviewUntil=now+3;else if(now>reviewUntil){phase=CameraCodec.LIVE;reviewUntil=0;}}
        if(phase==CameraCodec.ERROR&&now>=errorUntil)phase=CameraCodec.LIVE;
        s.phase=phase;s.remaining=phase==CameraCodec.COUNTDOWN?(int)Math.max(0,Math.ceil(countdown-now)):0;return s;
    }
    void saved(double now,boolean ok){capturing=false;if(ok){phase=CameraCodec.SAVED;reviewUntil=0;}else{phase=CameraCodec.ERROR;errorUntil=now+1;}}
    /** Back camera JPEG rotation: sensor orientation plus device rotation rounded to 90; unknown (-1) keeps the sensor value. */
    static int jpegOrientation(int sensor,int device){if(device<0)return ((sensor%360)+360)%360;int d=((device+45)/90*90)%360;return (sensor+d)%360;}
}
