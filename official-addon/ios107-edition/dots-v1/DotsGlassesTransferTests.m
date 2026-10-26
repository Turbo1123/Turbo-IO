#import "DotsGlassesTransfer.h"
#include "dots_carrier.h"
#include <assert.h>
static void drain(void){[[NSRunLoop mainRunLoop]runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];}
static NSDictionary *reply(DotsAck *ack,NSString *peer){uint8_t bytes[DOTS_ENVELOPE_MAX];size_t n=dots_ack_envelope(ack,bytes,sizeof bytes);assert(n);return @{@"eventType":@"messageReceived",@"message":@{@"deviceId":peer,@"businessId":@15,@"payload":[NSData dataWithBytes:bytes length:n]}};}
static NSDictionary *file(NSDictionary *args,NSString *type){return @{@"eventType":type,@"device":@{@"id":args[@"deviceId"]},@"role":@"sender",@"fileName":@"turbo-dots.tdo",@"taskId":[@"sdk-" stringByAppendingString:args[@"taskId"]]};}
int main(int argc,const char **argv){@autoreleasepool{
    assert(argc==2);NSURL *root=[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]] isDirectory:YES];
    DotsSnapshot snapshot={.conversation="conv",.revision=1,.count=1,.messages={{.id="message",.body="Synthetic SDK, no network or device.",.role=1,.state=4}}};
    __block TDGlassesTransfer *session;__block uint32_t now=100;__block BOOL allowed=YES;
    __block NSString *peer=@"synthetic-peer";__block NSUInteger sent=0,ended=0;
    __block NSDictionary *pendingFile;__block void(^pendingCallback)(id);__block NSString *path;
    __block unsigned mode=0;__block DotsModel model;__block DotsReceiver rx;dots_receiver_init(&rx,&model,7392);
    TDGlassesSubmit submit=^BOOL(NSDictionary *args,void(^done)(id)){
        assert(TDGlassesIsScopedCall(@"rayneonet_sendFile",args));assert(!TDGlassesIsScopedCall(@"other",args));
        assert(!TDGlassesIsScopedCall(@"rayneonet_sendFile",[NSMutableDictionary dictionaryWithDictionary:args]));
        assert([args[@"deviceId"]isEqual:peer]);sent++;path=args[@"filePath"];
        NSData *data=[NSData dataWithContentsOfFile:path];assert(data.length&&data.length<=DOTS_PACKET_MAX);
        assert(([[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil][NSFilePosixPermissions]unsignedIntValue]&0777)==0600);
        if(mode==3)return NO; // SDK never invoked
        if(mode==4){done(@{@"success":@NO});return YES;}
        DotsAck ack;assert(dots_receiver_accept(&rx,data.bytes,data.length,now,&ack));
        pendingFile=file(args,@"fileShareSuccess");pendingCallback=[done copy];
        if(mode==5)return YES; // no callback or event: uncertain timeout
        if(mode!=6)[session consume:reply(&ack,peer)]; // ACK arrives before SDK says done
        if(mode!=2&&mode!=7)[session consume:pendingFile];
        done(@{@"success":@YES,@"taskId":pendingFile[@"taskId"]});
        return YES;
    };
    session=[[TDGlassesTransfer alloc]initWithRoot:root peer:peer currentPeer:^{return peer;} allowed:^{return allowed;} clock:^{return now;} submit:submit];
    void(^progress)(NSString *,BOOL)=^(NSString *text,BOOL final){assert(text.length);if(final)ended++;};
    // Early business ACK and early native completion are reconciled only after
    // the submission callback tells us the native ID. Full transfer once.
    assert([session start:&snapshot query:1 progress:progress]);for(unsigned i=0;i<50&&session.busy;i++)drain();
    assert(!session.busy&&ended==1&&model.snapshot.revision==1&&sent==5);
    assert(![NSFileManager.defaultManager fileExistsAtPath:path]);assert(!TDGlassesIsScopedCall(@"rayneonet_sendFile",@{}));
    // ACK alone cannot release the spool/channel or send another packet.
    mode=2;snapshot.revision++;NSUInteger before=sent;assert([session start:&snapshot query:2 progress:progress]);drain();
    assert(sent==before+1&&session.busy&&[NSFileManager.defaultManager fileExistsAtPath:path]);
    NSMutableDictionary *wrong=[pendingFile mutableCopy];wrong[@"taskId"]=@"wrong";assert(![session consume:wrong]);assert(sent==before+1);
    mode=0;[session consume:pendingFile];for(unsigned i=0;i<50&&session.busy;i++)drain();assert(!session.busy&&model.snapshot.revision==2);
    // Known file failure releases; unknown submit retains ownership.
    mode=7;assert([session start:&snapshot query:3 progress:progress]);drain();NSMutableDictionary *failed=[pendingFile mutableCopy];failed[@"eventType"]=@"fileShareFailed";
    [failed removeObjectForKey:@"fileName"]; // Actual stock failure signature has no filename.
    assert([session consume:failed]&&!session.busy&&!session.uncertain);
    mode=4;assert([session start:&snapshot query:4 progress:progress]);drain();assert(session.busy&&session.uncertain);
    NSString *uncertainPath=path;assert([NSFileManager.defaultManager fileExistsAtPath:uncertainPath]);[session disconnected];assert(!session.busy&&[NSFileManager.defaultManager fileExistsAtPath:uncertainPath]);
    // Only the test owns this fake SDK file; production never guesses cleanup.
    assert([NSFileManager.defaultManager removeItemAtPath:uncertainPath.stringByDeletingLastPathComponent error:nil]);
    // Definite no-invocation is not uncertain, no need to reconnect.
    mode=3;assert([session start:&snapshot query:5 progress:progress]);assert(!session.busy&&!session.uncertain&&! [NSFileManager.defaultManager fileExistsAtPath:path]);
    // 12s file timeout cannot trigger blind retry; late exact completion
    // releases the guard without resuming cancelled plaintext.
    mode=5;assert([session start:&snapshot query:6 progress:progress]);before=sent;now+=12000;[session tick];assert(session.uncertain&&sent==before);
    mode=0;pendingCallback(@{@"success":@YES,@"taskId":pendingFile[@"taskId"]});drain();[session consume:pendingFile];assert(!session.busy&&sent==before);
    // ACK loss retries the exact same bytes only after definitive file done.
    mode=6;assert([session start:&snapshot query:7 progress:progress]);drain();NSData *first=[NSData dataWithContentsOfFile:path];before=sent;
    now+=4000;[session tick];drain();assert(sent==before+1&&[[NSData dataWithContentsOfFile:path]isEqual:first]);
    mode=0;now+=4000;[session tick];for(unsigned i=0;i<50&&session.busy;i++)drain();assert(!session.busy);
    // Protection toggling, cancellation and peer changes never advance.
    allowed=NO;before=sent;assert(![session start:&snapshot query:8 progress:progress]&&sent==before);allowed=YES;
    mode=2;assert([session start:&snapshot query:8 progress:progress]);drain();allowed=NO;[session tick];assert(session.uncertain);[session consume:pendingFile];assert(!session.busy);allowed=YES;
    assert([session start:&snapshot query:9 progress:progress]);drain();[session cancel];assert(session.uncertain);[session consume:pendingFile];assert(!session.busy);
    assert([session start:&snapshot query:10 progress:progress]);drain();peer=@"other-peer";[session tick];assert(session.uncertain);[session disconnected];assert(!session.busy);
    assert([NSFileManager.defaultManager removeItemAtPath:path.stringByDeletingLastPathComponent error:nil]);
    session=nil;pendingCallback=nil;
    puts("PASS: Dots injected SDK transfer; early ACK/file, native ID, delayed completion, identical retry, uncertain retention, OTA/cancel/disconnect. No device/network.");
}return 0;}
