package com.turboio.addon;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * Bounded durable AlwaysOn text outbox with per-revision server ACK semantics.
 *
 * A revision stays pending until the server explicitly accepts that same identity and
 * revision. Local read watermarks never confirm upload. ACKs are idempotent, an old ACK
 * never confirms a newer revision, confirmed capacity is reclaimed, and persistence
 * failures roll the in-memory mutation back instead of reporting success.
 */
public final class RayneoContextQueue {
    public static final int DEFAULT_BOUND = 256;
    public static final int TOMBSTONE_BOUND = 512;
    public static final String SOURCE_TIME_UNKNOWN = AlwaysOnConsume.SOURCE_TIME_UNKNOWN;
    private static final int VERSION = 4;
    private static final int VERSION_V3 = 3;
    private static final int VERSION_V2 = 2;

    public static final class Record {
        public final String id, sourceInstance, segmentId, roundId, role, text, sourceTime;
        public final long receivedTimeMs, updatedTimeMs, seq;
        public final int revision, ackedRevision;
        public final int attempts;
        public final String lastError;
        public final long windowId;
        Record(String id, String sourceInstance, String segmentId, String roundId, String role,
               String text, long receivedTimeMs, long updatedTimeMs, int revision, int ackedRevision,
               long seq, int attempts, String lastError, long windowId) {
            this.id = id;
            this.sourceInstance = sourceInstance;
            this.segmentId = segmentId;
            this.roundId = roundId;
            this.role = role;
            this.text = text;
            this.sourceTime = null;
            this.receivedTimeMs = receivedTimeMs;
            this.updatedTimeMs = updatedTimeMs;
            this.revision = revision;
            this.ackedRevision = ackedRevision;
            this.seq = seq;
            this.attempts = attempts;
            this.lastError = lastError == null ? "" : lastError;
            this.windowId = windowId;
        }
        Record withText(String value, long nowMs) {
            return new Record(id, sourceInstance, segmentId, roundId, role, value, receivedTimeMs,
                nowMs, revision + 1, ackedRevision, seq, 0, "", windowId);
        }
        Record withFailure(String error) {
            return new Record(id, sourceInstance, segmentId, roundId, role, text, receivedTimeMs,
                updatedTimeMs, revision, ackedRevision, seq, attempts + 1, error, windowId);
        }
    }

    public static final class IngestResult {
        public final boolean accepted, duplicate, revision, overflow, originalFailed, ignored, persisted;
        public final String error;
        public final Record record;
        IngestResult(boolean accepted, boolean duplicate, boolean revision, boolean overflow,
                     boolean originalFailed, boolean ignored, boolean persisted, String error, Record record) {
            this.accepted = accepted;
            this.duplicate = duplicate;
            this.revision = revision;
            this.overflow = overflow;
            this.originalFailed = originalFailed;
            this.ignored = ignored;
            this.persisted = persisted;
            this.error = error == null ? "" : error;
            this.record = record;
        }
        static IngestResult originalFailed() {
            return new IngestResult(false, false, false, false, true, false, false, "original_callback", null);
        }
        static IngestResult ignored() {
            return new IngestResult(false, false, false, false, false, true, false, "ignored", null);
        }
    }

    public static final class AckResult {
        public final boolean accepted, idempotent, stale, persisted;
        public final String error;
        AckResult(boolean accepted, boolean idempotent, boolean stale, boolean persisted, String error) {
            this.accepted = accepted;
            this.idempotent = idempotent;
            this.stale = stale;
            this.persisted = persisted;
            this.error = error == null ? "" : error;
        }
    }

    private static final class Tombstone {
        int lastRevision;
        int ackedRevision;
        long updatedMs;
        String textHash;
        long windowId;
        Tombstone(int lastRevision, int ackedRevision, long updatedMs, String textHash, long windowId) {
            this.lastRevision = lastRevision;
            this.ackedRevision = ackedRevision;
            this.updatedMs = updatedMs;
            this.textHash = textHash == null ? "" : textHash;
            this.windowId = windowId;
        }
    }

