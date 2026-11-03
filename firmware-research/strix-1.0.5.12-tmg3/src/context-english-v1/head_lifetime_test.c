#include "head_lifetime.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
int main(void) {
    CEHeadLifetime s;CEHeadSnapshot a,b;
    memset(&s,0xa5,sizeof s);assert(!ce_head_lifetime_snapshot(&s,42,&a));
    ce_head_lifetime_init(&s);assert(s.magic==CE_HEAD_TAIL_MAGIC && s.lease==0);
    assert(ce_head_lifetime_snapshot(&s,42,&a));
    for(unsigned i=1;i<=100000;i++) {
        s.lease=99;ce_head_lifetime_command(&s,(i%2)+1,i);
        assert(s.lease==0 && s.sequence_lo==i && s.sequence_hi==0 && s.last_caller==i);
        assert(ce_head_lifetime_snapshot(&s,42,&b));
        assert(!ce_head_snapshot_unchanged(&a,&b));a=b;
    }
    ce_head_lifetime_command(&s,3,99);assert(ce_head_lifetime_snapshot(&s,42,&b));
    assert(ce_head_snapshot_unchanged(&a,&b));
    s.sequence_lo=UINT32_MAX;s.sequence_hi=5;
    ce_head_lifetime_command(&s,1,1);assert(s.sequence_lo==0 && s.sequence_hi==6);
    s.sequence_lo=UINT32_MAX;s.sequence_hi=UINT32_MAX;s.lease=55;
    ce_head_lifetime_command(&s,2,3);
    assert(s.exhausted==1 && s.lease==0 && s.sequence_lo==UINT32_MAX && s.sequence_hi==UINT32_MAX);
    assert(ce_head_lifetime_snapshot(&s,42,&a));assert(!ce_head_snapshot_unchanged(&a,&a));
    assert(!ce_head_lifetime_snapshot(&s,0,&a));assert(a.monitor==0);
    assert(!ce_head_lifetime_snapshot(NULL,42,&a));
    assert(!ce_head_snapshot_unchanged(NULL,&a));
    puts("PASS: head lifetime invalidation, 100000 commands, carry/saturation; no ownership claim");
}
