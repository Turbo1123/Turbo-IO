package com.turboio.addon;

import java.util.ArrayList;
import java.util.Calendar;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.TimeZone;

/**
 * B {@code rayneo-context/v1} request/response codec and bounded ingest delivery.
 * Cross-end paths are POST {@code /ingest} and POST {@code /v1/rayneo/query}.
 * {@code /query} then {@code /jobs/{id}} is an internal knowledge envelope, not B.
 */
public final class RayneoContextProtocol {
    public static final String CONTRACT_VERSION = "rayneo-context/v1";
    public static final String SOURCE = "rayneo";
    public static final String INGEST_PATH = "/ingest";
    public static final String QUERY_PATH = "/v1/rayneo/query";
    public static final String CONTROL_PATH = "/v1/rayneo/control";
    public static final String INTERNAL_QUERY_PATH = "/query";
    public static final String INTERNAL_JOBS_PREFIX = "/jobs/";
    public static final String INTERNAL_ENVELOPE = "internal /query /jobs/{id} (not B rayneo-context/v1)";
    public static final int QUERY_LIMIT_DEFAULT = 20;
    public static final int QUERY_LIMIT_MAX = 50;

    private RayneoContextProtocol() {}

    public interface Poster {
        HttpResult post(String path, String jsonBody);
    }

    public static final class HttpResult {
        public final int status;
        public final String body;
        public final String errorClass;
        HttpResult(int status, String body, String errorClass) {
            this.status = status;
            this.body = body == null ? "" : body;
            this.errorClass = errorClass;
        }
        public boolean ok() { return errorClass == null && status >= 200 && status < 300; }
        public static HttpResult success(int status, String body) { return new HttpResult(status, body, null); }
        public static HttpResult error(String errorClass) { return new HttpResult(0, "", errorClass); }
        public static HttpResult unconfigured() { return error("unconfigured"); }
        public static HttpResult timeout() { return error("timeout"); }
        public static HttpResult offline() { return error("offline"); }
        public static HttpResult permission() { return error("permission"); }
    }

    public static final class DeliveryResult {
        public final String status;
        public final int sent;
        public final boolean acked;
        public final String lastError;
        public final int skippedOld;
        DeliveryResult(String status, int sent, boolean acked, String lastError) {
            this(status, sent, acked, lastError, 0);
        }
        DeliveryResult(String status, int sent, boolean acked, String lastError, int skippedOld) {
            this.status = status;
            this.sent = sent;
            this.acked = acked;
            this.lastError = lastError == null ? "" : lastError;
            this.skippedOld = skippedOld;
        }
    }

    public static Map<String, Object> ingestEvent(RayneoContextQueue.Record record) {
        LinkedHashMap<String, Object> payload = new LinkedHashMap<String, Object>();
        payload.put("source_instance", record.sourceInstance);
        payload.put("platform", "android");
        payload.put("collector_version", CONTRACT_VERSION);
        payload.put("segment_id", record.segmentId);
        payload.put("revision", Integer.valueOf(record.revision));
        payload.put("content_hash", "sha256:" + RayneoContextQueue.sha256(record.text));
        payload.put("text", record.text);
        payload.put("text_kind", "transcript");
        payload.put("source_ref", "rayneo:android:" + record.sourceInstance + ":" + record.segmentId);
        payload.put("source_time", null);
        payload.put("source_time_unknown", Boolean.TRUE);
        payload.put("received_at", isoUtc(record.receivedTimeMs));
        LinkedHashMap<String, Object> coverage = new LinkedHashMap<String, Object>();
        coverage.put("status", "unknown");
        coverage.put("note", "collector source time unavailable");
        payload.put("coverage", coverage);
        ArrayList<Object> gaps = new ArrayList<Object>();
        LinkedHashMap<String, Object> gap = new LinkedHashMap<String, Object>();
        gap.put("kind", "unknown_source_time");
        gaps.add(gap);
        payload.put("gaps", gaps);

        LinkedHashMap<String, Object> event = new LinkedHashMap<String, Object>();
        event.put("source", SOURCE);
        event.put("contract_version", CONTRACT_VERSION);
        event.put("type", "point");
        event.put("subtype", "transcript");
        event.put("time", isoUtc(record.receivedTimeMs));
        event.put("tz", "UTC");
        event.put("dedup_key", "rayneo:" + record.sourceInstance + ":" + record.segmentId);
        event.put("payload", payload);
        return event;
    }

    public static String ingestJson(RayneoContextQueue.Record record) {
        return json(ingestEvent(record));
    }

