package com.turboio.addon;

import android.content.Context;
import android.content.SharedPreferences;
import org.json.JSONObject;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URI;
import java.net.URL;
import java.nio.charset.StandardCharsets;

/**
 * Thin B-contract transport for rayneo-context/v1. This is an internal adapter:
 * the only cross-end protocol is POST /ingest and POST /v1/rayneo/query; the old
 * /query -> /jobs/{id} knowledge shape is not used as the Rayneo protocol.
 */
final class RayneoContextClient {
    static final int MAX_UPLOAD_PER_RUN = 8;
    static final int MAX_RETRY = 5;

    private final Context app;
    private final SharedPreferences prefs;

    RayneoContextClient(Context context) {
        app = context;
        prefs = app.getSharedPreferences("turboio_settings", 0);
    }

    static boolean validBase(String value) {
        try {
            URI uri = new URI(value == null ? "" : value.trim());
            if (!"https".equals(uri.getScheme()) || uri.getHost() == null) return false;
            if (uri.getUserInfo() != null || uri.getQuery() != null || uri.getFragment() != null) return false;
            String path = uri.getPath();
            return path == null || path.isEmpty() || "/".equals(path);
        } catch (Exception ignored) {
            return false;
        }
    }

    private String rayneoKey() {
        try {
            return SecretStore.get(app, "rayneo_key");
        } catch (Exception ignored) {
            return "";
        }
    }

    private String base() {
        String value = prefs.getString("rayneo_url", "").trim();
        return value.endsWith("/") ? value.substring(0, value.length() - 1) : value;
    }

    boolean uploadConfigured() {
        return prefs.getBoolean("rayneo_upload", false) && endpointConfigured();
    }

    boolean endpointConfigured() {
        return validBase(prefs.getString("rayneo_url", "")) && !rayneoKey().isEmpty();
    }

    boolean queryConfigured() {
        return prefs.getBoolean("rayneo_query", false) && validBase(prefs.getString("rayneo_url", ""))
            && !rayneoKey().isEmpty();
    }

    /** Uploads a bounded slice. A server body confirming the same revision is the only ACK trigger. */
    JSONObject uploadPending(RayneoContextQueue queue) throws Exception {
        final String root = base();
        final long windowId = prefs.getLong("rayneo_upload_window_id", 0L);
        RayneoContextProtocol.DeliveryResult delivered = RayneoContextProtocol.deliverWindow(queue,
            new RayneoContextProtocol.Poster() {
                public RayneoContextProtocol.HttpResult post(String path, String jsonBody) {
                    try {
                        JSONObject json = http(root + path, new JSONObject(jsonBody));
                        return RayneoContextProtocol.HttpResult.success(json.optInt("_http", 200), json.toString());
                    } catch (Exception error) {
                        return classify(error);
                    }
                }
            }, uploadConfigured(), MAX_UPLOAD_PER_RUN, windowId);
        JSONObject out = new JSONObject();
        return out.put("status", delivered.status)
            .put("sent", delivered.sent)
            .put("pending", queue == null ? 0 : queue.activeCount())
            .put("pendingTotal", queue == null ? 0 : queue.pendingCount())
            .put("retained", queue == null ? 0 : queue.retainedCount())
            .put("skippedOld", delivered.skippedOld)
            .put("acked", delivered.acked)
            .put("lastError", delivered.lastError)
            .put("contract_version", RayneoContextProtocol.CONTRACT_VERSION);
    }

    JSONObject query(String topic, int limit) throws Exception {
        if (!queryConfigured()) throw new IllegalArgumentException("rayneo_query_not_configured");
        String clean = topic == null ? "" : topic.trim();
        if (clean.length() < 2 || clean.length() > 200) throw new IllegalArgumentException("topic");
        int bounded = Math.max(1, Math.min(50, limit));
        JSONObject body = new JSONObject()
            .put("source", "rayneo")
            .put("topic", clean)
            .put("limit", bounded)
            .put("max_text_chars", 2000)
            .put("max_total_tokens", 4000)
            .put("include_derived", true);
        JSONObject result = http(base() + RayneoContextProtocol.QUERY_PATH, body);
        result.put("instruction_eligible", false);
        result.put("untrusted_data", true);
        result.put("source", RayneoContextProtocol.SOURCE);
        result.put("contract_version", RayneoContextProtocol.CONTRACT_VERSION);
        return result;
    }

    JSONObject control(String action) throws Exception {
        if (!uploadConfigured() && !queryConfigured()) throw new IllegalArgumentException("rayneo_not_configured");
        return http(base() + RayneoContextProtocol.CONTROL_PATH,
            new JSONObject().put("source", "rayneo").put("action", action));
    }

