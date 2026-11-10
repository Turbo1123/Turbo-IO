#include "head_gate.h"
#include <string.h>
bool ce_head_init(CEHeadGate *g, CEHeadOps ops) {
    if(!g || !ops.claim || !ops.owns || !ops.register_callback || !ops.start ||
       !ops.unregister_callback || !ops.stop || !ops.release)return false;
    memset(g,0,sizeof *g);g->ops=ops;return true;
}
void ce_head_close(CEHeadGate *g) {
    if(!g)return;
    // Invalidate first: unregister/stop may synchronously deliver a queued event.
    g->epoch=0;
    if(g->registered){g->registered=false;g->ops.unregister_callback(g->ops.ctx);}
    if(g->started){g->started=false;if(g->claimed && g->ops.owns(g->ops.ctx))g->ops.stop(g->ops.ctx);}
    if(g->claimed){g->claimed=false;g->ops.release(g->ops.ctx);}
}
bool ce_head_sync(CEHeadGate *g, const CESession *s) {
    if(!g || !s)return false;
    if(!ce_wants_gesture(s)){ce_head_close(g);return false;}
    if(g->started && g->epoch==s->epoch && g->ops.owns(g->ops.ctx))return true;
    ce_head_close(g);
    if(!g->ops.claim(g->ops.ctx))return false;
    g->claimed=true;
    if(!g->ops.owns(g->ops.ctx)){ce_head_close(g);return false;}
    if(!g->ops.register_callback(g->ops.ctx)){ce_head_close(g);return false;}
    g->registered=true;
    if(!g->ops.start(g->ops.ctx)){ce_head_close(g);return false;}
    g->started=true;
    if(!g->ops.owns(g->ops.ctx)){ce_head_close(g);return false;}
    g->epoch=s->epoch;return true;
}
bool ce_head_accepts(const CEHeadGate *g, const CESession *s, uint32_t queued_epoch) {
    return g && s && g->started && g->registered && g->claimed &&
        g->epoch==s->epoch && queued_epoch==s->epoch && ce_wants_gesture(s) && g->ops.owns(g->ops.ctx);
}
