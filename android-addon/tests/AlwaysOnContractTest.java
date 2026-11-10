import com.turboio.addon.AlwaysOnConsume;
import com.turboio.addon.RayneoContextProtocol;
import com.turboio.addon.RayneoContextQueue;
import com.turboio.addon.RayneoCurrentQuestion;
import com.turboio.addon.RayneoQueryBridge;
import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

public final class AlwaysOnContractTest {
    private static int checks;
    private static void check(boolean value) {
        checks++;
        if (!value) throw new AssertionError("check " + checks);
    }

    static final class Payload {
        public boolean getFinished() { return true; }
        public String getText() { return "今天讨论了项目Alpha接口"; }
        public String getRoundId() { return "round-alpha"; }
        public String getRole() { return "user"; }
        public String getSessionId() { return "seg-day1-alpha"; }
    }

    static final class FakePoster implements RayneoContextProtocol.Poster {
        final List<String> paths = new ArrayList<String>();
        final List<String> bodies = new ArrayList<String>();
        String queryResponse = "{\"source\":\"rayneo\",\"results\":[{\"text\":\"alpha\",\"revision\":2,"
            + "\"source_time\":null,\"source_time_unknown\":true,\"instruction_eligible\":false}]}";
        int ingestStatus = 200;
        String ingestError;
        String ackBody = "{}";
        public RayneoContextProtocol.HttpResult post(String path, String jsonBody) {
            paths.add(path);
            bodies.add(jsonBody);
            if (RayneoContextProtocol.INGEST_PATH.equals(path)) {
                if (ingestError != null) return RayneoContextProtocol.HttpResult.error(ingestError);
                return RayneoContextProtocol.HttpResult.success(ingestStatus, ackBody);
            }
            if (RayneoContextProtocol.QUERY_PATH.equals(path)) {
                return RayneoContextProtocol.HttpResult.success(200, queryResponse);
            }
            return RayneoContextProtocol.HttpResult.error("unexpected_path");
        }
    }

