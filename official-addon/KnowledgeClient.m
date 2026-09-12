#import "KnowledgeClient.h"
#import <Security/Security.h>
static NSUserDefaults *Settings(void){return [[NSUserDefaults alloc]initWithSuiteName:@"io.turboio.official-knowledge"];}
static NSDictionary *KeyQuery(void){return @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,(__bridge id)kSecAttrService:@"io.turboio.official-knowledge",(__bridge id)kSecAttrAccount:@"bridge-token"};}
static NSString *Token(void){NSMutableDictionary *q=[KeyQuery() mutableCopy];q[(__bridge id)kSecReturnData]=@YES;CFTypeRef out=NULL;if(SecItemCopyMatching((__bridge CFDictionaryRef)q,&out)!=errSecSuccess)return @"";return [[NSString alloc]initWithData:CFBridgingRelease(out) encoding:NSUTF8StringEncoding]?:@"";}
NSString *TIOKnowledgeEndpoint(void){return [Settings() stringForKey:@"endpoint"]?:@"";}
NSString *TIOSelectedAgent(void){return [Settings() stringForKey:@"agent"]?:@"Codex";}
BOOL TIOKnowledgeEnabled(void){return [Settings() boolForKey:@"enabled"]&&[TIOSelectedAgent() isEqual:@"Codex"]&&TIOKnowledgeEndpoint().length&&Token().length;}
void TIOSetKnowledgeEnabled(BOOL on){[Settings() setBool:on forKey:@"enabled"];}
BOOL TIOConfigureKnowledge(NSString *endpoint,NSString *token){
    NSURLComponents *u=[NSURLComponents componentsWithString:endpoint];
    if(![u.scheme isEqual:@"https"]||!u.host.length||u.user||u.password||u.query||u.fragment||![u.path isEqual:@"/api/turbo-knowledge"])return NO;
    if(token.length){NSCharacterSet *allowed=[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"];if(token.length<32||token.length>128||[token rangeOfCharacterFromSet:allowed.invertedSet].location!=NSNotFound)return NO;
        NSDictionary *attrs=@{(__bridge id)kSecValueData:[token dataUsingEncoding:NSUTF8StringEncoding],(__bridge id)kSecAttrAccessible:(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly};OSStatus s=SecItemUpdate((__bridge CFDictionaryRef)KeyQuery(),(__bridge CFDictionaryRef)attrs);if(s==errSecItemNotFound){NSMutableDictionary *all=[KeyQuery() mutableCopy];[all addEntriesFromDictionary:attrs];s=SecItemAdd((__bridge CFDictionaryRef)all,NULL);}if(s!=errSecSuccess)return NO;
    }else if(!Token().length||![TIOKnowledgeEndpoint() isEqual:u.URL.absoluteString])return NO;
    [Settings() setObject:u.URL.absoluteString forKey:@"endpoint"];return YES;
}
NSDictionary *TIOKnowledgeSnapshot(void){NSData *data=[Settings() dataForKey:@"snapshotJSON"];return data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]?:@{}:@{};}
void TIOImportKnowledgeConnection(void){
    NSString *path=[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/TurboIOKnowledgeConnection.json"];
    NSDictionary *attr=[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];if(![attr[NSFileType] isEqual:NSFileTypeRegular]||[attr[NSFileSize] unsignedIntegerValue]>8192)return;
    NSDictionary *j=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:path] options:0 error:nil];if(![j isKindOfClass:NSDictionary.class]||![j[@"endpoint"] isKindOfClass:NSString.class]||![j[@"token"] isKindOfClass:NSString.class])return;
    if(TIOConfigureKnowledge(j[@"endpoint"],j[@"token"])){TIOSetKnowledgeEnabled(YES);[NSFileManager.defaultManager removeItemAtPath:path error:nil];}
}
@interface TIOKnowledgeClient()
@property(nonatomic) NSURLSession *session;
@property(nonatomic) NSDate *started;
@end
@implementation TIOKnowledgeClient
- (void)cancel{self.cancelled=YES;[self.session invalidateAndCancel];self.session=nil;}
- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)t willPerformHTTPRedirection:(NSHTTPURLResponse *)r newRequest:(NSURLRequest *)q completionHandler:(void(^)(NSURLRequest *))done{done(nil);}
- (void)request:(NSString *)path body:(NSDictionary *)body completion:(void(^)(NSDictionary *,NSString *))completion{
    if(self.cancelled)return;TIOImportKnowledgeConnection();
    NSString *endpoint=TIOKnowledgeEndpoint(),*token=Token();if(!endpoint.length||!token.length){completion(nil,@"请先配置知识库连接。");return;}
    if(!self.session){NSURLSessionConfiguration *c=NSURLSessionConfiguration.ephemeralSessionConfiguration;c.HTTPCookieStorage=nil;c.URLCache=nil;c.URLCredentialStorage=nil;self.session=[NSURLSession sessionWithConfiguration:c delegate:self delegateQueue:NSOperationQueue.mainQueue];}
    NSMutableURLRequest *r=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:[endpoint stringByAppendingString:path]]];r.timeoutInterval=25;[r setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];[r setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    if(body){r.HTTPMethod=@"POST";r.HTTPBody=[NSJSONSerialization dataWithJSONObject:body options:0 error:nil];[r setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];}
    [[self.session dataTaskWithRequest:r completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){dispatch_async(dispatch_get_main_queue(),^{if(self.cancelled)return;NSInteger code=[response isKindOfClass:NSHTTPURLResponse.class]?[(NSHTTPURLResponse *)response statusCode]:0;NSDictionary *j=data.length<=256*1024?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
        if(error||![j isKindOfClass:NSDictionary.class]||(code!=200&&code!=202)){completion(nil,[NSString stringWithFormat:@"知识库连接失败（HTTP %ld）。请检查 Mac 服务、网络与令牌。",(long)code]);return;}completion(j,nil);
    });}] resume];
}
- (void)sources:(void(^)(NSDictionary *,NSString *))done{[self request:@"/sources" body:nil completion:done];}
- (void)poll:(NSString *)ident completion:(void(^)(NSDictionary *,NSString *))done{
    NSUUID *uuid=[[NSUUID alloc]initWithUUIDString:ident];if(!uuid){done(nil,@"查询编号无效。");return;}
    [self request:[@"/jobs/" stringByAppendingString:ident.lowercaseString] body:nil completion:^(NSDictionary *j,NSString *e){if(e){done(nil,e);return;}[Settings() setObject:[NSJSONSerialization dataWithJSONObject:j options:0 error:nil] forKey:@"snapshotJSON"];
        NSString *state=j[@"status"];if([@[@"completed",@"failed",@"interrupted"] containsObject:state]||!self.started||-[self.started timeIntervalSinceNow]>80){done(j,nil);return;}
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(!self.cancelled)[self poll:ident completion:done];});
    }];
}
- (void)query:(NSDictionary *)input completion:(void(^)(NSDictionary *,NSString *))done{
    if(!TIOKnowledgeEnabled()){done(nil,@"请开启知识库工具并选择已接入的 Codex。");return;}
    NSMutableDictionary *body=[input mutableCopy];body[@"requestId"]=NSUUID.UUID.UUIDString.lowercaseString;self.started=NSDate.date;
    [self request:@"/query" body:body completion:^(NSDictionary *j,NSString *e){if(e){done(nil,e);return;}NSString *ident=j[@"id"];if(![ident isKindOfClass:NSString.class]){done(nil,@"服务未返回查询编号。");return;}[Settings() setObject:ident forKey:@"lastJob"];[Settings() setObject:[NSJSONSerialization dataWithJSONObject:j options:0 error:nil] forKey:@"snapshotJSON"];[self poll:ident completion:done];}];
}
- (void)refreshLast:(void(^)(NSDictionary *,NSString *))done{NSString *ident=[Settings() stringForKey:@"lastJob"];if(!ident){done(nil,@"还没有知识库查询。");return;}self.started=nil;[self poll:ident completion:done];}
@end
