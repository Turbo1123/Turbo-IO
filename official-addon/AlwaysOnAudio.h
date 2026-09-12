#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSDictionary * _Nullable TIOAOStatus(void);
FOUNDATION_EXPORT BOOL TIOAOSetAudioSaving(BOOL enabled);
FOUNDATION_EXPORT NSArray<NSDictionary *> *TIOAOAudioFiles(NSURL *home);
FOUNDATION_EXPORT NSURL * _Nullable TIOAOAudioCopy(NSURL *home,NSURL *source,NSError **error);
FOUNDATION_EXPORT void TIOInstallAlwaysOnAudioMenu(void);
NS_ASSUME_NONNULL_END