    /** Uses saved SecretStore credentials on the actual app transport; never queries history. */
    String checkSavedAuthentication() throws Exception {
        if (prefs.getBoolean("rayneo_upload", false)) return "请先关闭上传并保存";
        if (!queryConfigured())
            return "请先保存有效的 HTTPS 根地址与查询配置";
        JSONObject body = new JSONObject().put("source", "rayneo")
            .put("segment_id", "auth-diag-" + java.util.UUID.randomUUID().toString())
            .put("limit", 1).put("max_text_chars", 1).put("max_total_tokens", 1)
            .put("include_derived", false);
        try {
            JSONObject result = http(base() + RayneoContextProtocol.QUERY_PATH, body);
            boolean empty = result.optBoolean("ok", false) && "rayneo".equals(result.optString("source"))
                && !result.optBoolean("query_disabled", true)
                && result.optJSONArray("items") != null && result.optJSONArray("items").length() == 0
                && result.optJSONArray("derived") != null && result.optJSONArray("derived").length() == 0;
            return result.optInt("_http", 0) == 200 && empty
                ? "HTTP 200；鉴权通过；指定测试标识无记录"
                : "响应不符合空结果约定；未显示内容";
        } catch (Exception error) {
            String safe = RayneoAuthDiagnostic.safe(error.getMessage());
            return safe.isEmpty() ? "检查失败；未显示服务正文" : safe;
        }
    }

    static RayneoContextProtocol.HttpResult classify(Exception error) {
        String message = error.getMessage() == null ? "" : error.getMessage();
        if (RayneoAuthDiagnostic.isAuth(message)) {
            return RayneoContextProtocol.HttpResult.error(message);
        }
        if (message.startsWith("HTTP 401") || message.startsWith("HTTP 403")) {
            return RayneoContextProtocol.HttpResult.permission();
        }
        if (error instanceof java.net.SocketTimeoutException || "timeout".equals(message)) {
            return RayneoContextProtocol.HttpResult.timeout();
        }
        if (error instanceof java.net.UnknownHostException || error instanceof java.net.ConnectException) {
            return RayneoContextProtocol.HttpResult.offline();
        }
        return RayneoContextProtocol.HttpResult.error(message.matches("HTTP [0-9]{3}") ? message : "upload_failed");
    }

    private JSONObject http(String url, JSONObject body) throws Exception {
        HttpURLConnection connection = (HttpURLConnection) new URL(url).openConnection();
        try {
            connection.setInstanceFollowRedirects(false);
            connection.setConnectTimeout(12000);
            connection.setReadTimeout(20000);
            connection.setRequestMethod("POST");
            connection.setDoOutput(true);
            connection.setRequestProperty("Authorization", "Bearer " + SecretStore.get(app, "rayneo_key"));
            connection.setRequestProperty("Accept", "application/json");
            connection.setRequestProperty("Content-Type", "application/json");
            byte[] bytes = body.toString().getBytes(StandardCharsets.UTF_8);
            connection.setFixedLengthStreamingMode(bytes.length);
            try (OutputStream stream = connection.getOutputStream()) {
                stream.write(bytes);
            }
            int code = connection.getResponseCode();
            if (code == 204) return new JSONObject().put("_http", code);
            if (code < 200 || code >= 300) {
                String serverCode = "";
                if (code == 401 || code == 403) {
                    // Bounded parse; retain only the two known error identifiers, never raw text.
                    try (InputStream in = connection.getErrorStream()) {
                        if (in != null) {
                            JSONObject errorObject = new JSONObject(RayneoAuthDiagnostic.readBounded(in)).optJSONObject("error");
                            serverCode = errorObject == null ? "" : errorObject.optString("code", "");
                        }
                    } catch (Exception ignored) { serverCode = ""; }
                }
                String safe = RayneoAuthDiagnostic.code(code, serverCode);
                if (RayneoAuthDiagnostic.isAuth(safe)
                    && prefs.getString("rayneo_first_auth_error", "").isEmpty()) {
                    prefs.edit().putString("rayneo_first_auth_error", safe).commit();
                }
                throw new IOException(safe);
            }
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            try (InputStream in = connection.getInputStream()) {
                byte[] block = new byte[8192];
                int n;
                while ((n = in.read(block)) != -1) {
                    if (out.size() + n > 1048576) throw new IOException("limit");
                    out.write(block, 0, n);
                }
            }
            String text = out.toString("UTF-8").trim();
            JSONObject json = text.isEmpty() ? new JSONObject() : new JSONObject(text);
            json.put("_http", code);
            return json;
        } finally {
            connection.disconnect();
        }
    }
}
