#import <Foundation/Foundation.h>
// Exact hosts observed in the user's official shelf URLs and HTTPS redirects.
// No wildcard Tencent/CDN trust, no credentials, no non-standard ports.
static inline NSURL *TWCoverURL(id value){
 if(![value isKindOfClass:NSString.class]||![value length]||[value length]>8192)return nil;
 NSURL *u=[NSURL URLWithString:value];
 if(![u.scheme.lowercaseString isEqual:@"https"]||u.user||u.password||u.fragment||(u.port&&u.port.integerValue!=443))return nil;
 return [@[@"cdn.weread.qq.com",@"res.weread.qq.com",@"weread-1258476243.file.myqcloud.com",@"wrco-40036.sh.gfp.tencent-cloud.com"]containsObject:u.host.lowercaseString]?u:nil;
}
#define TW_COVER_LIMIT (8u*1024u*1024u)
