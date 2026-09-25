#import "TodoRuntime.h"
#import "AppleCalendarSync.h"
#if TIO_NATIVE_NAV
#import "DisplayPhoneUI.h"
#import "ImageUploadTransport.h"
#endif
#if TIO_OTA_RESEARCH_ENABLED
#import "ExperimentalOTAFlash.h"
#import "ExperimentalOTAGuard.h"
#endif
#import "ProtocolContext.h"
#import "NavigationTransport.h"
#import "SubtitleHUD.h"
#import "TodoProtocol.h"
#import "TodoCompletionLedger.h"
#import "NewsReader.h"
#import "NewsTeleprompter.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// Only observed public ObjC callbacks. No Dart pointer invocation or cloud tokens.
static void (*PriorMethod)(id,SEL,id,id);
static void (*PriorSend)(id,SEL,id,id,id);
static __weak id BridgeInstance;
static __weak UITableViewController *RuntimePanel;
static NSString *AppCompletionState=@"";
static NSString *PendingAppDevice,*PendingAppWire;
static NSTimeInterval PendingAppAt;
static NSMutableDictionary<NSString *,NSNumber *> *AppConfirmedSources;
static NSMutableSet<NSString *> *PendingPhysicalConfirmations;
static NSMutableDictionary<NSString *,NSString *> *PendingCompletionTitles;
static NSMutableSet<NSString *> *UnlinkedCompletionRecoverySuppressed;
static TIOTodoCompletionLedger *PendingAppleCompletions;
static id CompletionForegroundObserver;
static void PresentPendingAppleCompletionIfPossible(void);
static NSDictionary *Snapshot,*Baseline;
static NSString *Device,*TestTitle,*TestWire,*TestDevice,*State=@"尚未观察到官方待办列表";
static NSString *LastNlpDomain,*LastNlpIntent,*LastNlpCommand;
static NSString *LastAppleCompletion=@"not_attempted";
static NSInteger LastAppleCompletionErrorCode;
static NSInteger LastPhysicalStatus=-1;
static BOOL LastPhysicalDeviceMatched;
static NSUInteger SnapshotCompletions;
static NSUInteger AppCompletionTransitions;
static NSUInteger AutomaticSnapshotNewRows,AutomaticSnapshotCompletionTransitions;
static NSString *LastSnapshotSyncStatus=@"not_attempted";
static NSTimeInterval LastSnapshotSyncAt;
static NSUInteger LinkedRowsInSnapshot;
static BOOL LastPhysicalPresentInSnapshot;
static NSUInteger SnapshotRows;
static NSUInteger CompletionReadyRows;
static NSString *RecentOfficialTitle,*RecentOfficialDevice,*RecentOutgoingWire,*RecentCandidateWire;
static NSTimeInterval RecentOfficialAt;
static NSUInteger OutgoingTaskPackets,OutgoingTitleMatches;
static BOOL OutgoingMatchedSnapshotCandidate;
static NSMutableArray<NSDictionary *> *PendingOfficialCreates;
static NSUInteger AppleTodoCreateAttempts,AppleTodoCreateSuccesses,AppleTodoCreateFailures;
static NSString *LastAppleTodoCreateStatus=@"not_attempted";
static NSString *OfficialCreateMatchStatus=@"not_attempted";
static NSString *const PendingOfficialCreatesKey=@"io.turboio.todo.pendingOfficialCreates.v2";
static NSString *const AppleTodoStatusKey=@"io.turboio.todo.lastAppleCreateStatus.v2";
static NSString *const OfficialMatchStatusKey=@"io.turboio.todo.officialMatchStatus.v2";
static NSString *const AppleTodoAttemptsKey=@"io.turboio.todo.appleCreateAttempts.v2";
static NSString *const AppleTodoSuccessesKey=@"io.turboio.todo.appleCreateSuccesses.v2";
static NSString *const AppleTodoFailuresKey=@"io.turboio.todo.appleCreateFailures.v2";
static NSString *const ObservedTodoRowsKey=@"io.turboio.todo.observedWireStates.v1";
static NSString *const TodoSyncBootstrapAtKey=@"io.turboio.todo.syncBootstrapAt.v1";
static const NSTimeInterval TodoSyncBootstrapGrace=7200.0;
static const NSTimeInterval OfficialCreateMatchWindow=600.0;
static const NSTimeInterval PendingOfficialCreateRetention=604800.0;
static NSMutableSet<NSString *> *AppleTodoSourcesInFlight;
static NSUInteger BrightnessCommands,BrightnessReports,SuggestionCardsSent,SuggestionChoicesReceived;
static NSInteger LastBrightnessCommand=-1,LastBrightnessReport=-1;
static NSArray<NSString *> *RelevantSettingKeys;
static NSTimeInterval SnapshotAt,TemplateAt;
static id Template;
static __weak id Listener;
static BOOL Installed,Busy,PhysicalComplete,Injecting;
static NSUInteger Snapshots,InboundSnapshots,OutboundSnapshots,TaskEvents,PhysicalEvents;
static id ChatContext;
static __weak id ChatListener;
static NSTimeInterval ChatAt;
static BOOL ToolOperation,ToolDispatching;
static void (^ToolCompletion)(NSDictionary *);
static NSString *const UnresolvedKey=@"io.turboio.todo.unresolvedSubmission";
static NSString *QualifiedSource(NSString *device,NSString *wire){
    if(!device.length||device.length>200||!wire.length||wire.length>19)return nil;
    return [NSString stringWithFormat:@"%@:%@",device,wire];
}
static TIOTodoCompletionLedger *CompletionLedger(void){
    if(!PendingAppleCompletions)PendingAppleCompletions=[[TIOTodoCompletionLedger alloc]initWithDefaults:NSUserDefaults.standardUserDefaults];
    return PendingAppleCompletions;
}
static void CompleteTool(NSString *status){void (^done)(NSDictionary *)=[ToolCompletion copy];ToolCompletion=nil;NSString *source=QualifiedSource(TestDevice,TestWire);if(done)done([status isEqual:@"created"]&&source?@{@"status":status,@"source_id":source}:@{@"status":status});}
BOOL TIOTodoIsToolDispatching(void){return ToolDispatching;}
void TIOTodoSetChatContext(id listener,id response){ChatListener=listener;ChatContext=response;ChatAt=[NSDate.date timeIntervalSince1970];}
static id Get(id o,NSString *k){@try{return [o valueForKey:k];}@catch(NSException *e){return nil;}}
static NSData *Data(id v){if([v isKindOfClass:NSData.class])return v;if([NSStringFromClass([v class]) isEqual:@"FlutterStandardTypedData"]){id d=Get(v,@"data");if([d isKindOfClass:NSData.class])return d;}return nil;}
static NSString *Text(id o){return [o isKindOfClass:NSString.class]?o:@"";}
static NSDictionary *Task(id params){if(![params isKindOfClass:NSDictionary.class])return nil;id t=params[@"task"];if([t isKindOfClass:NSString.class]&&[t length]<65536)t=[NSJSONSerialization JSONObjectWithData:[t dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];return [t isKindOfClass:NSDictionary.class]?t:nil;}
static void EnsurePendingOfficialCreates(void){
    if(PendingOfficialCreates)return;PendingOfficialCreates=[NSMutableArray array];AppleTodoSourcesInFlight=[NSMutableSet set];NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;
    LastAppleTodoCreateStatus=Text([defaults stringForKey:AppleTodoStatusKey]);if(!LastAppleTodoCreateStatus.length)LastAppleTodoCreateStatus=@"not_attempted";OfficialCreateMatchStatus=Text([defaults stringForKey:OfficialMatchStatusKey]);if(!OfficialCreateMatchStatus.length)OfficialCreateMatchStatus=@"not_attempted";
    AppleTodoCreateAttempts=[[defaults objectForKey:AppleTodoAttemptsKey] unsignedIntegerValue];AppleTodoCreateSuccesses=[[defaults objectForKey:AppleTodoSuccessesKey] unsignedIntegerValue];AppleTodoCreateFailures=[[defaults objectForKey:AppleTodoFailuresKey] unsignedIntegerValue];
    id stored=[defaults objectForKey:PendingOfficialCreatesKey];if(![stored isKindOfClass:NSArray.class])return;
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    for(id value in (NSArray *)stored){if(![value isKindOfClass:NSDictionary.class])continue;NSDictionary *row=value;NSString *title=Text(row[@"title"]),*device=Text(row[@"device"]);NSTimeInterval at=[row[@"at"] doubleValue];NSDictionary *baseline=row[@"baseline"];
        NSTimeInterval retention=Text(row[@"candidateWireId"]).length?PendingOfficialCreateRetention:OfficialCreateMatchWindow;
        if(!title.length||title.length>240||!device.length||device.length>200||at<=0||now-at>retention)continue;
        if(![baseline isKindOfClass:NSDictionary.class])continue;[PendingOfficialCreates addObject:row];
    }
}
static void PersistPendingOfficialCreates(void){
    EnsurePendingOfficialCreates();if(PendingOfficialCreates.count)[NSUserDefaults.standardUserDefaults setObject:[PendingOfficialCreates copy] forKey:PendingOfficialCreatesKey];else [NSUserDefaults.standardUserDefaults removeObjectForKey:PendingOfficialCreatesKey];[NSUserDefaults.standardUserDefaults synchronize];
}
static NSDictionary *RowForWire(NSDictionary *snapshot,NSString *wire){for(NSDictionary *row in snapshot[@"items"])if([row[@"wireId"] isEqual:wire])return row;return nil;}
static void PersistAppleTodoSyncState(void){NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;[defaults setObject:LastAppleTodoCreateStatus?:@"" forKey:AppleTodoStatusKey];[defaults setObject:@(AppleTodoCreateAttempts) forKey:AppleTodoAttemptsKey];[defaults setObject:@(AppleTodoCreateSuccesses) forKey:AppleTodoSuccessesKey];[defaults setObject:@(AppleTodoCreateFailures) forKey:AppleTodoFailuresKey];[defaults synchronize];}
static void PersistOfficialMatchState(void){NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;[defaults setObject:OfficialCreateMatchStatus?:@"" forKey:OfficialMatchStatusKey];[defaults synchronize];}
static void RefreshLinkedRowsForSnapshot(void){if(!Snapshot||!Device.length)return;LinkedRowsInSnapshot=0;for(NSDictionary *item in Snapshot[@"items"]){NSString *sourceID=QualifiedSource(Device,item[@"wireId"]);if(sourceID&&TIOAppleHasLinkedReminder(sourceID))LinkedRowsInSnapshot++;}}
static BOOL FindCreationAssignment(NSArray<NSArray<NSString *> *> *candidateSets,NSUInteger index,NSUInteger target,NSMutableSet<NSString *> *used,NSMutableArray<NSDictionary *> *assignment){
    if(assignment.count>=target)return YES;if(index>=candidateSets.count)return NO;
    for(NSString *wire in candidateSets[index]){if([used containsObject:wire])continue;[used addObject:wire];[assignment addObject:@{@"index":@(index),@"wire":wire}];if(FindCreationAssignment(candidateSets,index+1,target,used,assignment))return YES;[assignment removeLastObject];[used removeObject:wire];}
    return FindCreationAssignment(candidateSets,index+1,target,used,assignment);
}
static BOOL Sign(Method m,NSUInteger n){if(!m||method_getNumberOfArguments(m)!=n)return NO;char *r=method_copyReturnType(m);BOOL ok=r&&r[0]=='v';free(r);for(NSUInteger i=2;i<n;i++){char *t=method_copyArgumentType(m,(unsigned)i);ok=ok&&t&&t[0]=='@';free(t);}return ok;}
static void SaveEvidence(void){
    // No official transcript or unrelated tasks. Only the named test and metadata.
    NSMutableDictionary *row=[@{@"state":State?:@"",@"snapshots":@(Snapshots),@"taskEvents":@(TaskEvents),@"physicalEvents":@(PhysicalEvents),@"testTitle":TestTitle?:@"",@"testWireId":TestWire?:@"",@"physicalComplete":@(PhysicalComplete),@"time":@([NSDate.date timeIntervalSince1970])} mutableCopy];
    EnsurePendingOfficialCreates();row[@"inboundSnapshots"]=@(InboundSnapshots);row[@"outboundSnapshots"]=@(OutboundSnapshots);row[@"pendingOfficialCreates"]=@(PendingOfficialCreates.count);row[@"officialCreateMatchStatus"]=OfficialCreateMatchStatus?:@"";row[@"appleTodoCreateAttempts"]=@(AppleTodoCreateAttempts);row[@"appleTodoCreateSuccesses"]=@(AppleTodoCreateSuccesses);row[@"appleTodoCreateFailures"]=@(AppleTodoCreateFailures);row[@"lastAppleTodoCreateStatus"]=LastAppleTodoCreateStatus?:@"";
    row[@"toolOperation"]=@(ToolOperation);if(ToolOperation){row[@"testTitle"]=@"";row[@"testWireId"]=@"";} // No user task contents/IDs in diagnostic file.
    row[@"lastNlpDomain"]=LastNlpDomain?:@"";row[@"lastNlpIntent"]=LastNlpIntent?:@"";row[@"lastNlpCommand"]=LastNlpCommand?:@"";
    row[@"lastPhysicalStatus"]=@(LastPhysicalStatus);row[@"lastPhysicalDeviceMatched"]=@(LastPhysicalDeviceMatched);row[@"lastAppleCompletion"]=LastAppleCompletion?:@"";
    row[@"lastAppleCompletionErrorCode"]=@(LastAppleCompletionErrorCode);
    row[@"snapshotCompletions"]=@(SnapshotCompletions);
    row[@"appCompletionTransitions"]=@(AppCompletionTransitions);
    row[@"automaticSnapshotNewRows"]=@(AutomaticSnapshotNewRows);row[@"automaticSnapshotCompletionTransitions"]=@(AutomaticSnapshotCompletionTransitions);row[@"lastSnapshotSyncStatus"]=LastSnapshotSyncStatus?:@"not_attempted";row[@"lastSnapshotSyncAt"]=@(LastSnapshotSyncAt);
    row[@"pendingAppleCompletionCount"]=@(CompletionLedger().pendingCount);
    row[@"linkedRowsInSnapshot"]=@(LinkedRowsInSnapshot);row[@"lastPhysicalPresentInSnapshot"]=@(LastPhysicalPresentInSnapshot);
    row[@"snapshotRows"]=@(SnapshotRows);row[@"completionReadyRows"]=@(CompletionReadyRows);
    row[@"outgoingTaskPackets"]=@(OutgoingTaskPackets);row[@"outgoingTitleMatches"]=@(OutgoingTitleMatches);row[@"outgoingMatchedSnapshotCandidate"]=@(OutgoingMatchedSnapshotCandidate);
    row[@"brightnessCommands"]=@(BrightnessCommands);row[@"brightnessReports"]=@(BrightnessReports);
    row[@"lastBrightnessCommand"]=@(LastBrightnessCommand);row[@"lastBrightnessReport"]=@(LastBrightnessReport);
    row[@"relevantSettingKeys"]=RelevantSettingKeys?:@[];
    row[@"suggestionCardsSent"]=@(SuggestionCardsSent);row[@"suggestionChoicesReceived"]=@(SuggestionChoicesReceived);
    NSString *dir=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
    NSURL *url=[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"todo-runtime-test.json"]];NSData *data=[NSJSONSerialization dataWithJSONObject:row options:0 error:nil];[data writeToURL:url options:NSDataWritingAtomic error:nil];[NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:url.path error:nil];
}
static void AddRelevantKeys(NSDictionary *row,NSString *prefix,NSMutableArray<NSString *> *keys,NSUInteger depth){
    if(![row isKindOfClass:NSDictionary.class]||depth>2||keys.count>=24)return;
    for(id raw in row){
        if(![raw isKindOfClass:NSString.class]||[raw length]>80)continue;
        NSString *key=(NSString *)raw,*path=prefix.length?[prefix stringByAppendingFormat:@".%@",key]:key;
        NSString *lower=key.lowercaseString;
        if([lower containsString:@"bright"]||[lower containsString:@"light"]||[lower containsString:@"sensor"]||[lower containsString:@"sensing"]||[lower containsString:@"ambient"]) [keys addObject:path];
        if([row[key] isKindOfClass:NSDictionary.class])AddRelevantKeys(row[key],path,keys,depth+1);
        if(keys.count>=24)break;
    }
}
static void ObserveDeviceOrSuggestion(NSDictionary *args,BOOL inbound){
    if(![args isKindOfClass:NSDictionary.class])return;
    NSNumber *business=args[@"businessId"];
    if(![business isEqual:@15]&&![business isEqual:@21])return;
    NSDictionary *envelope=TIOTodoEnvelope(Data(args[@"payload"])),*body=envelope[@"json"];
    if(!envelope||![body isKindOfClass:NSDictionary.class])return;
    if([business isEqual:@21]){
        if(!inbound&&[envelope[@"type"] isEqual:@33]&&[body[@"type"] isEqual:@1])SuggestionCardsSent++;
        if(inbound&&[envelope[@"type"] isEqual:@34]&&([body[@"cmd"] isEqual:@1]||[body[@"cmd"] isEqual:@2]))SuggestionChoicesReceived++;
        SaveEvidence();return;
    }
    NSString *cmd=Text(body[@"cmd"]);NSDictionary *payload=body[@"payload"];
    if([cmd isEqual:@"brightness_change"]&&[payload isKindOfClass:NSDictionary.class]&&[payload[@"value"] isKindOfClass:NSNumber.class]){
        NSInteger value=[payload[@"value"] integerValue];
        if(value>=0&&value<=100){if(inbound){BrightnessReports++;LastBrightnessReport=value;}else{BrightnessCommands++;LastBrightnessCommand=value;}}
    }
    if(inbound){
        NSMutableArray *keys=[NSMutableArray array];AddRelevantKeys(body,@"",keys,0);
        if(keys.count)RelevantSettingKeys=[keys copy];
    }
    SaveEvidence();
}
static void RemovePendingCreateToken(NSString *token){
    if(!token.length)return;EnsurePendingOfficialCreates();NSIndexSet *matches=[PendingOfficialCreates indexesOfObjectsPassingTest:^BOOL(NSDictionary *entry,NSUInteger index,BOOL *stop){return [entry[@"token"] isEqual:token];}];if(matches.count)[PendingOfficialCreates removeObjectsAtIndexes:matches];
}
static void UpsertPendingCreate(NSDictionary *entry){
    NSString *token=Text(entry[@"token"]);if(!token.length)return;RemovePendingCreateToken(token);[PendingOfficialCreates addObject:entry];PersistPendingOfficialCreates();
}
static void RequestAppleCompletionConfirmation(NSString *sourceID,NSString *title);
static void ReconcileOfficialCreates(NSDictionary *snapshot,NSString *device,BOOL explicitRetry);
static void AttemptOfficialAppleCreate(NSDictionary *entry,NSDictionary *item){
    NSString *token=Text(entry[@"token"]),*title=Text(entry[@"title"]),*device=Text(entry[@"device"]),*wire=Text(item[@"wireId"]),*sourceID=QualifiedSource(device,wire);
    if(!sourceID||![item[@"title"] isEqual:title]){LastAppleTodoCreateStatus=@"invalid_official_row";PersistAppleTodoSyncState();SaveEvidence();return;}
    if(TIOAppleHasLinkedReminder(sourceID)){AppleTodoCreateSuccesses++;LastAppleTodoCreateStatus=@"already_linked";RemovePendingCreateToken(token);PersistAppleTodoSyncState();PersistPendingOfficialCreates();RefreshLinkedRowsForSnapshot();SaveEvidence();if([item[@"status"] isEqual:@1]||[CompletionLedger() isPending:sourceID])RequestAppleCompletionConfirmation(sourceID,title);return;}
    EnsurePendingOfficialCreates();if([AppleTodoSourcesInFlight containsObject:sourceID])return;[AppleTodoSourcesInFlight addObject:sourceID];AppleTodoCreateAttempts++;LastAppleTodoCreateStatus=@"writing";PersistAppleTodoSyncState();SaveEvidence();
    TIOAppleCreateReminder(title,sourceID,^(NSDictionary *result){
        [AppleTodoSourcesInFlight removeObject:sourceID];NSString *status=Text(result[@"status"]);if(!status.length)status=@"unknown";LastAppleTodoCreateStatus=status;
        if([status isEqual:@"created"]){AppleTodoCreateSuccesses++;RemovePendingCreateToken(token);}
        else{AppleTodoCreateFailures++;NSMutableDictionary *retry=[entry mutableCopy];retry[@"candidateWireId"]=wire;retry[@"lastAttemptAt"]=@([NSDate.date timeIntervalSince1970]);retry[@"lastStatus"]=status;UpsertPendingCreate(retry);}
        PersistAppleTodoSyncState();PersistPendingOfficialCreates();RefreshLinkedRowsForSnapshot();
        if([status isEqual:@"created"]){State=@"待办已写入苹果提醒事项";if([item[@"status"] isEqual:@1]||[CompletionLedger() isPending:sourceID])RequestAppleCompletionConfirmation(sourceID,title);}else State=[NSString stringWithFormat:@"待办同步未完成：%@",status];
        SaveEvidence();[RuntimePanel.tableView reloadData];if([status isEqual:@"created"])dispatch_async(dispatch_get_main_queue(),^{if(Snapshot&&Device.length)ReconcileOfficialCreates(Snapshot,Device,NO);});
    });
}
static NSDictionary *StoredTodoStatesForDevice(NSString *device){
    if(!device.length||device.length>200)return nil;
    id root=[NSUserDefaults.standardUserDefaults objectForKey:ObservedTodoRowsKey];if(![root isKindOfClass:NSDictionary.class])return nil;
    id states=((NSDictionary *)root)[device];return [states isKindOfClass:NSDictionary.class]?states:nil;
}
static void PersistTodoStatesForDevice(NSString *device,NSDictionary *snapshot){
    if(!device.length||device.length>200)return;NSDictionary *current=TIOTodoSnapshotStatusMap(snapshot);if(!current)return;
    NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;id raw=[defaults objectForKey:ObservedTodoRowsKey];NSMutableDictionary *root=[raw isKindOfClass:NSDictionary.class]?[raw mutableCopy]:[NSMutableDictionary dictionary];
    NSMutableDictionary *merged=[root[device] isKindOfClass:NSDictionary.class]?[root[device] mutableCopy]:[NSMutableDictionary dictionary];
    [merged addEntriesFromDictionary:current];root[device]=[merged copy];
    if(root.count>16){NSArray *keys=[root.allKeys sortedArrayUsingSelector:@selector(compare:)];for(NSUInteger i=0;root.count>16&&i<keys.count;i++)if(![keys[i] isEqual:device])[root removeObjectForKey:keys[i]];}
    [defaults setObject:root forKey:ObservedTodoRowsKey];[defaults synchronize];
}
static NSDictionary *AutomaticSnapshotCreateEntry(NSDictionary *item,NSString *device){
    NSString *wire=Text(item[@"wireId"]),*title=Text(item[@"title"]);if(!wire.length||!title.length||!device.length)return nil;
    NSString *token=[NSString stringWithFormat:@"snapshot-%@-%@",device,wire];if(token.length>240)token=[NSString stringWithFormat:@"snapshot-%@",NSUUID.UUID.UUIDString];
    return @{@"token":token,@"title":title,@"device":device,@"baseline":@{@"items":@[],@"total":@0,@"isLastBatch":@YES},@"at":@([NSDate.date timeIntervalSince1970]),@"candidateWireId":wire,@"automaticSnapshot":@YES};
}
static void QueueAutomaticSnapshotCreate(NSDictionary *item,NSString *device){
    NSString *wire=Text(item[@"wireId"]),*sourceID=QualifiedSource(device,wire);if(!sourceID)return;
    EnsurePendingOfficialCreates();if(TIOAppleHasLinkedReminder(sourceID)||[AppleTodoSourcesInFlight containsObject:sourceID])return;
    NSDictionary *pending=nil;for(NSDictionary *candidate in PendingOfficialCreates)if([Text(candidate[@"device"]) isEqual:device]&&[Text(candidate[@"candidateWireId"]) isEqual:wire]){pending=candidate;break;}
    if(pending){
        NSString *lastStatus=Text(pending[@"lastStatus"]);BOOL canRetry=!pending[@"lastAttemptAt"]||[@[@"failed",@"unknown",@"created_unlinked"] containsObject:lastStatus];
        if(canRetry)AttemptOfficialAppleCreate(pending,item);return;
    }
    NSDictionary *entry=AutomaticSnapshotCreateEntry(item,device);if(!entry)return;
    UpsertPendingCreate(entry);AttemptOfficialAppleCreate(entry,item);
}
static void ObserveAutomaticSnapshotDelta(NSDictionary *snapshot,NSString *device){
    if(!snapshot||!device.length)return;
    NSDictionary *known=StoredTodoStatesForDevice(device);NSArray<NSDictionary *> *newRows=nil,*completedRows=nil;
    if(known){NSDictionary *delta=TIOTodoSnapshotDelta(known,snapshot);newRows=delta[@"added"];completedRows=delta[@"completed"];}else{
        NSNumber *bootstrap=[NSUserDefaults.standardUserDefaults objectForKey:TodoSyncBootstrapAtKey];NSTimeInterval bootAt=bootstrap?bootstrap.doubleValue:NSDate.date.timeIntervalSince1970;if(!bootstrap){bootstrap=@(bootAt);[NSUserDefaults.standardUserDefaults setObject:bootstrap forKey:TodoSyncBootstrapAtKey];[NSUserDefaults.standardUserDefaults synchronize];}NSTimeInterval since=bootAt-TodoSyncBootstrapGrace;
        newRows=TIOTodoSnapshotRowsCreatedAfter(snapshot,MAX(1.0,since));completedRows=@[];
    }
    AutomaticSnapshotNewRows+=(newRows.count);AutomaticSnapshotCompletionTransitions+=(completedRows.count);LastSnapshotSyncAt=NSDate.date.timeIntervalSince1970;
    SnapshotCompletions+=completedRows.count;
    if(newRows.count)LastSnapshotSyncStatus=known?@"new_official_rows_detected":@"recent_install_catchup_detected";
    else LastSnapshotSyncStatus=known?@"baseline_checked_no_new_rows":@"initial_baseline_saved";
    for(NSDictionary *item in newRows){QueueAutomaticSnapshotCreate(item,device);if([item[@"status"] isEqual:@1]){NSString *sourceID=QualifiedSource(device,Text(item[@"wireId"]));if(sourceID){[CompletionLedger() markPending:sourceID];if(TIOAppleHasLinkedReminder(sourceID))RequestAppleCompletionConfirmation(sourceID,Text(item[@"title"]));else AppCompletionState=@"待办已完成；苹果提醒事项写入后仍需确认完成";}}}
    for(NSDictionary *item in completedRows){NSString *sourceID=QualifiedSource(device,Text(item[@"wireId"]));if(sourceID){[UnlinkedCompletionRecoverySuppressed removeObject:sourceID];RequestAppleCompletionConfirmation(sourceID,Text(item[@"title"]));}}
    PersistTodoStatesForDevice(device,snapshot);
}
static void ReconcileOfficialCreates(NSDictionary *snapshot,NSString *device,BOOL explicitRetry){
    EnsurePendingOfficialCreates();if(!PendingOfficialCreates.count)return;NSTimeInterval now=NSDate.date.timeIntervalSince1970;NSMutableArray *expired=[NSMutableArray array];
    for(NSDictionary *entry in [PendingOfficialCreates copy]){NSTimeInterval at=[entry[@"at"] doubleValue];NSTimeInterval retention=Text(entry[@"candidateWireId"]).length?PendingOfficialCreateRetention:OfficialCreateMatchWindow;if(at<=0||now-at>retention){[expired addObject:entry];continue;}}
    if(expired.count){for(NSDictionary *entry in expired)RemovePendingCreateToken(Text(entry[@"token"]));OfficialCreateMatchStatus=@"window_expired";PersistOfficialMatchState();PersistPendingOfficialCreates();}
    NSMutableSet<NSString *> *processed=[NSMutableSet set];BOOL sawUnmatched=NO;
    for(NSDictionary *entry in [PendingOfficialCreates copy]){
        NSString *token=Text(entry[@"token"]);if(!token.length||[processed containsObject:token]||![Text(entry[@"device"]) isEqual:device])continue;
        NSString *fixedWire=Text(entry[@"candidateWireId"]);
        if(fixedWire.length){[processed addObject:token];NSDictionary *row=RowForWire(snapshot,fixedWire);NSString *sourceID=QualifiedSource(device,fixedWire);
            if(sourceID&&TIOAppleHasLinkedReminder(sourceID)){AppleTodoCreateSuccesses++;LastAppleTodoCreateStatus=@"already_linked";RemovePendingCreateToken(token);PersistAppleTodoSyncState();PersistPendingOfficialCreates();continue;}
            NSString *lastStatus=Text(entry[@"lastStatus"]);BOOL crashRecovery=!entry[@"lastAttemptAt"];BOOL retryable=[@[@"failed",@"unknown",@"created_unlinked"] containsObject:lastStatus];
            if((explicitRetry||crashRecovery||retryable)&&row&&[row[@"title"] isEqual:entry[@"title"]]&&([row[@"status"] isEqual:@0]||[row[@"status"] isEqual:@1]))AttemptOfficialAppleCreate(entry,row);else sawUnmatched=YES;continue;
        }
        NSDictionary *baseline=entry[@"baseline"];if(![baseline isKindOfClass:NSDictionary.class]||![baseline[@"items"] isKindOfClass:NSArray.class]||![baseline[@"total"] isKindOfClass:NSNumber.class]||![baseline[@"isLastBatch"] isKindOfClass:NSNumber.class]){OfficialCreateMatchStatus=@"missing_precreate_snapshot";sawUnmatched=YES;continue;}
        if(!snapshot||![snapshot[@"isLastBatch"] boolValue]){sawUnmatched=YES;continue;}
        NSString *title=Text(entry[@"title"]);NSMutableArray<NSDictionary *> *group=[NSMutableArray array];
        for(NSDictionary *other in PendingOfficialCreates){NSString *otherToken=Text(other[@"token"]);NSDictionary *otherBaseline=other[@"baseline"];BOOL validBaseline=[otherBaseline isKindOfClass:NSDictionary.class]&&[otherBaseline[@"items"] isKindOfClass:NSArray.class]&&[otherBaseline[@"total"] isKindOfClass:NSNumber.class]&&[otherBaseline[@"isLastBatch"] isKindOfClass:NSNumber.class];if(![processed containsObject:otherToken]&&[Text(other[@"device"]) isEqual:device]&&[Text(other[@"title"]) isEqual:title]&&!Text(other[@"candidateWireId"]).length&&validBaseline){[group addObject:other];[processed addObject:otherToken];}}
        if(!group.count){sawUnmatched=YES;continue;}if(group.count>8){OfficialCreateMatchStatus=@"too_many_simultaneous_same_title_creates";sawUnmatched=YES;continue;}
        NSMutableArray<NSDictionary *> *readyGroup=[NSMutableArray array];NSMutableArray<NSArray<NSString *> *> *candidateSets=[NSMutableArray array];NSMutableSet<NSString *> *unionIDs=[NSMutableSet set];
        for(NSDictionary *intent in group){NSArray *rows=TIOTodoNewCandidates(intent[@"baseline"],snapshot,title);NSMutableArray *wires=[NSMutableArray array];for(NSDictionary *candidate in rows){NSString *wire=Text(candidate[@"wireId"]),*sourceID=QualifiedSource(device,wire);if(wire.length&&sourceID&&!TIOAppleHasLinkedReminder(sourceID)){[wires addObject:wire];[unionIDs addObject:wire];}}
            if(wires.count){[readyGroup addObject:intent];[candidateSets addObject:[wires sortedArrayUsingSelector:@selector(compare:)]];}
            else if(rows.count){RemovePendingCreateToken(Text(intent[@"token"]));AppleTodoCreateSuccesses++;LastAppleTodoCreateStatus=@"already_linked";PersistAppleTodoSyncState();}
        }
        if(!readyGroup.count){if(group.count)sawUnmatched=YES;continue;}
        if(unionIDs.count>readyGroup.count){OfficialCreateMatchStatus=@"ambiguous_same_title_candidates";sawUnmatched=YES;continue;}
        NSMutableArray<NSDictionary *> *assignment=[NSMutableArray array];if(!FindCreationAssignment(candidateSets,0,unionIDs.count,[NSMutableSet set],assignment)){OfficialCreateMatchStatus=@"ambiguous_same_title_candidates";sawUnmatched=YES;continue;}
        OfficialCreateMatchStatus=@"matched_unique_official_ids";PersistOfficialMatchState();
        for(NSDictionary *pair in assignment){NSUInteger index=[pair[@"index"] unsignedIntegerValue];NSDictionary *intent=readyGroup[index];NSString *wire=pair[@"wire"];NSDictionary *row=RowForWire(snapshot,wire);RemovePendingCreateToken(Text(intent[@"token"]));if(row)AttemptOfficialAppleCreate(intent,row);else{NSMutableDictionary *retry=[intent mutableCopy];retry[@"candidateWireId"]=wire;UpsertPendingCreate(retry);sawUnmatched=YES;}}
    }
    if(sawUnmatched&&[OfficialCreateMatchStatus isEqual:@"not_attempted"])OfficialCreateMatchStatus=@"waiting_for_complete_snapshot";
    PersistOfficialMatchState();PersistPendingOfficialCreates();SaveEvidence();
}
static void ObserveSnapshot(NSDictionary *args,BOOL inbound){
    if(![args isKindOfClass:NSDictionary.class]||![args[@"businessId"] isEqual:@22])return;NSDictionary *s=TIOTodoSnapshot(Data(args[@"payload"]));
    NSString *device=Text(args[@"deviceId"]);if(!s||!device.length||device.length>200)return;
    Snapshots++;if(inbound)InboundSnapshots++;else OutboundSnapshots++;BOOL full=[s[@"isLastBatch"] boolValue]&&[s[@"total"] unsignedIntegerValue]==[s[@"items"] count];
    if(!full){Snapshot=nil;State=@"收到分批列表，未将其当作全量基线";SaveEvidence();return;}
    Snapshot=s;Device=device;SnapshotAt=[NSDate.date timeIntervalSince1970];
    ReconcileOfficialCreates(s,device,NO);
    ObserveAutomaticSnapshotDelta(s,device);
    if(Busy){if(![device isEqual:TestDevice]){Busy=NO;State=@"设备发生变化；测试停止，未绑定";if(ToolOperation)CompleteTool(@"unknown");}
        else{NSDictionary *candidate=TIOTodoNewCandidate(Baseline,s,TestTitle);if(candidate){TestWire=candidate[@"wireId"];Busy=NO;State=@"官方列表出现唯一新项，已关联真实ID；仍需镜片验收";if(ToolOperation){[NSUserDefaults.standardUserDefaults removeObjectForKey:UnresolvedKey];[NSUserDefaults.standardUserDefaults synchronize];CompleteTool(@"created");}}}
    }
    LinkedRowsInSnapshot=0;SnapshotRows=[s[@"items"] count];CompletionReadyRows=0;
    for(NSDictionary *item in s[@"items"]){
        NSString *sourceID=QualifiedSource(device,item[@"wireId"]);
        if(sourceID&&TIOAppleHasLinkedReminder(sourceID))LinkedRowsInSnapshot++;
        if(TIOTodoEncodeStatusUpdate(item,1,(NSInteger)NSDate.date.timeIntervalSince1970))CompletionReadyRows++;
    }
    if(!Busy&&!TestWire.length)State=Template?@"已取得官方列表与新增模板；可测试创建入口":@"已取得官方全量列表基线；等待官方语音新增模板";SaveEvidence();PresentPendingAppleCompletionIfPossible();
}
static void ObserveOutgoingTask(NSDictionary *args){
    if(![args isKindOfClass:NSDictionary.class]||![args[@"businessId"] isEqual:@22])return;
    NSDictionary *row=TIOTodoOutgoingTask(Data(args[@"payload"]));if(!row)return;
    OutgoingTaskPackets++;
    NSString *device=Text(args[@"deviceId"]);
    if(RecentOfficialTitle.length&&[row[@"title"] isEqual:RecentOfficialTitle]&&
       [device isEqual:RecentOfficialDevice]&&[NSDate.date timeIntervalSince1970]-RecentOfficialAt<=120){
        OutgoingTitleMatches++;RecentOutgoingWire=row[@"wireId"];
        OutgoingMatchedSnapshotCandidate=RecentCandidateWire.length&&[RecentCandidateWire isEqual:RecentOutgoingWire];
    }
    SaveEvidence();
}
static NSData *FlutterTypedData(NSData *data){
    Class cls=NSClassFromString(@"FlutterStandardTypedData");SEL factory=NSSelectorFromString(@"typedDataWithBytes:");
    if(!data||![cls respondsToSelector:factory])return nil;
    return ((id(*)(id,SEL,id))objc_msgSend)(cls,factory,data);
}
static BOOL AppRecentlyConfirmedSource(NSString *sourceID){
    NSNumber *time=AppConfirmedSources[sourceID];
    if(!time)return NO;
    if(NSDate.date.timeIntervalSince1970-time.doubleValue>120){[AppConfirmedSources removeObjectForKey:sourceID];return NO;}
    return YES;
}
static NSString *AppleCompletionMessage(NSString *status){
    NSDictionary *labels=@{@"completed":@"苹果提醒事项已完成",@"already_completed":@"苹果提醒事项已经完成",@"missing":@"苹果中找不到对应提醒事项，请重新关联",@"ambiguous":@"苹果中有多条同名提醒事项，未修改任何一条",@"changed":@"苹果提醒事项标题已变化，未修改",@"read_only":@"苹果提醒事项所在清单只读",@"permission_denied":@"Turbo IO 没有苹果提醒事项访问权限",@"not_linked":@"此待办尚未关联苹果提醒事项",@"verification_failed":@"苹果没有读回完成状态，请重试",@"failed":@"苹果保存失败，请重试",@"invalid":@"待办编号或标题无效"};
    return labels[status]?:[NSString stringWithFormat:@"苹果提醒事项未完成（%@）",status.length?status:@"unknown"];
}
static UIViewController *TopCompletionPresenter(void){
    UIApplication *app=UIApplication.sharedApplication;if(app.applicationState!=UIApplicationStateActive)return nil;
    UIWindow *keyWindow=nil;
    if(@available(iOS 13.0,*))for(UIScene *scene in app.connectedScenes){
        if(scene.activationState!=UISceneActivationStateForegroundActive||![scene isKindOfClass:UIWindowScene.class])continue;
        for(UIWindow *window in ((UIWindowScene *)scene).windows)if(window.isKeyWindow){keyWindow=window;break;}
        if(keyWindow)break;
    }
    if(!keyWindow)for(UIWindow *window in app.windows)if(window.isKeyWindow){keyWindow=window;break;}
    UIViewController *controller=keyWindow.rootViewController;if(!controller)return nil;
    for(NSUInteger depth=0;depth<16;depth++){
        if(controller.presentedViewController&&!controller.presentedViewController.isBeingDismissed){controller=controller.presentedViewController;continue;}
        if([controller isKindOfClass:UINavigationController.class]){UIViewController *visible=((UINavigationController *)controller).visibleViewController;if(visible&&visible!=controller){controller=visible;continue;}}
        if([controller isKindOfClass:UITabBarController.class]){UIViewController *selected=((UITabBarController *)controller).selectedViewController;if(selected&&selected!=controller){controller=selected;continue;}}
        if([controller isKindOfClass:UISplitViewController.class]){UIViewController *visible=((UISplitViewController *)controller).viewControllers.lastObject;if(visible&&visible!=controller){controller=visible;continue;}}
        break;
    }
    if([controller isKindOfClass:UIAlertController.class]||controller.isBeingDismissed||controller.presentedViewController||!controller.isViewLoaded||!controller.view.window)return nil;
    return controller;
}
static void CompletionFeedback(NSString *message){
    AppCompletionState=message?:@"待办完成状态待处理";SaveEvidence();[RuntimePanel.tableView reloadData];
}
static void PresentUnlinkedCompletionInfo(NSString *sourceID,NSString *message){
    UIViewController *presenter=TopCompletionPresenter();CompletionFeedback(message);
    if(!presenter){[PendingPhysicalConfirmations removeObject:sourceID];return;}
    if(!UnlinkedCompletionRecoverySuppressed)UnlinkedCompletionRecoverySuppressed=[NSMutableSet set];
    [UnlinkedCompletionRecoverySuppressed addObject:sourceID];
    UIAlertController *info=[UIAlertController alertControllerWithTitle:@"待办尚未关联苹果提醒事项" message:message preferredStyle:UIAlertControllerStyleAlert];
    [info addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){[PendingPhysicalConfirmations removeObject:sourceID];CompletionFeedback(message);}]];
    [presenter presentViewController:info animated:YES completion:^{SaveEvidence();}];
}
static void CompleteUnlinkedReminderAfterConfirmation(NSString *sourceID,NSString *title,NSDictionary *candidate){
    NSString *identifier=Text(candidate[@"identifier"]);if(!identifier.length){[PendingPhysicalConfirmations removeObject:sourceID];[CompletionLedger() resetConfirmationPresentation:sourceID];PresentUnlinkedCompletionInfo(sourceID,@"苹果提醒事项编号无效，未修改苹果数据。");return;}
    LastAppleCompletion=@"linking_exact_title_reminder";LastAppleCompletionErrorCode=0;SaveEvidence();
    TIOAppleLinkReminder(sourceID,identifier,title,^(NSDictionary *link){
        NSString *linkStatus=Text(link[@"status"]);
        if(![linkStatus isEqual:@"linked"]&&![linkStatus isEqual:@"already_linked"]){[PendingPhysicalConfirmations removeObject:sourceID];[CompletionLedger() resetConfirmationPresentation:sourceID];LastAppleCompletion=linkStatus.length?linkStatus:@"unknown";LastAppleCompletionErrorCode=[link[@"errorCode"] integerValue];CompletionFeedback([NSString stringWithFormat:@"苹果提醒事项关联失败：%@。未更改完成状态。",AppleCompletionMessage(LastAppleCompletion)]);return;}
        TIOAppleCompleteLinkedReminder(sourceID,title,^(NSDictionary *result){
            NSString *status=Text(result[@"status"]);LastAppleCompletion=status.length?status:@"unknown";LastAppleCompletionErrorCode=[result[@"errorCode"] integerValue];
            [PendingPhysicalConfirmations removeObject:sourceID];
            if([status isEqual:@"completed"]||[status isEqual:@"already_completed"]){[CompletionLedger() clearPending:sourceID];[PendingCompletionTitles removeObjectForKey:sourceID];[UnlinkedCompletionRecoverySuppressed removeObject:sourceID];}
            else [CompletionLedger() resetConfirmationPresentation:sourceID];
            CompletionFeedback(AppleCompletionMessage(LastAppleCompletion));PresentPendingAppleCompletionIfPossible();
        });
    });
}
static void PresentUnlinkedCompletionConfirmation(NSString *sourceID,NSString *title,NSDictionary *candidate){
    UIViewController *presenter=TopCompletionPresenter();if(!presenter){[PendingPhysicalConfirmations removeObject:sourceID];CompletionFeedback(@"待办已完成；请回到 Turbo IO 前台后确认是否同步到苹果提醒事项");return;}
    NSString *list=Text(candidate[@"list"]);NSString *message=[NSString stringWithFormat:@"找到一条标题完全相同的苹果提醒事项%@。确认后会先关联，再将它标记为完成。",list.length?[NSString stringWithFormat:@"（%@）",list]:@""];
    UIAlertController *confirm=[UIAlertController alertControllerWithTitle:@"确认同步到苹果提醒事项" message:message preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"暂不同步" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action){[PendingPhysicalConfirmations removeObject:sourceID];if(!UnlinkedCompletionRecoverySuppressed)UnlinkedCompletionRecoverySuppressed=[NSMutableSet set];[UnlinkedCompletionRecoverySuppressed addObject:sourceID];CompletionFeedback(@"待办已完成；苹果提醒事项未改，可在待办同步页重新关联后再确认。");}]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"确认同步" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){CompleteUnlinkedReminderAfterConfirmation(sourceID,title,candidate);}]];
    [presenter presentViewController:confirm animated:YES completion:^{[CompletionLedger() markConfirmationPresented:sourceID];SaveEvidence();}];
}
static void PresentUnlinkedCompletionRecovery(NSString *sourceID,NSString *title){
    if(!sourceID.length||!title.length)return;
    if(!UnlinkedCompletionRecoverySuppressed)UnlinkedCompletionRecoverySuppressed=[NSMutableSet set];
    if([UnlinkedCompletionRecoverySuppressed containsObject:sourceID])return;
    if(!PendingPhysicalConfirmations)PendingPhysicalConfirmations=[NSMutableSet set];
    if([PendingPhysicalConfirmations containsObject:sourceID])return;
    if(!TopCompletionPresenter()){CompletionFeedback(@"待办已完成但尚未关联苹果提醒事项；回到 Turbo IO 前台后可继续匹配。");return;}
    [PendingPhysicalConfirmations addObject:sourceID];
    TIOAppleFindPendingReminders(title,^(NSDictionary *result){
        UIViewController *presenter=TopCompletionPresenter();if(!presenter){[PendingPhysicalConfirmations removeObject:sourceID];CompletionFeedback(@"待办已完成但尚未关联苹果提醒事项；回到 Turbo IO 前台后可继续匹配。");return;}
        if(![Text(result[@"status"]) isEqual:@"ok"]){NSString *status=Text(result[@"status"]);NSString *message=[status isEqual:@"permission_denied"]?@"Turbo IO 没有读取苹果提醒事项的权限，本次未修改苹果数据。请允许提醒事项访问后重试。":@"无法读取苹果提醒事项，本次未修改苹果数据；稍后可在待办同步页重试。";PresentUnlinkedCompletionInfo(sourceID,message);return;}
        NSArray *matches=[result[@"items"] isKindOfClass:NSArray.class]?result[@"items"]:@[];
        if(!matches.count){PresentUnlinkedCompletionInfo(sourceID,@"没有找到标题完全相同的未完成苹果提醒事项，本次未改动苹果数据。请在待办同步页关联正确事项后再确认。");return;}
        if(matches.count==1){NSDictionary *candidate=matches.firstObject;if(![candidate[@"writable"] boolValue]){PresentUnlinkedCompletionInfo(sourceID,@"对应的苹果提醒事项所在清单只读，未改动苹果数据。");return;}PresentUnlinkedCompletionConfirmation(sourceID,title,candidate);return;}
        UIAlertController *picker=[UIAlertController alertControllerWithTitle:@"选择对应的苹果提醒事项" message:@"发现多条同名未完成事项。先选清单，再确认完成同步。" preferredStyle:UIAlertControllerStyleActionSheet];
        for(NSDictionary *candidate in matches){NSString *label=[NSString stringWithFormat:@"%@ · %@%@",Text(candidate[@"title"]),Text(candidate[@"list"]),[candidate[@"writable"] boolValue]?@"":@"（只读）"];
            [picker addAction:[UIAlertAction actionWithTitle:label style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){[picker dismissViewControllerAnimated:YES completion:^{if([candidate[@"writable"] boolValue])PresentUnlinkedCompletionConfirmation(sourceID,title,candidate);else PresentUnlinkedCompletionInfo(sourceID,@"所选苹果提醒事项所在清单只读，未改动苹果数据。");}];}]];
        }
        [picker addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action){[PendingPhysicalConfirmations removeObject:sourceID];if(!UnlinkedCompletionRecoverySuppressed)UnlinkedCompletionRecoverySuppressed=[NSMutableSet set];[UnlinkedCompletionRecoverySuppressed addObject:sourceID];CompletionFeedback(@"待办已完成；尚未选择苹果提醒事项，苹果数据未改动。");}]];
        picker.popoverPresentationController.sourceView=presenter.view;picker.popoverPresentationController.sourceRect=CGRectMake(CGRectGetMidX(presenter.view.bounds),CGRectGetMidY(presenter.view.bounds),1,1);
        [presenter presentViewController:picker animated:YES completion:nil];
    });
}
static void RequestAppleCompletionConfirmation(NSString *sourceID,NSString *title){
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{RequestAppleCompletionConfirmation(sourceID,title);});return;}
    if(!sourceID.length)return;
    if(title.length){if(!PendingCompletionTitles)PendingCompletionTitles=[NSMutableDictionary dictionary];PendingCompletionTitles[sourceID]=title;}
    [CompletionLedger() markPending:sourceID];SaveEvidence();
    if(!TIOAppleHasLinkedReminder(sourceID)){PresentUnlinkedCompletionRecovery(sourceID,title);return;}
    [UnlinkedCompletionRecoverySuppressed removeObject:sourceID];
    if(![CompletionLedger() shouldPresentConfirmation:sourceID])return;
    if(!PendingPhysicalConfirmations)PendingPhysicalConfirmations=[NSMutableSet set];
    if([PendingPhysicalConfirmations containsObject:sourceID])return;
    UIViewController *presenter=TopCompletionPresenter();
    if(!presenter){
        AppCompletionState=[NSString stringWithFormat:@"待办“%@”已完成；打开 Turbo IO 后确认是否同步到苹果提醒事项",title.length?title:@"待办"];
        [RuntimePanel.tableView reloadData];return;
    }
    [PendingPhysicalConfirmations addObject:sourceID];
    NSString *displayTitle=title.length?title:@"这条待办";
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"确认同步到苹果提醒事项" message:[NSString stringWithFormat:@"待办“%@”已在 Turbo IO 完成。是否也将对应的苹果提醒事项标记为完成？",displayTitle] preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"暂不同步" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action){[PendingPhysicalConfirmations removeObject:sourceID];AppCompletionState=@"待办已完成；苹果提醒事项未改，可在待办同步页点选该项再次确认";[RuntimePanel.tableView reloadData];dispatch_async(dispatch_get_main_queue(),^{PresentPendingAppleCompletionIfPossible();});}]];
    [alert addAction:[UIAlertAction actionWithTitle:@"确认同步" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        [PendingPhysicalConfirmations removeObject:sourceID];
        LastAppleCompletion=@"completion_confirmed_writing";LastAppleCompletionErrorCode=0;SaveEvidence();
        TIOAppleCompleteLinkedReminder(sourceID,title,^(NSDictionary *result){
            NSString *status=Text(result[@"status"]);
            LastAppleCompletion=status.length?status:@"unknown";LastAppleCompletionErrorCode=[result[@"errorCode"] integerValue];
            if([status isEqual:@"completed"]||[status isEqual:@"already_completed"]){[CompletionLedger() clearPending:sourceID];[PendingCompletionTitles removeObjectForKey:sourceID];[UnlinkedCompletionRecoverySuppressed removeObject:sourceID];}
            AppCompletionState=AppleCompletionMessage(status);
            SaveEvidence();[RuntimePanel.tableView reloadData];PresentPendingAppleCompletionIfPossible();
        });
    }]];
    [presenter presentViewController:alert animated:YES completion:^{[CompletionLedger() markConfirmationPresented:sourceID];SaveEvidence();}];
}
static void PresentPendingAppleCompletionIfPossible(void){
    if(!Snapshot||!Device.length||!TopCompletionPresenter())return;
    NSString *devicePrefix=[Device stringByAppendingString:@":"];
    for(NSString *sourceID in [PendingCompletionTitles.allKeys copy]){
        if(![sourceID hasPrefix:devicePrefix]||![CompletionLedger() isPending:sourceID])continue;
        BOOL linked=TIOAppleHasLinkedReminder(sourceID);
        if(linked)[UnlinkedCompletionRecoverySuppressed removeObject:sourceID];
        if(linked||![UnlinkedCompletionRecoverySuppressed containsObject:sourceID]){RequestAppleCompletionConfirmation(sourceID,PendingCompletionTitles[sourceID]);return;}
    }
    for(NSDictionary *item in Snapshot[@"items"]){
        NSString *sourceID=QualifiedSource(Device,Text(item[@"wireId"]));
        if(sourceID&&[CompletionLedger() isPending:sourceID]){
            RequestAppleCompletionConfirmation(sourceID,Text(item[@"title"]));return;
        }
    }
}
void TIOTodoMarkCompleteFromApp(NSString *device,NSDictionary *item,void (^completion)(NSDictionary *)){
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{TIOTodoMarkCompleteFromApp(device,item,completion);});return;}
    if(!completion)return;
    __block BOOL callbackSent=NO;
    void (^completeOnce)(NSDictionary *)=^(NSDictionary *result){if(callbackSent)return;callbackSent=YES;completion(result?:@{@"status":@"unknown"});};
    NSString *wire=Text(item[@"wireId"]),*title=Text(item[@"title"]);
    if(Busy||PendingAppWire.length){completeOnce(@{@"status":@"busy"});return;}
    if(!Installed||!BridgeInstance||!PriorMethod||!Device.length||![Device isEqualToString:device]||!Snapshot){completeOnce(@{@"status":@"not_ready"});return;}
    NSDictionary *current=nil;for(NSDictionary *candidate in Snapshot[@"items"])if([candidate[@"wireId"] isEqual:wire]){current=candidate;break;}
    if(!current||![current[@"title"] isEqual:title]||![current[@"status"] isEqual:@0]){completeOnce(@{@"status":@"changed"});return;}
    NSString *sourceID=QualifiedSource(device,wire);if(!sourceID||!TIOAppleHasLinkedReminder(sourceID)){completeOnce(@{@"status":@"not_linked"});return;}
    NSData *payload=TIOTodoEncodeStatusUpdate(current,1,(NSInteger)NSDate.date.timeIntervalSince1970);
    NSData *typed=FlutterTypedData(payload);Class callClass=NSClassFromString(@"FlutterMethodCall");SEL factory=NSSelectorFromString(@"methodCallWithMethodName:arguments:");
    if(!typed||![callClass respondsToSelector:factory]){completeOnce(@{@"status":@"unsupported"});return;}
    NSDictionary *arguments=@{@"deviceId":device,@"businessId":@22,@"payload":typed};
    id call=((id(*)(id,SEL,id,id))objc_msgSend)(callClass,factory,@"rayneonet_sendMessage",arguments);
    if(!call){completeOnce(@{@"status":@"unsupported"});return;}
    PendingAppDevice=[device copy];PendingAppWire=[wire copy];PendingAppAt=NSDate.date.timeIntervalSince1970;
    AppCompletionState=[NSString stringWithFormat:@"已提交“%@”，等待眼镜回执",title];SaveEvidence();
    id plugin=BridgeInstance;
    PriorMethod(plugin,NSSelectorFromString(@"handleMethodCall:result:"),call,[^(id result){dispatch_async(dispatch_get_main_queue(),^{
        if([result isKindOfClass:NSClassFromString(@"FlutterError")]){PendingAppDevice=nil;PendingAppWire=nil;AppCompletionState=@"眼镜接口拒绝了完成更新";completeOnce(@{@"status":@"send_failed"});[RuntimePanel.tableView reloadData];return;}
        completeOnce(@{@"status":@"sent"});[RuntimePanel.tableView reloadData];
    });} copy]);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,20*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        if([PendingAppWire isEqualToString:wire]&&[PendingAppDevice isEqualToString:device]&&NSDate.date.timeIntervalSince1970-PendingAppAt>=20){PendingAppWire=nil;PendingAppDevice=nil;AppCompletionState=@"等待眼镜回执超时；App 已确认的苹果提醒事项状态已单独写入";completeOnce(@{@"status":@"timeout"});[RuntimePanel.tableView reloadData];}
    });
}
static void MethodHook(id self,SEL cmd,id call,id result){
#if TIO_OTA_RESEARCH_ENABLED
    if(TIOOTAFlashBlockCall(call)){if(result)((void(^)(id))result)(@{@"success":@NO,@"message":@"Turbo IO experimental transfer gate: not authorized or packet mismatch"});return;}
#endif
    NSString *methodName=Text(Get(call,@"method"));id args=Get(call,@"arguments");
    NSDictionary *completionCandidate=nil;NSString *completionDevice=[args isKindOfClass:NSDictionary.class]?Text(args[@"deviceId"]):@"";
    if([methodName isEqual:@"rayneonet_sendMessage"]&&[args isKindOfClass:NSDictionary.class]&&[args[@"businessId"] isEqual:@22]&&[completionDevice isEqual:Device])completionCandidate=TIOTodoOutgoingCompletionCandidate(Snapshot,Data(args[@"payload"]));
    if([args isKindOfClass:NSDictionary.class]){void(^work)(void)=^{TIOProtocolObserveCall(self,methodName,args);TIONewsTeleObserveCall(self,methodName,args);TIONavObserveCall(self,methodName,args);TIOSubtitleObserveCall(self,methodName,args);};if(NSThread.isMainThread)work();else dispatch_async(dispatch_get_main_queue(),work);}
    if([methodName isEqual:@"rayneonet_sendMessage"]&&[args isKindOfClass:NSDictionary.class]){void (^work)(void)=^{BridgeInstance=self;ObserveDeviceOrSuggestion(args,NO);if([args[@"businessId"] isEqual:@22]){ObserveOutgoingTask(args);ObserveSnapshot(args,NO);}};if(NSThread.isMainThread)work();else dispatch_async(dispatch_get_main_queue(),work);}
    if([Get(call,@"method") isEqual:@"rayneonet_sendFile"]&&[args isKindOfClass:NSDictionary.class]&&result){
        void(^original)(id)=result;
        PriorMethod(self,cmd,call,[^(id response){dispatch_async(dispatch_get_main_queue(),^{TIONewsTeleObserveFileResult(args,response);});original(response);} copy]);
    }else if(completionCandidate&&result){
        void(^original)(id)=result;NSString *wire=Text(completionCandidate[@"wireId"]),*title=Text(completionCandidate[@"title"]),*device=[completionDevice copy];
        PriorMethod(self,cmd,call,[^(id response){original(response);if([response isKindOfClass:NSClassFromString(@"FlutterError")])return;dispatch_async(dispatch_get_main_queue(),^{NSString *sourceID=QualifiedSource(device,wire);BOOL appInitiated=[device isEqual:PendingAppDevice]&&[wire isEqual:PendingAppWire];if(!sourceID||![device isEqual:Device]||appInitiated||AppRecentlyConfirmedSource(sourceID))return;AppCompletionTransitions++;[UnlinkedCompletionRecoverySuppressed removeObject:sourceID];SaveEvidence();RequestAppleCompletionConfirmation(sourceID,title);});} copy]);
    }else PriorMethod(self,cmd,call,result);
}
static void Send(id self,SEL cmd,NSString *channel,NSData *message,id reply){
    if([channel isKindOfClass:NSString.class]&&[channel.lowercaseString containsString:@"rayneonet"]&&message.length<262144){
        Class cls=NSClassFromString(@"FlutterStandardMethodCodec");
        @try{if([cls respondsToSelector:@selector(sharedInstance)]){id codec=((id(*)(id,SEL))objc_msgSend)(cls,@selector(sharedInstance));id event=((id(*)(id,SEL,id))objc_msgSend)(codec,NSSelectorFromString(@"decodeEnvelope:"),message);
#if TIO_NATIVE_NAV
            if(TIOImageUploadRouteFileEvent(event, ^BOOL(NSDictionary *e){return TDPPhoneConsumeEvent(e);}, ^(BOOL owned){
                if(owned){if(reply)((void(^)(NSData *))reply)(nil);}else PriorSend(self,cmd,channel,message,reply);
            }))return;
#endif
            if([event isKindOfClass:NSDictionary.class]&&[event[@"eventType"] isEqual:@"messageReceived"]&&[event[@"message"] isKindOfClass:NSDictionary.class]){
                NSMutableDictionary *e=[event mutableCopy],*m=[event[@"message"] mutableCopy];NSData *data=Data(m[@"payload"]);if(data)m[@"payload"]=data;e[@"message"]=m;NSDictionary *physical=TIOTodoPhysicalStatus(e);
#if TIO_OTA_RESEARCH_ENABLED
                TIOOTAFlashObserveEvent(e);
#if TIO_NATIVE_NAV
                if(TDPPhoneRouteReply(e,^(BOOL owned){if(owned){if(reply)((void(^)(NSData *))reply)(nil);}else PriorSend(self,cmd,channel,message,reply);}))return;
#endif
#endif
                dispatch_async(dispatch_get_main_queue(),^{TIOProtocolObserveEvent(e);TIONewsTeleObserveEvent(e);TIONavObserveEvent(e);TIOSubtitleObserveEvent(e);ObserveDeviceOrSuggestion(m,YES);if([m[@"businessId"] isEqual:@22])ObserveSnapshot(m,YES);});
                    if(physical)dispatch_async(dispatch_get_main_queue(),^{
                    PhysicalEvents++;
                    LastPhysicalStatus=[physical[@"status"] integerValue];LastPhysicalDeviceMatched=[physical[@"deviceId"] isEqual:Device];
                    LastPhysicalPresentInSnapshot=NO;
                    if(LastPhysicalDeviceMatched)for(NSDictionary *item in Snapshot[@"items"])if([item[@"wireId"] isEqual:physical[@"wireId"]]){LastPhysicalPresentInSnapshot=YES;break;}
                        SaveEvidence();
                        BOOL appInitiated=[physical[@"deviceId"] isEqual:PendingAppDevice]&&[physical[@"wireId"] isEqual:PendingAppWire];
                        if([physical[@"status"] isEqual:@1]){
                            if(appInitiated){AppCompletionState=@"眼镜已回执完成；苹果提醒事项已完成";PendingAppWire=nil;PendingAppDevice=nil;}
                            if([physical[@"deviceId"] isEqual:Device]&&Snapshot){NSMutableArray *items=[Snapshot[@"items"] mutableCopy];for(NSUInteger i=0;i<items.count;i++)if([items[i][@"wireId"] isEqual:physical[@"wireId"]]){NSMutableDictionary *row=[items[i] mutableCopy];row[@"status"]=@1;items[i]=row;Snapshot=[@{@"items":items,@"total":Snapshot[@"total"],@"isLastBatch":Snapshot[@"isLastBatch"]} copy];break;}}
                            [RuntimePanel.tableView reloadData];
                        }
                        if(TestWire.length&&[physical[@"wireId"] isEqual:TestWire]&&[physical[@"deviceId"] isEqual:TestDevice]){PhysicalComplete=[physical[@"status"] isEqual:@1];State=PhysicalComplete?@"收到此测试项的眼镜完成回传，真实ID匹配":@"收到此测试项的眼镜未完成回传";SaveEvidence();}
                        if([physical[@"status"] isEqual:@1]&&[physical[@"deviceId"] isEqual:Device]){
                            NSString *sourceID=QualifiedSource(physical[@"deviceId"],physical[@"wireId"]);
                            if(sourceID&&!appInitiated&&!AppRecentlyConfirmedSource(sourceID)){
                                NSString *title=nil;for(NSDictionary *item in Snapshot[@"items"])if([item[@"wireId"] isEqual:physical[@"wireId"]]){title=item[@"title"];break;}
                                [UnlinkedCompletionRecoverySuppressed removeObject:sourceID];
                                RequestAppleCompletionConfirmation(sourceID,title);
                            }
                    }else if([physical[@"deviceId"] isEqual:Device]){
                        NSString *sourceID=QualifiedSource(physical[@"deviceId"],physical[@"wireId"]);if(sourceID){[AppConfirmedSources removeObjectForKey:sourceID];[CompletionLedger() clearPending:sourceID];SaveEvidence();}
                    }
                });
            }
        }}@catch(NSException *e){}
    }PriorSend(self,cmd,channel,message,reply);
}
void TIOTodoObserveNlp(id listener,id response){
    if(Injecting||!Installed||![Get(response,@"finished") boolValue]||[Get(response,@"offline") boolValue])return;
    NSString *domain=Text(Get(response,@"domain")),*intentName=Text(Get(response,@"intent"));
    id command=Get(response,@"command");NSString *name=Text(Get(command,@"name"));
    NSCharacterSet *safe=[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"];
    if(domain.length<=64&&intentName.length<=64&&name.length<=64&&
       [domain rangeOfCharacterFromSet:safe.invertedSet].location==NSNotFound&&
       [intentName rangeOfCharacterFromSet:safe.invertedSet].location==NSNotFound&&
       [name rangeOfCharacterFromSet:safe.invertedSet].location==NSNotFound){
        LastNlpDomain=domain;LastNlpIntent=intentName;LastNlpCommand=name;SaveEvidence();
    }
    if(![domain isEqual:@"task"]||![intentName isEqual:@"create_task"])return;
    TaskEvents++;id params=Get(command,@"params");
    if(![Get(command,@"name") isEqual:@"create_task"]||!TIOTodoCreateIntent(@"task",@"create_task",params)){State=@"已收到官方新增回调，但参数形状不匹配；禁止构造调用";SaveEvidence();return;}
    Template=response;Listener=listener;TemplateAt=[NSDate.date timeIntervalSince1970];State=@"已取得真实官方新增模板；可执行一次命名测试";
    NSDictionary *intent=TIOTodoCreateIntent(@"task",@"create_task",params);
    EnsurePendingOfficialCreates();NSTimeInterval at=NSDate.date.timeIntervalSince1970;NSDictionary *pending=@{@"token":NSUUID.UUID.UUIDString,@"title":intent[@"title"],@"device":Device?:@"",@"baseline":Snapshot?:@{},@"at":@(at)};
    [PendingOfficialCreates addObject:pending];PersistPendingOfficialCreates();OfficialCreateMatchStatus=Snapshot&&Device.length?@"waiting_for_complete_snapshot":@"missing_precreate_snapshot";PersistOfficialMatchState();
    RecentOfficialTitle=intent[@"title"];RecentOfficialDevice=Device;RecentOfficialAt=at;RecentOutgoingWire=nil;RecentCandidateWire=nil;OutgoingTitleMatches=0;OutgoingMatchedSnapshotCandidate=NO;
    SaveEvidence();
}
NSDictionary *TIOTodoRuntimeStatus(void){EnsurePendingOfficialCreates();return @{@"installed":@(Installed),@"snapshots":@(Snapshots),@"taskEvents":@(TaskEvents),@"physicalEvents":@(PhysicalEvents),@"hasBaseline":@(Snapshot!=nil),@"hasTemplate":@(Template!=nil&&Listener!=nil),@"busy":@(Busy),@"state":State?:@"",@"testTitle":TestTitle?:@"",@"hasWireId":@(TestWire.length>0),@"physicalComplete":@(PhysicalComplete),@"completionReadyRows":@(CompletionReadyRows),@"pendingOfficialCreates":@(PendingOfficialCreates.count),@"pendingAppleCompletionCount":@(CompletionLedger().pendingCount),@"officialCreateMatchStatus":OfficialCreateMatchStatus?:@"",@"appleTodoCreateAttempts":@(AppleTodoCreateAttempts),@"appleTodoCreateSuccesses":@(AppleTodoCreateSuccesses),@"appleTodoCreateFailures":@(AppleTodoCreateFailures),@"lastAppleTodoCreateStatus":LastAppleTodoCreateStatus?:@""};}
void TIOTodoCreateFromTool(NSString *title,void (^completion)(NSDictionary *result)){
    if(!NSThread.isMainThread||!completion)return;
    NSDictionary *valid=TIOTodoCreateIntent(@"task",@"create_task",@{@"task":@{@"content":title?:@""}});
    if(!valid||Busy||[NSUserDefaults.standardUserDefaults boolForKey:UnresolvedKey]||(TestTitle.length&&!TestWire.length)){completion(@{@"status":@"rejected"});return;}
    NSTimeInterval now=[NSDate.date timeIntervalSince1970];
    if(!Installed||!Snapshot||now-SnapshotAt>120||!ChatContext||!ChatListener||now-ChatAt>120){completion(@{@"status":@"not_ready"});return;}
    title=valid[@"title"];for(NSDictionary *item in Snapshot[@"items"])if([item[@"title"] isEqual:title]){completion(@{@"status":@"rejected"});return;}
    Class rc=NSClassFromString(@"RayNeoNlpResultWrapper"),cc=NSClassFromString(@"NlpCommandWrapper");
    if(![ChatContext isKindOfClass:rc]||!cc){completion(@{@"status":@"not_ready"});return;}
    id response=[rc new],command=[cc new];
    @try{
        // Current live chat supplies correlation fields. Routing constants and
        // JSON-text params.task are from official 1.0.2 observations (v4 probe,
        // plus live successful create-intent parsing). The outer installation
        // is version/UUID guarded. No old task dates or old session IDs reused.
        for(NSString *key in @[@"sub",@"dialogId",@"sessionId",@"domain",@"intent",@"round",@"query",@"spoken",@"answer",@"finished",@"offline",@"hasNextRound",@"rawData"]){id value=Get(ChatContext,key);if(value)[response setValue:value forKey:key];}
        [response setValue:@"task" forKey:@"domain"];[response setValue:@"create_task" forKey:@"intent"];[response setValue:@"workflow" forKey:@"sub"];[response setValue:@YES forKey:@"hasNextRound"];
        NSDictionary *task=@{@"content":title};NSString *inner=[[NSString alloc]initWithData:[NSJSONSerialization dataWithJSONObject:task options:0 error:nil] encoding:NSUTF8StringEncoding];
        [command setValue:@"create_task" forKey:@"name"];[command setValue:@{@"task":inner} forKey:@"params"];[command setValue:NSUUID.UUID.UUIDString forKey:@"commandRequestId"];[command setValue:@{} forKey:@"otherState"];
        [response setValue:command forKey:@"command"];[response setValue:@YES forKey:@"finished"];[response setValue:@NO forKey:@"offline"];[response setValue:@"" forKey:@"answer"];[response setValue:@"" forKey:@"spoken"];[response setValue:@"" forKey:@"rawData"];
    }@catch(NSException *e){completion(@{@"status":@"not_ready"});return;}
    // Crash/restart cannot silently retry an uncertain native submission.
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:UnresolvedKey];if(![NSUserDefaults.standardUserDefaults synchronize]){completion(@{@"status":@"rejected"});return;}
    Baseline=Snapshot;TestDevice=Device;TestTitle=[title copy];TestWire=nil;PhysicalComplete=NO;ToolOperation=YES;ToolCompletion=[completion copy];Busy=YES;
    State=@"create_todo已调用官方入口；等待真实列表，不宣称创建成功";SaveEvidence();
    ToolDispatching=YES;Injecting=YES;
    @try{((void(*)(id,SEL,id))objc_msgSend)(ChatListener,NSSelectorFromString(@"onNlpResult:"),response);}
    @catch(NSException *e){Busy=NO;State=@"create_todo调用异常，结果未知；禁止重试";CompleteTool(@"unknown");SaveEvidence();}
    @finally{ToolDispatching=NO;Injecting=NO;}
    NSString *operationTitle=TestTitle;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,25*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(Busy&&ToolOperation&&TestTitle==operationTitle){Busy=NO;State=@"create_todo未确认唯一新ID，结果未知；禁止重试";CompleteTool(@"unknown");SaveEvidence();}});
}
NSString *TIOTodoCreateTestTask(void){
    if(!NSThread.isMainThread||!Installed)return @"待办观察入口未就绪。";
    if(Busy||TestTitle.length)return @"本进程已提交过一次测试；不会自动重试或重复创建。";
    NSTimeInterval now=[NSDate.date timeIntervalSince1970];
    if(!Snapshot||now-SnapshotAt>120||!Template||!Listener||now-TemplateAt>120)return @"请先用眼镜语音新增一条专用测试待办，再在两分钟内回此页测试。";
    NSString *title=[@"Turbo桥接入口测试 " stringByAppendingString:[NSUUID.UUID.UUIDString substringToIndex:6]];
    id sourceCommand=Get(Template,@"command");NSDictionary *sourceParams=Get(sourceCommand,@"params"),*task=Task(sourceParams);
    if(!task||!TIOTodoCreateIntent(@"task",@"create_task",sourceParams))return @"参数形状不匹配，未调用。";
    Class responseClass=NSClassFromString(@"RayNeoNlpResultWrapper"),commandClass=NSClassFromString(@"NlpCommandWrapper");if(![Template isKindOfClass:responseClass]||![sourceCommand isKindOfClass:commandClass])return @"官方包装类型不匹配。";
    id response=[responseClass new],command=[commandClass new];if(!response||!command)return @"无法构造官方包装，未调用。";
    @try{
        for(NSString *field in @[@"sub",@"dialogId",@"sessionId",@"domain",@"intent",@"round",@"query",@"spoken",@"answer",@"finished",@"offline",@"hasNextRound",@"rawData"]){id value=Get(Template,field);if(value)[response setValue:value forKey:field];}
        NSMutableDictionary *inner=[task mutableCopy];inner[@"content"]=title;NSMutableDictionary *params=[sourceParams mutableCopy];
        params[@"task"]=[sourceParams[@"task"] isKindOfClass:NSString.class]?[[NSString alloc]initWithData:[NSJSONSerialization dataWithJSONObject:inner options:0 error:nil] encoding:NSUTF8StringEncoding]:inner;
        [command setValue:@"create_task" forKey:@"name"];[command setValue:params forKey:@"params"];[command setValue:NSUUID.UUID.UUIDString forKey:@"commandRequestId"];[command setValue:Get(sourceCommand,@"otherState")?:@{} forKey:@"otherState"];
        [response setValue:command forKey:@"command"];[response setValue:[@"创建待办 " stringByAppendingString:title] forKey:@"query"];[response setValue:@"" forKey:@"answer"];[response setValue:@"" forKey:@"spoken"];
    }@catch(NSException *e){return @"包装属性不匹配，未调用。";}
    Baseline=Snapshot;TestDevice=Device;TestTitle=title;Busy=YES;State=@"仅提交一次官方创建回调；等待官方真实列表和ID，未声明成功";SaveEvidence();
    // The currently installed listener goes through the existing Addon hook;
    // task domain remains official. No standalone SDK or Bluetooth list rewrite.
    Injecting=YES;
    @try{((void(*)(id,SEL,id))objc_msgSend)(Listener,NSSelectorFromString(@"onNlpResult:"),response);}
    @catch(NSException *e){Busy=NO;State=@"官方回调调用异常；结果未知，禁止重试";SaveEvidence();}
    @finally{Injecting=NO;}
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,25*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(Busy){Busy=NO;State=@"25秒内未观察到唯一新项；结果未知，不自动重发";SaveEvidence();}});
    return [@"已提交：" stringByAppendingString:title];
}
void TIOInstallTodoRuntime(void){
    if(Installed)return;Method method=class_getInstanceMethod(NSClassFromString(@"rayneo_venus_sdk_plugin.RayneoNetPluginBridge"),NSSelectorFromString(@"handleMethodCall:result:"));Method send=class_getInstanceMethod(NSClassFromString(@"FlutterEngine"),NSSelectorFromString(@"sendOnChannel:message:binaryReply:"));
    if(!Sign(method,4)||!Sign(send,5)){State=@"观察方法签名不匹配，未安装";return;}
    NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;if(![defaults objectForKey:TodoSyncBootstrapAtKey]){[defaults setObject:@([NSDate.date timeIntervalSince1970]) forKey:TodoSyncBootstrapAtKey];[defaults synchronize];}
    PriorMethod=(void *)method_setImplementation(method,(IMP)MethodHook);PriorSend=(void *)method_setImplementation(send,(IMP)Send);Installed=YES;
    if(!CompletionForegroundObserver)CompletionForegroundObserver=[NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification){dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.35*NSEC_PER_SEC)),dispatch_get_main_queue(),^{PresentPendingAppleCompletionIfPossible();});}];