    public static void main(String[] args) throws Exception {
        String contract = readContract();
        check(contract.contains("\"contract_version\": \"rayneo-context/v1\""));
        check(contract.contains("\"path\": \"/ingest\""));
        check(contract.contains("\"path\": \"/v1/rayneo/query\""));
        check(contract.contains("\"path\": \"/v1/rayneo/control\""));
        check(contract.contains("\"source_time\": null"));
        check(contract.contains("\"source_time_unknown\": true"));
        check(contract.contains("\"instruction_eligible\": false"));
        check(contract.contains("\"source_instance\""));
        check(contract.contains("\"segment_id\""));
        check(contract.contains("\"dedup_key\""));
        check(!contract.contains("\"path\": \"/query\""));
        check(!contract.contains("/jobs/{id}"));

        check(RayneoContextProtocol.INGEST_PATH.equals("/ingest"));
        check(RayneoContextProtocol.QUERY_PATH.equals("/v1/rayneo/query"));
        check(RayneoContextProtocol.CONTROL_PATH.equals("/v1/rayneo/control"));
        check(RayneoContextProtocol.INTERNAL_QUERY_PATH.equals("/query"));
        check(RayneoContextProtocol.SOURCE.equals("rayneo"));
        check(RayneoContextProtocol.CONTRACT_VERSION.equals("rayneo-context/v1"));

        File root = Files.createTempDirectory("rayneo-b-").toFile();
        RayneoContextQueue queue = new RayneoContextQueue(new File(root, "q"), 8);
        AlwaysOnConsume.Segment segment = AlwaysOnConsume.accept(new Payload(), 1_700_000_000_000L,
            "rayneo-g6b-fixture-1", "rec-keep");
        check(segment != null);
        check("rayneo-g6b-fixture-1".equals(segment.sourceInstance));
        check(segment.segmentId.startsWith("seg-day1-alpha:"));
        check(segment.sourceTime == null);
        check(segment.sourceTimeUnknown);
        RayneoContextQueue.IngestResult ingested = queue.ingest(segment);
        check(ingested.accepted);

        Map<String, Object> event = RayneoContextProtocol.ingestEvent(ingested.record);
        check("rayneo".equals(event.get("source")));
        check("rayneo-context/v1".equals(event.get("contract_version")));
        check(("rayneo:" + ingested.record.sourceInstance + ":" + ingested.record.segmentId)
            .equals(event.get("dedup_key")));
        Map<?, ?> payload = (Map<?, ?>) event.get("payload");
        check(payload.get("source_time") == null);
        check(Boolean.TRUE.equals(payload.get("source_time_unknown")));
        check(payload.get("received_at") instanceof String);
        check("rayneo-g6b-fixture-1".equals(payload.get("source_instance")));
        check(ingested.record.segmentId.equals(payload.get("segment_id")));
        check(Boolean.TRUE.equals(((Map<?, ?>) payload.get("coverage")) != null));

        String json = RayneoContextProtocol.ingestJson(ingested.record);
        check(json.contains("\"source\":\"rayneo\""));
        check(json.contains("\"contract_version\":\"rayneo-context/v1\""));
        check(json.contains("\"source_time\":null"));
        check(json.contains("\"source_time_unknown\":true"));
        check(json.contains("\"received_at\""));
        check(json.contains("\"dedup_key\""));
        check(json.contains("\"segment_id\""));
        check(!json.contains("\"source_time\":\"unknown\""));

        String queryJson = RayneoContextProtocol.queryJson("项目Alpha", 8);
        check(queryJson.contains("\"source\":\"rayneo\""));
        check(queryJson.contains("\"topic\":\"项目Alpha\""));
        check(queryJson.contains("\"limit\":8"));

        FakePoster fake = new FakePoster();
        fake.ackBody = "{\"ok\":true,\"source\":\"rayneo\",\"segment_id\":\"" + ingested.record.segmentId
            + "\",\"revision\":1,\"raw_id\":\"raw-1\",\"canonical_id\":\"can-1\",\"effect\":\"ingested\"}";
        RayneoContextProtocol.DeliveryResult delivered = RayneoContextProtocol.deliver(queue, fake, true, 8);
        check("ok".equals(delivered.status));
        check(delivered.acked);
        check(fake.paths.size() == 1);
        check(RayneoContextProtocol.INGEST_PATH.equals(fake.paths.get(0)));
        check(queue.pending().isEmpty());

        RayneoContextQueue still = new RayneoContextQueue(new File(root, "q"), 8);
        check(still.pending().isEmpty());

        FakePoster unconfigured = new FakePoster();
        RayneoContextQueue local = new RayneoContextQueue(new File(root, "local"), 8);
        local.ingest(AlwaysOnConsume.accept(new Payload(), 1_700_000_000_100L, "inst-2", "rec-2"));
        RayneoContextProtocol.DeliveryResult skipped = RayneoContextProtocol.deliver(local, unconfigured, false, 8);
        check("local_only".equals(skipped.status));
        check(!skipped.acked);
        check(unconfigured.paths.isEmpty());
        check(local.pendingCount() == 1);

        FakePoster denied = new FakePoster();
        denied.ingestError = "permission";
        RayneoContextProtocol.DeliveryResult noAck = RayneoContextProtocol.deliver(local, denied, true, 8);
        check(!noAck.acked);
        check("stopped_first_error".equals(noAck.status));
        check("permission".equals(noAck.lastError) || noAck.lastError.contains("permission"));
        check(local.pendingCount() == 1);

        RayneoContextQueue mismatchQueue = new RayneoContextQueue(new File(root, "mismatch"), 8);
        RayneoContextQueue.IngestResult mismatchRow = mismatchQueue.ingest(AlwaysOnConsume.accept(
            new Payload(), 1_700_000_000_300L, "inst-3", "rec-3"));
        FakePoster emptyAck = new FakePoster();
        RayneoContextProtocol.DeliveryResult mismatch = RayneoContextProtocol.deliver(
            mismatchQueue, emptyAck, true, 8);
        check("stopped_first_error".equals(mismatch.status));
        check("protocol_mismatch".equals(mismatch.lastError));
        check(!mismatch.acked);
        check(mismatchQueue.pendingCount() == 1);

        FakePoster staleIgnored = new FakePoster();
        staleIgnored.ackBody = "{\"ok\":true,\"source\":\"rayneo\",\"segment_id\":\""
            + mismatchRow.record.segmentId + "\",\"revision\":1,\"raw_id\":\"raw-s\",\"canonical_id\":\"can-s\",\"effect\":\"stale_ignored\"}";
        RayneoContextProtocol.DeliveryResult staleResult = RayneoContextProtocol.deliver(
            mismatchQueue, staleIgnored, true, 8);
        check("stopped_first_error".equals(staleResult.status));
        check("stale_ignored".equals(staleResult.lastError));
        check(!staleResult.acked);
        check(mismatchQueue.pendingCount() == 1);

        RayneoContextQueue window = new RayneoContextQueue(new File(root, "window"), 8);
        window.ingest(AlwaysOnConsume.accept(new Payload(), 100L, "inst-old", "rec-old"));
        RayneoContextQueue.IngestResult newRow = window.ingest(AlwaysOnConsume.accept(
            new Payload(), 200L, "inst-new", "rec-new"));
        FakePoster windowPoster = new FakePoster();
        windowPoster.ackBody = "{\"ok\":true,\"source\":\"rayneo\",\"segment_id\":\""
            + newRow.record.segmentId + "\",\"revision\":1,\"raw_id\":\"raw-w\",\"canonical_id\":\"can-w\",\"effect\":\"ingested\"}";
        RayneoContextProtocol.DeliveryResult windowed = RayneoContextProtocol.deliver(
            window, windowPoster, true, 8, 150L);
        check("ok".equals(windowed.status));
        check(windowed.sent == 1);
        check(windowed.skippedOld == 1);
        check(window.pendingCount() == 1);
        check(window.pending().get(0).receivedTimeMs == 100L);
        check(windowPoster.paths.size() == 1);

        RayneoCurrentQuestion questions = new RayneoCurrentQuestion(local);
        FakePoster queryPoster = new FakePoster();
        Map<String, Object> queried = RayneoQueryBridge.invokeFromToolRequest(
            RayneoQueryBridge.TOOL_NAME, "项目Alpha", questions, queryPoster, true, 8, 1_700_000_000_200L);
        check(queryPoster.paths.contains(RayneoContextProtocol.QUERY_PATH));
        check(queryPoster.bodies.get(queryPoster.bodies.size() - 1).contains("\"source\":\"rayneo\""));
        check(Boolean.FALSE.equals(queried.get("instruction_eligible")));
        check("rayneo".equals(queried.get("source")));
        check("rayneo-context/v1".equals(queried.get("contract_version")));

        int priorRequests = queryPoster.paths.size();
        Map<String,Object> disabled = RayneoQueryBridge.invokeConfiguredToolRequest(
            RayneoQueryBridge.TOOL_NAME, "alpha", new RayneoCurrentQuestion(queue), queryPoster, false, 1, 1_700_000_010_000L);
        check("unconfigured".equals(disabled.get("error_class")));
        check(!RayneoQueryBridge.hasUsableResults(disabled));
        check(queryPoster.paths.size() == priorRequests);
        Map<String,Object> noTransport = RayneoQueryBridge.invokeConfiguredToolRequest(
            RayneoQueryBridge.TOOL_NAME, "alpha", new RayneoCurrentQuestion(queue), null, true, 1, 1_700_000_010_000L);
        check(!RayneoQueryBridge.hasUsableResults(noTransport));
        System.out.println("PASS " + checks + " always-on contract checks");
    }

    private static String readContract() throws Exception {
        File[] candidates = {
            new File("docs/contracts/b-rayneo-context-v1.json"),
            new File("../docs/contracts/b-rayneo-context-v1.json")
        };
        for (int i = 0; i < candidates.length; i++) {
            if (candidates[i].isFile()) {
                return new String(Files.readAllBytes(candidates[i].toPath()), StandardCharsets.UTF_8);
            }
        }
        throw new IllegalStateException("b-rayneo-context-v1.json");
    }
}
