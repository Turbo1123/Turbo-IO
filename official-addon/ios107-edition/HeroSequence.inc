// Decorative phone-only atlas animation: no network, timers, audio or protocol.
// One bounded texture, not 24 simultaneously decoded full-size UIImages.
@interface TIOHeroSequence:UIView
@property CALayer *sprite;
@property(nonatomic,strong) UIImage *atlas;
@property(nonatomic,strong) UIImage *still;
@property NSUInteger playCount;
@property BOOL pendingEntrance;
@property NSUInteger entranceGeneration;
- (void)playEntrance;
- (void)stopEntrance;
@end
@implementation TIOHeroSequence
- (instancetype)initWithFrame:(CGRect)frame {
 if((self=[super initWithFrame:frame])) {
  self.userInteractionEnabled=NO;self.isAccessibilityElement=NO;self.clipsToBounds=YES;
  self.sprite=[CALayer layer];self.sprite.contentsGravity=kCAGravityResize;
  self.sprite.magnificationFilter=kCAFilterLinear;self.sprite.minificationFilter=kCAFilterLinear;
  [self.layer addSublayer:self.sprite];
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(stopEntrance) name:UIApplicationWillResignActiveNotification object:nil];
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(becameActive) name:UIApplicationDidBecomeActiveNotification object:nil];
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(motionPreferenceChanged) name:UIAccessibilityReduceMotionStatusDidChangeNotification object:nil];
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(memoryWarning) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
 }
 return self;
}
- (void)dealloc{[NSNotificationCenter.defaultCenter removeObserver:self];}
- (void)loadAtlas {
 if(!self.still)self.still=[self boundedImage:@"hero-glass-v5" pixels:768];
 if(!self.atlas)self.atlas=[self boundedImage:@"hero-sequence-v5" pixels:1536];
}
- (UIImage *)boundedImage:(NSString *)name pixels:(NSUInteger)pixels {
 NSString *path=[NSBundle.mainBundle pathForResource:name ofType:@"png" inDirectory:@"TurboIOArt"];
 if(!path)return nil;
 CGImageSourceRef source=CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],NULL);if(!source)return nil;
 // Atlas 6 MiB + approved final still 2.25 MiB maximum; no per-frame UIImage array.
 CGImageRef cg=CGImageSourceCreateThumbnailAtIndex(source,0,(__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways:@YES,(__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize:@(pixels),(__bridge NSString *)kCGImageSourceShouldCacheImmediately:@YES});CFRelease(source);
 UIImage *result=nil;if(cg){result=[UIImage imageWithCGImage:cg];CGImageRelease(cg);}return result;
}
- (void)layoutSubviews {
 [super layoutSubviews];
 // Keep the generated silhouette above the slogan, including settling motion.
 // The atlas has transparent cell margins; do not fill the region by width.
 CGFloat size=MIN(self.bounds.size.width-22,240);
 [CATransaction begin];[CATransaction setDisableActions:YES];
 self.sprite.frame=CGRectMake(self.bounds.size.width-size-22,-24,size,size);
 [CATransaction commit];
}
- (void)stopEntrance {
 self.entranceGeneration++;
 self.pendingEntrance=NO;
 [self.sprite removeAllAnimations];
 [CATransaction begin];[CATransaction setDisableActions:YES];
 self.sprite.contents=(__bridge id)(self.still?:self.atlas).CGImage;
 self.sprite.contentsRect=self.still?CGRectMake(0,0,1,1):CGRectMake(5.0/6,3.0/4,1.0/6,1.0/4);
 self.sprite.transform=CATransform3DIdentity;self.sprite.opacity=1;
 [CATransaction commit];
}
- (void)playEntrance {
 [self loadAtlas];[self stopEntrance];if(!self.atlas||UIAccessibilityIsReduceMotionEnabled())return;
 if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive){self.pendingEntrance=YES;return;}
 self.playCount++;
 [CATransaction begin];[CATransaction setDisableActions:YES];self.sprite.contents=(__bridge id)self.atlas.CGImage;self.sprite.contentsRect=CGRectMake(5.0/6,3.0/4,1.0/6,1.0/4);[CATransaction commit];
 NSMutableArray *values=[NSMutableArray new],*times=[NSMutableArray new];
 for(NSUInteger i=0;i<24;i++){[values addObject:[NSValue valueWithCGRect:CGRectMake((i%6)/6.0,(i/6)/4.0,1.0/6,1.0/4)]];[times addObject:@(i/23.0)];}
 CAKeyframeAnimation *frames=[CAKeyframeAnimation animationWithKeyPath:@"contentsRect"];
 frames.values=values;frames.keyTimes=times;frames.calculationMode=kCAAnimationDiscrete;
 frames.duration=1.2;frames.repeatCount=0;frames.removedOnCompletion=YES;
 [self.sprite addAnimation:frames forKey:@"turbo-entrance-frames"];
 // Explicit one-shot cleanup also handles a suspended render server. A prior
 // entry's completion must never stop a newer entry, and must not retain view.
 NSUInteger generation=self.entranceGeneration;__weak typeof(self) weak=self;
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1300*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
  TIOHeroSequence *strong=weak;if(strong&&strong.entranceGeneration==generation)[strong stopEntrance];
 });
 // Native compositor interpolates the gentle settling motion, while poses use
 // actual generated sequence frames. No claim that 24 poses are 60 assets.
 CABasicAnimation *settle=[CABasicAnimation animationWithKeyPath:@"transform"];
 settle.fromValue=[NSValue valueWithCATransform3D:CATransform3DConcat(CATransform3DMakeTranslation(0,8,0),CATransform3DMakeScale(.94,.94,1))];settle.toValue=[NSValue valueWithCATransform3D:CATransform3DIdentity];settle.duration=1.2;settle.timingFunction=[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];[self.sprite addAnimation:settle forKey:@"turbo-entrance-settle"];
}
- (void)motionPreferenceChanged{if(UIAccessibilityIsReduceMotionEnabled())[self stopEntrance];}
- (void)becameActive{if(self.pendingEntrance&&self.window)[self playEntrance];}
- (void)memoryWarning{[self stopEntrance];self.atlas=nil;if(!self.window){self.sprite.contents=nil;self.still=nil;}}
@end