#if TIO_OTA_RESEARCH_ENABLED
    TIOOTARecordTransportHookReady();
#endif
}
@interface TIOTodoRuntimePanel:UITableViewController @end
static NSString *FriendlySyncStatus(NSString *status,BOOL matching){
    NSDictionary *labels=matching?@{@"not_attempted":@"等待眼镜新增待办",@"waiting_for_complete_snapshot":@"等待完整官方列表",@"missing_precreate_snapshot":@"缺少创建前列表基线，无法安全配对",@"no_matching_new_row":@"官方列表尚未出现对应的新编号",@"ambiguous_same_title_candidates":@"同名新增有歧义，暂未自动配对",@"too_many_simultaneous_same_title_creates":@"同名请求过多，暂未自动配对",@"matched_unique_official_ids":@"已按官方编号匹配",@"window_expired":@"匹配窗口已过期"}:@{@"not_attempted":@"尚未写入",@"writing":@"正在写入",@"created":@"已写入苹果提醒事项",@"already_linked":@"已有关联",@"permission_denied":@"提醒事项权限未开启",@"failed":@"苹果提醒事项保存失败",@"created_unlinked":@"已创建，但未取得苹果条目编号",@"invalid":@"待办信息不完整",@"unknown":@"未确认"};return labels[status]?:status?:@"未知";
}
@implementation TIOTodoRuntimePanel
- (void)viewDidLoad{[super viewDidLoad];EnsurePendingOfficialCreates();CompletionLedger();self.title=@"待办同步";RuntimePanel=self;self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"重试同步" style:UIBarButtonItemStylePlain target:self action:@selector(refresh)];}
- (void)viewDidAppear:(BOOL)animated{[super viewDidAppear:animated];dispatch_async(dispatch_get_main_queue(),^{PresentPendingAppleCompletionIfPossible();});}
- (void)refresh{EnsurePendingOfficialCreates();if(Snapshot&&Device.length)ReconcileOfficialCreates(Snapshot,Device,YES);[self.tableView reloadData];}
- (NSArray<NSDictionary *> *)todoRows{NSArray *items=Snapshot[@"items"];return [items isKindOfClass:NSArray.class]?items:@[];}
- (NSArray<NSDictionary *> *)scheduleRows{return TIOAppleScheduleRows();}
- (NSUInteger)pendingCompletionCount {NSUInteger count=0;for(NSDictionary *item in self.todoRows){NSString *sourceID=QualifiedSource(Device,Text(item[@"wireId"]));if(sourceID&&[CompletionLedger() isPending:sourceID])count++;}return count;}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return 1+self.todoRows.count+self.scheduleRows.count;}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s{NSUInteger pending=[self pendingCompletionCount];NSString *message=AppCompletionState.length?AppCompletionState:(pending?@"有已完成待办待确认；可在弹窗中同步，或点选对应事项再次确认。":@"从 Turbo IO 当前完整待办列表和本 App 创建的日程读取事项。");return [NSString stringWithFormat:@"%@\n自动匹配：%@ · 待处理 %@ 条 · 待确认完成 %@ 条\n苹果写入：%@（成功 %@ / 失败 %@）\n眼镜待办：完成状态变化后提示二次确认；确认后同步到苹果提醒事项。App 内确认完成时也同步苹果，并向眼镜提交同编号完成状态。\n本 App 创建的日程：确认后完成配对的苹果提醒事项，日历事件保留。",message,FriendlySyncStatus(OfficialCreateMatchStatus,YES),@(PendingOfficialCreates.count),@(pending),FriendlySyncStatus(LastAppleTodoCreateStatus,NO),@(AppleTodoCreateSuccesses),@(AppleTodoCreateFailures)];}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip{
    UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];c.detailTextLabel.numberOfLines=0;
    if(!ip.row){c.textLabel.text=State;c.detailTextLabel.text=[NSString stringWithFormat:@"当前待办 %@ 条 · 已关联 %@ 条 · 待配对 %@ 条\n完整列表 %@ 次（眼镜回传 %@ / App 下发 %@）\n最近写入：%@",@(self.todoRows.count),@(LinkedRowsInSnapshot),@(PendingOfficialCreates.count),@(Snapshots),@(InboundSnapshots),@(OutboundSnapshots),FriendlySyncStatus(LastAppleTodoCreateStatus,NO)];return c;}
    if(ip.row<=self.todoRows.count){NSDictionary *item=self.todoRows[(NSUInteger)ip.row-1];NSString *sourceID=QualifiedSource(Device,item[@"wireId"]);BOOL linked=sourceID&&TIOAppleHasLinkedReminder(sourceID),pending=sourceID&&[CompletionLedger() isPending:sourceID],done=[item[@"status"] isEqual:@1]||pending;
        NSString *appleState=linked?@"已关联":@"待关联";if(pending)appleState=linked?@"已完成，待确认苹果完成":@"已完成，待关联并确认";
        c.textLabel.text=[NSString stringWithFormat:@"%@ %@",done?@"✓":@"○",item[@"title"]];c.detailTextLabel.text=[NSString stringWithFormat:@"苹果提醒事项：%@ · 眼镜编号 %@",appleState,item[@"wireId"]];c.accessoryType=done?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryDisclosureIndicator;return c;}
    NSDictionary *schedule=self.scheduleRows[(NSUInteger)ip.row-1-self.todoRows.count];BOOL done=[schedule[@"completed"] boolValue];c.textLabel.text=[NSString stringWithFormat:@"%@ 日程 · %@",done?@"✓":@"○",schedule[@"title"]];c.detailTextLabel.text=[NSString stringWithFormat:@"%@ – %@ · 完成提醒后保留日历事件",schedule[@"start"],schedule[@"end"]];c.accessoryType=done?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryDisclosureIndicator;return c;
}
- (void)runConfirmedItem:(NSDictionary *)item sourceID:(NSString *)sourceID sendToGlasses:(BOOL)sendToGlasses{
    if(!AppConfirmedSources)AppConfirmedSources=[NSMutableDictionary dictionary];
    AppConfirmedSources[sourceID]=@([NSDate.date timeIntervalSince1970]);
    LastAppleCompletion=@"app_confirmed_writing";LastAppleCompletionErrorCode=0;SaveEvidence();
    TIOAppleCompleteLinkedReminder(sourceID,Text(item[@"title"]),^(NSDictionary *result){
        NSString *appleStatus=Text(result[@"status"]);if(!appleStatus.length)appleStatus=@"unknown";
        LastAppleCompletion=appleStatus;LastAppleCompletionErrorCode=[result[@"errorCode"] integerValue];
        BOOL appleDone=[appleStatus isEqual:@"completed"]||[appleStatus isEqual:@"already_completed"];
        if(appleDone){[CompletionLedger() clearPending:sourceID];AppCompletionState=AppleCompletionMessage(appleStatus);SaveEvidence();[self.tableView reloadData];
            if(sendToGlasses)TIOTodoMarkCompleteFromApp(Device,item,^(NSDictionary *glassResult){NSString *glassStatus=Text(glassResult[@"status"]);if([glassStatus isEqual:@"sent"])AppCompletionState=@"苹果提醒事项已完成；已提交眼镜，等待回执";else if([glassStatus isEqual:@"timeout"])AppCompletionState=@"苹果提醒事项已完成；眼镜回执超时";else AppCompletionState=[NSString stringWithFormat:@"苹果提醒事项已完成；眼镜同步失败（%@）",glassStatus.length?glassStatus:@"unknown"];[self.tableView reloadData];});
            return;
        }
        if(sendToGlasses)AppCompletionState=[NSString stringWithFormat:@"%@；未向眼镜提交完成状态",AppleCompletionMessage(appleStatus)];
        else AppCompletionState=AppleCompletionMessage(appleStatus);
        [self.tableView reloadData];SaveEvidence();
    });
}
- (void)confirmItem:(NSDictionary *)item sourceID:(NSString *)sourceID appleReminderID:(NSString *)reminderID onlyLink:(BOOL)onlyLink{
    NSString *title=item[@"title"];BOOL alreadyPending=[CompletionLedger() isPending:sourceID],sendToGlasses=!onlyLink&&!alreadyPending&&[item[@"status"] isEqual:@0];
    NSString *message=onlyLink?[NSString stringWithFormat:@"将标题完全相同的苹果提醒事项关联到眼镜待办“%@”。不会更改完成状态。",title]:(alreadyPending?[NSString stringWithFormat:@"“%@”已在 Turbo IO 完成。确认后将对应苹果提醒事项标记为完成。",title]:([item[@"status"] isEqual:@1]?[NSString stringWithFormat:@"把已经在 Turbo IO 完成的“%@”同步到对应苹果提醒事项？",title]:[NSString stringWithFormat:@"在 Turbo IO 中完成“%@”，同步苹果提醒事项，并把同一编号的完成状态提交到眼镜？",title]));
    UIAlertController *a=[UIAlertController alertControllerWithTitle:onlyLink?@"关联苹果提醒事项":@"确认完成待办" message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:onlyLink?@"确认关联":@"确认完成" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){
        void (^apply)(void)=^{if(onlyLink){AppCompletionState=[NSString stringWithFormat:@"已关联苹果提醒事项“%@”；未修改状态",title];[self.tableView reloadData];if([CompletionLedger() isPending:sourceID])PresentPendingAppleCompletionIfPossible();return;}[self runConfirmedItem:item sourceID:sourceID sendToGlasses:sendToGlasses];};
        if(!reminderID.length){apply();return;}
        TIOAppleLinkReminder(sourceID,reminderID,title,^(NSDictionary *link){if([link[@"status"] isEqual:@"linked"])apply();else{AppCompletionState=[NSString stringWithFormat:@"苹果提醒事项绑定失败：%@",link[@"status"]?:@"unknown"];[self.tableView reloadData];}});
    }]];[self presentViewController:a animated:YES completion:nil];
}
- (void)chooseAppleReminderForItem:(NSDictionary *)item{
    NSString *sourceID=QualifiedSource(Device,item[@"wireId"]),*title=item[@"title"];
    if(!sourceID){AppCompletionState=@"眼镜事项编号不完整，未修改";[self.tableView reloadData];return;}
    BOOL alreadyPending=[CompletionLedger() isPending:sourceID],sendToGlasses=!alreadyPending&&[item[@"status"] isEqual:@0];if(sendToGlasses&&!TIOTodoEncodeStatusUpdate(item,1,(NSInteger)NSDate.date.timeIntervalSince1970)){AppCompletionState=@"待办缺少原始创建时间或重要度字段，无法安全提交完成状态";[self.tableView reloadData];return;}
    if(TIOAppleHasLinkedReminder(sourceID)){[self confirmItem:item sourceID:sourceID appleReminderID:nil onlyLink:NO];return;}
    TIOAppleFindPendingReminders(title,^(NSDictionary *result){
        NSArray *matches=result[@"items"];
        if(![result[@"status"] isEqual:@"ok"]){AppCompletionState=[NSString stringWithFormat:@"无法读取苹果提醒事项：%@",result[@"status"]?:@"unknown"];[self.tableView reloadData];return;}
        void (^createNew)(void)=^{UIAlertController *confirm=[UIAlertController alertControllerWithTitle:@"新建并关联苹果提醒事项" message:[NSString stringWithFormat:@"将为“%@”新建一条无日期提醒事项，并绑定到这条眼镜待办。",title] preferredStyle:UIAlertControllerStyleAlert];[confirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[confirm addAction:[UIAlertAction actionWithTitle:@"新建并关联" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){NSDictionary *entry=@{@"token":NSUUID.UUID.UUIDString,@"title":title,@"device":Device?:@"",@"baseline":Snapshot?:@{},@"at":@([NSDate.date timeIntervalSince1970]),@"candidateWireId":item[@"wireId"]?:@""};AttemptOfficialAppleCreate(entry,item);[self.tableView reloadData];}]];[self presentViewController:confirm animated:YES completion:nil];};
        if(!matches.count){AppCompletionState=@"没有找到同名未完成苹果提醒事项";[self.tableView reloadData];createNew();return;}
        UIAlertController *picker=[UIAlertController alertControllerWithTitle:@"选择苹果提醒事项" message:[NSString stringWithFormat:@"为眼镜待办“%@”选择准确对应项；若不在苹果端，可以新建并关联。",title] preferredStyle:UIAlertControllerStyleActionSheet];
        [picker addAction:[UIAlertAction actionWithTitle:@"新建一条并关联" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){createNew();}]];
        for(NSDictionary *candidate in matches){NSString *label=[NSString stringWithFormat:@"%@ · %@",candidate[@"title"],candidate[@"list"]];[picker addAction:[UIAlertAction actionWithTitle:label style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){if(![candidate[@"writable"] boolValue]){AppCompletionState=@"所选苹果提醒事项所在列表只读，未修改";[self.tableView reloadData];return;}UIAlertController *choice=[UIAlertController alertControllerWithTitle:@"如何处理这两条事项？" message:alreadyPending?@"这条 Turbo IO 待办已完成。选择是否将对应苹果提醒事项也标记为完成。":@"可先只关联，然后在眼镜上完成；也可以现在就完成并同步。" preferredStyle:UIAlertControllerStyleAlert];[choice addAction:[UIAlertAction actionWithTitle:@"只关联" style:UIAlertActionStyleDefault handler:^(UIAlertAction *y){[self confirmItem:item sourceID:sourceID appleReminderID:candidate[@"identifier"] onlyLink:YES];}]];[choice addAction:[UIAlertAction actionWithTitle:alreadyPending?@"关联并同步完成":@"关联并完成" style:UIAlertActionStyleDefault handler:^(UIAlertAction *y){[self confirmItem:item sourceID:sourceID appleReminderID:candidate[@"identifier"] onlyLink:NO];}]];[choice addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:choice animated:YES completion:nil];}]];}
        [picker addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];picker.popoverPresentationController.sourceView=self.tableView;picker.popoverPresentationController.sourceRect=[self.tableView rectForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];[self presentViewController:picker animated:YES completion:nil];
    });
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip{
    [t deselectRowAtIndexPath:ip animated:YES];if(!ip.row){[self refresh];return;}
    if(ip.row<=self.todoRows.count){NSDictionary *item=self.todoRows[(NSUInteger)ip.row-1];[self chooseAppleReminderForItem:item];return;}
    NSDictionary *schedule=self.scheduleRows[(NSUInteger)ip.row-1-self.todoRows.count];if([schedule[@"completed"] boolValue])return;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"完成日程" message:[NSString stringWithFormat:@"完成“%@”对应的苹果提醒事项？苹果日历中的日程会保留。",schedule[@"title"]] preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"确认完成" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){TIOAppleCompleteScheduleReminder(schedule[@"scheduleID"],^(NSDictionary *result){AppCompletionState=[result[@"status"] isEqual:@"completed"]?@"日程提醒事项已完成；苹果日历事件保留":[NSString stringWithFormat:@"日程未完成：%@",result[@"status"]?:@"unknown"];[self.tableView reloadData];});}]];
    [self presentViewController:a animated:YES completion:nil];
}
@end
void TIOOpenTodoRuntime(id parent){if([parent isKindOfClass:UIViewController.class])[[(UIViewController *)parent navigationController] pushViewController:[[TIOTodoRuntimePanel alloc]initWithStyle:UITableViewStyleInsetGrouped] animated:YES];}
