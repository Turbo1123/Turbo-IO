#import <Foundation/Foundation.h>
// Validate untrusted local/imported drafts before preview, serialization or I/O.
// This is not a firmware decoder and does not perform any device operation.
BOOL TCEValidateDraft(id draft, NSString **reason);
