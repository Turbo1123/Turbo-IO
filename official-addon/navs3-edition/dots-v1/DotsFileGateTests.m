#import "DotsFileGate.h"
#include <assert.h>
static NSDictionary *args(void){return @{@"deviceId":@"fake-peer",@"filePath":@"/fake/path/book.txt"};}
static NSDictionary *event(NSString *native){return @{@"eventType":@"fileShareSuccess",@"device":@{@"id":@"fake-peer"},@"taskId":native,@"role":@"sender",@"fileName":@"book.txt"};}
int main(void){@autoreleasepool{
    TDDotsFileGate *gate=[TDDotsFileGate new];assert([gate acquire]);
    assert([gate blocksMethod:@"rayneonet_sendFile" scoped:NO]);assert(![gate blocksMethod:@"rayneonet_sendFile" scoped:YES]);
    for(NSString *method in @[@"rayneonet_sendMessage",@"rayneonet_disconnect",@"settings"]){assert(![gate blocksMethod:method scoped:NO]);}
    [gate releaseLease];
    for(unsigned i=0;i<200;i++){
        NSString *ticket=[gate willSend:args()];assert(ticket&&![gate acquire]);
        [gate observe:event(@"sdk-id")];assert(![gate acquire]);
        [gate submitted:ticket result:@{@"success":@YES,@"taskId":@"sdk-id"}];assert([gate acquire]);[gate releaseLease];
    }
    NSString *ticket=[gate willSend:args()];[gate submitted:ticket result:@{@"success":@YES,@"taskId":@"sdk-next"}];
    [gate observe:event(@"wrong")];assert(![gate acquire]);
    NSMutableDictionary *failed=[event(@"sdk-next")mutableCopy];failed[@"eventType"]=@"fileShareFailed";[failed removeObjectForKey:@"fileName"];
    [gate observe:failed];assert([gate acquire]);[gate releaseLease];
    ticket=[gate willSend:args()];[gate submitted:ticket result:@{@"success":@NO}];assert(![gate acquire]);
    assert(![gate blocksMethod:@"rayneonet_sendFile" scoped:NO]); // unknown official work blocks ONLY Dots
    for(unsigned i=0;i<40;i++)[gate willSend:args()];assert(![gate acquire]);assert(![gate blocksMethod:@"rayneonet_sendMessage" scoped:NO]);
    puts("PASS: Dots file lease; 200 foreign early-result cycles, exact IDs, failure without filename, bounded unknown work, no broad official block.");
}return 0;}
