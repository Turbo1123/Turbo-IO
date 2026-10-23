package com.turboio.addon;
import java.io.*;
import java.nio.ByteBuffer;
import java.nio.channels.FileChannel;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.nio.file.attribute.BasicFileAttributes;
import java.security.MessageDigest;
import java.util.*;

/** Glasses-log files (port of iOS TIOGlassesLogLocalURL/Copy and the archive receipt): the received archive must
 * sit under the host receive sandbox with no symlink from the point the path enters it, is copied only while its
 * size, mtime and identity stay fixed, and the private copy is verified by SHA-256 on restore. The original is
 * never modified or deleted. Pure Java (no Android). */
final class GlassesLogFiles {
    static final long LIMIT=32L*1024*1024;
    static Runnable changeHook;
    private GlassesLogFiles(){}
    static final class Copy{File file;long bytes;String sha256;}
    static final class Restored{File file;String task,sha256;long bytes;boolean recovered;}

    private static BasicFileAttributes lstat(Path p)throws IOException{return Files.readAttributes(p,BasicFileAttributes.class,LinkOption.NOFOLLOW_LINKS);}
    /** The validated path of a received archive under sandbox, or null. */
    static Path localPath(String filePath,File sandbox,long limit){
        try{
            if(filePath==null||filePath.isEmpty()||filePath.length()>1024||!filePath.startsWith("/")||filePath.indexOf('\0')>=0||sandbox==null)return null;
            for(String part:filePath.split("/"))if(part.equals("..")||part.equals("."))return null;
            Path root=sandbox.toPath().toRealPath();if(root.getParent()==null)return null;
            Path raw=Paths.get(filePath),real=raw.toRealPath();if(!real.startsWith(root)||real.equals(root))return null;
            boolean entered=false;Path walk=raw.getRoot();
            for(Path part:raw){walk=walk.resolve(part);
                if(!Files.exists(walk,LinkOption.NOFOLLOW_LINKS))return null;
                if(!entered&&walk.toRealPath().equals(root))entered=true;
                if(entered&&Files.isSymbolicLink(walk))return null;}
            if(!entered)return null;
            Path parent=raw.getParent();if(parent==null||!parent.toRealPath().startsWith(root))return null;
            BasicFileAttributes a=lstat(raw);if(!a.isRegularFile()||a.size()<=0||a.size()>limit)return null;
            return raw;
        }catch(IOException|RuntimeException e){return null;}
    }
    static String sha256(byte[] b){try{return hex(MessageDigest.getInstance("SHA-256").digest(b));}catch(Exception e){throw new IllegalStateException(e);}}
    private static String hex(byte[] d){StringBuilder s=new StringBuilder();for(byte x:d)s.append(String.format(Locale.ROOT,"%02x",x&255));return s.toString();}
    static String sha256(File f){try(InputStream in=new FileInputStream(f)){MessageDigest md=MessageDigest.getInstance("SHA-256");byte[] buf=new byte[65536];int k;while((k=in.read(buf))>0)md.update(buf,0,k);return hex(md.digest());}catch(Exception e){return null;}}
    /** A private 0600 copy research-<uuid>.tar.lz4 in dir; refused if the source changes or is not a stable regular file. */
    static Copy copy(Path source,File sandbox,File dir,long limit){
        File out=null;
        try{
            // Re-validate at copy time: the same no-symlink-inside-the-sandbox walk as localPath.
            if(source==null||dir==null||localPath(source.toString(),sandbox,limit)==null)return null;
            if(!dir.isDirectory()&&!dir.mkdirs())return null;
            BasicFileAttributes before=lstat(source);if(!before.isRegularFile()||before.size()<=0||before.size()>limit)return null;
            out=new File(dir,"research-"+UUID.randomUUID().toString().toLowerCase(Locale.ROOT)+".tar.lz4");long copied=0;
            try(FileChannel in=FileChannel.open(source,StandardOpenOption.READ,LinkOption.NOFOLLOW_LINKS);
                FileChannel o=FileChannel.open(out.toPath(),StandardOpenOption.CREATE_NEW,StandardOpenOption.WRITE,LinkOption.NOFOLLOW_LINKS)){
                ByteBuffer buf=ByteBuffer.allocate(65536);int k;while((k=in.read(buf))>0){copied+=k;if(copied>before.size())break;buf.flip();while(buf.hasRemaining())o.write(buf);buf.clear();}
                Runnable hook=changeHook;if(hook!=null)hook.run();
                BasicFileAttributes after=lstat(source);
                if(copied!=before.size()||after.size()!=before.size()||!after.lastModifiedTime().equals(before.lastModifiedTime())||!Objects.equals(after.fileKey(),before.fileKey()))throw new IOException("changed");
                o.force(true);
            }
            out.setReadable(false,false);out.setReadable(true,true);out.setWritable(false,false);out.setWritable(true,true);
            String sha=sha256(out);if(sha==null)throw new IOException("hash");
            Copy c=new Copy();c.file=out;c.bytes=copied;c.sha256=sha;return c;
        }catch(IOException|RuntimeException e){return copyRefuse(out);}
    }
    private static Copy copyRefuse(File partial){if(partial!=null)partial.delete();return null;}

