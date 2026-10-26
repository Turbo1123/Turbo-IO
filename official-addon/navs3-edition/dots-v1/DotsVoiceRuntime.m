#import "DotsVoiceRuntime.h"
#import "DotsVoice.h"
#import "DotsPhoneBridge.h"
#import <UIKit/UIKit.h>
static TDVoiceConversation *Voice;
static NSDictionary *Binding,*PendingRecent;
static BOOL(^Idle)(void);
static NSTimer *Timer;
static NSDate *Until;
static NSString *Status;
static BOOL AttemptedSnapshot;
static BOOL SyncPaused=YES; // Restart only restores phone history; never replays an old glasses push.
static NSDictionary *Identity(NSDictionary *b){return b?[b dictionaryWithValuesForKeys:@[@"base",@"device",@"cid",@"alias"]]:nil;}
static void Reset(void){[Voice cancelLocal];Voice=nil;Binding=nil;PendingRecent=nil;Until=nil;AttemptedSnapshot=NO;}
static BOOL Ensure(void){
    NSDictionary *b=TDDotsVoiceBinding();if(!b){Reset();return NO;}
    if(Voice&&[Binding isEqual:Identity(b)])return YES;
    Reset();TDDotsStore *store=TDSharedDotsStore(b[@"base"],b[@"device"]);if(!store)return NO;
    Binding=Identity(b);Voice=[[TDVoiceConversation alloc]initWithClient:[[TDDotsClient alloc]initWithBaseURL:TDBaseURL(b[@"base"]) token:b[@"token"]] store:store conversation:b[@"cid"]];
    Voice.changed=^{Status=Voice.status;};
    Voice.recent=^(NSDictionary *recent){if(!SyncPaused){PendingRecent=[recent copy];AttemptedSnapshot=NO;}};
    return YES;
}
static void Pump(void){
    if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive||!Ensure())return;
    if(Until&&[Until timeIntervalSinceNow]>0&&Voice.waiting)[Voice refresh];
    if(!SyncPaused&&PendingRecent&&!AttemptedSnapshot&&Idle&&Idle()&&TDDotsPhoneIdleForOTA()){
        // One attempt per revision; uncertain file results require manual recovery.
        AttemptedSnapshot=YES;NSString *scope=[Binding[@"base"] stringByAppendingFormat:@"|%@",Binding[@"device"]];
        if(TDDotsPhoneSend(PendingRecent,scope))Status=@"最新消息已开始同步；等待眼镜保存回执。";
        else Status=@"眼镜同步未开始，请在 Dots 页查看状态或手动同步。";
        PendingRecent=nil;
    }
}
void TDDotsVoiceConfigure(BOOL(^idle)(void)){
    if(Timer)return;Idle=[idle copy];Status=@"语音转发默认关闭";
    Timer=[NSTimer scheduledTimerWithTimeInterval:8 repeats:YES block:^(NSTimer *t){(void)t;Pump();}];Timer.tolerance=1;
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){(void)n;[Voice cancelLocal];PendingRecent=nil;TDDotsPhoneCancel();}];
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){(void)n;if(Ensure()){Until=[NSDate dateWithTimeIntervalSinceNow:660];[Voice refresh];}Pump();}];
}
void TDDotsVoiceBindingChanged(void){Reset();SyncPaused=YES;Status=@"绑定已改变；待用户下一次明确发问。";}
void TDDotsVoicePauseSync(void){SyncPaused=YES;PendingRecent=nil;Status=@"自动同步已暂停；下一次明确语音发问才恢复。";}
NSString *TDDotsVoiceStatus(void){return Status?:@"语音转发默认关闭";}
NSString *TDDotsVoiceSubmit(NSString *asr){
    NSUserDefaults *prefs=[[NSUserDefaults alloc]initWithSuiteName:@"TurboIO.Dots.v1"];
    if(![prefs boolForKey:@"voiceEnabled"])return nil;
    NSString *question=TDVoiceQuestion(asr,[prefs stringForKey:@"voiceAlias"]);if(question==nil)return nil;
    NSDictionary *b=TDDotsVoiceBinding();if(!b)return @"Dots 绑定或凭据已失效，请在手机重新连接；没有把问题转给其他模型。";
    if(!question.length)return [NSString stringWithFormat:@"想问%@什么？请连同问题再说一次。",b[@"alias"]];
    if(!Ensure())return @"Dots 绑定或本机记录不可用，请先在手机检查连接。";
    Until=[NSDate dateWithTimeIntervalSinceNow:660];
    if(![Voice submit:question])return Voice.status;
    SyncPaused=NO;
    return [NSString stringWithFormat:@"已为%@保存这个问题，正在提交。回答会留在手机 Dots 消息中，并尝试同步到眼镜。",b[@"alias"]];
}
