#import "CueCardsCore.h"
#import <assert.h>
#import <stdio.h>

static NSDictionary *Card(NSString *ident,NSString *title,NSString *text) {
    return @{@"id":ident,@"title":title,@"points":@[@{@"text":text,@"important":@NO}]};
}
static NSDictionary *Project(void) {
    return TCCueProject(@{@"id":@"project-1",@"title":@"演讲",@"cards":@[
        Card(@"card-1",@"开场",@"先介绍主题。"),
        Card(@"card-2",@"重点",@"说明核心观点。"),
        Card(@"card-3",@"结束",@"总结并致谢。")
    ]},NULL);
}
static void paging_tests(void) {
    NSDictionary *project=Project();assert(project);
    TCCueCursor *cursor=[[TCCueCursor alloc] initWithProject:project];assert(cursor);
    NSDictionary *first=cursor.snapshot;assert([first[@"index"] unsignedIntegerValue]==0);
    assert(![cursor move:-1 session:first[@"session"] card:first[@"card"] revision:[first[@"revision"] unsignedIntegerValue]]);
    assert(![cursor move:1 session:@"other-session" card:first[@"card"] revision:0]);
    assert(![cursor move:1 session:first[@"session"] card:@"other-card" revision:0]);
    assert(![cursor move:1 session:first[@"session"] card:first[@"card"] revision:1]);
    assert([cursor move:1 session:first[@"session"] card:first[@"card"] revision:0]);
    NSDictionary *second=cursor.snapshot;assert([second[@"index"] unsignedIntegerValue]==1&&[second[@"revision"] unsignedIntegerValue]==1);
    assert(![cursor move:1 session:first[@"session"] card:first[@"card"] revision:0]);
    assert([cursor move:1 session:second[@"session"] card:second[@"card"] revision:1]);
    NSDictionary *last=cursor.snapshot;assert([last[@"index"] unsignedIntegerValue]==2);
    assert(![cursor move:1 session:last[@"session"] card:last[@"card"] revision:2]);
    assert(cursor.index==2&&[cursor.snapshot[@"revision"] unsignedIntegerValue]==2);
    assert([cursor move:-1 session:last[@"session"] card:last[@"card"] revision:2]);
}
static void bounds_tests(void) {
    NSDictionary *project=Project();
    assert(TCCueBody(project,0,1));assert(TCCueBody(project,2,1));
    assert(!TCCueBody(project,3,1));assert(!TCCueBody(project,0,0));
    NSArray *five=@[
        @{@"text":@"一",@"important":@NO},@{@"text":@"二",@"important":@NO},
        @{@"text":@"三",@"important":@NO},@{@"text":@"四",@"important":@NO},
        @{@"text":@"五",@"important":@NO}
    ];
    NSString *error=nil;assert(!TCCueLines(@{@"points":five},&error));assert([error containsString:@"超过眼镜一屏"]);
}
static void watch_route_tests(void) {
    NSTimeInterval now=1800000000;
    assert([TCCueWatchRouteAction(@{@"action":@"refresh"},now) isEqual:@"refresh"]);
    assert([TCCueWatchRouteAction(@{@"action":@"listProjects"},now) isEqual:@"listProjects"]);
    assert([TCCueWatchRouteAction(@{@"action":@"showCard",@"projectID":@"project-1",@"index":@1},now) isEqual:@"showCard"]);
    NSDictionary *fresh=@{@"issuedAt":@(now-1)};
    NSMutableDictionary *message=[@{@"action":@"addCard",@"projectID":@"project-1",@"title":@"新卡",@"copy":@"正文",@"afterCardID":@"card-1",@"requestID":@"request-1"} mutableCopy];
    [message addEntriesFromDictionary:fresh];assert([TCCueWatchRouteAction(message,now) isEqual:@"addCard"]);
    assert([TCCueWatchRouteAction(@{@"action":@"start",@"projectID":@"project-1",@"issuedAt":@(now-1)},now) isEqual:@"start"]);
    assert([TCCueWatchRouteAction(@{@"action":@"stop",@"issuedAt":@(now-1)},now) isEqual:@"stop"]);
    assert([TCCueWatchRouteAction(@{@"action":@"next",@"session":@"s",@"card":@"card-1",@"revision":@0,@"issuedAt":@(now-1)},now) isEqual:@"next"]);
    assert([TCCueWatchRouteAction(@{@"action":@"previous",@"session":@"s",@"card":@"card-2",@"revision":@1,@"issuedAt":@(now-1)},now) isEqual:@"previous"]);
    assert(!TCCueWatchRouteAction(@{@"action":@"addCard",@"projectID":@"project-1",@"issuedAt":@(now-1)},now));
    assert(!TCCueWatchRouteAction(@{@"action":@"next",@"session":@"s",@"revision":@0,@"issuedAt":@(now-1)},now));
    assert(!TCCueWatchRouteAction(@{@"action":@"stop",@"issuedAt":@(now-16)},now));
    assert(!TCCueWatchRouteAction(@{@"action":@"start",@"projectID":@"project-1",@"issuedAt":@(now+6)},now));
    assert(!TCCueWatchRouteAction(@{@"action":@"deleteAll"},now));
}
int main(void) {
    paging_tests();bounds_tests();watch_route_tests();
    puts("PASS cue-card line/body bounds, session and revision guarded paging, and WatchConnectivity command routing; offline only.");
    return 0;
}
