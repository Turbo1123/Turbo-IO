#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
// Only the official app's generated audio-share directory, never other apps.
FOUNDATION_EXPORT NSArray<NSDictionary *> *TIOPreparedAudioFiles(NSURL *home);
FOUNDATION_EXPORT NSURL * _Nullable TIOAudioShareCopy(NSURL *home, NSURL *source, NSError **error);
FOUNDATION_EXPORT NSURL * _Nullable TIOMarkdownShareFile(NSURL *home, NSString *title, NSString *text, NSError **error);
FOUNDATION_EXPORT void TIOInstallRecordingExportMenu(void);
NS_ASSUME_NONNULL_END
