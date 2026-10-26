#import <Foundation/Foundation.h>
#import "ResearchCatalog.h"
int main(int argc,const char **argv){@autoreleasepool{
    if(argc!=3)return 2;
    NSArray *sections=TIOResearchSections(@"library");
    NSUInteger count=0;NSDictionary *entry=nil;
    for(NSDictionary *s in sections)for(NSDictionary *r in s[@"rows"])if([r[@"key"]isEqual:@"dots"]){count++;entry=r;}
    if(count!=1){fprintf(stderr,"FAIL: Dots missing or duplicated in actual grouped catalog\n");return 1;}
    if(![sections.firstObject[@"rows"][0][@"key"]isEqual:@"dots"]||![entry[@"section"]isEqual:@(-2)]||![entry[@"row"]isEqual:@28])return 1;
    // Match the actual settings-row definition and dispatcher, not the legacy
    // catalog alone. Runtime table data above must resolve the editorial route.
    NSString *shell=[NSString stringWithContentsOfFile:[NSString stringWithUTF8String:argv[1]] encoding:NSUTF8StringEncoding error:nil];
    NSString *addon=[NSString stringWithContentsOfFile:[NSString stringWithUTF8String:argv[2]] encoding:NSUTF8StringEncoding error:nil];
    if(![shell containsString:@"@[@\"对话与工具\",@[@\"Dots 消息\",@\"dots\",@\"bubble.left.and.bubble.right\"]"]||
       ![shell containsString:@"else EditorialRoute(self,self.pages,key)"]||
       ![addon containsString:@"if([r[@\"key\"] isEqual:@\"dots\"]){[self.navigationController pushViewController:TIOGetDotsPanel() animated:YES];return;}"])return 1;
    NSMutableSet *keys=[NSMutableSet new];
    for(NSDictionary *s in sections)for(NSDictionary *r in s[@"rows"]){if([keys containsObject:r[@"key"]])return 1;[keys addObject:r[@"key"]];}
    for(NSString *key in @[@"music",@"weread",@"navigation",@"contextEnglish",@"recordings",@"lifelogText"])if(![keys containsObject:key])return 1;
    puts("PASS: Dots visible in actual grouped catalog, first settings route connected, retained routes present");
}return 0;}
