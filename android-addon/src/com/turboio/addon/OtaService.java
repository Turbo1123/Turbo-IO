package com.turboio.addon;
import android.app.*;import android.content.*;import android.os.*;

/** Dedicated connected-device lease. Never auto-resumes a firmware transfer. */
public final class OtaService extends Service {
 private static OtaService instance;private static boolean ready;
 static boolean alive(){return instance!=null&&ready;}
 static void finish(){ready=false;if(instance!=null){OtaService s=instance;instance=null;s.stopForeground(STOP_FOREGROUND_REMOVE);s.stopSelf();}}
 @Override public void onCreate(){super.onCreate();instance=this;getSystemService(NotificationManager.class).createNotificationChannel(new NotificationChannel("turboio_ota","实验固件升级",NotificationManager.IMPORTANCE_LOW));}
 @Override public int onStartCommand(Intent intent,int flags,int id){if(intent==null){finish();return START_NOT_STICKY;}try{Intent launch=getPackageManager().getLaunchIntentForPackage(getPackageName());PendingIntent open=launch==null?null:PendingIntent.getActivity(this,7622,launch,PendingIntent.FLAG_IMMUTABLE|PendingIntent.FLAG_UPDATE_CURRENT);Notification n=new Notification.Builder(this,"turboio_ota").setSmallIcon(android.R.drawable.stat_sys_upload).setContentTitle("Turbo IO 实验固件升级").setContentText("保持蓝牙与供电；请回 App 查看状态，勿强退或重复更新").setContentIntent(open).setOnlyAlertOnce(true).setOngoing(true).setVisibility(Notification.VISIBILITY_PRIVATE).build();startForeground(7622,n,16);ready=true;}catch(RuntimeException e){OtaController.serviceLost();finish();}return START_NOT_STICKY;}
 @Override public IBinder onBind(Intent intent){return null;}
 @Override public void onTaskRemoved(Intent intent){/* Bluetooth transfer continues in this visible service; no retry. */}
 @Override public void onDestroy(){if(instance==this){instance=null;ready=false;OtaController.serviceLost();OfficialOtaBridge.serviceLost();}super.onDestroy();}
 @Override public void onTimeout(int id,int type){OtaController.serviceLost();OfficialOtaBridge.serviceLost();finish();}
}
