/* Private foreground receiver test. UxPlay core is GPLv3; not a public release. */
#import "Receiver.h"
#import <VideoToolbox/VideoToolbox.h>
#include "raop.h"
#include "AnnexB.h"
@interface TARReceiver ()<NSNetServiceDelegate>{
 raop_t *_raop;dnssd_t *_dns;VTDecompressionSessionRef _decoder;CMVideoFormatDescriptionRef _format;
 CVPixelBufferRef _latest;NSUInteger _latestSeq;NSLock *_lock;dispatch_queue_t _control;
 NSData *_sps,*_pps;NSString *_admitted;NSMutableArray<NSNetService *> *_services;NSUInteger _published;
}
@property(atomic,readwrite,copy) NSString *note,*pin;
@property(atomic,readwrite) BOOL running,stopping;
@property(atomic,readwrite) NSUInteger accessUnits,decodedFrames,receivedBytes,decodeErrors,connections;
@property(atomic,readwrite) int lastError;
- (void)packet:(video_decode_struct *)packet;
- (void)output:(CVPixelBufferRef)image error:(OSStatus)error;
- (BOOL)admitDevice:(NSString *)device;
@end
static TARReceiver *receiver(void *p){return (__bridge TARReceiver *)p;}
static void noop(void *p){(void)p;}
static void audio(void *p,raop_ntp_t *n,audio_decode_struct *d){(void)p;(void)n;(void)d;}
static void video(void *p,raop_ntp_t *n,video_decode_struct *d){(void)n;@autoreleasepool{[receiver(p) packet:d];}}
static void connection(void *p){receiver(p).connections++;}
static void reset(void *p,int reason){(void)reason;receiver(p).note=@"发送端已断开，可重新选择 Turbo IO";}
static void vreset(void *p,reset_type_t reason){(void)reason;receiver(p).note=@"发送端视频已停止，等待重新投屏";}
static int codec(void *p,video_codec_t c,unsigned short a,unsigned short b,unsigned short x,unsigned short y,unsigned short w,unsigned short h){
 (void)x;(void)y;(void)w;(void)h;if(c!=VIDEO_CODEC_H264||!a||!b||(NSUInteger)a*b>4096*2160){receiver(p).note=@"此测试仅支持 H.264 屏幕镜像";return -1;}return 0;
}
static double volume(void *p){(void)p;return -144;}
static void setvolume(void *p,float v){(void)p;(void)v;}
static void metadata(void *p,const void *b,int n){(void)p;(void)b;(void)n;}
static void remoteid(void *p,const char *a,const char *b){(void)p;(void)a;(void)b;}
static void progress(void *p,uint32_t *a,uint32_t *b,uint32_t *c){(void)p;(void)a;(void)b;(void)c;}
static void audioformat(void *p,unsigned char *c,unsigned short *s,bool *screen,bool *media,uint64_t *f){(void)p;(void)c;(void)s;(void)screen;(void)media;(void)f;}
static void mirror(void *p,bool yes){receiver(p).note=yes?@"镜像连接已建立，等待视频解码":@"镜像流已停止";}
static void showpin(void *p,char *s){receiver(p).pin=s?[NSString stringWithUTF8String:s]:@"";}
static void registerclient(void *p,const char *a,const char *b,const char *c){(void)p;(void)a;(void)b;(void)c;}
static bool check(void *p,const char *s){(void)p;(void)s;return false;}
static const char *password(void *p,int *n){(void)p;*n=0;return NULL;}
static void play(void *p,const char *s,float f){(void)s;(void)f;receiver(p).note=@"请使用控制中心的屏幕镜像，不支持网页视频直投";}
static void scalar(void *p,float f){(void)p;(void)f;}
static float removeplaylist(void *p){(void)p;return 0;}
static void playback(void *p,playback_info_t *i){(void)p;memset(i,0,sizeof(*i));}
static void custom(void *p,const char **s){(void)p;*s=NULL;}
static void admit(void *p,char *device,char *model,char *name,bool *yes){
 (void)model;(void)name;*yes=[receiver(p) admitDevice:device?[NSString stringWithUTF8String:device]:nil];
}
static void decoded(void *p,void *source,OSStatus error,VTDecodeInfoFlags flags,CVImageBufferRef image,CMTime pts,CMTime duration){
 (void)source;(void)flags;(void)pts;(void)duration;@autoreleasepool{[receiver(p) output:image error:error];}
}
@implementation TARReceiver
- (instancetype)init{if((self=[super init])){_lock=[NSLock new];_control=dispatch_queue_create("io.turbo.airplay.control",DISPATCH_QUEUE_SERIAL);self.note=@"尚未启动接收";self.pin=@"";}return self;}
- (void)output:(CVPixelBufferRef)image error:(OSStatus)error{
 if(!self.running)return;if(error||!image){self.decodeErrors++;self.lastError=error;return;}
 if(CVPixelBufferGetWidth(image)>4096||CVPixelBufferGetHeight(image)>2160)return;
 [_lock lock];CVPixelBufferRef old=_latest;_latest=CVPixelBufferRetain(image);_latestSeq++;[_lock unlock];if(old)CVPixelBufferRelease(old);self.decodedFrames++;
}
- (CVPixelBufferRef)copyLatest:(NSUInteger *)sequence{
 [_lock lock];CVPixelBufferRef p=_latest?CVPixelBufferRetain(_latest):NULL;if(sequence)*sequence=_latestSeq;[_lock unlock];return p;
}
- (void)packet:(video_decode_struct *)p{
 if(!self.running||p->is_h265||p->data_len<=0)return;self.accessUnits++;self.receivedBytes+=p->data_len;
 TARNAL nals[128];int count=tar_nals(p->data,(size_t)p->data_len,nals,128);if(count<1){self.decodeErrors++;return;}
 BOOL changed=NO;NSMutableData *sample=[NSMutableData new];
 for(int i=0;i<count;i++){TARNAL n=nals[i];unsigned type=n.data[0]&31;
  if(type==7||type==8){NSData *d=[NSData dataWithBytes:n.data length:n.length];NSData *old=type==7?_sps:_pps;if(![old isEqual:d]){changed=YES;if(type==7)_sps=d;else _pps=d;}continue;}
  if(type==9)continue;uint32_t length=CFSwapInt32HostToBig((uint32_t)n.length);[sample appendBytes:&length length:4];[sample appendBytes:n.data length:n.length];
 }
 if(changed&&_sps&&_pps){
  if(_decoder){VTDecompressionSessionWaitForAsynchronousFrames(_decoder);VTDecompressionSessionInvalidate(_decoder);CFRelease(_decoder);_decoder=NULL;}
  if(_format){CFRelease(_format);_format=NULL;}
  const uint8_t *params[]={_sps.bytes,_pps.bytes};size_t sizes[]={_sps.length,_pps.length};
  OSStatus e=CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault,2,params,sizes,4,&_format);
  if(!e){CMVideoDimensions dims=CMVideoFormatDescriptionGetDimensions(_format);if(dims.width<1||dims.height<1||dims.width>4096||dims.height>2160)e=-1;}
  if(!e){VTDecompressionOutputCallbackRecord cb={decoded,(__bridge void *)self};NSDictionary *attrs=@{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),(id)kCVPixelBufferIOSurfacePropertiesKey:@{}};
   e=VTDecompressionSessionCreate(kCFAllocatorDefault,_format,NULL,(__bridge CFDictionaryRef)attrs,&cb,&_decoder);
   if(!e)VTSessionSetProperty(_decoder,kVTDecompressionPropertyKey_RealTime,kCFBooleanTrue);
  }
  if(e){self.decodeErrors++;self.lastError=e;self.note=@"视频解码器初始化失败";return;}
 }
 if(!_decoder||!sample.length)return;
 CMBlockBufferRef buffer=NULL;CMSampleBufferRef frame=NULL;OSStatus e=CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault,NULL,sample.length,kCFAllocatorDefault,NULL,0,sample.length,0,&buffer);
 if(!e)e=CMBlockBufferReplaceDataBytes(sample.bytes,buffer,0,sample.length);
 size_t size=sample.length;CMSampleTimingInfo time={kCMTimeInvalid,CMTimeMake(self.accessUnits,30),kCMTimeInvalid};
 if(!e)e=CMSampleBufferCreateReady(kCFAllocatorDefault,buffer,_format,1,1,&time,1,&size,&frame);
 if(!e)e=VTDecompressionSessionDecodeFrame(_decoder,frame,0,NULL,NULL);
 if(frame)CFRelease(frame);if(buffer)CFRelease(buffer);if(e){self.decodeErrors++;self.lastError=e;}
}
- (void)start{
 NSAssert(NSThread.isMainThread,@"main only");if(self.running||self.stopping)return;self.running=YES;self.note=@"正在启动接收服务…";
 self.accessUnits=self.decodedFrames=self.receivedBytes=self.decodeErrors=self.connections=0;self.lastError=0;_published=0;
 NSString *mac=[NSUserDefaults.standardUserDefaults stringForKey:@"TARLocalDeviceID"];
 if(!mac.length){uint8_t b[6];arc4random_buf(b,sizeof(b));b[0]=(b[0]|2)&254;mac=[NSString stringWithFormat:@"%02X:%02X:%02X:%02X:%02X:%02X",b[0],b[1],b[2],b[3],b[4],b[5]];[NSUserDefaults.standardUserDefaults setObject:mac forKey:@"TARLocalDeviceID"];}
 uint8_t hw[6];NSArray *parts=[mac componentsSeparatedByString:@":"];if(parts.count!=6){self.running=NO;self.note=@"接收器标识无效";return;}for(int i=0;i<6;i++)hw[i]=(uint8_t)strtoul([parts[i]UTF8String],NULL,16);
 NSString *directory=[NSHomeDirectory()stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/AirPlay"];
 [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
 NSString *key=[directory stringByAppendingPathComponent:@"receiver.key"];
 unsigned pin=arc4random_uniform(9000)+1000;self.pin=[NSString stringWithFormat:@"%04u",pin];
 NSData *hardware=[NSData dataWithBytes:hw length:6];
 dispatch_async(_control,^{@autoreleasepool{
  int err=0;self->_dns=dnssd_init("Turbo IO",8,hardware.bytes,6,1,&err);
  raop_callbacks_t cb={0};cb.cls=(__bridge void *)self;cb.audio_process=audio;cb.video_process=video;cb.video_pause=noop;cb.video_resume=noop;cb.conn_feedback=noop;cb.conn_reset=reset;cb.video_reset=vreset;cb.video_set_codec_and_size=codec;cb.conn_init=connection;cb.conn_destroy=noop;cb.audio_flush=noop;cb.video_flush=noop;cb.audio_set_client_volume=volume;cb.audio_set_volume=setvolume;cb.audio_set_metadata=metadata;cb.audio_set_coverart=metadata;cb.audio_stop_coverart_rendering=noop;cb.audio_remote_control_id=remoteid;cb.audio_set_progress=progress;cb.audio_get_format=audioformat;cb.mirror_video_running=mirror;cb.display_pin=showpin;cb.register_client=registerclient;cb.check_register=check;cb.passwd=password;cb.export_dacp=remoteid;cb.on_video_play=play;cb.on_video_scrub=scalar;cb.on_video_rate=scalar;cb.on_video_stop=noop;cb.on_video_acquire_playback_info=playback;cb.on_video_playlist_remove=removeplaylist;cb.get_custom_profile=custom;
  cb.report_client_request=admit;
  if(self->_dns&&!err)self->_raop=raop_init(&cb);
  if(!self->_raop||raop_init2(self->_raop,0,mac.UTF8String,key.UTF8String)){self.note=@"AirPlay 核心初始化失败";dispatch_async(dispatch_get_main_queue(),^{[self stop];});return;}
  [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600,NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} ofItemAtPath:key error:nil];
  raop_set_log_level(self->_raop,0);raop_set_plist(self->_raop,"width",1280);raop_set_plist(self->_raop,"height",720);raop_set_plist(self->_raop,"maxFPS",30);raop_set_plist(self->_raop,"refreshRate",30);raop_set_plist(self->_raop,"pin",10000+pin);raop_set_dnssd(self->_raop,self->_dns);
  unsigned short port=0;if(raop_start_httpd(self->_raop,&port)<0||!port){self.note=@"监听端口启动失败";dispatch_async(dispatch_get_main_queue(),^{[self stop];});return;}
  raop_set_port(self->_raop,port);
  /* Build the upstream TXT records; private iOS core leaves publication to NSNetService. */
  if(dnssd_register_raop(self->_dns,port)||dnssd_register_airplay(self->_dns,port)){self.note=@"服务信息初始化失败";dispatch_async(dispatch_get_main_queue(),^{[self stop];});return;}
  int a=0,b=0;const char *air=dnssd_get_airplay_txt(self->_dns,&a),*raop=dnssd_get_raop_txt(self->_dns,&b);
  NSData *airTXT=[NSData dataWithBytes:air length:MAX(0,a)],*raopTXT=[NSData dataWithBytes:raop length:MAX(0,b)];
  dispatch_async(dispatch_get_main_queue(),^{if(!self.running)return;self->_services=[NSMutableArray new];
   NSArray *types=@[@"_airplay._tcp.",@"_raop._tcp."];NSArray *names=@[@"Turbo IO",[[mac stringByReplacingOccurrencesOfString:@":" withString:@""]stringByAppendingString:@"@Turbo IO"]];NSArray *txt=@[airTXT,raopTXT];
   for(int i=0;i<2;i++){NSNetService *s=[[NSNetService alloc]initWithDomain:@"local." type:types[i] name:names[i] port:port];s.delegate=self;[s setTXTRecordData:txt[i]];[self->_services addObject:s];[s publish];}
   self.note=@"正在发布 Turbo IO，请允许本地网络权限";
  });
 }});
}
- (BOOL)admitDevice:(NSString *)device{
 [_lock lock];BOOL yes=self.running&&device.length&&(!_admitted||[_admitted isEqual:device]);if(yes)_admitted=[device copy];[_lock unlock];return yes;
}
- (void)netServiceDidPublish:(NSNetService *)s{(void)s;if(++_published==2)self.note=@"服务已发布 · 在另一台设备选择屏幕镜像 → Turbo IO";}
- (void)netService:(NSNetService *)s didNotPublish:(NSDictionary *)error{(void)s;self.lastError=[error[NSNetServicesErrorCode] intValue];self.note=@"服务发布失败：检查本地网络权限及同一 Wi-Fi";[self stop];}
- (void)stop{
 NSAssert(NSThread.isMainThread,@"main only");if(self.stopping||!self.running)return;self.running=NO;self.stopping=YES;
 for(NSNetService *s in _services){s.delegate=nil;[s stop];}[_services removeAllObjects];
 dispatch_async(_control,^{@autoreleasepool{
  if(self->_raop){raop_destroy(self->_raop);self->_raop=NULL;}if(self->_dns){dnssd_destroy(self->_dns);self->_dns=NULL;}
  if(self->_decoder){VTDecompressionSessionWaitForAsynchronousFrames(self->_decoder);VTDecompressionSessionInvalidate(self->_decoder);CFRelease(self->_decoder);self->_decoder=NULL;}
  if(self->_format){CFRelease(self->_format);self->_format=NULL;}self->_sps=self->_pps=nil;
  [self->_lock lock];if(self->_latest){CVPixelBufferRelease(self->_latest);self->_latest=NULL;}self->_admitted=nil;[self->_lock unlock];
  dispatch_async(dispatch_get_main_queue(),^{self.stopping=NO;});
 }});
}
@end
