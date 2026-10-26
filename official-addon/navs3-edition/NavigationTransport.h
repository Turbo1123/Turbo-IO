#import <Foundation/Foundation.h>
void TIONavObserveCall(id plugin,NSString *method,NSDictionary *args);
void TIONavObserveEvent(NSDictionary *event);
void TIONavRefreshConnection(void);
void TIONavEnableDisplay(BOOL enabled);
void TIONavOfferDisplay(NSDictionary *display);
void TIONavPump(void);
NSDictionary *TIONavTransportStatus(void);
void TIONavEnableNotices(BOOL enabled);
void TIONavTestNotice(void);
