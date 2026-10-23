package com.turboio.addon;
public final class RayneoAuthDiagnosticTest {
    static int checks;
    static void check(boolean value) { checks++; if (!value) throw new AssertionError(checks); }
    public static void main(String[] args) throws Exception {
        for (int status : new int[]{401,403}) {
            for (String code : new String[]{"unauthorized","source_mismatch"}) {
                String value = RayneoAuthDiagnostic.code(status, code);
                check(value.equals("HTTP " + status + " " + code));
                check(RayneoAuthDiagnostic.isAuth(value));
                check(RayneoAuthDiagnostic.safe(value).equals(value));
            }
            for (String bad : new String[]{null,"","Bearer secret","unauthorized\nsecret","source_mismatch ","<html>secret</html>"}) {
                check(RayneoAuthDiagnostic.code(status,bad).equals("HTTP " + status + " permission"));
                check(RayneoAuthDiagnostic.safe(bad).isEmpty());
            }
        }
        for (int status : new int[]{200,400,404,500}) {
            String value=RayneoAuthDiagnostic.code(status,"unauthorized");
            check(value.equals("HTTP " + status));
            check(!RayneoAuthDiagnostic.isAuth(value));
        }
        check(RayneoAuthDiagnostic.safe("HTTP 401 unauthorized secret").isEmpty());
        check(RayneoAuthDiagnostic.safe("HTTP 401 source_mismatch\r\nBearer secret").isEmpty());
        check(RayneoAuthDiagnostic.readBounded(null).equals(""));
        check(RayneoAuthDiagnostic.readBounded(new java.io.ByteArrayInputStream(new byte[4096])).length()==4096);
        boolean rejected=false;
        try { RayneoAuthDiagnostic.readBounded(new java.io.ByteArrayInputStream(new byte[4097])); }
        catch(java.io.IOException expected) { rejected=expected.getMessage().equals("error_limit"); }
        check(rejected);
        rejected=false;
        try { RayneoAuthDiagnostic.readBounded(new java.io.InputStream() {
            public int read() throws java.io.IOException { throw new java.io.IOException("untrusted secret body"); }
        }); } catch(java.io.IOException expected) { rejected=true; }
        check(rejected);
        System.out.println("RayneoAuthDiagnosticTest " + checks + " checks PASS");
    }
}
