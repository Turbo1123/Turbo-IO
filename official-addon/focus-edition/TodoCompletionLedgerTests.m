#import "TodoCompletionLedger.h"
#include <assert.h>

int main(int argc,const char *argv[]) {@autoreleasepool {
    assert(argc==3);
    NSString *mode=[NSString stringWithUTF8String:argv[1]],*suite=[NSString stringWithUTF8String:argv[2]];
    assert([suite hasPrefix:@"io.turboio.todo.ledger-tests."]);
    NSUserDefaults *defaults=[[NSUserDefaults alloc]initWithSuiteName:suite];
    if([mode isEqual:@"cleanup"]){[defaults removePersistentDomainForName:suite];return 0;}
    if([mode isEqual:@"write"]){
        [defaults removePersistentDomainForName:suite];
        TIOTodoCompletionLedger *ledger=[[TIOTodoCompletionLedger alloc]initWithDefaults:defaults];
        assert(ledger.pendingCount==0);
        [ledger markPending:@"synthetic-device:7"];
        [ledger markPending:@"synthetic-device:7"];
        [ledger markPending:@""];
        [ledger markPending:@"synthetic-device:8"];
        assert(ledger.pendingCount==2);
        puts("PASS: pending Apple completion IDs saved without duplicates.");
    }else if([mode isEqual:@"read"]){
        TIOTodoCompletionLedger *ledger=[[TIOTodoCompletionLedger alloc]initWithDefaults:defaults];
        assert(ledger.pendingCount==2&&[ledger isPending:@"synthetic-device:7"]&&[ledger isPending:@"synthetic-device:8"]);
        [ledger markConfirmationPresented:@"synthetic-device:7"];
        assert(![ledger shouldPresentConfirmation:@"synthetic-device:7"]);
        [ledger resetConfirmationPresentation:@"synthetic-device:7"];
        assert([ledger shouldPresentConfirmation:@"synthetic-device:7"]);
        [ledger clearPending:@"synthetic-device:7"];
        assert(ledger.pendingCount==1);
        puts("PASS: a fresh process restores pending completion and clears only the confirmed ID.");
    }else if([mode isEqual:@"verify"]){
        TIOTodoCompletionLedger *ledger=[[TIOTodoCompletionLedger alloc]initWithDefaults:defaults];
        assert(ledger.pendingCount==1&&![ledger isPending:@"synthetic-device:7"]&&[ledger isPending:@"synthetic-device:8"]);
        [ledger clearPending:@"synthetic-device:8"];
        assert(ledger.pendingCount==0);
        puts("PASS: a later process reads the confirmed state and clears the final pending ID.");
    }else assert(0);
}return 0;}