    private final File file;
    private final File backup;
    private final int bound;
    private final ArrayList<Record> segments = new ArrayList<Record>();
    private final LinkedHashMap<String, Tombstone> tombstones = new LinkedHashMap<String, Tombstone>();
    private long watermark; // Local read cursor only; never an upload ACK.
    private long nextSeq = 1;
    private long lastSuccessfulAckMs;
    private String lastError = "";
    private String loadError = "";
    private boolean recoveredFromBackup;
    private long windowId, windowStartedMs;
    private boolean windowOpen, storeBlocked;
    private int deliveries;
    private int loadedVersion = VERSION;
    private File loadedSource;

    public RayneoContextQueue(File directory, int bound) {
        if (directory == null || bound < 1) throw new IllegalArgumentException("queue");
        this.bound = bound;
        if (!directory.isDirectory() && !directory.mkdirs()) throw new IllegalStateException("directory");
        this.file = new File(directory, "rayneo-context-v2.dat");
        this.backup = new File(directory, "rayneo-context-v2.bak");
        load();
    }

    /** Same durable owner, two bounded partitions. Retained rows never become sendable by time. */
    public synchronized boolean beginWindow(long nowMs) {
        if (storeBlocked) return fail("store_unavailable");
        if (deliveries != 0) return fail("delivery_in_progress");
        if (nowMs <= 0 || windowId == Long.MAX_VALUE) return fail("invalid_window");
        if (windowId > 0 && nowMs == windowStartedMs) {
            return windowOpen || fail("closed_window_requires_explicit_resume");
        }
        if (windowOpen) return fail("close_current_window_first");
        // Every existing row will be retained, even if its device timestamp is in the future.
        if (segments.size() > bound) return fail("retained_capacity_full_resume_current_window");
        State before = state();
        windowId++;
        windowStartedMs = nowMs;
        windowOpen = true;
        if (!persist()) { restore(before); return false; }
        return true;
    }

    public synchronized boolean closeWindow() {
        if (!windowOpen) return !storeBlocked;
        State before = state();
        windowOpen = false;
        if (!persist()) {
            restore(before);
            // Fail closed in this process, too. The caller first durably disables the upload pref.
            windowOpen = false;
            storeBlocked = true;
            return false;
        }
        return true;
    }

    /** Explicit recovery reuses the current identity; it never promotes retained rows. */
    public synchronized boolean resumeWindow() {
        if (storeBlocked || windowId == 0) return fail("window_unavailable");
        if (deliveries != 0) return fail("delivery_in_progress");
        if (windowOpen) return true;
        State before = state();
        windowOpen = true;
        if (!persist()) { restore(before); return false; }
        return true;
    }

    public synchronized long windowId() { return windowId; }
    public synchronized long windowStartedMs() { return windowStartedMs; }
    public synchronized boolean windowOpen() { return windowOpen && !storeBlocked; }
    public synchronized int activeCount() {
        int count = 0;
        for (Record row : segments) if (row.windowId == windowId) count++;
        return count;
    }
    public synchronized int retainedCount() { return segments.size() - activeCount(); }
    public synchronized boolean recordingReady() {
        return windowId > 0 && windowOpen() && activeCount() < bound;
    }
    public synchronized boolean canStartWindow() {
        return !storeBlocked && deliveries == 0 && segments.size() <= bound;
    }
    public synchronized boolean beginDelivery(long expectedWindow) {
        if (storeBlocked || windowId != expectedWindow || (windowId > 0 && !windowOpen)) return false;
        deliveries++;
        return true;
    }
    public synchronized void endDelivery() { if (deliveries > 0) deliveries--; }
    public synchronized boolean sendable(Record record) {
        return !storeBlocked && record.windowId == windowId && (windowId == 0 || windowOpen);
    }
    private boolean fail(String error) { lastError = error; return false; }

