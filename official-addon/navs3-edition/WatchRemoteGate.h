#import <Foundation/Foundation.h>
// Main-thread caller owns the gate. No offline queue, no arbitrary opcodes.
@interface TIOWatchGate : NSObject
- (BOOL)begin:(NSString *)session;
- (void)reset;
- (NSDictionary *)accept:(NSData *)data now:(double)now uptime:(double)uptime;
@end
