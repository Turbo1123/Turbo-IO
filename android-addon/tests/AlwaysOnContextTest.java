import com.turboio.addon.AlwaysOnConsume;
import com.turboio.addon.RayneoContextProtocol;
import com.turboio.addon.RayneoContextQueue;
import com.turboio.addon.RayneoCurrentQuestion;
import com.turboio.addon.RayneoQueryBridge;
import com.turboio.addon.RayneoSourceIdentity;
import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.List;
import java.util.Map;
import java.util.UUID;

public final class AlwaysOnContextTest {
    private static int checks;
    private static void check(boolean value) {
        checks++;
        if (!value) throw new AssertionError("check " + checks);
    }

    static final class Payload {
        boolean finished;
        String text, roundId, role, sessionId;
        Number roleNumber;
        Payload(boolean finished, String text, String roundId, String role) {
            this.finished = finished;
            this.text = text;
            this.roundId = roundId;
            this.role = role;
        }
        public boolean getFinished() { return finished; }
        public String getText() { return text; }
        public String getRoundId() { return roundId; }
        public Object getRole() { return roleNumber != null ? roleNumber : role; }
        public String getSessionId() { return sessionId; }
    }

    static final class Listener {
        int calls;
        Object last;
        public void onAlwaysOnResponse(Payload payload) { calls++; last = payload; }
    }

    static final class WrappedListener {
        int original;
        int wrapper;
        public void turboioOriginal_onAlwaysOnResponse(Payload payload) { original++; }
        public void onAlwaysOnResponse(Payload payload) { wrapper++; }
    }

    static final class ThrowingListener {
        public void onAlwaysOnResponse(Payload payload) { throw new RuntimeException("host"); }
    }