    public synchronized IngestResult ingest(AlwaysOnConsume.Segment segment) {
        if (storeBlocked) return new IngestResult(false, false, false, false, false, false, false,
            "store_unavailable", null);
        if (segment == null || segment.id == null || segment.sourceInstance == null || segment.segmentId == null) {
            return new IngestResult(false, false, false, false, false, false, false, "invalid_segment", null);
        }
        State before = state();
        int index = indexOf(segment.id);
        if (index >= 0) {
            Record previous = segments.get(index);
            if (previous.text.equals(segment.text)) {
                return new IngestResult(true, true, false, false, false, false, true, "", previous);
            }
            if (previous.windowId != windowId || (windowId > 0 && !windowOpen)) {
                return new IngestResult(false, false, true, false, false, false, false,
                    "retained_identity", null);
            }
            Record updated = new Record(previous.id, previous.sourceInstance, previous.segmentId,
                previous.roundId, previous.role, segment.text, previous.receivedTimeMs,
                segment.receivedTimeMs, previous.revision + 1, previous.ackedRevision, nextSeq++, 0, "", previous.windowId);
            segments.set(index, updated);
            if (!persist()) {
                restore(before);
                return new IngestResult(false, false, true, false, false, false, false, lastError, null);
            }
            trimTombstones();
            return new IngestResult(true, false, true, false, false, false, true, "", updated);
        }
        Tombstone tombstone = tombstones.get(segment.id);
        String incomingHash = sha256(segment.text);
        if (tombstone != null && incomingHash.equals(tombstone.textHash)) {
            return new IngestResult(true, true, false, false, false, false, true, "", null);
        }
        if (tombstone != null && tombstone.windowId != windowId) {
            return new IngestResult(false, false, true, false, false, false, false, "retained_identity", null);
        }
        long incomingWindow = windowId == 0 || windowOpen ? windowId : 0;
        int occupied = incomingWindow == windowId ? activeCount() : retainedCount();
        if (occupied >= bound) {
            lastError = "overflow";
            return new IngestResult(false, false, false, true, false, false, false, "overflow", null);
        }
        int revision = tombstone == null ? 1 : tombstone.lastRevision + 1;
        int acked = tombstone == null ? 0 : tombstone.ackedRevision;
        Record created = new Record(segment.id, segment.sourceInstance, segment.segmentId, segment.roundId,
            segment.role, segment.text, segment.receivedTimeMs, segment.receivedTimeMs, revision, acked,
            nextSeq++, 0, "", incomingWindow);
        segments.add(created);
        if (!persist()) {
            restore(before);
            return new IngestResult(false, false, false, false, false, false, false, lastError, null);
        }
        return new IngestResult(true, false, false, false, false, false, true, "", created);
    }

    /** Server ACK for one exact identity + revision. Never call this for local reads. */
    public synchronized AckResult ack(String id, int revision) {
        if (id == null || revision < 1) return new AckResult(false, false, false, false, "invalid_ack");
        State before = state();
        int index = indexOf(id);
        long now = System.currentTimeMillis();
        if (index >= 0) {
            Record record = segments.get(index);
            if (storeBlocked || record.windowId != windowId) {
                return new AckResult(false, false, false, false, "retained_ack_refused");
            }
            if (revision < record.revision) {
                return new AckResult(false, false, true, true, "stale_ack");
            }
            if (revision > record.revision) {
                return new AckResult(false, false, false, true, "future_ack");
            }
            segments.remove(index);
            Tombstone tombstone = tombstones.get(id);
            int last = tombstone == null ? revision : Math.max(tombstone.lastRevision, revision);
            tombstones.put(id, new Tombstone(last, revision, now, sha256(record.text), record.windowId));
            trimTombstones();
            lastSuccessfulAckMs = now;
            if (!persist()) {
                restore(before);
                return new AckResult(false, false, false, false, lastError);
            }
            return new AckResult(true, false, false, true, "");
        }
        Tombstone tombstone = tombstones.get(id);
        if (tombstone != null && revision <= tombstone.ackedRevision) {
            return new AckResult(true, true, false, true, "");
        }
        return new AckResult(false, false, false, true, "unknown_ack");
    }

    public synchronized void noteFailure(String id, int revision, String error) {
        int index = indexOf(id);
        if (index < 0) return;
        Record record = segments.get(index);
        if (record.revision != revision || record.windowId != windowId || storeBlocked) return;
        State before = state();
        segments.set(index, record.withFailure(error));
        if (!persist()) restore(before);
    }

    /** Pending server-unacknowledged revisions. */
    public synchronized List<Record> pending() {
        ArrayList<Record> out = new ArrayList<Record>();
        for (int i = 0; i < segments.size(); i++) {
            Record record = segments.get(i);
            if (record.revision > record.ackedRevision) out.add(record);
        }
        return Collections.unmodifiableList(out);
    }

    /** Alias kept for the original negative tests: this is the server outbox, not a read cursor. */
    public synchronized List<Record> unread() { return pending(); }

