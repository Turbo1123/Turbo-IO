#import <Foundation/Foundation.h>
// Main-thread runtime context only. Neither a connected-state assertion nor a
// saved session. Each operation must still require its own device response.
void TIOProtocolObserveCall(id plugin,NSString *method,NSDictionary *args);
void TIOProtocolObserveEvent(NSDictionary *event);
id TIOProtocolPlugin(void);
NSString *TIOProtocolDevice(void);
NSDictionary *TIOProtocolRoute(NSInteger business);
// Version/device scoped, sanitized templates only. No payload text, paths,
// device identifiers, credentials, old session IDs or live-ready flags on disk.
NSDictionary *TIOProtocolTemplate(NSString *kind,NSString *device);
BOOL TIOProtocolSaveTemplate(NSString *kind,NSString *device,NSDictionary *value);
NSDictionary *TIOProtocolSanitize(NSString *kind,NSDictionary *value);
NSDictionary *TIOProtocolDefaultSubtitle(void);
// Built-in auto-scroll layout from the 1.0.5(201) official sample; never a
// connection, transfer or playback receipt. Caller still needs live ACKs.
NSDictionary *TIOProtocolDefaultTeleprompter(NSDictionary *hostInfo);
