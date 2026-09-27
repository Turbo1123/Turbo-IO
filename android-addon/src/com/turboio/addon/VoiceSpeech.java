package com.turboio.addon;

import android.app.*;
import android.content.*;
import android.media.*;
import android.os.*;
import android.speech.tts.*;
import android.widget.*;
import java.io.*;
import java.util.*;

/** Local synthesis only. No service key, network voice, microphone or vendor audio mutation. */
final class VoiceSpeech {
    private static final Handler MAIN=new Handler(Looper.getMainLooper());
    private static Context app;private static SharedPreferences prefs;private static TextToSpeech tts;
    private static AudioManager audio;private static AudioFocusRequest focus;private static MediaPlayer player;
    private static boolean ready,initializing,foreground=true;private static long generation,engineGeneration;private static int serial;
    private static final SpeechBuffer buffer=new SpeechBuffer();private static final ArrayDeque<String> queue=new ArrayDeque<>();
    private static final Set<Runnable> listeners=new HashSet<>();private static String status="待命",activeId="",session="";
    private static File activeFile;private static boolean speaking,received,blocked;private static Object source;private static String official="";
    static void init(Context c){if(app!=null)return;app=c.getApplicationContext();prefs=app.getSharedPreferences("turboio_settings",0);audio=(AudioManager)app.getSystemService(Context.AUDIO_SERVICE);
        audio.registerAudioDeviceCallback(new AudioDeviceCallback(){public void onAudioDevicesRemoved(AudioDeviceInfo[] d){if(player!=null&&!phoneAllowed())checkRoute();}},MAIN);
    }
    static boolean enabled(){return prefs!=null&&prefs.getBoolean("tts_enabled",false);}
    static void foreground(boolean value){foreground=value;if(!value)stop("App 进入后台，停止前台测试朗读");}
    private static boolean phoneAllowed(){return prefs.getBoolean("tts_phone",false);}
    static String status(){return status;}
    private static void mark(String s){status=s;for(Runnable r:new ArrayList<>(listeners))try{r.run();}catch(RuntimeException ignored){}}
    static void stop(String reason){generation++;queue.clear();buffer.reset();official="";activeId="";source=null;session="";speaking=received=blocked=false;
        MAIN.removeCallbacks(watchdog);if(tts!=null)try{tts.stop();}catch(RuntimeException ignored){}releasePlayer();File old=activeFile;activeFile=null;if(old!=null)old.delete();mark(reason);
    }
    private static void releasePlayer(){if(player!=null){try{player.release();}catch(RuntimeException ignored){}player=null;}if(focus!=null&&audio!=null){audio.abandonAudioFocusRequest(focus);focus=null;}}
    static void asr(Object owner,String sid,boolean finished){if(!enabled())return;
        // A new utterance interrupts immediately; repeated partial/final callbacks
        // before an answer do not restart the generation unnecessarily.
        if(received||source!=owner||!Objects.equals(session,sid)){stop("新一轮识别，停止旧朗读");source=owner;session=sid==null?"":sid;}
    }
    static void delta(Object owner,String sid,String text,boolean end){if(!enabled()||blocked)return;if(source!=owner||!Objects.equals(session,sid)){stop("接收回答");source=owner;session=sid==null?"":sid;}
        String full=text.startsWith(official)?text:official.startsWith(text)?official:official+text;
        if(full.length()>SpeechBuffer.MAX){fail("回答超过朗读长度限制");return;}official=full;append(full,true,end);}
    static void suppress(){fail("本轮包含官方语音，避免重复朗读");}
    static void custom(Object owner,String sid,String full,boolean end){if(!enabled()||blocked)return;if(source!=owner||!Objects.equals(session,sid)){stop("接收自有回答");source=owner;session=sid==null?"":sid;}append(full,true,end);}
    static void finish(Object owner){if(enabled()&&source==owner&&received&&!blocked)append("",false,true);}
    private static void append(String text,boolean full,boolean end){if(!foreground)return;try{received=true;List<String> sentences=buffer.append(text,full,end);if(queue.size()+sentences.size()>64)throw new IllegalArgumentException();queue.addAll(sentences);if(!queue.isEmpty())ensureEngine();}catch(RuntimeException e){fail("朗读队列超过限制或文本被重写；本轮停止");}}
    private static void fail(String why){stop(why);blocked=true;}
    private static void ensureEngine(){if(ready){pump();return;}if(initializing)return;initializing=true;mark("正在初始化本机语音引擎");
        long token=generation,engine=++engineGeneration;
        MAIN.postDelayed(()->{if(initializing&&engineGeneration==engine){initializing=ready=false;engineGeneration++;if(tts!=null){tts.shutdown();tts=null;}fail("语音引擎初始化超时，请检查系统语音服务");}},15000);
        try{if(tts!=null){tts.shutdown();tts=null;}tts=new TextToSpeech(app,result->MAIN.post(()->{if(engine!=engineGeneration)return;initializing=false;if(result!=TextToSpeech.SUCCESS){ready=false;fail("未找到本机 TTS 引擎，请在系统安装语音数据");return;}
            try{Voice selected=null;Set<Voice> voices=tts.getVoices();if(voices!=null)for(Voice v:voices)if(!v.isNetworkConnectionRequired()&&v.getLocale().getLanguage().equals("zh")&&(v.getFeatures()==null||!v.getFeatures().contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED))){if(selected==null||v.getQuality()>selected.getQuality())selected=v;}
                if(selected==null||tts.setVoice(selected)!=TextToSpeech.SUCCESS){ready=false;fail("缺少已安装的中文本机音色，请先在系统下载；不会改用联网音色");return;}
                tts.setSpeechRate(prefs.getFloat("tts_rate",1f));tts.setOnUtteranceProgressListener(new UtteranceProgressListener(){public void onStart(String id){}public void onDone(String id){MAIN.post(()->synthesized(id));}public void onError(String id){MAIN.post(()->{if(id.equals(activeId))fail("本机语音合成失败");});}});
                ready=true;if(token==generation)pump();else if(!queue.isEmpty())pump();else mark("本机中文音色已就绪");
            }catch(RuntimeException e){ready=false;fail("本机语音初始化失败");}
        }));}catch(RuntimeException e){initializing=false;fail("系统语音服务不可用");}
    }
    private static boolean bluetooth(AudioDeviceInfo d){if(d==null)return false;int t=d.getType();return t==AudioDeviceInfo.TYPE_BLUETOOTH_A2DP||t==AudioDeviceInfo.TYPE_BLE_HEADSET||t==AudioDeviceInfo.TYPE_BLE_SPEAKER||t==AudioDeviceInfo.TYPE_HEARING_AID;}
    private static AudioDeviceInfo output(){try{for(AudioDeviceInfo d:audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS))if(bluetooth(d))return d;}catch(RuntimeException ignored){}return null;}
    private static void pump(){if(!ready||speaking||queue.isEmpty())return;
        if(!phoneAllowed()&&output()==null){fail("未发现蓝牙媒体音频路由；请在系统连接眼镜/耳机，或明确允许手机播放");return;}
        try{File root=new File(app.getCacheDir(),"turboio-tts");if(!root.isDirectory()&&!root.mkdirs())throw new IOException();File[] files=root.listFiles();if(files==null)throw new IOException();for(File f:files)if(f.getName().matches("speech-[0-9a-f-]+\\.wav")&&f.isFile())f.delete();
            activeFile=File.createTempFile("speech-",".wav",root); // own cache only; released every utterance
            activeId=generation+":"+(++serial);speaking=true;mark("正在合成本机语音");
            int result=tts.synthesizeToFile(queue.removeFirst(),new Bundle(),activeFile,activeId);
            if(result!=TextToSpeech.SUCCESS){fail("语音引擎拒绝合成");return;}MAIN.removeCallbacks(watchdog);MAIN.postDelayed(watchdog,30000);
        }catch(Exception e){fail("无法创建本机语音缓存");}
    }
    private static final Runnable watchdog=()->fail("朗读超时，已停止并释放音频");
    private static void synthesized(String id){if(!id.equals(activeId)||activeFile==null)return;
        if(activeFile.length()<44||activeFile.length()>8*1024*1024){fail("合成音频大小异常");return;}
        try{AudioDeviceInfo route=output();if(route==null&&!phoneAllowed()){fail("蓝牙音频已断开，未外放");return;}
            AudioAttributes attr=new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build();
            focus=new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK).setAudioAttributes(attr).setOnAudioFocusChangeListener(change->{if(change<0)MAIN.post(()->fail("音频焦点变化，停止朗读"));},MAIN).build();
            if(audio.requestAudioFocus(focus)!=AudioManager.AUDIOFOCUS_REQUEST_GRANTED){fail("未获得音频焦点；后台时请回到 App 测试");return;}
            player=new MediaPlayer();MediaPlayer current=player;current.setAudioAttributes(attr);current.setDataSource(activeFile.getPath());
            if(route!=null&&!current.setPreferredDevice(route)&&!phoneAllowed()){fail("系统拒绝蓝牙路由选择，未播放");return;}
            current.addOnRoutingChangedListener(router->{if(current==player)checkRoute();},MAIN);
            current.setOnErrorListener((m,w,e)->{if(current==player)fail("本机音频播放失败");return true;});
            current.setOnCompletionListener(m->{if(current!=player)return;MAIN.removeCallbacks(watchdog);releasePlayer();if(activeFile!=null)activeFile.delete();activeFile=null;activeId="";speaking=false;mark("本段播放完成");pump();});
            current.setOnPreparedListener(m->{if(current!=player||!id.equals(activeId))return;current.setVolume(0,0);current.start();checkRoute();MAIN.postDelayed(()->{if(current==player)checkRoute();},200);MAIN.postDelayed(()->{if(current==player&&current.getRoutedDevice()==null)fail("系统未确认输出路由，保持静音并停止");},2000);});
            current.prepareAsync();mark("等待实际音频路由");MAIN.removeCallbacks(watchdog);MAIN.postDelayed(watchdog,90000);
        }catch(Exception e){fail("无法播放合成语音");}
    }
    private static void checkRoute(){if(player==null)return;AudioDeviceInfo d=player.getRoutedDevice();if(d==null)return;
        if(!phoneAllowed()&&!bluetooth(d)){fail("实际输出不是蓝牙耳机，已保持静音并停止");return;}player.setVolume(1,1);mark(bluetooth(d)?"正在通过蓝牙媒体设备播放":"正在通过系统媒体输出播放（已允许）");
    }
    static void show(Activity a){EditorialUI.Screen screen=new EditorialUI.Screen(a,"回答同步朗读");LinearLayout b=screen.body;
        b.addView(EditorialUI.text(a,"本机中文 TTS · 无需 Key",22,EditorialUI.INK));b.addView(EditorialUI.text(a,"只选择已安装的非联网音色。蓝牙连接不等于媒体音频已连接；实际输出以系统路由为准。不会开启麦克风或修改官方音频会话。",14,EditorialUI.MUTED));
        EditorialUI.toggle(a,b,"回答同步朗读",enabled(),(v,on)->{prefs.edit().putBoolean("tts_enabled",on).apply();stop(on?"已启用；等待下一轮回答":"已关闭");});
        EditorialUI.toggle(a,b,"允许手机/其他系统媒体输出（默认关闭）",phoneAllowed(),(v,on)->{prefs.edit().putBoolean("tts_phone",on).apply();stop("音频策略已修改");});
        TextView state=EditorialUI.text(a,status,15,EditorialUI.LIME);b.addView(state);Runnable refresh=()->state.setText(status);listeners.add(refresh);screen.dialog.setOnDismissListener(d->listeners.remove(refresh));
        EditorialUI.button(a,b,"播放测试语音",true,()->{stop("测试语音");append("Turbo IO 本机语音测试，校验七三九二。",false,true);});
        EditorialUI.button(a,b,"停止朗读",false,()->stop("已手动停止"));
        EditorialUI.button(a,b,"系统语音设置",false,()->{try{a.startActivity(new Intent("com.android.settings.TTS_SETTINGS"));}catch(RuntimeException e){EditorialUI.notice(a,"系统未提供语音设置入口，请在设置中搜索文字转语音。");}});
    }
}
