package com.turboio.addon;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;
import java.util.UUID;

/**
 * Durable source_instance plus recording session. Neither value is minted on
 * every process restart; that would break dedup. A new recording session is
 * only created when the identity file is first written.
 */
public final class RayneoSourceIdentity {
    public static final String FILE = "source-instance.v1";
    public final String sourceInstance;
    public final String recordingSession;

    RayneoSourceIdentity(String sourceInstance, String recordingSession) {
        this.sourceInstance = sourceInstance;
        this.recordingSession = recordingSession;
    }

    public static RayneoSourceIdentity loadOrCreate(File directory) {
        if (directory == null) throw new IllegalArgumentException("directory");
        if (!directory.isDirectory() && !directory.mkdirs()) throw new IllegalStateException("directory");
        File file = new File(directory, FILE);
        RayneoSourceIdentity loaded = read(file);
        if (loaded != null) return loaded;
        RayneoSourceIdentity created = new RayneoSourceIdentity(
            "rayneo-android-" + UUID.randomUUID().toString(),
            "rec-" + UUID.randomUUID().toString());
        write(file, created);
        RayneoSourceIdentity confirmed = read(file);
        return confirmed != null ? confirmed : created;
    }

    private static RayneoSourceIdentity read(File file) {
        if (!file.isFile()) return null;
        BufferedReader reader = null;
        try {
            reader = new BufferedReader(new InputStreamReader(new FileInputStream(file), StandardCharsets.UTF_8));
            String instance = AlwaysOnConsume.normalizeSourceInstance(reader.readLine());
            String session = AlwaysOnConsume.normalizeToken(reader.readLine(), 128);
            if (instance == null || session == null) return null;
            return new RayneoSourceIdentity(instance, session);
        } catch (Exception ignored) {
            return null;
        } finally {
            if (reader != null) try { reader.close(); } catch (Exception ignored) {}
        }
    }

    private static void write(File file, RayneoSourceIdentity identity) {
        File tmp = new File(file.getPath() + ".tmp");
        BufferedWriter writer = null;
        try {
            writer = new BufferedWriter(new OutputStreamWriter(new FileOutputStream(tmp), StandardCharsets.UTF_8));
            writer.write(identity.sourceInstance);
            writer.newLine();
            writer.write(identity.recordingSession);
            writer.newLine();
            writer.flush();
            writer.close();
            writer = null;
            Files.move(tmp.toPath(), file.toPath(), StandardCopyOption.REPLACE_EXISTING);
        } catch (Exception ignored) {
            try { Files.deleteIfExists(tmp.toPath()); } catch (Exception ignoredAgain) {}
        } finally {
            if (writer != null) try { writer.close(); } catch (Exception ignored) {}
        }
    }
}
