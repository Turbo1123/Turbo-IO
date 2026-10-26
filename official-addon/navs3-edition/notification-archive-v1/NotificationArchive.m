#import "NotificationArchive.h"
#import "TodoProtocol.h"
#import <CommonCrypto/CommonDigest.h>
#import <TargetConditionals.h>
#import <sqlite3.h>
#include <math.h>

static const NSUInteger MaxPacket=65536, MaxText=32768;
static NSString *Hash(NSData *data) {
    unsigned char bytes[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,bytes);
    NSMutableString *s=[NSMutableString new];for(unsigned i=0;i<sizeof(bytes);i++)[s appendFormat:@"%02x",bytes[i]];return s;
}
static BOOL Integer(id x,NSInteger lo,NSInteger hi) {
    if(![x isKindOfClass:NSNumber.class]||CFGetTypeID((__bridge CFTypeRef)x)==CFBooleanGetTypeID())return NO;
    double n=[x doubleValue];return isfinite(n)&&floor(n)==n&&n>=lo&&n<=hi;
}
static NSString *String(id value,NSUInteger limit) {
    if(![value isKindOfClass:NSString.class]||[value length]>limit)return nil;
    for(NSUInteger i=0;i<[value length];i++)if([value characterAtIndex:i]==0)return nil;
    return value;
}
NSDictionary *TNADecodeEvent(NSDictionary *event,NSString *session,NSTimeInterval at) {
    if(!isfinite(at)||at<=0||![event isKindOfClass:NSDictionary.class]||![event[@"eventType"] isEqual:@"messageReceived"])return nil;
    id m=event[@"message"];
    if(![m isKindOfClass:NSDictionary.class]||!Integer(m[@"businessId"],21,21))return nil;
    NSString *device=String(m[@"deviceId"],200);NSData *wire=m[@"payload"];
    if(!device.length||![wire isKindOfClass:NSData.class]||wire.length>MaxPacket)return nil;
    NSDictionary *envelope=TIOTodoEnvelope(wire); // strict version1 / non-binary envelope
    if(!Integer(envelope[@"type"],1,1))return nil;
    NSDictionary *j=envelope[@"json"];
    NSString *uid=String(j[@"notificationUID"],128),*app=String(j[@"appId"],256);
    if(!uid.length||!app.length||!Integer(j[@"eventId"],0,2)||!String(session,64).length)return nil;
    NSMutableDictionary *r=[@{@"uid":uid,@"session":session,@"appId":app,@"eventId":j[@"eventId"],@"receivedAt":@(at),@"origin":@"glasses-ancs",@"deviceHash":Hash([device dataUsingEncoding:NSUTF8StringEncoding])} mutableCopy];
    for(NSString *key in @[@"appName",@"title",@"subtitle",@"content",@"timestamp"]){
        id value=j[key];NSString *s=value?String(value,[key isEqual:@"content"]?MaxText:([key isEqual:@"timestamp"]?128:2048)):@"";
        if(!s)return nil;r[key]=s;
    }
    // Keep only explicitly understood fields. Never retain opaque extra JSON.
    for(NSString *key in @[@"eventFlags",@"categoryID",@"categoryCount"]){if(j[key]){if(!Integer(j[key],0,255))return nil;r[key]=j[key];}}
    NSData *data=[NSJSONSerialization dataWithJSONObject:r options:NSJSONWritingSortedKeys error:nil];
    if(!data||data.length>MaxPacket)return nil;
    r[@"id"]=TNAFingerprint(r);return r;
}
NSString *TNAFingerprint(NSDictionary *record) {
    NSMutableDictionary *copy=[record mutableCopy];[copy removeObjectForKey:@"id"];[copy removeObjectForKey:@"receivedAt"];
    NSData *data=[NSJSONSerialization dataWithJSONObject:copy options:NSJSONWritingSortedKeys error:nil];return data?Hash(data):nil;
}
static BOOL ValidRecord(NSDictionary *r) {
    if(![r isKindOfClass:NSDictionary.class]||![r[@"origin"] isEqual:@"glasses-ancs"]||!String(r[@"uid"],128).length||!String(r[@"appId"],256).length||!String(r[@"session"],64).length||String(r[@"deviceHash"],64).length!=64||!Integer(r[@"eventId"],0,2))return NO;
    for(NSString *k in @[@"appName",@"title",@"subtitle",@"content",@"timestamp"]){if(!String(r[k],[k isEqual:@"content"]?MaxText:([k isEqual:@"timestamp"]?128:2048)))return NO;}
    return [r[@"receivedAt"] isKindOfClass:NSNumber.class]&&isfinite([r[@"receivedAt"] doubleValue])&&[r[@"receivedAt"] doubleValue]>0&&[r[@"id"] isEqual:TNAFingerprint(r)];
}

