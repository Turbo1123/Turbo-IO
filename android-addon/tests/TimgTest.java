package com.turboio.addon;
import java.nio.file.*;import java.util.*;

/** TIMG v2 single image (TVP2 image-upload-test, wide) and the iOS TIOImageUpload state machine. */
public final class TimgTest {
    static int n;static void ok(boolean b,String why){n++;if(!b)throw new AssertionError("timg "+n+" "+why);}
    public static void main(String[] a)throws Exception{
        byte[] px=new byte[Timg.PIXELS];for(int i=0;i<px.length;i++)px[i]=(byte)(i%251);
        ok(Arrays.equals(Timg.packet(px,77,1),Files.readAllBytes(Paths.get(a[0]).resolve("packet.bin"))),"packet byte-identical to the firmware-accepted reference");
        ok(Timg.packet(px,0,1)==null&&Timg.packet(px,77,0)==null&&Timg.packet(new byte[10],77,1)==null,"invalid packet refused");
        int[] r=Timg.fit(1024,1024);ok(r[0]==192&&r[1]==0&&r[2]==128&&r[3]==128,"fit square "+Arrays.toString(r));
        r=Timg.fit(4000,500);ok(r[2]==512&&r[3]==64&&r[1]==32,"fit wide "+Arrays.toString(r));
        int[] argb=new int[Timg.PIXELS];Arrays.fill(argb,0xffffffff);argb[1]=0xff000000;argb[2]=0xffff0000;byte[] g=Timg.luma(argb);ok((g[0]&255)==255&&g[1]==0&&(g[2]&255)==76,"luma");
        // State machine (iOS TIOImageUpload).
        List<Object[]> sent=new ArrayList<>();ImageUpload u=new ImageUpload((pkt,dev,task,submitted)->{sent.add(new Object[]{pkt,dev,task,submitted});});
        ok(u.state().equals("receiver_not_verified")&&!u.send(px,10),"needs authorization");
        ok(u.authorize("AA",77,10)&&u.state().equals("ready"),"authorize");ok(u.send(px,11)&&u.state().equals("submitting"),"send");
        @SuppressWarnings("unchecked") java.util.function.Consumer<Boolean> sub=(java.util.function.Consumer<Boolean>)sent.get(0)[3];sub.accept(true);ok(u.state().equals("transferring"),"transferring");
        u.fileResult("AA",(String)sent.get(0)[2],true);ok(u.state().equals("file_received_waiting_renderer"),"file received");
        ok(!u.send(px,11.5),"one in flight / 1 s apart");
        ImageUpload t=new ImageUpload((pkt,dev,task,s2)->{});t.authorize("AA",77,0);t.send(px,1);t.tick(16.1);ok(t.state().equals("timeout_result_unknown")&&!t.send(px,20),"timeout unknown, no retry");
        ImageUpload e=new ImageUpload((pkt,dev,task,s2)->{});e.authorize("AA",77,0);e.tick(30);ok(e.state().equals("session_expired")&&!e.send(px,30.5),"30 s window");
        ImageUpload d=new ImageUpload((pkt,dev,task,s2)->{});d.authorize("AA",77,0);d.send(px,1);d.disconnect();ok(d.state().equals("disconnected_result_unknown"),"disconnect while pending");
        ImageUpload f=new ImageUpload((pkt,dev,task,s2)->{});f.authorize("AA",77,0);f.send(px,1);f.fileResult("BB","x",false);ok(f.state().equals("submitting"),"foreign file result ignored");
        // Uncertain transport outcome is not a definite failure (iOS: only failed/rejected is file_failed).
        ImageUpload q=new ImageUpload((pkt,dev,task,s2)->{});q.authorize("AA",77,0);q.send(px,1);q.fileOutcome("AA",q.task(),TransferGate.State.UNCERTAIN);ok(q.state().equals("timeout_result_unknown")&&!q.send(px,3),"uncertain → result unknown, no retry");
        ImageUpload w=new ImageUpload((pkt,dev,task,s2)->{});w.authorize("AA",77,0);w.send(px,1);w.fileOutcome("AA",w.task(),TransferGate.State.FAILED);ok(w.state().equals("file_failed"),"failed → file_failed");
        ImageUpload c=new ImageUpload((pkt,dev,task,s2)->{});c.authorize("AA",77,0);c.send(px,1);c.fileOutcome("AA",c.task(),TransferGate.State.CONFIRMED);ok(c.state().equals("file_received_waiting_renderer"),"confirmed → file received");
        // A throwing sender must not escape into the host; it becomes a submission failure.
        ImageUpload x=new ImageUpload((pkt,dev,task,s2)->{throw new IllegalArgumentException();});x.authorize("AA",77,0);ok(x.send(px,1)&&x.state().equals("submission_failed"),"sender exception → submission_failed");
        System.out.println("TimgTest: "+n+" checks; golden packet, fit, luma, state machine");
    }
}
