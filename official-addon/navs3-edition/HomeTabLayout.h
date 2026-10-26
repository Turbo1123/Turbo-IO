#import <Foundation/Foundation.h>
FOUNDATION_EXPORT NSString *TIOHomeTabName(NSString *label);
// Full touch-sized targets only. Collapse verified same-name descendants;
// never collapse unrelated full-button duplicates.
FOUNDATION_EXPORT NSArray<NSDictionary *> *TIOHomeTabCandidates(NSArray<NSDictionary *> *hits);
// Pure validation: only the four observed official tabs, in order, near the
// bottom of a portrait viewport. An incomplete/ambiguous tree is not a tab bar.
FOUNDATION_EXPORT NSDictionary *TIOHomeTabLayout(NSArray<NSDictionary *> *nodes,double width,double height,double safeBottom);
