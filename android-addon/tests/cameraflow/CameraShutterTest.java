package com.turboio.addon;

/** Shutter timing and photo orientation, independent of Camera2. */
public final class CameraShutterTest {
    static int n;static void ok(boolean b,String why){n++;if(!b)throw new AssertionError("shutter "+n+" "+why);}
    public static void main(String[] a){
        // A press before the capture session exists is dropped, never replayed later.
        CameraShutter s=new CameraShutter(0);ok(!s.press(1,false),"no session → dropped");ok(s.phase()==CameraCodec.LIVE,"stays live");
        for(double t=1;t<30;t+=.05)ok(!s.tick(t,true,false).capture,"never fires later");
        // Immediate shutter, then nothing until the capture completes.
        ok(s.press(30,true)&&s.phase()==CameraCodec.CAPTURING,"immediate capture");ok(!s.press(30.1,true),"no second capture while busy");
        s.saved(31,true);ok(s.phase()==CameraCodec.SAVED,"saved");
        // Review stays 3 s once the thumbnail has been delivered, then live again.
        ok(s.tick(32,true,true).phase==CameraCodec.SAVED,"review pending thumbnail");ok(s.tick(32.1,true,false).phase==CameraCodec.SAVED,"review starts");ok(s.tick(35.2,true,false).phase==CameraCodec.LIVE,"back to live");
        // Countdown: remaining seconds reported, capture exactly once at zero; cancel aborts it.
        CameraShutter d=new CameraShutter(1);ok(!d.press(100,true)&&d.phase()==CameraCodec.COUNTDOWN,"countdown");
        CameraShutter.Step st=d.tick(101,true,false);ok(!st.capture&&st.remaining==2,"remaining 2");st=d.tick(103,true,false);ok(st.capture&&d.phase()==CameraCodec.CAPTURING,"fires at zero");ok(!d.tick(103.05,true,false).capture,"once");
        CameraShutter c=new CameraShutter(2);c.press(200,true);c.cancel();ok(c.phase()==CameraCodec.LIVE,"cancel");for(double t=200;t<210;t+=.05)ok(!c.tick(t,true,false).capture,"cancelled never fires");
        // A session that disappears during a countdown cancels it instead of firing later.
        CameraShutter g=new CameraShutter(1);g.press(300,true);ok(!g.tick(303.1,false,false).capture&&g.phase()==CameraCodec.LIVE,"lost session cancels");
        // Capture that never completes: stop after 20 s, never retake.
        CameraShutter t=new CameraShutter(0);t.press(400,true);ok(!t.tick(419,true,false).timedOut,"within 20 s");ok(t.tick(420.1,true,false).timedOut,"timeout");
        // Failure shows ERROR for 1 s, then live; a new press is allowed again.
        CameraShutter f=new CameraShutter(0);f.press(500,true);f.saved(501,false);ok(f.phase()==CameraCodec.ERROR,"error");ok(f.tick(501.5,true,false).phase==CameraCodec.ERROR,"error shown");ok(f.tick(502.1,true,false).phase==CameraCodec.LIVE,"then live");ok(f.press(503,true),"press again");
        // JPEG orientation for a back camera: sensor + device rotation (rounded to 90).
        ok(CameraShutter.jpegOrientation(90,0)==90&&CameraShutter.jpegOrientation(90,90)==180&&CameraShutter.jpegOrientation(90,270)==0&&CameraShutter.jpegOrientation(90,180)==270,"sensor 90");
        ok(CameraShutter.jpegOrientation(90,44)==90&&CameraShutter.jpegOrientation(90,46)==180&&CameraShutter.jpegOrientation(90,350)==90&&CameraShutter.jpegOrientation(270,90)==0,"rounding");
        ok(CameraShutter.jpegOrientation(90,-1)==90,"unknown orientation keeps sensor");
        System.out.println("CameraShutterTest: "+n+" checks; no late shutter, countdown, cancel, review, timeout, orientation");
    }
}
