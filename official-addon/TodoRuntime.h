#import <Foundation/Foundation.h>
FOUNDATION_EXPORT void TIOInstallTodoRuntime(void);
FOUNDATION_EXPORT void TIOTodoObserveNlp(id listener,id response);
FOUNDATION_EXPORT NSDictionary *TIOTodoRuntimeStatus(void);
FOUNDATION_EXPORT NSString *TIOTodoCreateTestTask(void);
FOUNDATION_EXPORT void TIOOpenTodoRuntime(id parent);
FOUNDATION_EXPORT void TIOTodoSetChatContext(id listener,id response);
FOUNDATION_EXPORT BOOL TIOTodoIsToolDispatching(void);
FOUNDATION_EXPORT void TIOTodoCreateFromTool(NSString *title,void (^completion)(NSDictionary *result));