    public static Map<String, Object> queryRequest(String topic, int limit) {
        LinkedHashMap<String, Object> body = new LinkedHashMap<String, Object>();
        body.put("source", SOURCE);
        body.put("topic", topic);
        body.put("limit", Integer.valueOf(Math.max(1, Math.min(QUERY_LIMIT_MAX, limit <= 0 ? QUERY_LIMIT_DEFAULT : limit))));
        body.put("max_text_chars", Integer.valueOf(2000));
        body.put("max_total_tokens", Integer.valueOf(4000));
        body.put("include_derived", Boolean.TRUE);
        return body;
    }

    public static String queryJson(String topic, int limit) {
        return json(queryRequest(topic, limit));
    }

    public static DeliveryResult deliver(RayneoContextQueue queue, Poster poster, boolean configured, int max) {
        return deliver(queue, poster, configured, max, 0L);
    }

    /**
     * Bounded delivery with first-error stop. A local ACK is written only after the
     * server response body confirms the same source/segment/revision with stable IDs.
     * Older pending rows before minReceivedMs are left untouched for an explicit window.
     */
    public static DeliveryResult deliver(RayneoContextQueue queue, Poster poster, boolean configured,
            int max, long minReceivedMs) {
        return deliverBound(queue, poster, configured, max, minReceivedMs, queue == null ? 0 : queue.windowId());
    }

    public static DeliveryResult deliverWindow(RayneoContextQueue queue, Poster poster, boolean configured,
            int max, long expectedWindow) {
        if (expectedWindow <= 0) return new DeliveryResult("window_not_ready", 0, false, "window_binding_mismatch");
        return deliverBound(queue, poster, configured, max, 0, expectedWindow);
    }

    private static DeliveryResult deliverBound(RayneoContextQueue queue, Poster poster, boolean configured,
            int max, long minReceivedMs, long expectedWindow) {
        if (queue == null) return new DeliveryResult("no_queue", 0, false, "");
        if (!configured || poster == null) {
            return new DeliveryResult("local_only", 0, false, "endpoint_or_permission_not_configured");
        }
        if (!queue.beginDelivery(expectedWindow)) {
            return new DeliveryResult("window_not_ready", 0, false, "window_binding_mismatch");
        }
        try {
        List<RayneoContextQueue.Record> pending = queue.pending();
        int sent = 0;
        int skippedOld = 0;
        String lastError = "";
        int bound = Math.max(1, max);
        for (int i = 0; i < pending.size() && sent < bound; i++) {
            RayneoContextQueue.Record record = pending.get(i);
            if (!queue.sendable(record) || record.receivedTimeMs < minReceivedMs) {
                skippedOld++;
                continue;
            }
            HttpResult result = poster.post(INGEST_PATH, ingestJson(record));
            if (result != null && result.ok()) {
                String ackError = ingestAckError(record, result.body);
                if (!ackError.isEmpty()) {
                    lastError = ackError;
                    queue.noteFailure(record.id, record.revision, ackError);
                    break;
                }
                RayneoContextQueue.AckResult ack = queue.ack(record.id, record.revision);
                if (!ack.accepted && !ack.idempotent) {
                    lastError = "ack_rejected:" + ack.error;
                    queue.noteFailure(record.id, record.revision, lastError);
                    break;
                }
                sent++;
            } else {
                lastError = result == null || result.errorClass == null || result.errorClass.isEmpty()
                    ? "upload_failed" : result.errorClass;
                queue.noteFailure(record.id, record.revision, lastError);
                break;
            }
        }
        return new DeliveryResult(lastError.isEmpty() ? "ok" : "stopped_first_error", sent, sent > 0,
            lastError, skippedOld);
        } finally {
            queue.endDelivery();
        }
    }

    /** Empty body, unknown shape, stale_ignored or mismatched identity are not server ACKs. */
    static String ingestAckError(RayneoContextQueue.Record record, String body) {
        if (record == null || body == null || body.trim().isEmpty()) return "protocol_mismatch";
        Boolean ok = jsonBool(body, "ok");
        String source = jsonString(body, "source");
        String segmentId = jsonString(body, "segment_id");
        Long revision = jsonLong(body, "revision");
        String rawId = jsonString(body, "raw_id");
        String canonicalId = jsonString(body, "canonical_id");
        String effect = jsonString(body, "effect");
        if ("stale_ignored".equals(effect)) return "stale_ignored";
        if (!Boolean.TRUE.equals(ok) || !SOURCE.equals(source) || !record.segmentId.equals(segmentId)
                || revision == null || revision.longValue() != record.revision
                || rawId == null || rawId.isEmpty() || canonicalId == null || canonicalId.isEmpty()
                || !("ingested".equals(effect) || "revision_applied".equals(effect)
                    || "replay_idempotent".equals(effect))) {
            return "protocol_mismatch";
        }
        return "";
    }

