package com.turboio.addon;
import java.io.*;import java.nio.file.*;import java.util.*;

/** GlassesLogFiles against a real temp dir: sandbox path walk, stable private copy, receipts and restore. */
public final class GlassesLogFilesTest {
    static int n;static void ok(boolean b,String why){n++;if(!b)throw new AssertionError("files "+n+" "+why);}
    static final String TASK="73920000-1234-4567-8123-000000008642";
    public static void main(String[] a)throws Exception{
        Path tmp=Files.createTempDirectory("glog");try{
            Path sandbox=Files.createDirectories(tmp.resolve("files/cc_transfer")),home=Files.createDirectories(tmp.resolve("private"));
            byte[] body=new byte[5000];new Random(7).nextBytes(body);Path src=sandbox.resolve("venus_123_log.tar.lz4");Files.write(src,body);
            ok(GlassesLogFiles.localPath(src.toString(),sandbox.toFile(),100000)!=null,"local path under the sandbox");
            ok(GlassesLogFiles.localPath(src.toString(),sandbox.toFile(),1)==null,"size limit");
            ok(GlassesLogFiles.localPath(src.toString(),home.toFile(),100000)==null,"other root refused");
            ok(GlassesLogFiles.localPath(sandbox.resolve("venus_9_log.tar.lz4").toString(),sandbox.toFile(),100000)==null,"missing file");
            ok(GlassesLogFiles.localPath(sandbox.toString()+"/../cc_transfer/venus_123_log.tar.lz4",sandbox.toFile(),100000)==null,"dot-dot refused");
            Path real=Files.createDirectories(sandbox.resolve("real"));Files.write(real.resolve("venus_5_log.tar.lz4"),body);Files.createSymbolicLink(sandbox.resolve("link"),real);
            ok(GlassesLogFiles.localPath(sandbox.resolve("link/venus_5_log.tar.lz4").toString(),sandbox.toFile(),100000)==null,"symlinked dir refused");
            Path outside=Files.write(tmp.resolve("venus_6_log.tar.lz4"),body);Files.createSymbolicLink(sandbox.resolve("venus_7_log.tar.lz4"),outside);
            ok(GlassesLogFiles.localPath(sandbox.resolve("venus_7_log.tar.lz4").toString(),sandbox.toFile(),100000)==null,"symlinked file refused");
            Path rootLink=Files.createSymbolicLink(tmp.resolve("alias"),sandbox);
            ok(GlassesLogFiles.localPath(rootLink.resolve("venus_123_log.tar.lz4").toString(),sandbox.toFile(),100000)==null,"entering the root through a symlink refused");
            // Copy.
            Path p=GlassesLogFiles.localPath(src.toString(),sandbox.toFile(),100000);GlassesLogFiles.Copy c=GlassesLogFiles.copy(p,sandbox.toFile(),home.toFile(),100000);
            ok(c!=null&&Arrays.equals(Files.readAllBytes(c.file.toPath()),body)&&Files.exists(src)&&c.bytes==5000&&c.file.getName().matches("research-[0-9a-f-]{36}\\.tar\\.lz4"),"copy identical, original kept");
            ok(c.sha256.equals(GlassesLogFiles.sha256(body)),"sha256");
            ok(GlassesLogFiles.copy(p,sandbox.toFile(),home.toFile(),1)==null,"copy limit");
            ok(GlassesLogFiles.copy(sandbox.resolve("link/venus_5_log.tar.lz4"),sandbox.toFile(),home.toFile(),100000)==null,"copy refuses a symlinked path");
            int before=home.toFile().list().length;GlassesLogFiles.changeHook=()->{try{Files.write(src,new byte[]{1,2,3},StandardOpenOption.APPEND);}catch(IOException e){throw new UncheckedIOException(e);}};
            ok(GlassesLogFiles.copy(p,sandbox.toFile(),home.toFile(),100000)==null&&home.toFile().list().length==before,"file changing during copy refused, partial removed");GlassesLogFiles.changeHook=null;
            // A symlink BEFORE the sandbox (Android /data/user/0 → /data/data) is fine; the root is the real directory.
            Path user=Files.createSymbolicLink(tmp.resolve("user0"),tmp.resolve("files"));String viaUser=user.resolve("cc_transfer/venus_123_log.tar.lz4").toString();
            ok(GlassesLogFiles.localPath(viaUser,new File(user.toString(),"cc_transfer"),100000)!=null,"symlink before the sandbox is allowed");
            GlassesLogFiles.Copy viaCopy=GlassesLogFiles.copy(Paths.get(viaUser),new File(user.toString(),"cc_transfer"),home.toFile(),100000);ok(viaCopy!=null&&viaCopy.bytes==Files.size(src),"copy through a pre-sandbox symlink");
            // Receipts and restore.
            GlassesLogFiles.Copy fresh=GlassesLogFiles.copy(GlassesLogFiles.localPath(src.toString(),sandbox.toFile(),100000),sandbox.toFile(),home.toFile(),100000);
            ok(GlassesLogFiles.saveReceipt(home.toFile(),fresh,"test",TASK),"save receipt");
            GlassesLogFiles.Restored r=GlassesLogFiles.restore(home.toFile(),"test");ok(r!=null&&TASK.equals(r.task)&&r.bytes==fresh.bytes&&!r.recovered&&r.file.equals(fresh.file),"restore");
            ok(GlassesLogFiles.restore(home.toFile(),"other")==null,"other device refused");
            try(java.io.RandomAccessFile raf=new java.io.RandomAccessFile(fresh.file,"rw")){raf.seek(10);int v=raf.read();raf.seek(10);raf.write(v^1);}ok(GlassesLogFiles.restore(home.toFile(),"test")==null,"same-size tamper refused by sha256");
            Files.write(fresh.file.toPath(),new byte[]{9},StandardOpenOption.APPEND);ok(GlassesLogFiles.restore(home.toFile(),"test")==null,"tampered copy refused");
            Map<String,Object> bad=new LinkedHashMap<>(GlassesLogFiles.readJson(new File(home.toFile(),"archive.json")));bad.put("savedName","../x.tar.lz4");GlassesLogFiles.writeJson(new File(home.toFile(),"archive.json"),bad);
            ok(GlassesLogFiles.restore(home.toFile(),"test")==null,"savedName must be a bare research name");
            Map<String,Object> owner=new LinkedHashMap<>();owner.put("device","test");ok(GlassesLogFiles.writeJson(new File(home.toFile(),"owner.json"),owner)&&"test".equals(GlassesLogFiles.readJson(new File(home.toFile(),"owner.json")).get("device")),"json round trip");
            ok(GlassesLogFiles.readJson(new File(home.toFile(),"missing.json"))==null,"missing json");
        }finally{try(java.util.stream.Stream<Path> w=Files.walk(tmp)){w.sorted(Comparator.reverseOrder()).forEach(x->x.toFile().delete());}}
        System.out.println("GlassesLogFilesTest: "+n+" checks; sandbox walk (symlinks, dot-dot, other root), stable copy, sha256, receipts, restore");
    }
}
