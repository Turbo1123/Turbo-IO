#import <Foundation/Foundation.h>
#include "dots_view.h"
// Pure conversion only: no BLE, file transfer, wakeup or menu entry.
FOUNDATION_EXPORT BOOL TDMakeSnapshot(NSDictionary *recent,DotsSnapshot *output,NSError **error);
