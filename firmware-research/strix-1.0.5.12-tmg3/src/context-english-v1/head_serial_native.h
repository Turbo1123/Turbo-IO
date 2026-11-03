#ifndef CE_HEAD_SERIAL_NATIVE_H
#define CE_HEAD_SERIAL_NATIVE_H
#include "head_gate.h"
#include "head_lifetime.h"
typedef struct {uint32_t monitor,token;bool subscribed;} CESerialHead;
/* A real reservation is distinct from a successful detector start. Original
 * notification commands preempt it. Requires ALL serial lifecycle hooks. */
CEHeadOps ce_serial_head_ops(CESerialHead *);
bool ce_serial_head_available(CESerialHead *);
int ce_serial_foreign(unsigned op,uint32_t original_caller);
void *ce_serial_publish(void *manager,void *replacement);
void *ce_serial_retire(void *manager);
void ce_serial_before_destroy(void *monitor);
#endif
