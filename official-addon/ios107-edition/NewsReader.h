#import <Foundation/Foundation.h>
FOUNDATION_EXPORT NSString *TIONewsTopic(NSString *input);
FOUNDATION_EXPORT NSString *TIONewsPrompt(NSString *topic,NSDate *date);
FOUNDATION_EXPORT NSArray<NSString *> *TIONewsPages(NSString *text);
FOUNDATION_EXPORT NSString *TIONewsManuscript(NSString *text);
typedef void (^TIONewsCancel)(void);
typedef TIONewsCancel (^TIONewsFetch)(NSString *prompt,void (^completion)(NSString *text,NSString *error));
FOUNDATION_EXPORT void TIONewsConfigure(TIONewsFetch fetch);
FOUNDATION_EXPORT id TIONewsReaderController(void);
FOUNDATION_EXPORT void TIOOpenNewsReader(id parent);
// Observed official preview transport only; no microphone/start-record command.
FOUNDATION_EXPORT void TIONewsObserveSend(id plugin,NSDictionary *args);
FOUNDATION_EXPORT void TIONewsObserveReceive(NSDictionary *event);
FOUNDATION_EXPORT NSDictionary *TIONewsCaptionStatus(void);
FOUNDATION_EXPORT void TIONewsCaptionStart(void (^completion)(BOOL,NSString *));
FOUNDATION_EXPORT BOOL TIONewsCaptionText(NSString *text);
FOUNDATION_EXPORT void TIONewsCaptionStop(void);
