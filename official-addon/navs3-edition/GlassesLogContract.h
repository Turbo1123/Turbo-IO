#import <Foundation/Foundation.h>
// Offline contract validation only. No hooks, device commands, uploads or deletes.
NSDictionary *TIOGlassesLogAck(NSDictionary *event, NSString *deviceID);
NSString *TIOGlassesLogTaskID(id value);
NSDictionary *TIOGlassesLogFile(NSDictionary *event, NSString *deviceID, NSString *taskID);
// Validate an existing regular file inside a caller-supplied private sandbox.
// Does not open/copy it: a future copier must independently revalidate at open time.
NSURL *TIOGlassesLogLocalURL(NSDictionary *candidate, NSURL *sandbox, NSUInteger limit);
BOOL TIOGlassesLogWindowValid(NSTimeInterval started, NSTimeInterval now, BOOL active, BOOL pending);
NSURL *TIOGlassesLogCopy(NSDictionary *candidate, NSURL *sandbox, NSURL *destinationDirectory, NSUInteger limit);
