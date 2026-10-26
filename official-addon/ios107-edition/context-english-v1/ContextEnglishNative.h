#import <Foundation/Foundation.h>
#include "english_view.h"
// Convert validated candidates to a bounded native deck, not a serialized wire packet.
FOUNDATION_EXPORT BOOL CEFillNativeDeck(NSArray *cards, CEDeck *out, NSError **error);
// Explicit synthetic device-test content. No archive, model or network access.
FOUNDATION_EXPORT NSArray<NSDictionary *> *CEOfflineTestCards(NSUInteger limit);
