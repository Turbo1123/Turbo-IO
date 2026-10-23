package com.turboio.addon;

import java.lang.reflect.Method;

/**
 * Android AlwaysOn final-text consume. Host ABI (not a smali class path):
 * {@code onAlwaysOnResponse(Lcom/rayneo/airuntime/controller/RayNeoAlwaysOnResponse;)V}.
 * The original listener callback is invoked first; only finished getter values are accepted.
 *
 * Identity is a durable source_instance plus a segment id that includes a recording
 * session key. roundId|role is not treated as globally unique across sessions.
 * source_time is JSON null with source_time_unknown=true; received_at is separate.
 */
public final class AlwaysOnConsume {
    public static final String JNI_METHOD = "onAlwaysOnResponse";
    public static final String JNI_SIGNATURE =
        "onAlwaysOnResponse(Lcom/rayneo/airuntime/controller/RayNeoAlwaysOnResponse;)V";
    public static final String PAYLOAD_TYPE = "com.rayneo.airuntime.controller.RayNeoAlwaysOnResponse";
    public static final String ORIGINAL_PREFIX = "turboioOriginal_";
    public static final String SOURCE_TIME_UNKNOWN = "unknown";
    public static final String CONTRACT_VERSION = "rayneo-context/v1";
    public static final String DEFAULT_SOURCE_INSTANCE = "rayneo-android-unscoped";
    public static final String DEFAULT_RECORDING_SESSION = "session";

    private AlwaysOnConsume() {}

    public static final class Segment {
        public final String id, sourceInstance, segmentId, roundId, role, text, recordingSession;
        public final String sourceTime;
        public final boolean sourceTimeUnknown;
        public final long receivedTimeMs;
        Segment(String id, String sourceInstance, String segmentId, String roundId, String role,
                String text, long receivedTimeMs, String recordingSession) {
            this.id = id;
            this.sourceInstance = sourceInstance;
            this.segmentId = segmentId;
            this.roundId = roundId;
            this.role = role;
            this.text = text;
            this.receivedTimeMs = receivedTimeMs;
            this.recordingSession = recordingSession;
            this.sourceTime = null;
            this.sourceTimeUnknown = true;
        }
    }

    /** roundId|role only. Not a cross-session identity. */
    public static String identity(String roundId, String role) {
        if (roundId == null || role == null || roundId.isEmpty() || role.isEmpty()) return null;
        if (roundId.length() > 512 || role.length() > 80) return null;
        return roundId + "|" + role;
    }

    public static String segmentId(String recordingSession, String roundId, String role) {
        String roundRole = identity(roundId, role);
        String session = normalizeToken(recordingSession, 128);
        if (roundRole == null || session == null) return null;
        return session + ":" + roundId + ":" + role;
    }

    public static String scopedIdentity(String sourceInstance, String recordingSession,
            String roundId, String role) {
        String segment = segmentId(recordingSession, roundId, role);
        String source = normalizeSourceInstance(sourceInstance);
        if (segment == null || source == null) return null;
        return source + "|" + segment;
    }

    public static String normalizeSourceInstance(String sourceInstance) {
        return normalizeToken(sourceInstance, 128);
    }

    public static String normalizeToken(String value, int max) {
        if (value == null) return null;
        String trimmed = value.trim();
        if (trimmed.isEmpty() || trimmed.length() > max) return null;
        for (int i = 0; i < trimmed.length(); i++) {
            char c = trimmed.charAt(i);
            if (c < 33 || c == '|' || c > 126) return null;
        }
        return trimmed;
    }

    public static Segment accept(Object payload, long receivedTimeMs) {
        return accept(payload, receivedTimeMs, DEFAULT_SOURCE_INSTANCE, DEFAULT_RECORDING_SESSION);
    }

    public static Segment accept(Object payload, long receivedTimeMs, String sourceInstance) {
        return accept(payload, receivedTimeMs, sourceInstance, DEFAULT_RECORDING_SESSION);
    }

