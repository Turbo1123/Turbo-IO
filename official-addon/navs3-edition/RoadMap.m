#import "RoadMap.h"
#include "nav_map.h"
#include <math.h>
#include <float.h>
static BOOL N(id v,double lo,double hi){return [v isKindOfClass:NSNumber.class]&&isfinite([v doubleValue])&&[v doubleValue]>=lo&&[v doubleValue]<=hi;}
static BOOL LL(id p){return [p isKindOfClass:NSArray.class]&&[p count]==2&&N(p[0],-85,85)&&N(p[1],-180,180);}
static void W16(uint8_t *p,unsigned x){p[0]=x;p[1]=x>>8;}static void W32(uint8_t *p,uint32_t x){W16(p,x);W16(p+2,x>>16);}
static NSArray *XY(NSArray *ll,NSArray *origin){double y=([ll[0] doubleValue]-[origin[0] doubleValue])*111319.49,x=([ll[1] doubleValue]-[origin[1] doubleValue])*111319.49*cos([origin[0] doubleValue]*M_PI/180);return @[@(x),@(y)];}
static double Distance(NSArray *a,NSArray *b){NSArray *p=XY(a,b);return hypot([p[0] doubleValue],[p[1] doubleValue]);}
static BOOL Clip(double *x,double *y,double *xx,double *yy){double dx=*xx-*x,dy=*yy-*y,t0=0,t1=1,p[]={-dx,dx,-dy,dy},q[]={*x+500,500-*x,*y+500,500-*y};for(int i=0;i<4;i++){if(fabs(p[i])<1e-9){if(q[i]<0)return NO;}else{double t=q[i]/p[i];if(p[i]<0)t0=fmax(t0,t);else t1=fmin(t1,t);if(t0>t1)return NO;}}double ox=*x,oy=*y;*x=ox+dx*t0;*y=oy+dy*t0;*xx=ox+dx*t1;*yy=oy+dy*t1;return YES;}
static NSArray *Pieces(NSArray *coords,NSArray *origin,NSArray *(^convert)(double,double),BOOL osm){
 NSMutableArray *pieces=[NSMutableArray new],*part=nil;NSArray *last=nil;NSUInteger budget=0;
 for(id pair in coords){NSArray *ll=osm&&[pair isKindOfClass:NSArray.class]&&[pair count]==2?@[pair[1],pair[0]]:pair;if(!LL(ll)){last=nil;part=nil;continue;}if(osm&&convert)ll=convert([ll[0] doubleValue],[ll[1] doubleValue]);if(!LL(ll)){last=nil;part=nil;continue;}NSArray *xy=XY(ll,origin);
  if(last){double x=[last[0] doubleValue],y=[last[1] doubleValue],xx=[xy[0] doubleValue],yy=[xy[1] doubleValue];if(Clip(&x,&y,&xx,&yy)){
   NSArray *a=@[@((int)lround(x*4)),@((int)lround(y*4))],*b=@[@((int)lround(xx*4)),@((int)lround(yy*4))];
   if(!part||![part.lastObject isEqual:a]){part=[NSMutableArray arrayWithObject:a];[pieces addObject:part];}
   if(![part.lastObject isEqual:b])[part addObject:b];budget++;if(budget>=2048)break;
  }else part=nil;}last=xy;
 }
 return pieces;
}
static NSString *Text(id value){return [value isKindOfClass:NSString.class]?value:[value isKindOfClass:NSNumber.class]?[value stringValue]:@"";}
static NSArray *Simplify(NSArray *p){
 if(p.count<3||p.count>2049)return p;NSUInteger todo[4098],top=0;NSMutableIndexSet *keep=[NSMutableIndexSet indexSetWithIndex:0];[keep addIndex:p.count-1];todo[top++]=0;todo[top++]=p.count-1;
 while(top){NSUInteger b=todo[--top],a=todo[--top],at=0;double ax=[p[a][0] doubleValue],ay=[p[a][1] doubleValue],dx=[p[b][0] doubleValue]-ax,dy=[p[b][1] doubleValue]-ay,den=dx*dx+dy*dy,best=64;
  for(NSUInteger i=a+1;i<b;i++){double x=[p[i][0] doubleValue]-ax,y=[p[i][1] doubleValue]-ay,t=den?MAX(0,MIN(1,(x*dx+y*dy)/den)):0,ex=x-dx*t,ey=y-dy*t,d=ex*ex+ey*ey;if(d>best){best=d;at=i;}}
  if(at){[keep addIndex:at];todo[top++]=a;todo[top++]=at;todo[top++]=at;todo[top++]=b;}
 }
 NSMutableArray *out=[NSMutableArray new];[keep enumerateIndexesUsingBlock:^(NSUInteger i,BOOL *stop){[out addObject:p[i]];}];return out;
}
static NSData *NameData(id value){
 NSString *name=Text(value);NSMutableString *s=[NSMutableString new];__block unsigned width=0;
 [name enumerateSubstringsInRange:NSMakeRange(0,name.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *c,NSRange r,NSRange all,BOOL *stop){
  unichar u=[c characterAtIndex:0];if(c.length!=1||u<32||(u>=127&&u<=159)||(u>=0x200b&&u<=0x202e)||(u>=0x2060&&u<=0x206f)||u>=0xfff0)return;unsigned w=u<128?9:16;if(width+w>104||[s lengthOfBytesUsingEncoding:NSUTF8StringEncoding]+[c lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>=TNR_LABEL_BYTES){*stop=YES;return;}width+=w;[s appendString:c];
 }];return [s dataUsingEncoding:NSUTF8StringEncoding];
}
static unsigned RoadStyle(NSString *h){if([@[@"motorway",@"trunk",@"motorway_link",@"trunk_link"] containsObject:h])return 0;if([h hasPrefix:@"primary"])return 1;if([h hasPrefix:@"secondary"])return 2;if([h hasPrefix:@"tertiary"])return 3;if([@[@"residential",@"unclassified",@"living_street"] containsObject:h])return 4;return 5;}
@implementation TIORoadMap{
 NSArray *(^_convert)(double,double);NSArray *_features,*_bbox,*_origin,*_regions;double _labelHeading,_sceneAt;NSData *_scene,*_scene2;uint32_t _generation;id _segment;NSString *_note;
 NSURLSession *_session;NSURLSessionDataTask *_task;NSMutableData *_received;NSTimeInterval _lastRequest;NSUInteger _requests,_epoch;BOOL _httpOK;
}
- (instancetype)initWithWGS84ToMap:(NSArray *(^)(double,double))convert{if((self=[super init])){_convert=[convert copy];_note=@"路网关闭 · 保留原路线示意图";}return self;}
- (NSString *)note{return _note?:@"";}
- (void)reset{_epoch++;[_task cancel];[_session invalidateAndCancel];_task=nil;_session=nil;_received=nil;_regions=nil;_features=nil;_bbox=nil;_scene=nil;_scene2=nil;_origin=nil;_segment=nil;_requests=0;_lastRequest=0;self.allowNetwork=NO;_note=@"路网缓存已清理";}
- (void)dealloc{[_session invalidateAndCancel];}
- (NSArray *)wgs:(NSArray *)map{
 if(!LL(map))return nil;if(!_convert)return map;
 // Only the Overpass search/fixture coverage uses WGS84. Render origin,
 // AMap route and pose stay in GCJ02; OSM lon/lat converts exactly once.
 double lat=[map[0] doubleValue],lon=[map[1] doubleValue];
 for(int i=0;i<6;i++){NSArray *candidate=@[@(lat),@(lon)];if(!LL(candidate))return nil;
  NSArray *q=_convert(lat,lon);if(!LL(q))return nil;
  if(Distance(q,map)<=.5)return candidate;
  lat-=[q[0] doubleValue]-[map[0] doubleValue];lon-=[q[1] doubleValue]-[map[1] doubleValue];
 }return nil; // Do not request/show a mismatched region when inverse fails.
}
// Two bounded geographic regions. Refresh coverage and render coverage are distinct.
- (BOOL)bbox:(NSArray *)b contains:(NSArray *)ll margin:(double)metres {
 if(b.count!=4||!LL(ll))return NO;
 double lat=[ll[0] doubleValue],lon=[ll[1] doubleValue],dy=metres/111319.49,dx=dy/MAX(.2,cos(lat*M_PI/180));
 return lat>=[b[0] doubleValue]+dy&&lat<=[b[2] doubleValue]-dy&&lon>=[b[1] doubleValue]+dx&&lon<=[b[3] doubleValue]-dx;
}
- (BOOL)hasCoverage:(NSArray *)ll margin:(double)metres {
 for(NSDictionary *r in _regions)if([self bbox:r[@"bbox"] contains:ll margin:metres])return YES;
 return NO;
}
- (void)installFeatures:(NSArray *)features bbox:(NSArray *)bbox {
 if(!features.count||features.count>5000||bbox.count!=4)return;
 NSMutableArray *regions=[NSMutableArray arrayWithArray:_regions?:@[]];
 NSIndexSet *same=[regions indexesOfObjectsPassingTest:^BOOL(NSDictionary *r,NSUInteger i,BOOL *stop){return [r[@"bbox"] isEqual:bbox];}];[regions removeObjectsAtIndexes:same];
 [regions addObject:@{@"bbox":bbox,@"features":features}];while(regions.count>2)[regions removeObjectAtIndex:0];_regions=regions;
 _bbox=bbox;NSMutableArray *all=[NSMutableArray new];NSMutableSet *seen=[NSMutableSet new];
 // Current region first. Deduplicate overlapping road fragments without persisting location.
 for(NSDictionary *r in [regions reverseObjectEnumerator])for(NSDictionary *f in r[@"features"]){
  if(all.count>=10000)break;if([seen containsObject:f])continue;[seen addObject:f];[all addObject:f];
 }
 _features=all;_scene=nil;_scene2=nil;
}
- (BOOL)covers:(NSArray *)ll {return [self hasCoverage:ll margin:0];}
- (NSDictionary *)coverageStatus {
 return @{@"regions":@(_regions.count),@"features":@(_features.count),@"requests":@(_requests),@"networkAllowed":@(self.allowNetwork),@"requestInFlight":@(_task!=nil),@"requestLimit":@6};
}
- (BOOL)hasVisibleLabelsAt:(NSArray *)position heading:(unsigned)heading {
 if(!_scene2||!_origin)return NO;
 // Evaluate the unchanged firmware's exact clipping/overlap rules locally.
 TNRState state={0};if(!tnr_receive(&state,TNR_SCENE2,_scene2.bytes,_scene2.length,0))return NO;
 NSArray *xy=XY(position,_origin);double x=[xy[0] doubleValue]*4,y=[xy[1] doubleValue]*4;
 if(fabs(x)>2000||fabs(y)>2000)return NO;
 uint8_t pose[12]={0};W32(pose,_generation);W16(pose+4,(int)lround(x));W16(pose+6,(int)lround(y));W16(pose+8,heading%360);
 if(!tnr_receive(&state,TNR_POSE,pose,12,0))return NO;
 TNRLabelView out[TNR_MAX_LABELS];return tnr_labels(&state,200,out)>0;
}
- (NSString *)fixturePath:(NSString *)name{return [NSBundle.mainBundle pathForResource:name ofType:@"json" inDirectory:@"TurboHUDMaps"];}
- (BOOL)loadFixture:(NSArray *)ll{for(NSString *name in @[@"shenzhen",@"hongkong"]){NSString *p=[self fixturePath:name];NSData *d=p?[NSData dataWithContentsOfFile:p]:nil;if(!d||d.length>2*1024*1024)continue;NSDictionary *j=[NSJSONSerialization JSONObjectWithData:d options:0 error:nil];if(![j isKindOfClass:NSDictionary.class]||![j[@"meta"] isKindOfClass:NSDictionary.class]||![j[@"geojson"] isKindOfClass:NSDictionary.class])continue;NSArray *b=j[@"meta"][@"bbox"],*features=j[@"geojson"][@"features"];if(![b isKindOfClass:NSArray.class]||b.count!=4||![features isKindOfClass:NSArray.class]||features.count>5000)continue;BOOL valid=YES;for(id n in b)valid&=N(n,-180,180);if(!valid)continue;double lat=[ll[0] doubleValue],lon=[ll[1] doubleValue];if(lat< [b[0] doubleValue]||lat>[b[2] doubleValue]||lon<[b[1] doubleValue]||lon>[b[3] doubleValue])continue;[self installFeatures:features bbox:b];_note=@"公开区域离线路网 · © OpenStreetMap";return YES;}return NO;}
- (void)request:(NSArray *)ll{
 NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;if(!self.allowNetwork||_task||_requests>=6||(_lastRequest&&now-_lastRequest<60))return;
 double lat=[ll[0] doubleValue],lon=[ll[1] doubleValue],dlat=.006,dlon=.006/MAX(.2,cos(lat*M_PI/180));
 NSArray *bbox=@[@(lat-dlat),@(lon-dlon),@(lat+dlat),@(lon+dlon)];
 NSString *query=[NSString stringWithFormat:@"[out:json][timeout:15][maxsize:16777216];way[highway](%.6f,%.6f,%.6f,%.6f);out tags geom;",lat-dlat,lon-dlon,lat+dlat,lon+dlon];
 NSString *encoded=[query stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];NSURL *url=[NSURL URLWithString:[@"https://overpass-api.de/api/interpreter?data=" stringByAppendingString:encoded]];
 NSMutableURLRequest *r=[NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:22];[r setValue:@"TurboIO-TNR1-private-pilot/1.0" forHTTPHeaderField:@"User-Agent"];
 NSURLSessionConfiguration *c=NSURLSessionConfiguration.ephemeralSessionConfiguration;c.requestCachePolicy=NSURLRequestReloadIgnoringLocalCacheData;c.URLCache=nil;c.HTTPCookieStorage=nil;c.timeoutIntervalForResource=25;c.HTTPMaximumConnectionsPerHost=1;
 _session=[NSURLSession sessionWithConfiguration:c delegate:self delegateQueue:NSOperationQueue.mainQueue];_received=[NSMutableData new];_httpOK=NO;_task=[_session dataTaskWithRequest:r];_task.taskDescription=[[NSJSONSerialization dataWithJSONObject:bbox options:0 error:nil] base64EncodedStringWithOptions:0];
 _lastRequest=now;_requests++;_note=@"试验图源请求中（最多6次/会话，间隔60秒）";[_task resume];
}
- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)t willPerformHTTPRedirection:(NSHTTPURLResponse *)r newRequest:(NSURLRequest *)q completionHandler:(void(^)(NSURLRequest *))done{done(nil);}
- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)t didReceiveResponse:(NSURLResponse *)r completionHandler:(void(^)(NSURLSessionResponseDisposition))done{_httpOK=s==_session&&t==_task&&[(NSHTTPURLResponse *)r statusCode]==200&&r.expectedContentLength<=2*1024*1024;done(_httpOK?NSURLSessionResponseAllow:NSURLSessionResponseCancel);}
- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)t didReceiveData:(NSData *)d{if(s!=_session||t!=_task)return;if(d.length>2*1024*1024-_received.length){_httpOK=NO;[t cancel];return;}[_received appendData:d];}
- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)t didCompleteWithError:(NSError *)error{
 if(s!=_session||t!=_task)return;NSData *data=_received;NSString *b64=t.taskDescription;BOOL ok=_httpOK&&!error;NSUInteger epoch=_epoch;_task=nil;_received=nil;_session=nil;[s finishTasksAndInvalidate];
 if(!ok){_note=@"图源不可用 · 不伪造道路，保留路线示意图";return;}
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{NSDictionary *j=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];NSMutableArray *features=[NSMutableArray new];NSUInteger points=0;
  if([j isKindOfClass:NSDictionary.class]&&[j[@"elements"] isKindOfClass:NSArray.class]&&[j[@"elements"] count]<=5000&&!j[@"remark"])for(NSDictionary *way in j[@"elements"]){if(![way isKindOfClass:NSDictionary.class]||![way[@"type"] isEqual:@"way"]||![way[@"geometry"] isKindOfClass:NSArray.class])continue;NSMutableArray *coords=[NSMutableArray new];for(id point in way[@"geometry"]){if(![point isKindOfClass:NSDictionary.class]||!N(point[@"lat"],-85,85)||!N(point[@"lon"],-180,180)){[coords removeAllObjects];break;}[coords addObject:@[point[@"lon"],point[@"lat"]]];if(++points>40000)break;}if(points>40000){[features removeAllObjects];break;}if(coords.count>=2){NSMutableDictionary *p=[way[@"tags"] isKindOfClass:NSDictionary.class]?[way[@"tags"] mutableCopy]:[NSMutableDictionary new];p[@"kind"]=@"road";[features addObject:@{@"properties":p,@"geometry":@{@"coordinates":coords,@"type":@"LineString"}}];}}
  NSArray *bbox=[NSJSONSerialization JSONObjectWithData:[[NSData alloc]initWithBase64EncodedString:b64 options:0] options:0 error:nil];dispatch_async(dispatch_get_main_queue(),^{if(epoch!=self->_epoch)return;if(features.count&&bbox.count==4){[self installFeatures:features bbox:bbox];self->_note=@"联网路网就绪 · © OpenStreetMap · 非高德底图";}else self->_note=@"图源格式或容量不合格 · 已拒绝";});
 });
}
- (NSData *)scene:(NSArray *)coords origin:(NSArray *)origin{
 NSMutableArray *items=[NSMutableArray new];NSUInteger visited=0;
 for(NSDictionary *f in _features){if(++visited>10000)break;NSDictionary *p=f[@"properties"],*g=f[@"geometry"];if(![p[@"kind"] isEqual:@"road"]||![g[@"type"] isEqual:@"LineString"]||![g[@"coordinates"] isKindOfClass:NSArray.class])continue;
  if([Text(p[@"area"]) isEqual:@"yes"])continue;
  unsigned style=RoadStyle(Text(p[@"highway"]));for(NSArray *part in Pieces(g[@"coordinates"],origin,_convert,YES)){if(part.count<2)continue;double rank=DBL_MAX;for(NSUInteger i=1;i<part.count;i++){double x=[part[i-1][0] doubleValue],y=[part[i-1][1] doubleValue],dx=[part[i][0] doubleValue]-x,dy=[part[i][1] doubleValue]-y,t=MAX(0,MIN(1,-(x*dx+y*dy)/MAX(1,dx*dx+dy*dy)));rank=MIN(rank,hypot(x+dx*t,y+dy*t)/4);}NSString *bridge=Text(p[@"bridge"]),*tunnel=Text(p[@"tunnel"]);unsigned flags=(bridge.length&&![bridge isEqual:@"no"]?1:0)|(tunnel.length&&![tunnel isEqual:@"no"]?2:0);[items addObject:@{@"points":part,@"style":@(style),@"flags":@(flags),@"layer":@(MAX(-8,MIN(8,[Text(p[@"layer"]) intValue]))),@"name":Text(p[@"name:zh"]).length?Text(p[@"name:zh"]):Text(p[@"name"]),@"rank":@(rank+style*18)}];if(items.count>4096)break;}if(items.count>4096)break;
 }
 [items sortUsingComparator:^NSComparisonResult(id a,id b){return [a[@"rank"] compare:b[@"rank"]];}];
 NSMutableArray *route=[NSMutableArray new];for(NSArray *part in Pieces(coords,origin,nil,NO))if(part.count>=2)[route addObject:@{@"points":part,@"style":@6,@"flags":@0,@"layer":@8,@"rank":@0}];
 NSMutableArray *selected=[NSMutableArray new];NSUInteger points=0;for(NSDictionary *item in [route arrayByAddingObjectsFromArray:items]){NSArray *part=Simplify(item[@"points"]);if(selected.count>=TNR_MAX_PATHS||points+part.count>TNR_MAX_POINTS||16+8*(selected.count+1)+4*(points+part.count)+40*TNR_MAX_LABELS+12>TNR_MAX_BYTES-32)continue;points+=part.count;NSMutableDictionary *simple=[item mutableCopy];simple[@"points"]=part;[selected addObject:simple];}
 [selected sortUsingComparator:^NSComparisonResult(id a,id b){if([a[@"style"] intValue]==6||[b[@"style"] intValue]==6)return [a[@"style"] intValue]==[b[@"style"] intValue]?NSOrderedSame:[a[@"style"] intValue]==6?NSOrderedDescending:NSOrderedAscending;return [a[@"layer"] compare:b[@"layer"]];}];
 if(!selected.count||!points||_generation==UINT32_MAX)return nil;NSMutableData *out=[NSMutableData dataWithLength:16+8*selected.count+4*points];uint8_t *b=out.mutableBytes;W32(b,++_generation);W16(b+4,320);W16(b+6,(unsigned)selected.count);W16(b+8,(unsigned)points);NSUInteger at=16+8*selected.count;
 for(NSUInteger i=0;i<selected.count;i++){NSDictionary *r=selected[i];NSArray *part=r[@"points"];W16(b+16+8*i,(unsigned)part.count);b[18+8*i]=[r[@"style"] intValue];b[19+8*i]=[r[@"flags"] intValue];b[20+8*i]=(uint8_t)[r[@"layer"] intValue];for(NSArray *p in part){W16(b+at,[p[0] intValue]);W16(b+at+2,[p[1] intValue]);at+=4;}}
 /* Labels derive only from actual road tags. Keep at most four unique names,
  * with geographic anchors; firmware clips/culls collisions on every pose. */
 // Place names on visible points along actual road segments, not arbitrary end vertices.
 // Use the same heading transform and occlusion zones as the unchanged firmware.
 NSMutableData *labels=[NSMutableData new];NSMutableSet *seen=[NSMutableSet new];NSMutableArray *occupied=[NSMutableArray new];
 double radians=_labelHeading*M_PI/180,ss=sin(radians),cc=cos(radians);
 for(NSDictionary *item in [selected sortedArrayUsingComparator:^NSComparisonResult(id a,id b){return [a[@"rank"] compare:b[@"rank"]];}]){
  NSData *name=NameData(item[@"name"]);if(!name.length||[seen containsObject:name])continue;
  unsigned width=0;NSString *text=[[NSString alloc]initWithData:name encoding:NSUTF8StringEncoding];for(NSUInteger j=0;j<text.length;j++)width+=[text characterAtIndex:j]<128?9:16;
  NSArray *part=item[@"points"],*anchor=nil,*screenRect=nil;double best=DBL_MAX;
  for(NSUInteger j=1;j<part.count;j++)for(unsigned step=0;step<=16;step++){
   double t=step/16.,x=[part[j-1][0] doubleValue]*(1-t)+[part[j][0] doubleValue]*t,y=[part[j-1][1] doubleValue]*(1-t)+[part[j][1] doubleValue]*t;
   double px=96+(x*cc-y*ss)*192/1280.,py=101-(x*ss+y*cc)*192/1280.;double left=px-width/2.,top=py-10;
   if(left<7||left+width>185||top<7||top+20>137||(left<115&&left+width>77&&top<118&&top+20>79)||(left<74&&left+width>0&&top<147&&top+20>112))continue;
   BOOL collision=NO;for(NSArray *r in occupied){double rx=[r[0] doubleValue],ry=[r[1] doubleValue],rw=[r[2] doubleValue];if(left<rx+rw+8&&left+width+8>rx&&top<ry+28&&top+28>ry){collision=YES;break;}}if(collision)continue;
   double score=(px-96)*(px-96)+(py-48)*(py-48);if(score<best){best=score;anchor=@[@((int)lround(x)),@((int)lround(y))];screenRect=@[@(left),@(top),@(width)];}
  }
  if(!anchor)continue;uint8_t q[40]={0};W16(q,[anchor[0] intValue]);W16(q+2,[anchor[1] intValue]);q[4]=(uint8_t)name.length;memcpy(q+8,name.bytes,name.length);[labels appendBytes:q length:40];[seen addObject:name];[occupied addObject:screenRect];if(seen.count>=TNR_MAX_LABELS)break;
 }
 NSMutableData *v2=[out mutableCopy];[v2 appendData:labels];uint8_t pose[12]={0};W32(pose,_generation);[v2 appendBytes:pose length:12];W16((uint8_t *)v2.mutableBytes+10,(unsigned)seen.count);_scene2=tnr_body_valid(TNR_SCENE2,v2.bytes,v2.length)?v2:nil;
 return tnr_body_valid(TNR_SCENE,out.bytes,out.length)?out:nil;
}
- (NSDictionary *)decorate:(NSDictionary *)frame coordinates:(NSArray *)coords{
 if(!self.enabled||![frame[@"phase"] isEqual:@"navigating"]||coords.count<2||coords.count>512||!LL(frame[@"tnrLocation"])||!N(frame[@"tnrLocationAt"],0,DBL_MAX)||NSProcessInfo.processInfo.systemUptime-[frame[@"tnrLocationAt"] doubleValue]>4)return frame;
 NSArray *position=frame[@"tnrLocation"];NSArray *wgs=[self wgs:position];if(!LL(wgs)){_note=@"坐标转换未收敛 · 不显示错位路网";return frame;}
 BOOL covered=[self covers:wgs];if(!covered)covered=[self loadFixture:wgs];
 // Prefetch before the rendered viewport reaches an edge. Do not clear the old
 // region while a new request is queued, rate-limited, fails, or is parsing.
 if(![self hasCoverage:wgs margin:300]) [self request:wgs];
 if(covered)_note=_task?@"周边路网已显示 · 正在预取下一段":@"周边路网已就绪 · © OpenStreetMap";
 else _note=_task?@"正在加载周边道路 · 保留已知路网":self.allowNetwork?(_requests>=6?@"本次图源请求已达上限 · 仅显示已有道路":@"当前区域路网暂缺 · 保留已有道路"):@"未授权周边道路 · 仅显示已有道路";
 double now=NSProcessInfo.processInfo.systemUptime,heading=[frame[@"navHeading"] doubleValue],turn=fabs(fmod(heading-_labelHeading+540,360)-180);
 BOOL refreshNames=_features.count&&now-_sceneAt>=3&&(turn>=30||Distance(position,_origin?:position)>50||![self hasVisibleLabelsAt:position heading:(unsigned)heading]);
 if(!_scene||!_origin||Distance(position,_origin)>100||![_segment isEqual:frame[@"segment"]]||refreshNames){
  _origin=position;_segment=frame[@"segment"];_labelHeading=heading;_sceneAt=now;_scene=[self scene:coords origin:_origin];
 }
 if(!_scene)return frame;NSArray *xy=XY(position,_origin);double x=[xy[0] doubleValue]*4,y=[xy[1] doubleValue]*4;if(fabs(x)>2000||fabs(y)>2000)return frame;
 uint8_t pose[12]={0};W32(pose,_generation);W16(pose+4,(int)lround(x));W16(pose+6,(int)lround(y));W16(pose+8,[frame[@"navHeading"] unsignedIntValue]%360);
 NSMutableDictionary *out=[frame mutableCopy];out[@"tnrScene"]=_scene;if(_scene2)out[@"tnrScene2"]=_scene2;out[@"tnrPose"]=[NSData dataWithBytes:pose length:12];out[@"tnrPoseAt"]=frame[@"tnrLocationAt"];return out;
}
@end
