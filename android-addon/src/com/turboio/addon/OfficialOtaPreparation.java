package com.turboio.addon;
import android.app.*;import android.content.*;import android.os.*;import android.widget.*;
import java.io.*;import java.util.concurrent.atomic.AtomicInteger;

/** Private preparation profile; no API releases its permanent OTA send gate. */
public final class OfficialOtaPreparation {
 private static Boolean mode;private static Context app;private static OfficialOtaFeed feed;
 private static volatile String note="仅验证官方检测、下载与解压；此包不能刷眼镜";
 private static volatile String directoryResult="官方准备目录：尚未核对";
 private static boolean reporting;
 private static final AtomicInteger blocked=new AtomicInteger(),reads=new AtomicInteger();
 private static final AtomicInteger[] types=new AtomicInteger[12];
 static{for(int i=0;i<types.length;i++)types[i]=new AtomicInteger();}
 public static synchronized boolean enabled(){
  if(mode!=null)return mode;
  try{Object c=Class.forName("android.app.ActivityThread").getMethod("currentApplication").invoke(null);if(!(c instanceof Context))return true;app=((Context)c).getApplicationContext();
   String[] files=app.getAssets().list("turboio");mode=files!=null&&java.util.Arrays.asList(files).contains("official-ota-preparation.txt");
  }catch(Exception e){return true;}return mode;
 }
 static synchronized void init(Context c){if(!enabled()||feed!=null)return;app=c.getApplicationContext();
  if(OtaController.critical()){note="旧实验结果保护尚未解除，禁止开放新下载源";return;}
  try{OfficialOtaFeed f=new OfficialOtaFeed(SystemClock::elapsedRealtime,()->enabled()&&!OtaController.critical());f.start(18794);feed=f;}
  catch(Exception e){note="本机来源无法启动；保持禁止刷写，不切换其他地址";}
  if(!reporting){reporting=true;Handler h=new Handler(Looper.getMainLooper());h.post(new Runnable(){String last="";public void run(){String value=status();if(!value.equals(last)){exportStatus(value);last=value;}h.postDelayed(this,2000);}});}
 }
 public static Boolean allowQueue(Object message){if(!enabled())return null;
  try{Object biz=NavReflect.field(message,"c");if(!(biz instanceof Enum)){blocked.incrementAndGet();return false;}
   if(!"MARS_FOTA".equals(((Enum<?>)biz).name()))return null;
   Object payload=NavReflect.field(message,"e");boolean ok=payload instanceof byte[]&&OtaFrame.readOnly((byte[])payload);
   if(ok)reads.incrementAndGet();else{blocked.incrementAndGet();if(payload instanceof byte[])try{int t=OtaFrame.decode((byte[])payload).type;if(t<types.length)types[t].incrementAndGet();}catch(RuntimeException ignored){}}
   return ok;
  }catch(Exception e){blocked.incrementAndGet();return false;}
 }
 static String status(){String counts="";for(int i=1;i<types.length;i++)if(types[i].get()>0)counts+=" type"+i+"="+types[i].get();return "ANDROID · OFFICIAL-OTA-PREPARE-01\n"+note+"\n"+(feed==null?"本机源未启动":feed.status())+"\n发送隔离：永久开启（此构建无刷写授权入口）\n只读放行："+reads.get()+" · 拦截："+blocked.get()+counts+"\n候选："+OtaPackage.NAME+"\n"+directoryResult;}
 private static void exportStatus(String text){try{File root=app.getExternalFilesDir(null);if(root==null)return;File tmp=new File(root,"official-ota-preparation-status.tmp"),dest=new File(root,"official-ota-preparation-status.txt");try(FileOutputStream out=new FileOutputStream(tmp)){out.write(text.getBytes("UTF-8"));out.getFD().sync();}tmp.renameTo(dest);}catch(Exception ignored){}}
 private static void checkDirectory(){directoryResult="官方准备目录：只读核对中";new Thread(()->{
  File root=app.getFilesDir();File[] candidates={new File(root,"ota/Strix_OS_1.0.4.12"),new File(root.getParentFile(),"app_flutter/ota/Strix_OS_1.0.4.12")};int found=0,valid=0;
  for(File dir:candidates)if(dir.exists()){found++;try{OtaPackage.verifyDirectory(dir.toPath());valid++;}catch(Exception ignored){}}
  directoryResult=valid==1&&found==1?"官方准备目录：15/15 成员固定摘要通过（仅磁盘快照，不代表已刷写）":"官方准备目录：发现 "+found+" 处，匹配 "+valid+" 处；尚未确认唯一候选";
 },"TurboIO-ota-directory-readonly").start();}
 static void show(Activity a){init(a);EditorialUI.Screen s=new EditorialUI.Screen(a,"官方升级 · 只下载验收");
  s.body.addView(EditorialUI.text(a,"使用 Android 官方更新页、下载器、校验和解压流程。此测试包禁止 OTA 开始/清单/分片发送，不能刷眼镜。",15,EditorialUI.INK));
  TextView status=EditorialUI.text(a,status(),14,EditorialUI.LIME);s.body.addView(status);
  EditorialUI.button(a,s.body,"选择指定 ZIP，开启 15 分钟只下载",true,()->{if(feed==null||OtaController.critical()){EditorialUI.notice(a,"发送保护或本机来源未就绪");return;}DocumentPicker.pick(a,OtaPackage.ZIP_SIZE,bytes->{note="正在核对候选，尚未开放下载";new Thread(()->{try{feed.arm(bytes);note="候选校验通过；请返回官方设置 → 固件更新，检查并下载。不要开始安装。";}catch(Exception e){note="候选或保护校验失败，没有开放下载";}},"TurboIO-ota-prepare").start();});});
  EditorialUI.button(a,s.body,"关闭下载来源",false,()->{if(feed!=null)feed.disarm();note="来源已关闭，发送隔离仍永久生效";});
  EditorialUI.button(a,s.body,"下载后：只读核对官方解压目录",false,OfficialOtaPreparation::checkDirectory);
  EditorialUI.button(a,s.body,"返回官方 App",false,()->s.dialog.dismiss());
  s.body.addView(EditorialUI.text(a,"下载次数不等于已解压；解压通过不等于已刷入。必须核对官方实际准备目录和日志。",13,EditorialUI.MUTED));
  Handler h=new Handler(Looper.getMainLooper());Runnable tick=new Runnable(){public void run(){if(!s.dialog.isShowing())return;status.setText(status());h.postDelayed(this,500);}};h.post(tick);s.dialog.setOnDismissListener(d->h.removeCallbacks(tick));
 }
}
