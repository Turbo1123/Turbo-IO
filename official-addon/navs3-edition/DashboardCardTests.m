#import "DashboardCard.h"
#import "A2UIProbe.h"
#include <assert.h>
int main(void){@autoreleasepool{
 NSDictionary *todo=@{@"id":@"3",@"type":@"native",@"name":@"todo"},*weather=@{@"id":@"1",@"type":@"native",@"name":@"weather"},*own=@{@"id":TDCIdentifier(),@"type":@"a2ui",@"name":@"Turbo"};
 NSDictionary *a=@{@"widgets":@[@3,@1],@"simple_mode":@0,@"widgets_v2":@[todo,weather,own]};
 NSDictionary *j=TDCMoveFirst(a);assert([j[@"payload"][@"value"] isEqual:@0]);
 NSDictionary *b=[NSJSONSerialization JSONObjectWithData:[j[@"payload"][@"data"] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
 assert(TDCOrderVerified(a,b));assert(([b[@"widgets_v2"] isEqual:@[own,todo,weather]]));assert(([a[@"widgets_v2"] isEqual:@[todo,weather,own]]));
 assert([TDCMoveFirst(b) isEqual:j]);
 for(id bad in @[@{},@{@"widgets_v2":@[todo,todo]},@{@"widgets_v2":@[@{@"id":TDCIdentifier(),@"type":@"native"}]}])assert(!TDCMoveFirst(bad));
 NSMutableDictionary *bad=[b mutableCopy];bad[@"widgets_v2"]=@[own,weather,todo];assert(!TDCOrderVerified(a,bad));bad[@"widgets_v2"]=@[own,todo];assert(!TDCOrderVerified(a,bad));bad=[b mutableCopy];bad[@"simple_mode"]=@1;assert(!TDCOrderVerified(a,bad));
 assert(TDCInstall(TDCDemoText(NO))&&TDCInstall(TDCDemoText(YES)));assert(!TDCInstall(@"TDC1;101;90;85;375;1280;1400;2000;0;1;2"));
 NSDictionary *install=TDCInstall(TDCDemoText(NO));NSData *packet=TDCRequest(7392,install);assert(packet.length<1500);assert([TIOA2UIDecode(packet)[@"json"] isEqual:install]);assert([TIOA2UIDecode(packet)[@"mode"] isEqual:@1]);assert(!TDCRequest(0,install));
 NSDictionary *extra=[NSJSONSerialization JSONObjectWithData:[install[@"payload"][@"data"][@"extras"] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];assert([extra[@"uiContent"][@"updateComponents"][@"components"] count]==1);
 puts("dashboard packet/stable-order/preservation/idempotence: PASS");
}}