@implementation TNAStore {
    NSURL *_directory;sqlite3 *_db;NSString *_error;NSUInteger _evicted;
}
- (instancetype)initWithDirectory:(NSURL *)dir {if((self=[super init]))_directory=dir;return self;}
- (void)dealloc {if(_db)sqlite3_close(_db);}
- (BOOL)sql:(const char *)sql {if(sqlite3_exec(_db,sql,NULL,NULL,NULL)!=SQLITE_OK){_error=@"本机数据库操作失败；未宣称保存成功";return NO;}return YES;}
- (BOOL)open {
    if(_db)return YES;
    NSMutableDictionary *attrs=[@{NSFilePosixPermissions:@0700} mutableCopy];
#if TARGET_OS_IPHONE
    attrs[NSFileProtectionKey]=NSFileProtectionCompleteUntilFirstUserAuthentication;
#endif
    NSError *e=nil;
    if(![NSFileManager.defaultManager createDirectoryAtURL:_directory withIntermediateDirectories:YES attributes:attrs error:&e]){_error=@"无法创建本机归档目录";return NO;}
    [_directory setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:&e];
    if(e){_error=@"无法设置归档备份排除；已停止保存";return NO;}
    NSURL *path=[_directory URLByAppendingPathComponent:@"notifications.sqlite"];
    int rc=sqlite3_open_v2(path.fileSystemRepresentation,&_db,SQLITE_OPEN_READWRITE|SQLITE_OPEN_CREATE|SQLITE_OPEN_FULLMUTEX,NULL);
    if(rc!=SQLITE_OK){if(_db)sqlite3_close(_db);_db=NULL;_error=@"数据库暂不可用；请解锁手机后重试";return NO;}
    sqlite3_busy_timeout(_db,500);
    attrs[NSFilePosixPermissions]=@0600;
    if(![NSFileManager.defaultManager setAttributes:attrs ofItemAtPath:path.path error:&e]){sqlite3_close(_db);_db=NULL;_error=@"无法保护归档文件；已停止保存";return NO;}
    if(![self sql:"PRAGMA page_size=4096; PRAGMA journal_mode=DELETE; PRAGMA secure_delete=ON; PRAGMA synchronous=FULL; PRAGMA max_page_count=8192; CREATE TABLE IF NOT EXISTS notifications (id TEXT PRIMARY KEY, received REAL NOT NULL, body BLOB NOT NULL, bytes INTEGER NOT NULL); CREATE INDEX IF NOT EXISTS notifications_time ON notifications(received DESC);"]){sqlite3_close(_db);_db=NULL;return NO;}
    _error=nil;return YES;
}
- (BOOL)pruneAt:(NSTimeInterval)now {
    if(!isfinite(now)||![self open])return NO;
    sqlite3_stmt *s=NULL;
    if(sqlite3_prepare_v2(_db,"DELETE FROM notifications WHERE received < ?",-1,&s,NULL)!=SQLITE_OK)return NO;
    sqlite3_bind_double(s,1,now-30*86400);BOOL ok=sqlite3_step(s)==SQLITE_DONE;sqlite3_finalize(s);
    if(!ok)return NO;_evicted+=(NSUInteger)sqlite3_changes(_db);
    if(![self sql:"DELETE FROM notifications WHERE id IN (SELECT id FROM notifications ORDER BY received DESC, rowid DESC LIMIT -1 OFFSET 2000)"])return NO;
    _evicted+=(NSUInteger)sqlite3_changes(_db);
    // Logical payload cap: 8 MiB, irrespective of record count. The DB has a
    // separate 32 MiB page cap, so even corrupt/unusual inputs cannot grow forever.
    for(;;){
        sqlite3_int64 bytes=0;
        if(sqlite3_prepare_v2(_db,"SELECT COALESCE(SUM(bytes),0) FROM notifications",-1,&s,NULL)!=SQLITE_OK)return NO;
        if(sqlite3_step(s)==SQLITE_ROW)bytes=sqlite3_column_int64(s,0);else ok=NO;sqlite3_finalize(s);
        if(!ok)return NO;if(bytes<=8*1024*1024)break;
        if(![self sql:"DELETE FROM notifications WHERE id=(SELECT id FROM notifications ORDER BY received, rowid LIMIT 1)"])return NO;_evicted+=(NSUInteger)sqlite3_changes(_db);
    }
    return YES;
}
- (NSString *)insert:(NSDictionary *)record now:(NSTimeInterval)now {
    if(!ValidRecord(record)||!isfinite(now))return @"error";
    NSData *data=[NSJSONSerialization dataWithJSONObject:record options:NSJSONWritingSortedKeys error:nil];
    if(!data.length||data.length>MaxPacket||![self open]||![self sql:"BEGIN IMMEDIATE"])return @"error";
    sqlite3_stmt *s=NULL;BOOL ok=sqlite3_prepare_v2(_db,"INSERT OR IGNORE INTO notifications(id,received,body,bytes) VALUES(?,?,?,?)",-1,&s,NULL)==SQLITE_OK;
    if(ok){sqlite3_bind_text(s,1,[record[@"id"] UTF8String],-1,SQLITE_TRANSIENT);sqlite3_bind_double(s,2,[record[@"receivedAt"] doubleValue]);sqlite3_bind_blob(s,3,data.bytes,(int)data.length,SQLITE_TRANSIENT);sqlite3_bind_int(s,4,(int)data.length);ok=sqlite3_step(s)==SQLITE_DONE;}
    if(s)sqlite3_finalize(s);BOOL inserted=ok&&sqlite3_changes(_db)>0;
    if(ok)ok=[self pruneAt:now];
    if(!ok){[self sql:"ROLLBACK"];_error=@"保存失败；空间不足或数据库不可用";return @"error";}
    if(![self sql:"COMMIT"]){[self sql:"ROLLBACK"];return @"error";}_error=nil;return inserted?@"inserted":@"duplicate";
}
- (NSArray<NSDictionary *> *)recordsMatching:(NSString *)query limit:(NSUInteger)limit {
    if(![self open])return @[];
    // No SQL interpolation; cap memory/result size. Search decoded bounded rows.
    query=String(query,200)?:@"";limit=MIN(MAX(limit,1),2000);NSMutableArray *out=[NSMutableArray new];sqlite3_stmt *s=NULL;
    if(sqlite3_prepare_v2(_db,"SELECT body FROM notifications ORDER BY received DESC, rowid DESC LIMIT 2000",-1,&s,NULL)!=SQLITE_OK)return @[];
    while(sqlite3_step(s)==SQLITE_ROW&&out.count<limit){@autoreleasepool{
        int count=sqlite3_column_bytes(s,0);if(count<1||(NSUInteger)count>MaxPacket)continue;
        NSData *d=[NSData dataWithBytes:sqlite3_column_blob(s,0) length:(NSUInteger)count];id r=[NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
        if(!ValidRecord(r))continue;
        BOOL match=!query.length;for(NSString *k in @[@"appName",@"appId",@"title",@"subtitle",@"content"]){if([r[k] isKindOfClass:NSString.class]&&[r[k] rangeOfString:query options:NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch].location!=NSNotFound)match=YES;}
        if(match)[out addObject:r];
    }}sqlite3_finalize(s);return out;
}
- (NSDictionary *)status {
    NSUInteger count=0,bytes=0;if([self open]){sqlite3_stmt *s=NULL;if(sqlite3_prepare_v2(_db,"SELECT COUNT(*),COALESCE(SUM(bytes),0) FROM notifications",-1,&s,NULL)==SQLITE_OK){if(sqlite3_step(s)==SQLITE_ROW){count=(NSUInteger)sqlite3_column_int64(s,0);bytes=(NSUInteger)sqlite3_column_int64(s,1);}sqlite3_finalize(s);}}
    return @{@"count":@(count),@"bytes":@(bytes),@"evictedThisRun":@(_evicted),@"error":_error?:@""};
}
- (BOOL)clear {
    if(![self open]||![self sql:"DELETE FROM notifications; VACUUM;"])return NO;
    _error=nil;return YES;
}
@end
