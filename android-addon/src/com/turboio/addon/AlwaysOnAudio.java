package com.turboio.addon;
import java.io.*;
import java.nio.file.*;
import java.nio.file.attribute.BasicFileAttributes;
import java.util.*;

/** Official always-on (全天智记) audio dumps (port of iOS AlwaysOnAudioFiles.m / AlwaysOnOgg.m): list only the
 * official sessions directory, copy a listed file only while it is unchanged, validate Ogg/Opus copies and repair
 * legacy granule positions in the copy. The original files are never modified. */
final class AlwaysOnAudio {
    static final String COPY_ERROR="无法生成稳定的智记音频副本。请先停止本次全天智记，再刷新重试；原文件未改。";
    static final long MAX_FILE=1024L*1024*1024;
    static Runnable testHook;
    private AlwaysOnAudio(){}
    static final class Entry{final File file;final String name,kind;final long date,bytes;Entry(File f,String n,String k,long d,long b){file=f;name=n;kind=k;date=d;bytes=b;}}
    private static boolean dir(Path p){return Files.isDirectory(p,LinkOption.NOFOLLOW_LINKS);}
    /** <base>/always_on_debug/sessions: depth ≤ 3, opus/ogg/pcm, regular, 1 B..1 GiB, no symlinks, ≤4000 visited, ≤500 rows. */
    static List<Entry> list(File base){
        List<Entry> rows=new ArrayList<>();Path b=base.toPath(),debug=b.resolve("always_on_debug"),root=debug.resolve("sessions");
        if(!dir(b)||!dir(debug)||!dir(root))return rows;
        int[] seen={0};
        try{Files.walkFileTree(root,EnumSet.noneOf(FileVisitOption.class),3,new SimpleFileVisitor<Path>(){
            @Override public FileVisitResult visitFile(Path f,BasicFileAttributes a){
                if(++seen[0]>4000)return FileVisitResult.TERMINATE;
                if(a.isSymbolicLink()||!a.isRegularFile()||a.size()<=0||a.size()>MAX_FILE)return FileVisitResult.CONTINUE;
                String name=f.getFileName().toString(),lower=name.toLowerCase(Locale.ROOT);int dot=lower.lastIndexOf('.');String ext=dot<0?"":lower.substring(dot+1);
                if(!ext.equals("opus")&&!ext.equals("ogg")&&!ext.equals("pcm"))return FileVisitResult.CONTINUE;
                String kind=lower.contains("cached")?"缓存音频":lower.contains("realtime")?"实时音频":"智记调试音频（来源待核对）";
                rows.add(new Entry(f.toFile(),name,kind,a.lastModifiedTime().toMillis(),a.size()));return rows.size()>=500?FileVisitResult.TERMINATE:FileVisitResult.CONTINUE;}
            @Override public FileVisitResult visitFileFailed(Path f,IOException e){return FileVisitResult.CONTINUE;}
        });}catch(IOException ignored){}
        rows.sort((x,y)->Long.compare(y.date,x.date));return rows;
    }
    private static void delete(File f){File[] c=f.listFiles();if(c!=null)for(File x:c)delete(x);f.delete();}
    /** Stable copy of a listed file into exportRoot/<uuid>/全天智记音频.<ext>; Ogg/Opus copies validated or refused. */
    static File copy(File base,File source,File exportRoot){
        File folder=null;
        try{
            String want=source.getCanonicalPath();boolean listed=false;for(Entry e:list(base))if(e.file.getCanonicalPath().equals(want)&&!Files.isSymbolicLink(source.toPath()))listed=true;
            if(!listed)throw new IllegalArgumentException(COPY_ERROR);
            long size=source.length(),modified=source.lastModified();if(size<=0||size>MAX_FILE)throw new IllegalArgumentException(COPY_ERROR);
            String lower=source.getName().toLowerCase(Locale.ROOT),ext=lower.substring(lower.lastIndexOf('.')+1);
            if(exportRoot.exists()&&!dir(exportRoot.toPath()))throw new IllegalArgumentException(COPY_ERROR);
            folder=new File(exportRoot,UUID.randomUUID().toString());if(!folder.mkdirs())throw new IllegalArgumentException(COPY_ERROR);
            // Keep the actual format extension; raw PCM is never renamed into a fake WAV.
            File out=new File(folder,"全天智记音频."+ext);long copied=0;
            try(InputStream in=new FileInputStream(source);OutputStream o=new FileOutputStream(out)){byte[] buf=new byte[65536];int k;while((k=in.read(buf))>0){copied+=k;if(copied>size)break;o.write(buf,0,k);}o.flush();}
            Runnable hook=testHook;if(hook!=null)hook.run();
            if(copied!=size||source.length()!=size||source.lastModified()!=modified)throw new IllegalArgumentException(COPY_ERROR);
            if((ext.equals("ogg")||ext.equals("opus"))&&!finalizeOgg(out))throw new IllegalArgumentException(COPY_ERROR);
            return out;
        }catch(IllegalArgumentException e){if(folder!=null)delete(folder);throw e;}
        catch(IOException|RuntimeException e){if(folder!=null)delete(folder);throw new IllegalArgumentException(COPY_ERROR);}
    }
    private static long le32(byte[] p,int at){return (p[at]&255L)|(p[at+1]&255L)<<8|(p[at+2]&255L)<<16|(p[at+3]&255L)<<24;}
    private static long le64(byte[] p,int at){return le32(p,at)|le32(p,at+4)<<32;}
    private static long crc(byte[] p){long c=0;for(int i=0;i<p.length;i++){c^=((i>=22&&i<26)?0:(p[i]&255L))<<24;for(int b=0;b<8;b++)c=((c<<1)^(((c&0x80000000L)!=0)?0x04c11db7L:0))&0xffffffffL;}return c;}
    private static int samples(byte[] p,int n){
        if(n==0)return 0;int t=p[0]&255;int spf=(t&128)!=0?(48000<<((t>>3)&3))/400:((t&96)==96?((t&8)!=0?960:480):(((t>>3)&3)==3?2880:(48000<<((t>>3)&3))/100));
        int frames=(t&3)==0?1:(t&3)==3?(n>1?p[1]&63:0):2;return frames>0&&spf*frames<=5760?spf*frames:0;
    }
    /** TIOFinalizeAlwaysOnOgg: valid single-stream Ogg Opus; legacy granules (count*960+preskip) rewritten to sample totals. */
    static boolean finalizeOgg(File copy){boolean[] repair={false};if(!scan(copy,false,repair))return false;return !repair[0]||scan(copy,true,null);}
    private static boolean scan(File file,boolean write,boolean[] needsRepair){
        boolean ok=false,eos=false,legacy=true,correct=true;long serial=0,seq=0,total=0,count=0;int packets=0,skip=0;ByteArrayOutputStream packet=new ByteArrayOutputStream();
        try(RandomAccessFile f=new RandomAccessFile(file,write?"rw":"r")){
            for(int pageIndex=0;pageIndex<100000;pageIndex++){
                long offset=f.getFilePointer();byte[] header=new byte[27];int got=f.read(header);
                if(got<=0){ok=eos&&packets>2&&packet.size()==0&&(legacy||correct);break;}
                if(eos||got!=27)break;
                if(header[0]!='O'||header[1]!='g'||header[2]!='g'||header[3]!='S'||header[4]!=0||(header[5]&~7)!=0||(((header[5]&1)!=0)!=(packet.size()>0)))break;
                if(pageIndex==0){if((header[5]&2)==0||le32(header,18)!=0)break;serial=le32(header,14);}else if((header[5]&2)!=0)break;
                if(le32(header,14)!=serial||le32(header,18)!=seq++)break;
                int n=header[26]&255;byte[] laces=new byte[n];if(n>0&&f.read(laces)!=n)break;int size=0;for(byte l:laces)size+=l&255;
                byte[] body=new byte[size];if(size>0&&f.read(body)!=size)break;
                byte[] page=new byte[27+n+size];System.arraycopy(header,0,page,0,27);System.arraycopy(laces,0,page,27,n);System.arraycopy(body,0,page,27+n,size);
                if(crc(page)!=le32(header,22))break;
                int at=0,completed=0;boolean valid=true;
                for(int i=0;i<n;i++){int len=laces[i]&255;packet.write(body,at,len);at+=len;if(packet.size()>65536){valid=false;break;}if(len==255)continue;
                    byte[] p=packet.toByteArray();int plen=p.length;
                    if(packets==0){if(plen!=19||!new String(p,0,8,"ISO-8859-1").equals("OpusHead")||p[8]!=1||p[18]!=0||!(p[9]==1||p[9]==2)){valid=false;break;}skip=(p[10]&255)|(p[11]&255)<<8;}
                    else if(packets==1){if(plen<8||!new String(p,0,8,"ISO-8859-1").equals("OpusTags")){valid=false;break;}}
                    else{int s=samples(p,plen);if(s==0){valid=false;break;}total+=s;count++;completed++;}
                    packets++;packet.reset();}
                if(!valid)break;long gp=le64(header,6);eos=(header[5]&4)!=0;
                if(eos&&(count==0||packet.size()>0))break;
                if(completed>0){legacy=legacy&&gp==count*960+skip;correct=correct&&gp==total;
                    if(write){for(int i=0;i<8;i++)page[6+i]=(byte)(total>>(8*i));long c=crc(page);for(int i=0;i<4;i++)page[22+i]=(byte)(c>>(8*i));long resume=f.getFilePointer();f.seek(offset);f.write(page);f.seek(resume);}}
                else if(gp!=(packet.size()>0?-1L:0))break;
            }
            if(write&&ok)f.getFD().sync();
        }catch(IOException|RuntimeException e){ok=false;}
        if(needsRepair!=null)needsRepair[0]=ok&&legacy&&!correct;return ok;
    }
    /** TIOAOSetAudioSaving read-back rule. */
    static boolean verify(Map<?,?> s,boolean enabled){
        if(s==null||!Boolean.valueOf(enabled).equals(s.get("dumpEnabled")))return false;
        return !enabled||(Boolean.FALSE.equals(s.get("dumpEvents"))&&Boolean.TRUE.equals(s.get("dumpRealtimeAudio"))&&Boolean.TRUE.equals(s.get("dumpCachedAudio")));
    }
}
