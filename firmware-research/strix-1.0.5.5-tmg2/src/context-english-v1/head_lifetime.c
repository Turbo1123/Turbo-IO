#include "head_lifetime.h"
void ce_head_lifetime_init(CEHeadLifetime *s) {
    if(!s)return;
    *s=(CEHeadLifetime){0};s->magic=CE_HEAD_TAIL_MAGIC;
}
void ce_head_lifetime_command(CEHeadLifetime *s,unsigned op,uint32_t caller) {
    if(!s || s->magic!=CE_HEAD_TAIL_MAGIC || (op!=1 && op!=2))return;
    s->lease=0;s->last_op=op;s->last_caller=caller;
    if(s->sequence_lo==UINT32_MAX && s->sequence_hi==UINT32_MAX){s->exhausted=1;return;}
    if(++s->sequence_lo==0)++s->sequence_hi;
}
bool ce_head_lifetime_snapshot(const CEHeadLifetime *s,uint32_t monitor,CEHeadSnapshot *out) {
    if(!out)return false;
    if(!s || !monitor || s->magic!=CE_HEAD_TAIL_MAGIC) {
        /* Five bounded stores: do not turn a critical-section failure path
         * into an out-of-line libc/memclr dependency. */
        volatile CEHeadSnapshot *z=out;
        z->monitor=0;z->sequence_lo=0;z->sequence_hi=0;z->lease=0;z->exhausted=0;
        return false;
    }
    *out=(CEHeadSnapshot){monitor,s->sequence_lo,s->sequence_hi,s->lease,s->exhausted};
    return true;
}
bool ce_head_snapshot_unchanged(const CEHeadSnapshot *a,const CEHeadSnapshot *b) {
    return a && b && a->monitor && a->monitor==b->monitor && !a->exhausted && !b->exhausted &&
        a->sequence_lo==b->sequence_lo && a->sequence_hi==b->sequence_hi && a->lease==b->lease;
}
