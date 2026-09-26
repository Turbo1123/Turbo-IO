package com.turboio.addon;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;

/**
 * Current-question context. Cross-end query is B {@code POST /v1/rayneo/query}
 * via {@link RayneoQueryBridge}. {@link #query}/{@link #status} remain the
 * internal {@code /query} then {@code /jobs/{id}} envelope and are labeled as such.
 * Context is labeled data, never instructions, user intent, task creation, or an
 * official RayNeo answer.
 */
public final class RayneoCurrentQuestion {
    public static final String SOURCE = "rayneo";
    public static final String CONTRACT_VERSION = "rayneo-context/v1";
    public static final String CONTEXT_SOURCE = "rayneo";
    public static final String COLLECTOR_IMPL = "rayneo-ambient-adapter";
    public static final int RESULT_BOUND = 8;
    public static final int JOB_BOUND = 32;
    public static final long FRESH_MS = 5L * 60L * 1000L;
    public static final String NOT_INSTRUCTIONS = "context_is_not_instructions";
    public static final String INTERNAL_ENVELOPE = RayneoContextProtocol.INTERNAL_ENVELOPE;

    private final RayneoContextQueue queue;
    private final LinkedHashMap<String, Job> jobs = new LinkedHashMap<String, Job>();
    private int queryCount;
    private int asrEvents;

    public RayneoCurrentQuestion(RayneoContextQueue queue) {
        if (queue == null) throw new IllegalArgumentException("queue");
        this.queue = queue;
    }

    public synchronized void observeAsr() { asrEvents++; }

    public synchronized int queryCount() { return queryCount; }

    public synchronized int asrEvents() { return asrEvents; }

    public synchronized void markQueried() { queryCount++; }

    /**
     * B/local current-question query used by the glasses ToolClient path.
     * Does not use the internal /query then /jobs envelope.
     */
    public synchronized Map<String, Object> queryCurrent(String topic, long nowMs) {
        String normalized = normalizeQuery(topic);
        queryCount++;
        List<RayneoContextQueue.Record> pool = queue.snapshot();
        List<RayneoContextQueue.Record> chosen = select(pool, normalized);
        ArrayList<Map<String, Object>> results = new ArrayList<Map<String, Object>>();
        int start = Math.max(0, chosen.size() - RESULT_BOUND);
        for (int i = start; i < chosen.size(); i++) results.add(bItem(chosen.get(i), nowMs));
        LinkedHashMap<String, Object> envelope = new LinkedHashMap<String, Object>();
        envelope.put("source", SOURCE);
        envelope.put("contract_version", CONTRACT_VERSION);
        envelope.put("status", results.isEmpty() ? "empty" : "ok");
        envelope.put("topic", normalized);
        envelope.put("results", results);
        envelope.put("instruction_eligible", Boolean.FALSE);
        envelope.put("untrusted_data", Boolean.TRUE);
        envelope.put("answer", null);
        envelope.put("transport", "local-queue");
        envelope.put("classification", classification());
        envelope.put("diagnostics", queue.diagnostics());
        envelope.put("labels", labels(null, nowMs, true));
        return envelope;
    }

    /** Internal knowledge-shaped query. Not the B cross-end protocol. */
    public synchronized Map<String, Object> query(String query, String source, String requestId) {
        String normalized = normalizeQuery(query);
        if (!SOURCE.equals(source)) throw new IllegalArgumentException("source");
        String id = normalizeId(requestId);
        Job existing = jobs.get(id);
        if (existing != null) {
            if (!existing.query.equals(normalized) || !existing.source.equals(source)) {
                throw new IllegalArgumentException("request_conflict");
            }
            return queuedEnvelope(existing);
        }
        queryCount++;
        Job job = new Job(id, normalized, source);
        if (jobs.size() >= JOB_BOUND) {
            String first = jobs.keySet().iterator().next();
            jobs.remove(first);
        }
        jobs.put(id, job);
        return queuedEnvelope(job);
    }

    /** Internal knowledge-shaped status. Not the B cross-end protocol. */
    public synchronized Map<String, Object> status(String requestId, long nowMs) {
        Job job = jobs.get(normalizeId(requestId));
        if (job == null) throw new IllegalArgumentException("unknown_job");
        if (!"completed".equals(job.status)) {
            job.result = complete(job, nowMs);
            job.status = "completed";
        }
        return job.result;
    }

    /** Local read cursor only; server upload ACK is queue.ack(id, revision). */
    public synchronized void ack(long seq) { queue.advanceWatermark(seq); }

    public synchronized Map<String, Object> queueDiagnostics() { return queue.diagnostics(); }

    public static boolean isInstructions(Map<String, Object> envelope) { return false; }

    public static boolean isUserIntent(Map<String, Object> envelope) { return false; }

    public static boolean isTaskCreation(Map<String, Object> envelope) { return false; }

    public static boolean isOfficialRayNeoAnswer(Map<String, Object> envelope) { return false; }

    public static String asSystemPrompt(Map<String, Object> envelope) {
        throw new IllegalStateException(NOT_INSTRUCTIONS);
    }

