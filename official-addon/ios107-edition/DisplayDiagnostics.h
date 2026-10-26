#import <Foundation/Foundation.h>
// Opt-in, bounded numeric metadata only. No device IDs, task IDs, keys or content.
void TDPDiagConfigure(NSURL *file);
void TDPDiagRecord(NSString *event,NSDictionary *numbers);
void TDPDiagEnvelope(id event);
NSDictionary *TDPDiagSnapshot(void);
