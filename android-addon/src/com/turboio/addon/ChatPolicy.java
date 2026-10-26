package com.turboio.addon;

import java.net.URI;
import java.util.ArrayList;
import java.util.List;

/** Platform-independent rules ported from the iOS addon, not vendor source. */
public final class ChatPolicy {
    private ChatPolicy() {}
    public static boolean eligible(String domain, String intent, String sub, boolean offline, boolean command) {
        return "chat".equals(domain) && "chat".equals(intent) && "workflow".equals(sub) && !offline && !command;
    }
    /** DeepSeek "thinking":{"type":"disabled"} extension; a missing pref keeps the previous always-on behaviour. */
    public static boolean thinkingDisabled(Boolean stored){return stored==null||stored;}
    public static boolean endpoint(String value) {
        try {
            URI uri = new URI(value);
            return "https".equalsIgnoreCase(uri.getScheme()) && uri.getHost() != null
                && uri.getRawUserInfo() == null && uri.getRawQuery() == null && uri.getRawFragment() == null
                && uri.getPath().endsWith("/chat/completions");
        } catch (Exception ignored) { return false; }
    }
    public static String delta(String previous, String current) {
        return current.startsWith(previous) ? current.substring(previous.length()) : null;
    }
    public static final class History {
        private final List<String[]> messages = new ArrayList<>();
        public synchronized void append(String question, String answer) {
            if (question == null || answer == null || question.isEmpty() || answer.isEmpty()
                || question.length() > 16000 || answer.length() > 64000) return;
            messages.add(new String[]{"user", question});
            messages.add(new String[]{"assistant", answer});
            while (messages.size() > 50) messages.remove(0);
        }
        public synchronized List<String[]> snapshot() {
            List<String[]> result = new ArrayList<>();
            for (String[] row : messages) result.add(row.clone());
            return result;
        }
        public synchronized void clear() { messages.clear(); }
    }
}