    public static String asUserIntentText(Map<String, Object> envelope) {
        throw new IllegalStateException(NOT_INSTRUCTIONS);
    }

    static Map<String, Object> remoteEnvelope(String body, long nowMs) {
        LinkedHashMap<String, Object> envelope = new LinkedHashMap<String, Object>();
        envelope.put("source", SOURCE);
        envelope.put("contract_version", CONTRACT_VERSION);
        envelope.put("status", "ok");
        envelope.put("instruction_eligible", Boolean.FALSE);
        envelope.put("untrusted_data", Boolean.TRUE);
        envelope.put("answer", null);
        envelope.put("transport", "POST " + RayneoContextProtocol.QUERY_PATH);
        envelope.put("classification", classification());
        envelope.put("freshness", "unknown_source_time");
        ArrayList<Map<String, Object>> results = new ArrayList<Map<String, Object>>();
        if (body != null && body.contains("\"text\"")) {
            LinkedHashMap<String, Object> item = new LinkedHashMap<String, Object>();
            item.put("source", SOURCE);
            item.put("instruction_eligible", Boolean.FALSE);
            item.put("source_time", null);
            item.put("source_time_unknown", Boolean.TRUE);
            item.put("raw", body);
            item.put("classification", classification());
            results.add(item);
        }
        envelope.put("results", results);
        envelope.put("received_at", RayneoContextProtocol.isoUtc(nowMs));
        if (results.isEmpty()) envelope.put("status", "empty");
        return envelope;
    }

    private Map<String, Object> complete(Job job, long nowMs) {
        List<RayneoContextQueue.Record> unread = queue.pending();
        List<RayneoContextQueue.Record> chosen = select(unread, job.query);
        ArrayList<Map<String, Object>> results = new ArrayList<Map<String, Object>>();
        int start = Math.max(0, chosen.size() - RESULT_BOUND);
        for (int i = start; i < chosen.size(); i++) results.add(item(chosen.get(i), nowMs));
        LinkedHashMap<String, Object> envelope = new LinkedHashMap<String, Object>();
        envelope.put("id", job.id);
        envelope.put("status", "completed");
        envelope.put("transport", INTERNAL_ENVELOPE);
        LinkedHashMap<String, Object> input = new LinkedHashMap<String, Object>();
        input.put("query", job.query);
        input.put("source", job.source);
        input.put("requestId", job.id);
        envelope.put("input", input);
        envelope.put("results", results);
        envelope.put("untrusted_data", Boolean.TRUE);
        envelope.put("instruction_eligible", Boolean.FALSE);
        envelope.put("answer", null);
        LinkedHashMap<String, Object> cursor = new LinkedHashMap<String, Object>();
        cursor.put("watermark", Long.valueOf(queue.watermark()));
        long head = queue.watermark();
        for (int i = 0; i < unread.size(); i++) {
            if (unread.get(i).seq > head) head = unread.get(i).seq;
        }
        cursor.put("head", Long.valueOf(head));
        envelope.put("cursor", cursor);
        envelope.put("labels", labels(null, nowMs, true));
        envelope.put("classification", classification());
        return envelope;
    }

    private Map<String, Object> bItem(RayneoContextQueue.Record record, long nowMs) {
        LinkedHashMap<String, Object> row = new LinkedHashMap<String, Object>();
        row.put("source", SOURCE);
        row.put("source_ref", "rayneo:android:" + record.sourceInstance + ":" + record.segmentId);
        row.put("revision", Integer.valueOf(record.revision));
        row.put("segment_id", record.segmentId);
        row.put("text_kind", "transcript");
        row.put("text", record.text);
        row.put("source_time", null);
        row.put("source_time_unknown", Boolean.TRUE);
        row.put("received_at", RayneoContextProtocol.isoUtc(record.receivedTimeMs));
        row.put("freshness", nowMs - record.receivedTimeMs <= FRESH_MS ? "unknown_source_time" : "historical");
        LinkedHashMap<String, Object> coverage = new LinkedHashMap<String, Object>();
        coverage.put("status", "unknown");
        row.put("coverage", coverage);
        ArrayList<Object> gaps = new ArrayList<Object>();
        LinkedHashMap<String, Object> gap = new LinkedHashMap<String, Object>();
        gap.put("kind", "unknown_source_time");
        gaps.add(gap);
        row.put("gaps", gaps);
        row.put("instruction_eligible", Boolean.FALSE);
        row.put("classification", classification());
        return row;
    }