    public static void main(String[] args) throws Exception {
        check("onAlwaysOnResponse(Lcom/rayneo/airuntime/controller/RayNeoAlwaysOnResponse;)V"
            .equals(AlwaysOnConsume.JNI_SIGNATURE));
        check("com.rayneo.airuntime.controller.RayNeoAlwaysOnResponse".equals(AlwaysOnConsume.PAYLOAD_TYPE));

        File root = Files.createTempDirectory("rayneo-ctx-").toFile();
        RayneoSourceIdentity identity = RayneoSourceIdentity.loadOrCreate(new File(root, "id"));
        RayneoSourceIdentity again = RayneoSourceIdentity.loadOrCreate(new File(root, "id"));
        check(identity.sourceInstance.equals(again.sourceInstance));
        check(identity.recordingSession.equals(again.recordingSession));
        check(identity.sourceInstance.startsWith("rayneo-android-"));

        RayneoContextQueue queue = new RayneoContextQueue(new File(root, "q1"), 2);
        Listener listener = new Listener();
        long now = 1_700_000_000_000L;

        Payload partial = new Payload(false, "draft", "r1", "user");
        check(AlwaysOnConsume.dispatch(listener, partial, queue, now));
        check(listener.calls == 1);
        check(queue.size() == 0);

        Payload first = new Payload(true, "buy milk later", "r1", "user");
        check(AlwaysOnConsume.dispatch(listener, first, queue, now));
        check(listener.calls == 2);
        check(queue.size() == 1);
        AlwaysOnConsume.Segment accepted = AlwaysOnConsume.accept(first, now, "inst-a", "rec-a");
        check(accepted != null);
        check("inst-a".equals(accepted.sourceInstance));
        check(accepted.segmentId.contains("rec-a"));
        check(accepted.segmentId.contains("r1"));
        check(accepted.id.startsWith("inst-a|"));
        check(accepted.sourceTime == null);
        check(accepted.sourceTimeUnknown);
        check(queue.snapshot().get(0).sourceTime == null);

        Payload sameSession = new Payload(true, "other recording", "r1", "user");
        sameSession.sessionId = "rec-b";
        AlwaysOnConsume.Segment otherSession = AlwaysOnConsume.accept(sameSession, now, "inst-a", "rec-a");
        check(otherSession != null);
        check(!accepted.segmentId.equals(otherSession.segmentId));
        check(otherSession.segmentId.startsWith("rec-b:"));

        Payload duplicate = new Payload(true, "buy milk later", "r1", "user");
        RayneoContextQueue.IngestResult replay = queue.ingest(AlwaysOnConsume.accept(duplicate, now + 5));
        check(replay.accepted && replay.duplicate && !replay.revision);
        check(queue.size() == 1);
        check(queue.snapshot().get(0).revision == 1);

        Payload revised = new Payload(true, "buy milk now", "r1", "user");
        RayneoContextQueue.IngestResult rev = queue.ingest(AlwaysOnConsume.accept(revised, now + 10));
        check(rev.accepted && rev.revision);
        check(queue.size() == 1);
        check(queue.snapshot().get(0).revision == 2);
        check("buy milk now".equals(queue.snapshot().get(0).text));

        Payload other = new Payload(true, "weather later", "r2", "user");
        check(AlwaysOnConsume.dispatch(listener, other, queue, now + 20));
        check(queue.size() == 2);

        Payload overflow = new Payload(true, "third unique", "r3", "user");
        RayneoContextQueue.IngestResult overflowed = queue.ingest(AlwaysOnConsume.accept(overflow, now + 30));
        check(!overflowed.accepted && overflowed.overflow);
        check(queue.size() == 2);

        // (a) ACK revision 1 then ingest revision 2 leaves revision 2 pending.
        File revDir = new File(root, "rev");
        RayneoContextQueue revQueue = new RayneoContextQueue(revDir, 8);
        Payload v1 = new Payload(true, "alpha one", "roundA", "user");
        RayneoContextQueue.IngestResult firstRev = revQueue.ingest(AlwaysOnConsume.accept(v1, now, "inst", "rec"));
        check(firstRev.accepted && firstRev.record.revision == 1);
        String revId = firstRev.record.id;
        RayneoContextQueue.AckResult ack1 = revQueue.ack(revId, 1);
        check(ack1.accepted && ack1.persisted);
        check(revQueue.pending().isEmpty());
        Payload v2 = new Payload(true, "alpha two", "roundA", "user");
        RayneoContextQueue.IngestResult secondRev = revQueue.ingest(AlwaysOnConsume.accept(v2, now + 1, "inst", "rec"));
        check(secondRev.accepted && secondRev.revision || secondRev.record.revision == 2);
        check(secondRev.record.revision == 2);
        check(revQueue.pending().size() == 1);
        check(revQueue.unread().get(0).revision == 2);
        check("alpha two".equals(revQueue.unread().get(0).text));

        RayneoContextQueue.AckResult stale = revQueue.ack(revId, 1);
        check(!stale.accepted && stale.stale);
        check(revQueue.pending().size() == 1);
        RayneoContextQueue.AckResult dupAck = revQueue.ack(revId, 2);
        check(dupAck.accepted);
        RayneoContextQueue.AckResult dupAck2 = revQueue.ack(revId, 2);
        check(dupAck2.accepted && dupAck2.idempotent);
        check(revQueue.pending().isEmpty());

        // ACK loss: no ACK, restart still pending.
        File lossDir = new File(root, "loss");
        RayneoContextQueue loss = new RayneoContextQueue(lossDir, 4);
        loss.ingest(AlwaysOnConsume.accept(new Payload(true, "keep me", "loss1", "user"), now, "inst", "rec"));
        check(loss.pendingCount() == 1);
        RayneoContextQueue lossReload = new RayneoContextQueue(lossDir, 4);
        check(lossReload.pendingCount() == 1);
        check("keep me".equals(lossReload.pending().get(0).text));

        // (b) bound=2, ACK both identities, third new identity accepted.
        File capDir = new File(root, "cap");
        RayneoContextQueue cap = new RayneoContextQueue(capDir, 2);
        RayneoContextQueue.IngestResult a = cap.ingest(AlwaysOnConsume.accept(
            new Payload(true, "one", "c1", "user"), now, "inst", "rec"));
        RayneoContextQueue.IngestResult b = cap.ingest(AlwaysOnConsume.accept(
            new Payload(true, "two", "c2", "user"), now, "inst", "rec"));
        check(a.accepted && b.accepted);
        RayneoContextQueue.IngestResult full = cap.ingest(AlwaysOnConsume.accept(
            new Payload(true, "three", "c3", "user"), now, "inst", "rec"));
        check(!full.accepted && full.overflow);
        check(cap.ack(a.record.id, a.record.revision).accepted);
        check(cap.ack(b.record.id, b.record.revision).accepted);
        RayneoContextQueue.IngestResult third = cap.ingest(AlwaysOnConsume.accept(
            new Payload(true, "three", "c3", "user"), now, "inst", "rec"));
        check(third.accepted && !third.overflow);
        RayneoContextQueue.IngestResult fourth = cap.ingest(AlwaysOnConsume.accept(
            new Payload(true, "four", "c4", "user"), now, "inst", "rec"));
        check(fourth.accepted);
        RayneoContextQueue.IngestResult fifth = cap.ingest(AlwaysOnConsume.accept(
            new Payload(true, "five", "c5", "user"), now, "inst", "rec"));
        check(!fifth.accepted && fifth.overflow);

        // (c) unwritable persist target is not accepted-as-durable; last valid remains.
        File persistDir = new File(root, "persist");
        RayneoContextQueue durable = new RayneoContextQueue(persistDir, 4);
        RayneoContextQueue.IngestResult kept = durable.ingest(AlwaysOnConsume.accept(
            new Payload(true, "durable-one", "p1", "user"), now, "inst", "rec"));
        check(kept.accepted && kept.persisted);
        File tmp = new File(persistDir, "rayneo-context-v2.dat.tmp");
        check(tmp.mkdir());
        RayneoContextQueue.IngestResult failed = durable.ingest(AlwaysOnConsume.accept(
            new Payload(true, "durable-two", "p2", "user"), now + 2, "inst", "rec"));
        check(!failed.accepted);
        check(!failed.persisted);
        check(durable.size() == 1);
        check("durable-one".equals(durable.snapshot().get(0).text));
        check(!durable.lastError().isEmpty());
        Files.deleteIfExists(tmp.toPath());
        RayneoContextQueue reloadedPersist = new RayneoContextQueue(persistDir, 4);
        check(reloadedPersist.size() == 1);
        check("durable-one".equals(reloadedPersist.snapshot().get(0).text));

        File corruptDir = new File(root, "corrupt");
        RayneoContextQueue ok = new RayneoContextQueue(corruptDir, 4);
        ok.ingest(AlwaysOnConsume.accept(new Payload(true, "before-corrupt", "k1", "user"), now, "inst", "rec"));
        Files.write(new File(corruptDir, "rayneo-context-v2.dat").toPath(), new byte[]{1, 2, 3, 4});
        RayneoContextQueue recovered = new RayneoContextQueue(corruptDir, 4);
        check(!recovered.loadError().isEmpty());
        check(recovered.recoveredFromBackup() || recovered.size() == 1 || recovered.size() == 0);

        WrappedListener wrapped = new WrappedListener();
        RayneoContextQueue wrapQueue = new RayneoContextQueue(new File(root, "q2"), 8);
        Payload wrapPayload = new Payload(true, "wrapped final", "w1", "assistant");
        check(AlwaysOnConsume.dispatch(wrapped, wrapPayload, wrapQueue, now));
        check(wrapped.original == 1);
        check(wrapped.wrapper == 0);

        ThrowingListener throwing = new ThrowingListener();
        check(!AlwaysOnConsume.dispatch(throwing, wrapPayload, wrapQueue, now));

        Payload numbered = new Payload(true, "role number", "n1", null);
        numbered.roleNumber = Integer.valueOf(0);
        check(AlwaysOnConsume.accept(numbered, now).segmentId.endsWith(":n1:0"));

        RayneoContextQueue wide = new RayneoContextQueue(new File(root, "q3"), 16);
        RayneoCurrentQuestion questions = new RayneoCurrentQuestion(wide);
        Listener asrListener = new Listener();
        for (int i = 0; i < 10; i++) {
            Payload row = new Payload(true, "note " + i + " glasses context", "g" + i, "user");
            AlwaysOnConsume.dispatch(asrListener, row, wide, now - (i == 9 ? 10L * 60L * 1000L : 0));
        }
        check(wide.size() == 10);
        int queriesBeforeAsr = questions.queryCount();
        AlwaysOnConsume.observeAsr(questions, "hello glasses", true, "sid-1");
        AlwaysOnConsume.observeAsr(questions, "partial", false, "sid-1");
        check(questions.asrEvents() == 2);
        check(questions.queryCount() == queriesBeforeAsr);

        Map<String, Object> current = questions.queryCurrent("glasses context", now);
        check("rayneo".equals(current.get("source")));
        check("rayneo-context/v1".equals(current.get("contract_version")));
        check(Boolean.FALSE.equals(current.get("instruction_eligible")));
        check(current.get("answer") == null);
        List<?> currentResults = (List<?>) current.get("results");
        check(!currentResults.isEmpty());
        Map<?, ?> hit = (Map<?, ?>) currentResults.get(0);
        check(hit.get("source_time") == null);
        check(Boolean.TRUE.equals(hit.get("source_time_unknown")));
        check(Boolean.FALSE.equals(hit.get("instruction_eligible")));
        check(hit.get("received_at") instanceof String);
        check(hit.get("segment_id") instanceof String);
        check("transcript".equals(hit.get("text_kind")));

        Map<String, Object> viaTool = RayneoQueryBridge.invokeFromToolRequest(
            RayneoQueryBridge.TOOL_NAME, "glasses context", questions, now);
        check(Boolean.FALSE.equals(viaTool.get("instruction_eligible")));
        check(RayneoQueryBridge.hasUsableResults(viaTool));
        check(!RayneoCurrentQuestion.isInstructions(viaTool));
        check(!RayneoCurrentQuestion.isUserIntent(viaTool));
        check(!RayneoCurrentQuestion.isTaskCreation(viaTool));
        check(!RayneoCurrentQuestion.isOfficialRayNeoAnswer(viaTool));
        boolean refused = false;
        try { RayneoCurrentQuestion.asSystemPrompt(viaTool); } catch (IllegalStateException error) {
            refused = RayneoCurrentQuestion.NOT_INSTRUCTIONS.equals(error.getMessage());
        }
        check(refused);
        boolean intentRefused = false;
        try { RayneoCurrentQuestion.asUserIntentText(viaTool); } catch (IllegalStateException error) {
            intentRefused = true;
        }
        check(intentRefused);

        String jobId = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee";
        Map<String, Object> queued = questions.query("glasses context", RayneoCurrentQuestion.SOURCE, jobId);
        check("queued".equals(queued.get("status")));
        check(RayneoContextProtocol.INTERNAL_ENVELOPE.equals(queued.get("transport")));
        Map<String, Object> done = questions.status(jobId, now);
        check(RayneoContextProtocol.INTERNAL_ENVELOPE.equals(done.get("transport")));
        check(Boolean.FALSE.equals(done.get("instruction_eligible")));
        check(done.get("answer") == null);

        Map<String, Object> empty = RayneoQueryBridge.invokeFromToolRequest(
            RayneoQueryBridge.TOOL_NAME, "zzzz-not-present-xx", questions, now);
        check("empty".equals(empty.get("status")) || ((List<?>) empty.get("results")).isEmpty());
        check(Boolean.FALSE.equals(empty.get("instruction_eligible")));

        Map<String, Object> timeout = RayneoQueryBridge.invokeFromToolRequest(
            RayneoQueryBridge.TOOL_NAME, "glasses", questions,
            new RayneoContextProtocol.Poster() {
                public RayneoContextProtocol.HttpResult post(String path, String body) {
                    return RayneoContextProtocol.HttpResult.timeout();
                }
            }, true, 8, now);
        check("empty".equals(timeout.get("status")));
        check("timeout".equals(timeout.get("error_class")));
        check(!RayneoQueryBridge.hasUsableResults(timeout));

        String turbo = read("src/com/turboio/addon/TurboAddon.java", "android-addon/src/com/turboio/addon/TurboAddon.java");
        check(turbo.contains("public static void dispatchAlwaysOn(Object source, Object response)"));
        check(turbo.contains("AlwaysOnConsume.dispatchDetailed"));
        check(turbo.contains("scheduleRayneoUpload"));
        check(turbo.contains("RayneoQueryBridge.TOOL_NAME"));
        check(turbo.contains("tools.call(RayneoQueryBridge.TOOL_NAME"));
        check(turbo.contains("RayneoQueryBridge.LABELED_DATA_PREFIX"));
        check(!turbo.contains("persona + rayneoCtx"));
        int asrAt = turbo.indexOf("public static void dispatchAsr");
        int nlpAt = turbo.indexOf("public static void dispatchNlp");
        check(asrAt > 0 && nlpAt > asrAt);
        String asrBody = turbo.substring(asrAt, nlpAt);
        check(asrBody.contains("AlwaysOnConsume.observeAsr(rayneoQuestion"));
        check(!asrBody.contains("questions.query") && !asrBody.contains("rayneoQuestion.query")
            && !asrBody.contains("queryCurrent") && !asrBody.contains("RayneoQueryBridge"));
        check(!turbo.contains("RayneoAlwaysOn") && !turbo.contains("RayneoUploader") && !turbo.contains("RayneoBridge"));

        String tools = read("src/com/turboio/addon/ToolClient.java", "android-addon/src/com/turboio/addon/ToolClient.java");
        check(tools.contains("RayneoQueryBridge.invokeConfiguredToolRequest"));
        check(tools.contains("RayneoQueryBridge.TOOL_NAME"));
        check(!tools.contains("/query") || tools.contains("knowledge"));

        System.out.println("PASS " + checks + " always-on context checks");
    }

    private static String read(String a, String b) throws Exception {
        File[] candidates = { new File(a), new File(b) };
        for (int i = 0; i < candidates.length; i++) {
            if (candidates[i].isFile()) {
                byte[] bytes = Files.readAllBytes(candidates[i].toPath());
                return new String(bytes, StandardCharsets.UTF_8);
            }
        }
        throw new IllegalStateException(a);
    }
}
