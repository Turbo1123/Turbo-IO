package com.turboio.addon;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ClipData;
import android.content.Intent;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.widget.Toast;
import java.io.*;
import java.text.SimpleDateFormat;
import java.util.*;

/** Read-only candidate browser. Never edits official recording databases. */
final class RecordingExports {
    private static final Handler MAIN = new Handler(Looper.getMainLooper());
    static void show(Activity activity, boolean text) {
        Toast.makeText(activity,"正在查找本机已保存文件",Toast.LENGTH_SHORT).show();
        new Thread(() -> {
            List<File> files = new ArrayList<>(); Set<String> seen = new HashSet<>(); int[] budget = {3000};
            try {
                for(File root : new File[]{activity.getFilesDir(), new File(activity.getApplicationInfo().dataDir,"app_flutter"), activity.getExternalFilesDir(null)})
                    scan(root, 0, text, files, seen, budget);
            } catch (IOException ignored) {}
            files.sort((a,b)->Long.compare(b.lastModified(),a.lastModified()));
            MAIN.post(() -> {
                if(activity.isFinishing()) return;
                if(files.isEmpty()) { new AlertDialog.Builder(activity).setTitle("暂未发现可导出文件")
                    .setMessage("请先在官方 App 保存或下载录音。此处仅查本机文件，不代表云端没有记录；数据库内的转写还需单独适配。").setPositiveButton("知道了",null).show(); return; }
                SimpleDateFormat format = new SimpleDateFormat("MM-dd HH:mm",Locale.ROOT);
                String[] rows = new String[files.size()];
                for(int i=0;i<rows.length;i++) { File file=files.get(i); rows[i]=file.getName()+"\n"+format.format(new Date(file.lastModified()))+" · "+file.length()/1024+" KB"; }
                new AlertDialog.Builder(activity).setTitle(text?"本地文字 / Markdown 文件":"本地音频候选（录音 / 智记）")
                    .setItems(rows,(d,which)->new AlertDialog.Builder(activity).setTitle("分享所选文件？")
                        .setMessage("仅导出本机副本，不删除原件。请确认这是你要分享的记录。")
                        .setNegativeButton("取消",null).setPositiveButton("打开系统分享",(d2,w)->share(activity,files.get(which),text?"text/plain":"audio/*")).show())
                    .setNegativeButton("返回",null).show();
            });
        },"TurboIO-file-list").start();
    }
    private static void scan(File node,int depth,boolean text,List<File> out,Set<String> seen,int[] budget) throws IOException {
        if(node==null || depth>9 || budget[0]--<=0 || out.size()>=200 || !node.exists()) return;
        if(!node.getAbsolutePath().equals(node.getCanonicalPath())) return; // no symlinks
        if(!seen.add(node.getCanonicalPath())) return;
        if(node.isDirectory()) {
            String name=node.getName(); if(name.equals("flutter_assets")||name.equals("logs")||name.equals("databases")) return;
            File[] children=node.listFiles(); if(children!=null) for(File child:children) scan(child,depth+1,text,out,seen,budget);
        } else if(node.isFile() && node.length()>0) {
            String name=node.getName().toLowerCase(Locale.ROOT), path=node.getPath().toLowerCase(Locale.ROOT);
            boolean audio=name.matches(".*\\.(m4a|wav|aac|ogg|opus|mp3|flac)$");
            boolean document=name.endsWith(".md") || (name.endsWith(".txt") && (path.contains("record")||path.contains("transcript")||path.contains("lifelog")||path.contains("always")));
            if(text?document:audio) out.add(node);
        }
    }
    /** Share a file that already lives under cache/share_plus (no second copy). */
    static void shareInPlace(Activity activity,File file,String mime) {
        try {
            File root=new File(activity.getCacheDir(),"share_plus").getCanonicalFile();String path=file.getCanonicalPath();
            if(!path.startsWith(root.getPath()+File.separator)||!file.isFile()) throw new IOException();
            Uri.Builder b=new Uri.Builder().scheme("content").authority(activity.getPackageName()+".flutter.share_provider").appendPath("cache");
            for(String part:path.substring(root.getPath().length()+1).split(java.util.regex.Pattern.quote(File.separator))) b.appendPath(part);
            Uri uri=b.build();Intent intent=new Intent(Intent.ACTION_SEND).setType(mime).putExtra(Intent.EXTRA_STREAM,uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            intent.setClipData(ClipData.newRawUri("Turbo IO export",uri));activity.startActivity(Intent.createChooser(intent,"分享文件副本"));
        } catch(Exception ignored) {Toast.makeText(activity,"分享失败，原件未改动",Toast.LENGTH_LONG).show();}
    }
    static void share(Activity activity,File original,String mime) {
        new Thread(() -> {
            try {
                if(!original.isFile() || original.length()>512L*1024*1024) throw new IOException();
                File folder=new File(activity.getCacheDir(),"share_plus");
                if(!folder.isDirectory() && !folder.mkdirs()) throw new IOException();
                String name="TurboIO-"+UUID.randomUUID().toString().substring(0,8)+"-"+original.getName();
                File copy=new File(folder,name);
                try(InputStream in=new FileInputStream(original); OutputStream out=new FileOutputStream(copy)) {
                    byte[] bytes=new byte[65536]; int n; while((n=in.read(bytes))!=-1) out.write(bytes,0,n);
                }
                // Verified 1.0.4 manifest: cache root is cache/share_plus/.
                Uri uri=new Uri.Builder().scheme("content").authority(activity.getPackageName()+".flutter.share_provider").appendPath("cache").appendPath(name).build();
                MAIN.post(()->{try {
                    Intent intent=new Intent(Intent.ACTION_SEND).setType(mime).putExtra(Intent.EXTRA_STREAM,uri)
                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                    intent.setClipData(ClipData.newRawUri("Turbo IO export",uri));
                    activity.startActivity(Intent.createChooser(intent,"分享文件副本"));
                } catch(Exception ignored) {Toast.makeText(activity,"分享失败，原件未改动",Toast.LENGTH_LONG).show();}});
            } catch(Exception ignored) { MAIN.post(()->Toast.makeText(activity,"文件不可读或超过 512 MB，原件未改动",Toast.LENGTH_LONG).show()); }
        },"TurboIO-export").start();
    }
}