    public synchronized List<Record> snapshot() {
        return Collections.unmodifiableList(new ArrayList<Record>(segments));
    }

    /** Local current-question cursor only; does not reclaim capacity and is not an ACK. */
    public synchronized long watermark() { return watermark; }

    public synchronized void advanceWatermark(long seq) {
        if (seq > watermark) {
            State before = state();
            watermark = seq;
            if (!persist()) restore(before);
        }
    }

    public synchronized int size() { return segments.size(); }

    public synchronized int pendingCount() { return pending().size(); }

    public synchronized int unackedRevisionCount() {
        int count = 0;
        for (int i = 0; i < segments.size(); i++) {
            Record record = segments.get(i);
            if (record.revision > record.ackedRevision) count++;
        }
        return count;
    }

    public synchronized long lastSuccessfulAckMs() { return lastSuccessfulAckMs; }

    public synchronized String lastError() { return lastError; }

    public synchronized String loadError() { return loadError; }

    public synchronized boolean recoveredFromBackup() { return recoveredFromBackup; }

    public synchronized Map<String, Object> diagnostics() {
        LinkedHashMap<String, Object> row = new LinkedHashMap<String, Object>();
        row.put("queueDepth", Integer.valueOf(segments.size()));
        row.put("pendingCount", Integer.valueOf(pendingCount()));
        row.put("unackedRevisions", Integer.valueOf(unackedRevisionCount()));
        row.put("bound", Integer.valueOf(bound));
        row.put("activePending", Integer.valueOf(activeCount()));
        row.put("retainedPending", Integer.valueOf(retainedCount()));
        row.put("activeRemaining", Integer.valueOf(Math.max(0, bound - activeCount())));
        row.put("windowId", Long.valueOf(windowId));
        row.put("windowOpen", Boolean.valueOf(windowOpen()));
        row.put("recordingReady", Boolean.valueOf(recordingReady()));
        row.put("canStartWindow", Boolean.valueOf(canStartWindow()));
        row.put("lastSuccessfulAckMs", Long.valueOf(lastSuccessfulAckMs));
        row.put("lastError", lastError);
        row.put("loadError", loadError);
        row.put("recoveredFromBackup", Boolean.valueOf(recoveredFromBackup));
        row.put("tombstones", Integer.valueOf(tombstones.size()));
        return Collections.unmodifiableMap(row);
    }

    public int bound() { return bound; }

    private int indexOf(String id) {
        for (int i = 0; i < segments.size(); i++) {
            if (id.equals(segments.get(i).id)) return i;
        }
        return -1;
    }

    private void trimTombstones() {
        while (tombstones.size() > TOMBSTONE_BOUND) {
            String first = tombstones.keySet().iterator().next();
            tombstones.remove(first);
        }
    }

    private void load() {
        if (tryLoad(file)) return;
        if (tryLoad(backup)) {
            recoveredFromBackup = true;
            loadError = "main_store_corrupt_recovered_from_backup";
            return;
        }
        if (file.isFile() || backup.isFile()) {
            loadError = "store_corrupt_writes_blocked_original_preserved";
            storeBlocked = true;
        }
    }