    private Map<String, Object> item(RayneoContextQueue.Record record, long nowMs) {
        LinkedHashMap<String, Object> row = new LinkedHashMap<String, Object>();
        row.put("id", record.id);
        row.put("source", SOURCE);
        row.put("contract_version", CONTRACT_VERSION);
        row.put("source_ref", "rayneo:android:" + record.sourceInstance + ":" + record.roundId + ":" + record.role);
        row.put("segment_id", record.segmentId);
        row.put("text_kind", "transcript");
        row.put("instruction_eligible", Boolean.FALSE);
        row.put("text", record.text);
        row.put("role", record.role);
        row.put("roundId", record.roundId);
        row.put("revision", Integer.valueOf(record.revision));
        row.put("seq", Long.valueOf(record.seq));
        row.put("source_time", null);
        row.put("source_time_unknown", Boolean.TRUE);
        row.put("received_at", RayneoContextProtocol.isoUtc(record.receivedTimeMs));
        row.put("labels", labels(record, nowMs, false));
        row.put("classification", classification());
        return row;
    }

    private Map<String, Object> labels(RayneoContextQueue.Record record, long nowMs, boolean envelope) {
        LinkedHashMap<String, Object> labels = new LinkedHashMap<String, Object>();
        labels.put("source", CONTEXT_SOURCE);
        LinkedHashMap<String, Object> time = new LinkedHashMap<String, Object>();
        time.put("source_time", null);
        time.put("source_time_unknown", Boolean.TRUE);
        if (record != null) {
            time.put("received_at", RayneoContextProtocol.isoUtc(record.receivedTimeMs));
            time.put("receivedTimeMs", Long.valueOf(record.receivedTimeMs));
            labels.put("freshness", freshness(record.receivedTimeMs, nowMs));
        } else {
            labels.put("freshnessBasis", "received_time");
        }
        labels.put("time", time);
        if (envelope) labels.put("freshnessBasis", "received_time");
        return labels;
    }

    static String freshness(long receivedTimeMs, long nowMs) {
        if (nowMs < receivedTimeMs) return "stale";
        return nowMs - receivedTimeMs <= FRESH_MS ? "fresh" : "stale";
    }

    static Map<String, Object> classification() {
        LinkedHashMap<String, Object> row = new LinkedHashMap<String, Object>();
        row.put("instructions", Boolean.FALSE);
        row.put("userIntent", Boolean.FALSE);
        row.put("taskCreation", Boolean.FALSE);
        row.put("officialRayNeoAnswer", Boolean.FALSE);
        row.put("instruction_eligible", Boolean.FALSE);
        row.put("kind", "labeled_context");
        return row;
    }

    private static Map<String, Object> queuedEnvelope(Job job) {
        LinkedHashMap<String, Object> envelope = new LinkedHashMap<String, Object>();
        envelope.put("id", job.id);
        envelope.put("status", "queued");
        envelope.put("transport", INTERNAL_ENVELOPE);
        LinkedHashMap<String, Object> input = new LinkedHashMap<String, Object>();
        input.put("query", job.query);
        input.put("source", job.source);
        input.put("requestId", job.id);
        envelope.put("input", input);
        envelope.put("classification", classification());
        envelope.put("untrusted_data", Boolean.TRUE);
        envelope.put("instruction_eligible", Boolean.FALSE);
        return envelope;
    }

    static List<RayneoContextQueue.Record> select(List<RayneoContextQueue.Record> unread, String query) {
        ArrayList<RayneoContextQueue.Record> phrase = new ArrayList<RayneoContextQueue.Record>();
        ArrayList<RayneoContextQueue.Record> tokens = new ArrayList<RayneoContextQueue.Record>();
        String needle = query.toLowerCase(Locale.ROOT).trim();
        for (int i = 0; i < unread.size(); i++) {
            RayneoContextQueue.Record record = unread.get(i);
            String haystack = record.text.toLowerCase(Locale.ROOT);
            if (haystack.contains(needle)) phrase.add(record);
            else if (tokenHit(haystack, needle)) tokens.add(record);
        }
        return phrase.isEmpty() ? tokens : phrase;
    }

    static boolean tokenHit(String haystack, String needle) {
        String[] parts = needle.split("\\s+");
        int hits = 0;
        int need = 0;
        for (int i = 0; i < parts.length; i++) {
            if (parts[i].length() < 2) continue;
            need++;
            if (haystack.contains(parts[i])) hits++;
        }
        return need > 0 && hits == need;
    }

    static boolean relevant(String text, String query) {
        String haystack = text.toLowerCase(Locale.ROOT);
        String needle = query.toLowerCase(Locale.ROOT).trim();
        return haystack.contains(needle) || tokenHit(haystack, needle);
    }

    static String normalizeQuery(String query) {
        if (query == null) throw new IllegalArgumentException("query");
        String value = query.trim();
        if (value.length() < 2 || value.length() > 200) throw new IllegalArgumentException("query");
        for (int i = 0; i < value.length(); i++) {
            if (value.charAt(i) < 32) throw new IllegalArgumentException("query");
        }
        return value;
    }

    static String normalizeId(String requestId) {
        try {
            return UUID.fromString(requestId).toString();
        } catch (Exception ignored) {
            throw new IllegalArgumentException("requestId");
        }
    }

    private static final class Job {
        final String id, query, source;
        String status = "queued";
        Map<String, Object> result;
        Job(String id, String query, String source) {
            this.id = id;
            this.query = query;
            this.source = source;
        }
    }
}
