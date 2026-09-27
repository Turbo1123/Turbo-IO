package com.turboio.addon;
import android.app.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.os.*;
import android.widget.*;
import java.util.*;

/** User-visible leases, no boot receiver or sticky restart, no pairing/reconnect side effects. */
public final class BackgroundWork extends Service {
 private static Context app;private static BackgroundWork instance;private static boolean foreground=true,stopping;private static final Map<String,Integer> jobs=new LinkedHashMap<>();private static final Map<String,Runnable> stops=new HashMap<>();private static String note="后台任务未开启";
 static void init(Context c){app=c.getApplicationContext();}
 static void onForeground(boolean value){foreground=value;}
 static void register(String key,Runnable stop){stops.put(key,stop);}
 static boolean enabled(){return app!=null&&app.getSharedPreferences("turboio_background",0).getBoolean("enabled",false);}
 static boolean held(String key){return instance!=null&&jobs.containsKey(key);}
 static boolean acquire(String key,int types){if(!enabled()||stopping||!foreground&&instance==null)return false;if((types&128)!=0&&app.checkSelfPermission("android.permission.RECORD_AUDIO")!=PackageManager.PERMISSION_GRANTED)return false;if((types&8)!=0&&app.checkSelfPermission("android.permission.ACCESS_FINE_LOCATION")!=PackageManager.PERMISSION_GRANTED)return false;if((types&16)!=0&&Build.VERSION.SDK_INT>=31&&app.checkSelfPermission("android.permission.BLUETOOTH_CONNECT")!=PackageManager.PERMISSION_GRANTED)return false;
  jobs.put(key,types);try{app.startForegroundService(new Intent(app,BackgroundWork.class));return true;}catch(RuntimeException e){jobs.remove(key);note="系统拒绝后台服务，请回到前台重新开始";return false;}}
 static void release(String key){jobs.remove(key);if(instance!=null)instance.update();}
 private int types(){int t=0;for(int v:jobs.values())t|=v;return t;}
 private void update(){if(jobs.isEmpty()){stopForeground(STOP_FOREGROUND_REMOVE);stopSelf();return;}try{Intent launch=getPackageManager().getLaunchIntentForPackage(getPackageName());PendingIntent open=launch==null?null:PendingIntent.getActivity(this,201,launch,PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);PendingIntent stop=PendingIntent.getService(this,202,new Intent(this,BackgroundWork.class).setAction("stop"),PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);Notification n=new Notification.Builder(this,"turboio_tasks").setSmallIcon(android.R.drawable.stat_notify_sync).setContentTitle("Turbo IO 正在运行").setContentText(String.join(" · ",jobs.keySet())).setContentIntent(open).setOngoing(true).setOnlyAlertOnce(true).setVisibility(Notification.VISIBILITY_PRIVATE).addAction(new Notification.Action.Builder(null,"停止所有扩展任务",stop).build()).build();startForeground(7621,n,types());note="后台已运行："+String.join("、",jobs.keySet());}catch(RuntimeException e){note="后台权限/服务类型被系统拒绝，任务已停止";stopAll();}}
 static void stopAll(){if(stopping)return;stopping=true;List<String> keys=new ArrayList<>(jobs.keySet());jobs.clear();for(String k:keys){Runnable r=stops.get(k);if(r!=null)try{r.run();}catch(RuntimeException ignored){}}if(instance!=null){instance.stopForeground(STOP_FOREGROUND_REMOVE);instance.stopSelf();}stopping=false;}
 @Override public void onCreate(){super.onCreate();instance=this;NotificationManager m=getSystemService(NotificationManager.class);m.createNotificationChannel(new NotificationChannel("turboio_tasks","Turbo IO 活动任务",NotificationManager.IMPORTANCE_LOW));}
 @Override public int onStartCommand(Intent intent,int flags,int id){if(intent==null||"stop".equals(intent.getAction())){stopAll();stopSelf();return START_NOT_STICKY;}update();return START_NOT_STICKY;}
 @Override public IBinder onBind(Intent intent){return null;}
 @Override public void onTaskRemoved(Intent intent){stopAll();stopSelf();}
 @Override public void onDestroy(){if(instance==this){instance=null;stopAll();}super.onDestroy();}
 @Override public void onTimeout(int id,int type){stopAll();stopSelf();}
 static void show(Activity a){EditorialUI.Screen s=new EditorialUI.Screen(a,"后台运行");s.body.addView(EditorialUI.text(a,"只维持你主动开始的任务。音乐、阅读、新闻、字幕与导航使用各自的前台服务类型；系统通知随时可停止。关闭开关会停止当前扩展任务。",15,EditorialUI.MUTED));EditorialUI.toggle(a,s.body,"允许活动任务在后台继续",enabled(),(v,on)->{app.getSharedPreferences("turboio_background",0).edit().putBoolean("enabled",on).apply();if(!on)stopAll();else if(Build.VERSION.SDK_INT>=33&&a.checkSelfPermission("android.permission.POST_NOTIFICATIONS")!=PackageManager.PERMISSION_GRANTED)a.requestPermissions(new String[]{"android.permission.POST_NOTIFICATIONS"},7621);});TextView state=EditorialUI.text(a,note,14,EditorialUI.LIME);s.body.addView(state);EditorialUI.button(a,s.body,"刷新实际后台状态",false,()->state.setText(note+"\n服务："+(instance==null?"未启动":"运行中")));EditorialUI.button(a,s.body,"停止扩展后台任务",false,()->{stopAll();state.setText("已停止；官方 App 的其他任务不在此列表");});s.body.addView(EditorialUI.text(a,"不会自动取消电池优化、不会自动重连或重新配对。进程被杀后回到手机确认状态，再开始任务；不自动恢复收音或重传。",13,EditorialUI.MUTED));}
}
