#import <UIKit/UIKit.h>
#import "ImageUpload.h"
// Source-only experimental page. The caller supplies the verified native
// transport/session client. nil permits local pick/preview/export only.
UIViewController *TIOImageUploadController(TIOImageUpload *client);
#if TIO_IMAGE_RX_LAB
// One-shot manual-SID R4 lab only. No synthetic AP display acknowledgment.
UIViewController *TIOImageUploadLabController(void);
BOOL TIOImageUploadLabConsumeFileEvent(NSDictionary *event);
#endif
