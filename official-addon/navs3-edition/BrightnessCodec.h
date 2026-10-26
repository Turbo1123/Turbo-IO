#import <Foundation/Foundation.h>
FOUNDATION_EXPORT NSData *TIOBrightnessPacket(BOOL query, NSInteger mode, NSInteger level);
FOUNDATION_EXPORT NSDictionary *TIOBrightnessReply(NSDictionary *event);
