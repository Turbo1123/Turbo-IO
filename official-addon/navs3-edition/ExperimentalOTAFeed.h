#import <Foundation/Foundation.h>

// Private loopback source, not a flasher. No Bluetooth calls or official cache writes.
// Production arming remains compile-time disabled until same-version cache and
// official host acceptance are verified. Test executables explicitly opt in.
@interface TIOExperimentalOTAFeed : NSObject
@property(nonatomic,readonly) uint16_t port;
- (BOOL)startOnPort:(uint16_t)port error:(NSError **)error;
- (BOOL)armArchive:(NSURL *)archive lifetime:(NSTimeInterval)seconds error:(NSError **)error;
- (void)disarm;
- (void)stop;
- (NSDictionary *)status;
// Bounded loopback HTTP round-trip; call off main, never authorizes anything.
- (BOOL)checkHealth;
@end
// Opt-in package marker plus exact host/path checks; normal builds never listen.
void TIOStartExperimentalOTAFeedIfMarked(void);
NSDictionary *TIOExperimentalOTAFeedStatus(void);
BOOL TIOBeginExperimentalOTAPreparation(NSError **error);
void TIOCancelExperimentalOTAPreparation(void);
void TIORefreshExperimentalOTAReport(void);
