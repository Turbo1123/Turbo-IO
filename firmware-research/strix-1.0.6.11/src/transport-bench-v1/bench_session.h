#ifndef TB_BENCH_SESSION_H
#define TB_BENCH_SESSION_H
#include "bench_wire.h"
typedef struct {TBReceiver receiver;uint32_t ticket,ticket_ms;} TBSession;
/* Fully decoded commands only. Caller must first verify peer/transport identity,
 * own the UI-thread executor and provide a fresh nonzero random HELLO ticket.
 * allowed means no conflicting task/OTA and test ownership is still valid.
 * true means emit reply; false means no ACK yet, not transport failure. */
bool tb_session_command(TBSession *,const TBPacket *,uint32_t now,
                        bool allowed,uint32_t fresh_ticket,TBPacket *reply);
TBResult tb_session_tick(TBSession *,uint32_t now,bool allowed);
void tb_session_stop(TBSession *);
#endif
