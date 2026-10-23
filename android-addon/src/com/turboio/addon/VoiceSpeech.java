package com.turboio.addon;

import android.app.*;
import android.content.*;
import android.media.*;
import android.os.*;
import android.speech.tts.*;
import android.widget.*;
import java.io.*;
import java.util.*;

/** Answer read-out: local Android TTS by default, or Ali Flash realtime cloud TTS (CloudTts) when selected with a key.
 * No microphone or vendor audio mutation; output only to Bluetooth media unless phone output is explicitly allowed. */
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
    private static boolean cloud(){return prefs!=null&&"cloud".equals(prefs.getString("tts_engine","local"));}
    private static CloudTts cloudTts;private static String cloudFull="";private static PcmPlayer pcmPlayer;
    private static CloudTts cloudTts(){
        if(cloudTts==null){pcmPlayer=new PcmPlayer();cloudTts=new CloudTts(new WsTransport(),pcmPlayer,()->{try{return SecretStore.get(app,"tts_key");}catch(Exception e){return "";}},prefs.getString("tts_endpoint",CloudTts.DEFAULT_ENDPOINT));CloudTts mine=cloudTts;cloudTts.onStatus(st->MAIN.post(()->{if(cloudTts==mine&&cloud())mark(st);}));}
        return cloudTts;
    }
    /** DashScope duplex socket on the shared bounded RFC6455 client. */
    private static final class WsTransport implements CloudTts.Transport{
        private BoundedWebSocket ws;
        public void open(String url,String key,CloudTts.Listener l){ws=new BoundedWebSocket(new BoundedWebSocket.Listener(){public void opened(){}public void text(String t){l.text(t);}public void closed(String c){l.closed(c);}public void binary(byte[] b){l.binary(b);}},true);ws.connect(url,key,"X-DashScope-DataInspection: enable\r\n");}
        public boolean send(String json){return ws!=null&&ws.send(json);}
        public void close(){if(ws!=null)ws.close();ws=null;}
    }
    /** PCM16 LE mono 24 kHz to the Bluetooth media output on its own thread, so a slow AudioTrack never blocks callers. */
    private static final class PcmPlayer implements CloudTts.Pcm{
        private final java.util.concurrent.LinkedBlockingQueue<byte[]> queue=new java.util.concurrent.LinkedBlockingQueue<>();
        private final java.util.concurrent.atomic.AtomicLong queued=new java.util.concurrent.atomic.AtomicLong();private Thread thread;
        public boolean available(){return phoneAllowed()||output()!=null;}
        public synchronized boolean write(byte[] pcm){
            if(queued.get()+pcm.length>CloudTts.PCM_BUDGET_BYTES)return false;queued.addAndGet(pcm.length);queue.offer(pcm.clone());
            if(thread==null){Thread t=new Thread(()->run(Thread.currentThread()),"TurboIO-tts-pcm");thread=t;t.start();}return true;
        }
        /** Leaves only when idle and nothing was queued meanwhile (checked under the lock), so a late write is never stranded. */
        private synchronized boolean retire(Thread self){if(thread!=self)return true;if(!queue.isEmpty())return false;thread=null;return true;}
        private void run(Thread self){
            AudioAttributes attr=new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build();
            AudioFocusRequest f=new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK).setAudioAttributes(attr).setOnAudioFocusChangeListener(change->{if(change<0)MAIN.post(()->fail("音频焦点变化，停止朗读"));},MAIN).build();
            AudioTrack t=null;
            try{if(audio.requestAudioFocus(f)!=AudioManager.AUDIOFOCUS_REQUEST_GRANTED){MAIN.post(()->mark("未获得音频焦点，云端朗读未播放"));return;}
                int min=AudioTrack.getMinBufferSize(24000,AudioFormat.CHANNEL_OUT_MONO,AudioFormat.ENCODING_PCM_16BIT);
                t=new AudioTrack.Builder().setAudioAttributes(attr).setAudioFormat(new AudioFormat.Builder().setSampleRate(24000).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).setEncoding(AudioFormat.ENCODING_PCM_16BIT).build()).setBufferSizeInBytes(Math.max(min*4,48000)).setTransferMode(AudioTrack.MODE_STREAM).build();
                AudioDeviceInfo route=output();if(route!=null)t.setPreferredDevice(route);else if(!phoneAllowed()){MAIN.post(()->mark("眼镜音频未连接"));return;}
                t.play();
                while(true){byte[] b=queue.poll(3,java.util.concurrent.TimeUnit.SECONDS);if(b==null){if(retire(self))break;continue;}queued.addAndGet(-b.length);if(t.write(b,0,b.length)<0)break;}
            }catch(InterruptedException e){/* stop()/new turn: silent, not a playback failure */}
            catch(Exception e){MAIN.post(()->mark("眼镜音频播放失败"));}
            finally{if(t!=null){try{t.pause();t.flush();t.stop();}catch(RuntimeException ignored){}t.release();}retire(self);audio.abandonAudioFocusRequest(f);}
        }
        public synchronized void stop(){Thread t=thread;thread=null;queue.clear();queued.set(0);if(t!=null)t.interrupt();}
    }
    private static void mark(String s){status=s;for(Runnable r:new ArrayList<>(listeners))try{r.run();}catch(RuntimeException ignored){}}
    static void stop(String reason){if(cloudTts!=null)cloudTts.cancel();cloudFull="";generation++;queue.clear();buffer.reset();official="";activeId="";source=null;session="";speaking=received=blocked=false;
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
    private static void append(String text,boolean full,boolean end){if(!foreground)return;
        if(cloud()){received=true;cloudFull=full?text:cloudFull+text;CloudTts c=cloudTts();c.append(cloudFull,end);mark(c.status());return;}
        try{received=true;List<String> sentences=buffer.append(text,full,end);if(queue.size()+sentences.size()>64)throw new IllegalArgumentException();queue.addAll(sentences);if(!queue.isEmpty())ensureEngine();}catch(RuntimeException e){fail("朗读队列超过限制或文本被重写；本轮停止");}}
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
        b.addView(EditorialUI.text(a,cloud()?"阿里 qwen-audio-3.1-tts-flash · 云端":"本机中文 TTS · 无需 Key · 默认",22,EditorialUI.INK));b.addView(EditorialUI.text(a,"本机模式只选择已安装的非联网音色；云端模式把回答文字发送到你配置的阿里服务。蓝牙连接不等于媒体音频已连接；实际输出以系统路由为准。不会开启麦克风或修改官方音频会话。",14,EditorialUI.MUTED));
        EditorialUI.toggle(a,b,"朗读引擎：阿里 Flash 云端（关闭为本机语音）",cloud(),(v,on)->{prefs.edit().putString("tts_engine",on?"cloud":"local").apply();stop(on?"已切换为云端 Flash":"已切换为本机语音");});
        EditorialUI.button(a,b,"阿里 Flash TTS 配置",false,()->configureCloud(a));
        EditorialUI.toggle(a,b,"回答同步朗读",enabled(),(v,on)->{prefs.edit().putBoolean("tts_enabled",on).apply();stop(on?"已启用；等待下一轮回答":"已关闭");});
        EditorialUI.toggle(a,b,"允许手机/其他系统媒体输出（默认关闭）",phoneAllowed(),(v,on)->{prefs.edit().putBoolean("tts_phone",on).apply();stop("音频策略已修改");});
        TextView state=EditorialUI.text(a,status,15,EditorialUI.LIME);b.addView(state);Runnable refresh=()->state.setText(status);listeners.add(refresh);screen.dialog.setOnDismissListener(d->listeners.remove(refresh));
        EditorialUI.button(a,b,"播放测试语音",true,()->{stop("测试语音");append(cloud()?"Turbo IO 云端语音测试，校验七三九二。":"Turbo IO 本机语音测试，校验七三九二。",false,true);});
        EditorialUI.button(a,b,"停止朗读",false,()->stop("已手动停止"));
        EditorialUI.button(a,b,"系统语音设置",false,()->{try{a.startActivity(new Intent("com.android.settings.TTS_SETTINGS"));}catch(RuntimeException e){EditorialUI.notice(a,"系统未提供语音设置入口，请在设置中搜索文字转语音。");}});
    }
    /** Key goes to the Android Keystore-backed SecretStore and is never shown again; endpoint must pass CloudTts.endpointValid. */
    private static void configureCloud(Activity a){
        LinearLayout box=new LinearLayout(a);box.setOrientation(LinearLayout.VERTICAL);int pad=(int)(16*a.getResources().getDisplayMetrics().density);box.setPadding(pad,pad/2,pad,0);
        EditText key=new EditText(a);key.setHint("DashScope API Key（留空保留现有值）");key.setInputType(android.text.InputType.TYPE_CLASS_TEXT|android.text.InputType.TYPE_TEXT_VARIATION_PASSWORD);box.addView(key);
        EditText endpoint=new EditText(a);endpoint.setHint("服务地址（可选）");endpoint.setText(prefs.getString("tts_endpoint",CloudTts.DEFAULT_ENDPOINT));box.addView(endpoint);
        TextView note=new TextView(a);note.setText("仅 wss://dashscope.aliyuncs.com 或 *.maas.aliyuncs.com 的 /api-ws/v1/inference。Key 加密保存，不回显、不写日志。");box.addView(note);
        new AlertDialog.Builder(a).setTitle("阿里 Flash TTS 配置").setView(box).setNegativeButton("取消",null).setPositiveButton("保存",(d,w)->{
            String url=endpoint.getText().toString().trim();if(!CloudTts.endpointValid(url)){EditorialUI.notice(a,"服务地址不符合要求，未保存");return;}
            try{String k=key.getText().toString().trim();if(!k.isEmpty())SecretStore.put(app,"tts_key",k);}catch(Exception e){EditorialUI.notice(a,"Key 保存失败");return;}
            prefs.edit().putString("tts_endpoint",url).apply();stop("云端 TTS 配置已保存");cloudTts=null;/* old engine stopped before it is replaced */}).show();
    }
}