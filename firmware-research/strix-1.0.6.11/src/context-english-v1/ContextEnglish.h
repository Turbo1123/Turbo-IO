#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
// Pure functions. No database access, network requests, or credential handling.
// `rows` uses the extension's final-transcripts schema; time is RECEIPT time.
FOUNDATION_EXPORT NSDictionary * _Nullable CEPrepareDay(NSArray *rows, NSString *day,
    NSTimeZone *zone, NSString *target, NSUInteger count, NSError **error);
// Only call after the user has approved this exact selected-source snapshot.
FOUNDATION_EXPORT NSDictionary * _Nullable CEModelRequest(NSDictionary *selection,
    NSString *model, BOOL approved, NSError **error);
// Validates candidate content, not linguistic correctness or exam-list membership.
FOUNDATION_EXPORT NSArray<NSDictionary *> * _Nullable CEValidateResponse(
    NSDictionary *response, NSDictionary *selection, NSError **error);
NS_ASSUME_NONNULL_END
