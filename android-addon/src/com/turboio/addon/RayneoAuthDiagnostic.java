package com.turboio.addon;

/** Content-free allowlist: server messages and credentials must never enter diagnostics. */
final class RayneoAuthDiagnostic {
    static String readBounded(java.io.InputStream in) throws java.io.IOException {
        java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
        if (in == null) return "";
        byte[] block = new byte[512]; int n;
        while ((n = in.read(block)) != -1) {
            if (out.size() + n > 4096) throw new java.io.IOException("error_limit");
            out.write(block, 0, n);
        }
        return out.toString("UTF-8");
    }
    static String code(int status, String serverCode) {
        String suffix = "unauthorized".equals(serverCode) || "source_mismatch".equals(serverCode)
            ? serverCode : "permission";
        return status == 401 || status == 403 ? "HTTP " + status + " " + suffix : "HTTP " + status;
    }
    static boolean isAuth(String value) {
        return "HTTP 401 unauthorized".equals(value) || "HTTP 401 source_mismatch".equals(value)
            || "HTTP 401 permission".equals(value) || "HTTP 403 unauthorized".equals(value)
            || "HTTP 403 source_mismatch".equals(value) || "HTTP 403 permission".equals(value);
    }
    static String safe(String value) { return isAuth(value) ? value : ""; }
}