    static String jsonString(String body, String key) {
        int[] value = findJsonValue(body, key);
        if (value == null) return null;
        int start = value[0];
        if (start >= body.length() || body.charAt(start) != '"') return null;
        StringBuilder out = new StringBuilder();
        for (int i = start + 1; i < body.length(); i++) {
            char c = body.charAt(i);
            if (c == '"') return out.toString();
            if (c == '\\' && i + 1 < body.length()) {
                char next = body.charAt(++i);
                if (next == 'u' && i + 4 < body.length()) {
                    out.append((char) Integer.parseInt(body.substring(i + 1, i + 5), 16));
                    i += 4;
                } else {
                    out.append(next);
                }
            } else {
                out.append(c);
            }
        }
        return null;
    }

    static Long jsonLong(String body, String key) {
        int[] value = findJsonValue(body, key);
        if (value == null) return null;
        int end = value[1];
        String token = body.substring(value[0], end).trim();
        try {
            return Long.valueOf(Long.parseLong(token));
        } catch (Exception ignored) {
            return null;
        }
    }

    static Boolean jsonBool(String body, String key) {
        int[] value = findJsonValue(body, key);
        if (value == null) return null;
        String token = body.substring(value[0], value[1]).trim();
        if ("true".equals(token)) return Boolean.TRUE;
        if ("false".equals(token)) return Boolean.FALSE;
        return null;
    }

    private static int[] findJsonValue(String body, String key) {
        String needle = "\"" + key + "\"";
        int at = body.indexOf(needle);
        if (at < 0) return null;
        int p = at + needle.length();
        while (p < body.length() && Character.isWhitespace(body.charAt(p))) p++;
        if (p >= body.length() || body.charAt(p) != ':') return null;
        p++;
        while (p < body.length() && Character.isWhitespace(body.charAt(p))) p++;
        int start = p;
        if (p < body.length() && body.charAt(p) == '"') {
            boolean escaped = false;
            for (p = start + 1; p < body.length(); p++) {
                char c = body.charAt(p);
                if (c == '"' && !escaped) return new int[] { start, p + 1 };
                escaped = c == '\\' && !escaped;
                if (c != '\\') escaped = false;
            }
            return null;
        }
        while (p < body.length() && ",}] \t\r\n".indexOf(body.charAt(p)) < 0) p++;
        return new int[] { start, p };
    }

    public static String isoUtc(long ms) {
        Calendar calendar = Calendar.getInstance(TimeZone.getTimeZone("UTC"), Locale.ROOT);
        calendar.setTimeInMillis(ms);
        return String.format(Locale.ROOT, "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ",
            Integer.valueOf(calendar.get(Calendar.YEAR)),
            Integer.valueOf(calendar.get(Calendar.MONTH) + 1),
            Integer.valueOf(calendar.get(Calendar.DAY_OF_MONTH)),
            Integer.valueOf(calendar.get(Calendar.HOUR_OF_DAY)),
            Integer.valueOf(calendar.get(Calendar.MINUTE)),
            Integer.valueOf(calendar.get(Calendar.SECOND)),
            Integer.valueOf(calendar.get(Calendar.MILLISECOND)));
    }

    public static String json(Object value) {
        if (value == null) return "null";
        if (value instanceof Boolean) return ((Boolean) value).booleanValue() ? "true" : "false";
        if (value instanceof Number) return value.toString();
        if (value instanceof String) return quote((String) value);
        if (value instanceof Map) {
            StringBuilder out = new StringBuilder();
            out.append('{');
            boolean first = true;
            Map<?, ?> map = (Map<?, ?>) value;
            for (Map.Entry<?, ?> entry : map.entrySet()) {
                if (!first) out.append(',');
                first = false;
                out.append(quote(String.valueOf(entry.getKey())));
                out.append(':');
                out.append(json(entry.getValue()));
            }
            out.append('}');
            return out.toString();
        }
        if (value instanceof List) {
            StringBuilder out = new StringBuilder();
            out.append('[');
            List<?> list = (List<?>) value;
            for (int i = 0; i < list.size(); i++) {
                if (i > 0) out.append(',');
                out.append(json(list.get(i)));
            }
            out.append(']');
            return out.toString();
        }
        return quote(String.valueOf(value));
    }

    static String quote(String value) {
        StringBuilder out = new StringBuilder(value.length() + 2);
        out.append('"');
        for (int i = 0; i < value.length(); i++) {
            char c = value.charAt(i);
            switch (c) {
                case '"': out.append("\\\""); break;
                case '\\': out.append("\\\\"); break;
                case '\n': out.append("\\n"); break;
                case '\r': out.append("\\r"); break;
                case '\t': out.append("\\t"); break;
                default:
                    if (c < 32) out.append(String.format(Locale.ROOT, "\\u%04x", Integer.valueOf(c)));
                    else out.append(c);
            }
        }
        out.append('"');
        return out.toString();
    }
}
