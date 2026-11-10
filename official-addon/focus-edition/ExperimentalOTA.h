#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
// Embedded pinned candidate descriptor (candidates/*.json, generated into
// OTACandidate.gen.m). nil when missing or structurally invalid: every
// consumer below then fails closed.
FOUNDATION_EXPORT NSDictionary * _Nullable TIOOTACandidate(void);
// Immutable verified payloads for a single explicitly authorized transfer.
NSDictionary<NSString *,NSData *> * _Nullable TIOCopyExperimentalOTAPayloads(NSURL *directory,NSError **error);
// Fixed reviewed candidate only. Integrity approval never means authorization to flash.
FOUNDATION_EXPORT NSString *TIOExperimentalOTASHA(void);
FOUNDATION_EXPORT NSDictionary * _Nullable TIOCheckExperimentalOTA(NSData *data, NSError **error);
FOUNDATION_EXPORT NSDictionary * _Nullable TIOReadExperimentalOTA(NSURL *file, NSError **error);
FOUNDATION_EXPORT NSDictionary * _Nullable TIOImportExperimentalOTA(NSURL *source, NSURL *directory, NSError **error);
// Point-in-time read-only snapshot, NOT a frozen transfer session or flash approval.
FOUNDATION_EXPORT NSDictionary * _Nullable TIOCheckExperimentalOTADirectory(NSURL *directory, NSError **error);
NS_ASSUME_NONNULL_END
