#import "MusicLibrary.h"
NSString * const TMMusicAccountChanged = @"TurboMusicAccountChangedV2";
static NSDictionary *Dict(id x){return [x isKindOfClass:NSDictionary.class]?x:@{};}
static NSArray *List(id x){return [x isKindOfClass:NSArray.class]?x:@[];}
static NSString *Text(id x, NSUInteger max){return [x isKindOfClass:NSString.class]?[x substringToIndex:MIN([x length],max)]:@"";}
static NSNumber *ID(id x){return [x isKindOfClass:NSNumber.class]&&[x longLongValue]>0?x:nil;}
NSDictionary *TMMusicCookieValues(NSString *text){
 if(![text isKindOfClass:NSString.class]||text.length>16384)return nil;
 NSMutableDictionary *out=[NSMutableDictionary new];
 for(NSString *part in [text componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@";\r\n"]]){
  NSString *trim=[part stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];if(!trim.length)continue;
  NSRange r=[trim rangeOfString:@"="];if(r.location==NSNotFound)return nil;
  NSString *name=[trim substringToIndex:r.location],*value=[[trim substringFromIndex:r.location+1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
  if(![@[@"MUSIC_U",@"__csrf"] containsObject:name])return nil;
  if(!value.length||value.length>8192||out[name])return nil;
  NSCharacterSet *allowed=[NSCharacterSet characterSetWithRange:NSMakeRange(33,94)];
  if([value rangeOfCharacterFromSet:allowed.invertedSet].location!=NSNotFound||[value containsString:@";"])return nil;
  out[name]=value;
 }
 return [out[@"MUSIC_U"] length]?out:nil;
}
NSDictionary *TMMusicSafeSong(id value){
 NSDictionary *v=Dict(value);NSNumber *sid=ID(v[@"id"]);if(!sid)return nil;
 NSDictionary *album=Dict(v[@"al"]?:v[@"album"]);NSMutableArray *artists=[NSMutableArray new];
 for(id a in List(v[@"ar"]?:v[@"artists"])){NSString *name=Text(Dict(a)[@"name"],128);if(name.length)[artists addObject:name];if(artists.count==8)break;}
 NSString *artist=Text(v[@"artist"],512);if(!artist.length)artist=[artists componentsJoinedByString:@" / "];
 NSString *cover=Text(v[@"cover"]?:album[@"picUrl"],2048);NSURLComponents *url=[NSURLComponents componentsWithString:cover];NSString *host=url.host.lowercaseString;
 if((![url.scheme isEqual:@"https"]&&![url.scheme isEqual:@"http"])||url.user||url.password||!([host hasSuffix:@".126.net"]||[host hasSuffix:@".163.com"]))cover=@"";
 id duration=v[@"dt"]?:v[@"duration"];double ms=[duration isKindOfClass:NSNumber.class]?[duration doubleValue]:0;if(!isfinite(ms)||ms<0||ms>86400000)ms=0;
 return @{@"id":sid,@"name":Text(v[@"name"],256),@"artist":artist,@"cover":cover,@"duration":@(ms)};
}
NSArray *TMMusicSafeQueue(id value){NSMutableArray *rows=[NSMutableArray new];NSMutableSet *seen=[NSMutableSet new];for(id v in List(value)){NSDictionary *song=TMMusicSafeSong(v);if(song&&![seen containsObject:song[@"id"]]){[rows addObject:song];[seen addObject:song[@"id"]];}if(rows.count>=300)break;}return rows;}
void TMMusicClearMemory(void){for(NSString *key in @[@"TurboMusicLastSongV1",@"TurboMusicPlaybackV2",@"TurboMusicLocalHistoryV2",@"TurboMusicLibraryKindV2",@"TurboMusicLibraryQueryV2"])[NSUserDefaults.standardUserDefaults removeObjectForKey:key];}
static NSString *Error(NSDictionary *j,NSString *error){if(error)return error;if(![j isKindOfClass:NSDictionary.class]||![j[@"code"]isKindOfClass:NSNumber.class])return @"音乐服务返回格式异常，请重试";NSInteger code=[j[@"code"]integerValue];if(code==200)return nil;if(code==301||code==401||code==302)return @"登录已失效，请重新导入或登录";return [NSString stringWithFormat:@"音乐服务暂不可用（%ld），下拉重试",(long)code];}
@implementation TMMusicLibrary { TMRequest _request; }
- (instancetype)initWithRequest:(TMRequest)request{if((self=[super init]))_request=[request copy];return self;}
- (void)account:(void(^)(NSNumber *,NSString *))done{_request(@"/api/w/nuser/account/get",@{},NO,^(NSDictionary *j,NSString *error){NSString *e=Error(j,error);NSNumber *uid=ID(Dict(j[@"profile"])[@"userId"]);done(uid,e?:(!uid?@"登录已失效，请重新导入或登录":nil));});}
- (void)details:(NSArray *)ids offset:(NSUInteger)offset done:(TMLibraryReply)done{
 NSMutableArray *valid=[NSMutableArray new];NSMutableSet *seen=[NSMutableSet new];for(id v in ids){NSNumber *n=ID([v isKindOfClass:NSDictionary.class]?v[@"id"]:v);if(n&&![seen containsObject:n]){[valid addObject:n];[seen addObject:n];}if(valid.count>=20000)break;}
 NSUInteger total=valid.count;if(offset>=total){done(@[],total,nil);return;}NSArray *page=[valid subarrayWithRange:NSMakeRange(offset,MIN(50,total-offset))];NSMutableArray *c=[NSMutableArray new];for(NSNumber *n in page)[c addObject:@{@"id":n}];
 NSString *json=[[NSString alloc]initWithData:[NSJSONSerialization dataWithJSONObject:c options:0 error:nil] encoding:NSUTF8StringEncoding];
 _request(@"/api/v3/song/detail",@{@"c":json},NO,^(NSDictionary *j,NSString *error){NSString *e=Error(j,error);if(e){done(@[],total,e);return;}if(![j[@"songs"]isKindOfClass:NSArray.class]){done(@[],total,@"歌曲详情格式异常，请重试");return;}NSMutableDictionary *byID=[NSMutableDictionary new];for(id v in j[@"songs"]){NSDictionary *s=TMMusicSafeSong(v);if(s)byID[s[@"id"]]=s;}NSMutableArray *rows=[NSMutableArray new];for(NSNumber *n in page)if(byID[n])[rows addObject:byID[n]];done(rows,total,nil);});
}
- (void)fetch:(NSString *)kind query:(NSString *)query offset:(NSUInteger)offset done:(TMLibraryReply)done{
 if(offset>20000){done(@[],0,@"已达到列表上限");return;}
 if([kind isEqual:@"liked"]){[self account:^(NSNumber *uid,NSString *error){if(error){done(@[],0,error);return;}self->_request(@"/api/song/like/get",@{@"uid":uid},NO,^(NSDictionary *j,NSString *e){NSString *err=Error(j,e);if(err||![j[@"ids"]isKindOfClass:NSArray.class]){done(@[],0,err?:@"喜欢列表格式异常");return;}[self details:j[@"ids"] offset:offset done:done];});}];return;}
 if([kind isEqual:@"playlists"]){[self account:^(NSNumber *uid,NSString *error){if(error){done(@[],0,error);return;}self->_request(@"/api/user/playlist",@{@"uid":uid,@"limit":@50,@"offset":@(offset),@"includeVideo":@YES},NO,^(NSDictionary *j,NSString *e){NSString *err=Error(j,e);if(err||![j[@"playlist"]isKindOfClass:NSArray.class]){done(@[],0,err?:@"歌单列表格式异常");return;}NSMutableArray *rows=[NSMutableArray new];for(id v in j[@"playlist"]){NSDictionary *p=Dict(v);if(ID(p[@"id"]))[rows addObject:@{@"id":p[@"id"],@"name":Text(p[@"name"],256),@"artist":[NSString stringWithFormat:@"%lu 首",(unsigned long)[List(p[@"tracks"]) count]?:[p[@"trackCount"] unsignedIntegerValue]],@"cover":Text(p[@"coverImgUrl"],2048)}];if(rows.count==50)break;}done(rows,offset+rows.count+([j[@"more"]boolValue]?1:0),nil);});}];return;}
 if([kind isEqual:@"playlist"]){long long pid=query.longLongValue;if(pid<=0){done(@[],0,@"歌单 ID 无效");return;}_request(@"/api/v6/playlist/detail",@{@"id":@(pid),@"n":@50,@"s":@0},YES,^(NSDictionary *j,NSString *e){NSString *err=Error(j,e);NSDictionary *p=Dict(j[@"playlist"]);if(err||![p[@"trackIds"]isKindOfClass:NSArray.class]){done(@[],0,err?:@"歌单不可访问或数据异常");return;}[self details:p[@"trackIds"] offset:offset done:done];});return;}
 if([kind isEqual:@"recent"]){_request(@"/api/play-record/song/list",@{@"limit":@300},NO,^(NSDictionary *j,NSString *e){NSString *err=Error(j,e);NSDictionary *data=Dict(j[@"data"]);if(err||![data[@"list"]isKindOfClass:NSArray.class]){done(@[],0,err?:@"最近播放列表格式异常");return;}NSMutableArray *items=[NSMutableArray new];for(id v in data[@"list"]){NSDictionary *row=Dict(v);id song=row[@"data"]?:row[@"song"];if(song)[items addObject:song];if(items.count>=300)break;}NSArray *songs=TMMusicSafeQueue(items);NSUInteger total=songs.count;done(offset<total?[songs subarrayWithRange:NSMakeRange(offset,MIN(50,total-offset))]:@[],total,nil);});return;}
 if([kind isEqual:@"search"]){NSString *q=[Text(query,100) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(!q.length){done(@[],0,nil);return;}_request(@"/api/cloudsearch/pc",@{@"s":q,@"type":@1,@"limit":@50,@"offset":@(offset),@"total":@YES},NO,^(NSDictionary *j,NSString *e){NSString *err=Error(j,e);NSDictionary *result=Dict(j[@"result"]);if(err){done(@[],0,err);return;}NSArray *rows=TMMusicSafeQueue(result[@"songs"]);NSUInteger total=[result[@"songCount"]respondsToSelector:@selector(unsignedIntegerValue)]?[result[@"songCount"]unsignedIntegerValue]:rows.count;done(rows,MIN(20000,total),nil);});return;}
 done(@[],0,@"未知音乐列表");
}
@end
