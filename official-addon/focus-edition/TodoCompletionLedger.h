#import <Foundation/Foundation.h>

@interface TIOTodoCompletionLedger : NSObject

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;
- (BOOL)isPending:(NSString *)sourceID;
- (void)markPending:(NSString *)sourceID;
- (BOOL)shouldPresentConfirmation:(NSString *)sourceID;
- (void)markConfirmationPresented:(NSString *)sourceID;
- (void)resetConfirmationPresentation:(NSString *)sourceID;
- (void)clearPending:(NSString *)sourceID;
@property (nonatomic, readonly) NSUInteger pendingCount;

@end
