#import <Foundation/Foundation.h>
// Bounded compiler ZIP only. Never extracts files, runs JS, or follows URLs.
NSDictionary *TAPReadPackage(NSData *zip, NSString **error);
NSData *TAPEncodeDocument(NSDictionary *document, NSString **error);
NSData *TAPPhoneCommand(unsigned op, uint32_t request, uint32_t session,
                       NSDictionary *package, NSDictionary *target, unsigned slot);
NSDictionary *TAPPhoneReply(NSData *data);
NSData *TAPEventBytes(NSDictionary *event);
NSString *TAPSHA256(NSData *data);