    private boolean tryLoad(File source) {
        if (!source.isFile()) return false;
        DataInputStream in = null;
        try {
            in = new DataInputStream(new BufferedInputStream(new FileInputStream(source)));
            int version = in.readInt();
            if (version != VERSION && version != VERSION_V3 && version != VERSION_V2) throw new IOException("version");
            watermark = in.readLong();
            nextSeq = in.readLong();
            lastSuccessfulAckMs = in.readLong();
            in.readInt(); // bound snapshot; constructor bound remains authoritative
            windowId = version >= VERSION ? in.readLong() : 0;
            windowStartedMs = version >= VERSION ? in.readLong() : 0;
            windowOpen = version >= VERSION && in.readBoolean();
            if (windowId < 0 || windowStartedMs < 0) throw new IOException("window");
            int count = in.readInt();
            if (count < 0 || count > (long) bound * (version >= VERSION ? 2 : 1)) throw new IOException("count");
            ArrayList<Record> rows = new ArrayList<Record>(count);
            for (int i = 0; i < count; i++) {
                String id = readString(in);
                String sourceInstance = readString(in);
                String segmentId = readString(in);
                String roundId = readString(in);
                String role = readString(in);
                String text = readString(in);
                long received = in.readLong();
                long updated = in.readLong();
                int revision = in.readInt();
                int acked = in.readInt();
                long seq = in.readLong();
                int attempts = in.readInt();
                String error = readString(in);
                long recordWindow = version >= VERSION ? in.readLong() : 0;
                if (recordWindow < 0 || recordWindow > windowId) throw new IOException("record_window");
                rows.add(new Record(id, sourceInstance, segmentId, roundId, role, text, received,
                    updated, revision, acked, seq, attempts, error, recordWindow));
            }
            int tombCount = in.readInt();
            if (tombCount < 0 || tombCount > TOMBSTONE_BOUND) throw new IOException("tombstones");
            LinkedHashMap<String, Tombstone> tombs = new LinkedHashMap<String, Tombstone>();
            for (int i = 0; i < tombCount; i++) {
                String id = readString(in);
                int last = in.readInt();
                int acked = in.readInt();
                long updated = in.readLong();
                String hash = version >= VERSION_V3 ? readString(in) : "";
                long recordWindow = version >= VERSION ? in.readLong() : 0;
                if (recordWindow < 0 || recordWindow > windowId) throw new IOException("tombstone_window");
                tombs.put(id, new Tombstone(last, acked, updated, hash, recordWindow));
            }
            segments.clear();
            segments.addAll(rows);
            if (activeCount() > bound || retainedCount() > bound) throw new IOException("partition_bound");
            tombstones.clear();
            tombstones.putAll(tombs);
            trimTombstones();
            loadedVersion = version;
            loadedSource = source;
            return true;
        } catch (IOException ignored) {
            segments.clear();
            tombstones.clear();
            watermark = 0;
            nextSeq = 1;
            lastSuccessfulAckMs = 0;
            windowId = windowStartedMs = 0;
            windowOpen = false;
            return false;
        } finally {
            if (in != null) try { in.close(); } catch (IOException ignored) {}
        }
    }

    private boolean persist() {
        if (storeBlocked) return fail("store_unavailable");
        File tmp = new File(file.getPath() + ".tmp");
        DataOutputStream out = null;
        try {
            FileOutputStream raw = new FileOutputStream(tmp);
            out = new DataOutputStream(new BufferedOutputStream(raw));
            out.writeInt(VERSION);
            out.writeLong(watermark);
            out.writeLong(nextSeq);
            out.writeLong(lastSuccessfulAckMs);
            out.writeInt(bound);
            out.writeLong(windowId);
            out.writeLong(windowStartedMs);
            out.writeBoolean(windowOpen);
            out.writeInt(segments.size());
            for (int i = 0; i < segments.size(); i++) {
                Record record = segments.get(i);
                writeString(out, record.id);
                writeString(out, record.sourceInstance);
                writeString(out, record.segmentId);
                writeString(out, record.roundId);
                writeString(out, record.role);
                writeString(out, record.text);
                out.writeLong(record.receivedTimeMs);
                out.writeLong(record.updatedTimeMs);
                out.writeInt(record.revision);
                out.writeInt(record.ackedRevision);
                out.writeLong(record.seq);
                out.writeInt(record.attempts);
                writeString(out, record.lastError);
                out.writeLong(record.windowId);
            }
            out.writeInt(tombstones.size());
            for (Map.Entry<String, Tombstone> entry : tombstones.entrySet()) {
                writeString(out, entry.getKey());
                out.writeInt(entry.getValue().lastRevision);
                out.writeInt(entry.getValue().ackedRevision);
                out.writeLong(entry.getValue().updatedMs);
                writeString(out, entry.getValue().textHash);
                out.writeLong(entry.getValue().windowId);
            }
            out.flush();
            raw.getFD().sync();
            out.close();
            out = null;
            if (loadedVersion < VERSION && loadedSource != null) {
                // Preserve the exact valid legacy bytes once before changing the format.
                File legacy = new File(file.getParentFile(), "rayneo-context-pre-window-v3.dat");
                if (!legacy.exists()) {
                    File legacyTmp = new File(legacy.getPath() + ".tmp");
                    Files.copy(loadedSource.toPath(), legacyTmp.toPath(), StandardCopyOption.REPLACE_EXISTING);
                    try (FileOutputStream sync = new FileOutputStream(legacyTmp, true)) { sync.getFD().sync(); }
                    move(legacyTmp, legacy);
                }
            }
            move(tmp, file);
            loadedVersion = VERSION;
            loadedSource = file;
            try {
                File backupTmp = new File(backup.getPath() + ".tmp");
                Files.copy(file.toPath(), backupTmp.toPath(), StandardCopyOption.REPLACE_EXISTING);
                try (FileOutputStream sync = new FileOutputStream(backupTmp, true)) { sync.getFD().sync(); }
                move(backupTmp, backup);
            } catch (IOException ignored) {
                // The main store is already durable; backup refresh failure is not an ingest failure.
            }
            lastError = "";
            return true;
        } catch (IOException error) {
            lastError = error.getMessage() == null ? "persist_failed" : error.getMessage();
            try { Files.deleteIfExists(tmp.toPath()); } catch (IOException ignored) {}
            return false;
        } finally {
            if (out != null) try { out.close(); } catch (IOException ignored) {}
        }
    }

