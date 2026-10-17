import com.turboio.addon.AlwaysOnConsume;
import com.turboio.addon.RayneoContextProtocol;
import com.turboio.addon.RayneoContextQueue;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.*;

/** Behavioral fixtures only; no device, private queue, network or Android preferences. */
public final class AlwaysOnWindowTest {
    private static int checks;
    private static void check(boolean value) { checks++; if (!value) throw new AssertionError("window check " + checks); }
    public static final class Payload {
        final String id, text;
        Payload(String id, String text) { this.id=id; this.text=text; }
        public boolean getFinished() { return true; }
        public String getText() { return text; }
        public String getRoundId() { return id; }
        public String getRole() { return "user"; }
    }
    private static AlwaysOnConsume.Segment segment(String id, String text, long time) {
        return AlwaysOnConsume.accept(new Payload(id,text),time,"test-source","test-recording");
    }
    private static String ack(RayneoContextQueue.Record row) {
        return "{\"ok\":true,\"source\":\"rayneo\",\"segment_id\":\""+row.segmentId
            +"\",\"revision\":"+row.revision+",\"raw_id\":\"raw-test\",\"canonical_id\":\"canonical-test\",\"effect\":\"ingested\"}";
    }
    private static void string(DataOutputStream out,String s)throws Exception {
        byte[] bytes=s.getBytes(StandardCharsets.UTF_8);out.writeInt(bytes.length);out.write(bytes);
    }
    private static byte[] legacy(File dir,int count)throws Exception {
        dir.mkdirs();File f=new File(dir,"rayneo-context-v2.dat");
        try(DataOutputStream out=new DataOutputStream(new FileOutputStream(f))) {
            out.writeInt(3);out.writeLong(0);out.writeLong(count+1);out.writeLong(0);out.writeInt(count);out.writeInt(count);
            for(int i=0;i<count;i++) {
                AlwaysOnConsume.Segment s=segment("old-"+i,"retained-text-"+i,100);
                for(String v:new String[]{s.id,s.sourceInstance,s.segmentId,"old-"+i,"user",s.text})string(out,v);
                out.writeLong(100);out.writeLong(100);out.writeInt(1);out.writeInt(0);out.writeLong(i+1);out.writeInt(0);string(out,"");
            }
            out.writeInt(0);
        }
        return Files.readAllBytes(f.toPath());
    }
    private static String retainedDigest(RayneoContextQueue q) {
        StringBuilder out=new StringBuilder();
        for(RayneoContextQueue.Record r:q.snapshot())if(r.windowId==0)
            out.append(r.id).append('|').append(r.sourceInstance).append('|').append(r.segmentId)
                .append('|').append(r.roundId).append('|').append(r.role).append('|').append(r.text)
                .append('|').append(r.receivedTimeMs).append('|').append(r.updatedTimeMs)
                .append('|').append(r.revision).append('|').append(r.ackedRevision).append('|').append(r.seq)
                .append('|').append(r.attempts).append('|').append(r.lastError).append('\n');
        return out.toString();
    }
    public static void main(String[] args)throws Exception {
        File root=Files.createTempDirectory("rayneo-window-").toFile();
        File fullDir=new File(root,"full");byte[] original=legacy(fullDir,256);
        RayneoContextQueue full=new RayneoContextQueue(fullDir,256);
        check(full.size()==256 && full.canStartWindow());String retained=retainedDigest(full);
        check(full.beginWindow(200));long window=full.windowId();
        check(full.activeCount()==0 && full.retainedCount()==256 && full.recordingReady());
        check(Arrays.equals(original,Files.readAllBytes(new File(fullDir,"rayneo-context-pre-window-v3.dat").toPath())));
        check(full.beginWindow(200) && full.windowId()==window); // same committed request, no reclassification
        RayneoContextQueue.IngestResult added=full.ingest(segment("new","synthetic current window",201));
        check(added.accepted && added.persisted && added.record.windowId==window);
        check(full.ingest(segment("new","synthetic current window",202)).duplicate);
        check(full.size()==257 && full.activeCount()==1 && full.retainedCount()==256);
        check(!full.ingest(segment("old-0","changed old callback",202)).accepted);
        check(retained.equals(retainedDigest(full)));
        check(!full.ack(full.snapshot().get(0).id,1).accepted);
        RayneoContextQueue restarted=new RayneoContextQueue(fullDir,256);
        check(restarted.windowId()==window && restarted.windowOpen() && restarted.activeCount()==1);
        check(retained.equals(retainedDigest(restarted)));
        final int[] calls={0};final RayneoContextQueue deliveryQueue=restarted;
        RayneoContextProtocol.Poster poster=(path,body)->{
            calls[0]++;check(!body.contains("retained-text-"));check(body.contains("synthetic current window"));
            check(!deliveryQueue.beginWindow(300)); // a new boundary cannot race an in-flight request
            return RayneoContextProtocol.HttpResult.success(200,ack(added.record));
        };
        check(!RayneoContextProtocol.deliverWindow(restarted,poster,true,8,window+1).acked && calls[0]==0);
        RayneoContextProtocol.DeliveryResult delivered=RayneoContextProtocol.deliverWindow(restarted,poster,true,8,window);
        check(delivered.sent==1 && calls[0]==1 && delivered.skippedOld==256);
        check(restarted.activeCount()==0 && restarted.retainedCount()==256 && restarted.pendingCount()==256);
        check(restarted.ack(added.record.id,1).idempotent);
        check(retained.equals(retainedDigest(restarted)));
        check(restarted.lastSuccessfulAckMs()>0);
        check(new RayneoContextQueue(fullDir,256).lastSuccessfulAckMs()==restarted.lastSuccessfulAckMs());
        check(restarted.closeWindow());check(restarted.beginWindow(300));
        check(restarted.windowId()==window+1 && restarted.recordingReady());
        check(!restarted.ingest(segment("new","late revision from acknowledged old window",301)).accepted);
        RayneoContextQueue.IngestResult second=restarted.ingest(segment("second","second window",301));check(second.accepted);
        check(restarted.closeWindow());check(!restarted.canStartWindow());
        byte[] beforeRefusal=Files.readAllBytes(new File(fullDir,"rayneo-context-v2.dat").toPath());
        check(!restarted.beginWindow(400));check(Arrays.equals(beforeRefusal,Files.readAllBytes(new File(fullDir,"rayneo-context-v2.dat").toPath())));
        check(restarted.windowId()==window+1 && !restarted.windowOpen());
        check(!RayneoContextProtocol.deliverWindow(restarted,poster,true,8,restarted.windowId()).acked);
        check(restarted.resumeWindow());check(restarted.windowId()==window+1);
        check(restarted.ack(second.record.id,second.record.revision).accepted);
        check(restarted.closeWindow() && restarted.beginWindow(400));
        check(restarted.retainedCount()==256 && restarted.activeCount()==0);

        // A clock jump must not promote existing rows. Membership is a durable generation, not time.
        RayneoContextQueue clocks=new RayneoContextQueue(new File(root,"clock"),2);
        RayneoContextQueue.IngestResult future=clocks.ingest(segment("future","old future timestamp",999999));
        check(clocks.beginWindow(100));check(clocks.retainedCount()==1);
        final int[] clockPosts={0};
        check(RayneoContextProtocol.deliverWindow(clocks,(p,b)->{clockPosts[0]++;return null;},true,8,clocks.windowId()).sent==0);
        check(clockPosts[0]==0 && clocks.size()==1);
        check(clocks.closeWindow());RayneoContextQueue.IngestResult paused=clocks.ingest(segment("paused","not authorized for window",200));
        check(paused.accepted && paused.record.windowId==0);check(clocks.resumeWindow());
        check(clocks.activeCount()==0 && clocks.retainedCount()==2);

        // Active revisions and exact ACKs survive restart without consuming retained capacity.
        RayneoContextQueue rev=new RayneoContextQueue(new File(root,"revision"),2);check(rev.beginWindow(100));
        RayneoContextQueue.IngestResult r1=rev.ingest(segment("r","one",101));
        RayneoContextQueue.IngestResult r2=rev.ingest(segment("r","two",102));
        check(r2.record.revision==2 && r2.record.windowId==r1.record.windowId);
        check(rev.ack(r1.record.id,1).stale);check(rev.pendingCount()==1);
        rev=new RayneoContextQueue(new File(root,"revision"),2);check(rev.pending().get(0).revision==2);
        check(rev.ack(r2.record.id,2).accepted);check(rev.ack(r2.record.id,2).idempotent);

        File activeDir=new File(root,"active-bound");RayneoContextQueue active=new RayneoContextQueue(activeDir,2);
        check(active.beginWindow(100));
        RayneoContextQueue.Record a=active.ingest(segment("a","active-a",101)).record;
        RayneoContextQueue.Record b=active.ingest(segment("b","active-b",102)).record;
        check(!active.recordingReady() && active.activeCount()==2);
        check(active.ingest(segment("overflow","must stay bounded",103)).overflow);
        // A confirmed network response with failed local ACK persistence must retain the exact revision.
        File ackBlocked=new File(activeDir,"rayneo-context-v2.dat.tmp");check(ackBlocked.mkdir());
        check(!active.ack(a.id,1).persisted && active.activeCount()==2);ackBlocked.delete();
        active=new RayneoContextQueue(activeDir,2);check(active.pending().get(0).id.equals(a.id));
        final RayneoContextQueue closing=active;final int[] closePosts={0};
        RayneoContextProtocol.DeliveryResult closed=RayneoContextProtocol.deliverWindow(active,(p,body)->{
            closePosts[0]++;check(closing.closeWindow());
            return RayneoContextProtocol.HttpResult.success(200,ack(a));
        },true,8,active.windowId());
        check(closed.sent==1 && closePosts[0]==1 && active.activeCount()==1);
        check(active.pending().get(0).id.equals(b.id) && !active.windowOpen());
        check(active.resumeWindow());check(active.ack(b.id,1).accepted && active.recordingReady());

        // Failed first migration keeps both memory and original bytes unchanged; retry is safe.
        File failDir=new File(root,"failed-transition");byte[] old=legacy(failDir,2);
        RayneoContextQueue failed=new RayneoContextQueue(failDir,2);
        File obstruction=new File(failDir,"rayneo-context-v2.dat.tmp");check(obstruction.mkdir());
        check(!failed.beginWindow(200));check(failed.windowId()==0 && failed.size()==2);
        check(Arrays.equals(old,Files.readAllBytes(new File(failDir,"rayneo-context-v2.dat").toPath())));
        check(new RayneoContextQueue(failDir,2).windowId()==0);
        obstruction.delete();check(failed.beginWindow(200));
        check(failed.ingest(segment("safe","saved new row",201)).accepted);
        check(failed.closeWindow());
        // Resume persistence failure does not mark the window open.
        check(obstruction.mkdir());check(!failed.resumeWindow());check(!failed.windowOpen());obstruction.delete();
        RayneoContextQueue afterFailure=new RayneoContextQueue(failDir,2);check(!afterFailure.windowOpen());check(afterFailure.resumeWindow());

        // Crash-style partial staging is ignored; corrupt main recovers the last committed backup.
        Files.write(new File(failDir,"rayneo-context-v2.dat.tmp").toPath(),new byte[]{7,8,9});
        check(new RayneoContextQueue(failDir,2).size()==3);
        Files.write(new File(failDir,"rayneo-context-v2.dat").toPath(),new byte[]{1,2,3});
        RayneoContextQueue recovered=new RayneoContextQueue(failDir,2);
        check(recovered.recoveredFromBackup() && recovered.retainedCount()==2 && recovered.activeCount()==1);
        // Never silently start empty or overwrite originals when both committed copies are corrupt.
        Files.write(new File(failDir,"rayneo-context-v2.bak").toPath(),new byte[]{4,5,6});
        RayneoContextQueue corrupt=new RayneoContextQueue(failDir,2);
        check(!corrupt.beginWindow(500));check(!corrupt.ingest(segment("blocked","must not overwrite",501)).accepted);
        check(Arrays.equals(new byte[]{1,2,3},Files.readAllBytes(new File(failDir,"rayneo-context-v2.dat").toPath())));
        check(Arrays.equals(new byte[]{4,5,6},Files.readAllBytes(new File(failDir,"rayneo-context-v2.bak").toPath())));
        File v2Dir=new File(root,"legacy-v2");byte[] v2=legacy(v2Dir,1);v2[3]=2;
        Files.write(new File(v2Dir,"rayneo-context-v2.dat").toPath(),v2);
        RayneoContextQueue oldV2=new RayneoContextQueue(v2Dir,1);check(oldV2.size()==1 && oldV2.beginWindow(100));
        check(oldV2.retainedCount()==1 && oldV2.recordingReady());
        check(Arrays.equals(v2,Files.readAllBytes(new File(v2Dir,"rayneo-context-pre-window-v3.dat").toPath())));
        System.out.println("PASS "+checks+" window capacity/recovery checks");
    }
}