    static Map<String,Object> readJson(File f){
        try{if(f==null||!f.isFile()||f.length()>65536)return null;Object o=BoundedJson.readDevice(Files.readAllBytes(f.toPath()));return o instanceof Map?BoundedJson.map(o):null;}catch(IOException|RuntimeException e){return null;}
    }
    /** Atomic sorted-key JSON, owner-only. */
    static boolean writeJson(File f,Map<String,Object> json){
        File tmp=new File(f.getParentFile(),"."+f.getName()+"."+UUID.randomUUID()+".tmp");
        try{byte[] b=BoundedJson.canonical(json);try(FileOutputStream o=new FileOutputStream(tmp)){o.write(b);o.getFD().sync();}
            tmp.setReadable(false,false);tmp.setReadable(true,true);Files.move(tmp.toPath(),f.toPath(),StandardCopyOption.REPLACE_EXISTING,StandardCopyOption.ATOMIC_MOVE);return true;}
        catch(IOException|RuntimeException e){tmp.delete();return false;}
    }
    static boolean saveReceipt(File home,Copy c,String device,String task){
        if(c==null||device==null||GlassesLogContract.taskId(task)==null)return false;Map<String,Object> r=new LinkedHashMap<>();
        r.put("bytes",c.bytes);r.put("sha256",c.sha256);r.put("savedName",c.file.getName());r.put("formatVerified",false);r.put("device",device);r.put("task",GlassesLogContract.taskId(task));r.put("source","native-receiver");
        return writeJson(new File(home,"archive.json"),r);
    }
    /** The saved archive, if its receipt matches the owner device and the file's size and SHA-256. */
    static Restored restore(File home,String ownerDevice){
        Map<String,Object> r=readJson(new File(home,"archive.json"));if(r==null||ownerDevice==null)return null;
        Object name=r.get("savedName"),dev=r.get("device"),bytes=r.get("bytes"),sha=r.get("sha256"),src=r.get("source");String task=GlassesLogContract.taskId(r.get("task"));
        if(!(name instanceof String)||!((String)name).matches("research-[0-9a-z-]{1,64}\\.tar\\.lz4")||!ownerDevice.equals(dev)||task==null||!(sha instanceof String)||!(bytes instanceof Long))return null;
        long n=(Long)bytes;if(n<=0||n>LIMIT)return null;
        File f=new File(home,(String)name);Path p=localPath(f.getAbsolutePath(),home,LIMIT);if(p==null||f.length()!=n||!sha.equals(sha256(f)))return null;
        Restored out=new Restored();out.file=f;out.task=task;out.sha256=(String)sha;out.bytes=n;out.recovered="mac-recovered-v1".equals(src);return out;
    }
}