    private static void move(File from, File to) throws IOException {
        try {
            Files.move(from.toPath(), to.toPath(), StandardCopyOption.ATOMIC_MOVE,
                StandardCopyOption.REPLACE_EXISTING);
        } catch (IOException atomic) {
            Files.move(from.toPath(), to.toPath(), StandardCopyOption.REPLACE_EXISTING);
        }
    }

    private State state() {
        return new State(new ArrayList<Record>(segments), copyTombstones(), watermark, nextSeq,
            lastSuccessfulAckMs, windowId, windowStartedMs, windowOpen);
    }

    private void restore(State state) {
        segments.clear();
        segments.addAll(state.segments);
        tombstones.clear();
        tombstones.putAll(state.tombstones);
        watermark = state.watermark;
        nextSeq = state.nextSeq;
        lastSuccessfulAckMs = state.lastSuccessfulAckMs;
        windowId = state.windowId;
        windowStartedMs = state.windowStartedMs;
        windowOpen = state.windowOpen;
    }

    private LinkedHashMap<String, Tombstone> copyTombstones() {
        LinkedHashMap<String, Tombstone> copy = new LinkedHashMap<String, Tombstone>();
        for (Map.Entry<String, Tombstone> entry : tombstones.entrySet()) {
            Tombstone value = entry.getValue();
            copy.put(entry.getKey(), new Tombstone(value.lastRevision, value.ackedRevision, value.updatedMs,
                value.textHash, value.windowId));
        }
        return copy;
    }

    private static final class State {
        final ArrayList<Record> segments;
        final LinkedHashMap<String, Tombstone> tombstones;
        final long watermark, nextSeq, lastSuccessfulAckMs, windowId, windowStartedMs;
        final boolean windowOpen;
        State(ArrayList<Record> segments, LinkedHashMap<String, Tombstone> tombstones,
              long watermark, long nextSeq, long lastSuccessfulAckMs, long windowId,
              long windowStartedMs, boolean windowOpen) {
            this.segments = segments;
            this.tombstones = tombstones;
            this.watermark = watermark;
            this.nextSeq = nextSeq;
            this.lastSuccessfulAckMs = lastSuccessfulAckMs;
            this.windowId = windowId;
            this.windowStartedMs = windowStartedMs;
            this.windowOpen = windowOpen;
        }
    }

    private static void writeString(DataOutputStream out, String value) throws IOException {
        byte[] bytes = (value == null ? "" : value).getBytes(StandardCharsets.UTF_8);
        out.writeInt(bytes.length);
        out.write(bytes);
    }

    private static String readString(DataInputStream in) throws IOException {
        int length = in.readInt();
        if (length < 0 || length > 64 * 1024) throw new IOException("string");
        byte[] bytes = new byte[length];
        in.readFully(bytes);
        return new String(bytes, StandardCharsets.UTF_8);
    }

    static String sha256(String text) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] hash = digest.digest((text == null ? "" : text).getBytes(StandardCharsets.UTF_8));
            StringBuilder out = new StringBuilder(hash.length * 2);
            for (int i = 0; i < hash.length; i++) {
                out.append(String.format(Locale.ROOT, "%02x", Integer.valueOf(hash[i] & 0xff)));
            }
            return out.toString();
        } catch (Exception error) {
            throw new IllegalStateException("sha256", error);
        }
    }
}