    public static Segment accept(Object payload, long receivedTimeMs, String sourceInstance,
            String recordingSession) {
        if (payload == null || receivedTimeMs <= 0) return null;
        Object finished = getter(payload, "Finished");
        if (!Boolean.TRUE.equals(finished)) return null;
        String text = str(getter(payload, "Text"));
        String roundId = str(getter(payload, "RoundId"));
        String role = str(getter(payload, "Role"));
        if (text.isEmpty() || text.length() > 32000) return null;
        String payloadSession = firstToken(str(getter(payload, "SessionId")),
            str(getter(payload, "DialogId")));
        String session = payloadSession != null ? payloadSession
            : normalizeToken(recordingSession, 128);
        if (session == null) session = DEFAULT_RECORDING_SESSION;
        String source = normalizeSourceInstance(sourceInstance);
        String segment = segmentId(session, roundId, role);
        if (segment == null || source == null) return null;
        return new Segment(source + "|" + segment, source, segment, roundId, role, text,
            receivedTimeMs, session);
    }

    /** Prefer the renamed original, then the host method. Failure means the payload is not consumed. */
    public static boolean invokeOriginal(Object source, Object payload) {
        if (source == null || payload == null) return false;
        Method method = find(source, ORIGINAL_PREFIX + JNI_METHOD, payload);
        if (method == null) method = find(source, JNI_METHOD, payload);
        if (method == null) return false;
        try {
            method.setAccessible(true);
            method.invoke(source, payload);
            return true;
        } catch (Exception ignored) {
            return false;
        }
    }

    public static boolean dispatch(Object source, Object payload, RayneoContextQueue queue, long nowMs) {
        RayneoContextQueue.IngestResult result = dispatchDetailed(source, payload, queue, nowMs,
            DEFAULT_SOURCE_INSTANCE, DEFAULT_RECORDING_SESSION);
        return result != null && !result.originalFailed;
    }

    public static RayneoContextQueue.IngestResult dispatchDetailed(Object source, Object payload,
            RayneoContextQueue queue, long nowMs, String sourceInstance) {
        return dispatchDetailed(source, payload, queue, nowMs, sourceInstance, DEFAULT_RECORDING_SESSION);
    }

    public static RayneoContextQueue.IngestResult dispatchDetailed(Object source, Object payload,
            RayneoContextQueue queue, long nowMs, String sourceInstance, String recordingSession) {
        if (!invokeOriginal(source, payload)) return RayneoContextQueue.IngestResult.originalFailed();
        Segment segment = accept(payload, nowMs, sourceInstance, recordingSession);
        if (segment == null || queue == null) return RayneoContextQueue.IngestResult.ignored();
        return queue.ingest(segment);
    }

    /** ASR / onAsr must not start a current-question query. */
    public static void observeAsr(RayneoCurrentQuestion bridge, String text, boolean finished, String session) {
        if (bridge == null) return;
        bridge.observeAsr();
    }

    private static String firstToken(String a, String b) {
        String first = normalizeToken(a, 128);
        if (first != null) return first;
        return normalizeToken(b, 128);
    }

    private static Object getter(Object object, String name) {
        try {
            Method method = object.getClass().getMethod("get" + name);
            method.setAccessible(true);
            return method.invoke(object);
        } catch (Exception ignored) {
            return null;
        }
    }

    private static String str(Object value) {
        if (value instanceof String) return (String) value;
        if (value instanceof Number) return String.valueOf(value);
        if (value == null) return "";
        try {
            Method method = value.getClass().getMethod("getStringValue");
            Object raw = method.invoke(value);
            return raw instanceof String ? (String) raw : "";
        } catch (Exception ignored) {
            return "";
        }
    }

    private static Method find(Object source, String name, Object payload) {
        Class<?> type = source.getClass();
        try {
            return type.getMethod(name, payload.getClass());
        } catch (NoSuchMethodException ignored) {}
        Method[] methods = type.getMethods();
        for (int i = 0; i < methods.length; i++) {
            Method method = methods[i];
            if (!name.equals(method.getName())) continue;
            Class<?>[] parameters = method.getParameterTypes();
            if (parameters.length == 1 && parameters[0].isAssignableFrom(payload.getClass())) return method;
        }
        return null;
    }
}
