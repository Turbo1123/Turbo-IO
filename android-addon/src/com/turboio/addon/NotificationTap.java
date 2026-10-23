package com.turboio.addon;
import android.app.Notification;
import android.content.*;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.service.notification.StatusBarNotification;
import java.io.File;
import java.util.*;
import java.util.concurrent.*;

/** Android glue for notification history: the host's NotificationListenerService hands every posted/removed
 * notification here after its own handling. Only bounded text fields are copied on the listener thread; storage runs
 * on one serial executor. Off by default (pref turboio_notifications/enabled). */
final class NotificationTap {
    private static NotificationRuntime runtime;private static Context app;
    private static final Map<String,String> labels=new LinkedHashMap<String,String>(64,.75f,true){protected boolean removeEldestEntry(Map.Entry<String,String> e){return size()>64;}};
    static synchronized NotificationRuntime runtime(Context c){
        if(runtime==null){app=c.getApplicationContext();ExecutorService io=Executors.newSingleThreadExecutor();
            // no_backup: notification text must never reach Auto Backup / device transfer (iOS excludes it from backup).
            io.execute(()->{try{delete(new File(app.getFilesDir(),"turboio/notifications"));}catch(Throwable ignored){}});
            runtime=new NotificationRuntime(new NotificationArchive.Store(new File(app.getNoBackupFilesDir(),"turboio/notifications")),io,NotificationTap::fields,app.getPackageName(),()->System.currentTimeMillis()/1000.0);
            runtime.labeler=NotificationTap::label;
            runtime.setEnabled(app.getSharedPreferences("turboio_notifications",0).getBoolean("enabled",false));}
        return runtime;
    }
    static void setEnabled(Context c,boolean on){runtime(c).setEnabled(on);c.getSharedPreferences("turboio_notifications",0).edit().putBoolean("enabled",on).apply();}
    private static String label(String pkg){
        synchronized(labels){String hit=labels.get(pkg);if(hit!=null)return hit;}
        String name=pkg;try{PackageManager pm=app.getPackageManager();name=String.valueOf(pm.getApplicationLabel(pm.getApplicationInfo(pkg,0)));}catch(Exception ignored){}
        synchronized(labels){labels.put(pkg,name);}return name;
    }
    static void delete(File f){File[] children=f.listFiles();if(children!=null)for(File c:children)delete(c);f.delete();}
    /** Bounded copy: oversized text is refused without copying it (the listener runs on the host's main thread). */
    private static String text(Bundle b,String key,int max){CharSequence v=b==null?null:b.getCharSequence(key);if(v==null)return "";if(v.length()>max)throw new IllegalArgumentException("too long");return v.toString();}
    static NotificationRuntime.Fields fields(Object o){
        StatusBarNotification sbn=(StatusBarNotification)o;Notification n=sbn.getNotification();NotificationRuntime.Fields f=new NotificationRuntime.Fields();
        f.key=sbn.getKey();f.pkg=sbn.getPackageName();f.postTime=sbn.getPostTime();
        // Cheap status checks first: ongoing / foreground-service and the host's own notifications are skipped unread.
        f.ongoing=n!=null&&(n.flags&(Notification.FLAG_ONGOING_EVENT|Notification.FLAG_FOREGROUND_SERVICE))!=0;
        if(f.ongoing||app.getPackageName().equals(f.pkg))return f;
        Bundle extras=n==null?null:n.extras;f.appName=null;// label resolved on the executor
        f.title=text(extras,Notification.EXTRA_TITLE,2048);f.subtitle=text(extras,Notification.EXTRA_SUB_TEXT,2048);
        String big=text(extras,Notification.EXTRA_BIG_TEXT,NotificationArchive.MAX_TEXT);f.content=big.isEmpty()?text(extras,Notification.EXTRA_TEXT,NotificationArchive.MAX_TEXT):big;return f;
    }
    static void posted(Object service,StatusBarNotification sbn){if(service instanceof Context&&sbn!=null)runtime((Context)service).posted(sbn);}
    static void removed(Object service,StatusBarNotification sbn){if(service instanceof Context&&sbn!=null)runtime((Context)service).removed(sbn);}
}
