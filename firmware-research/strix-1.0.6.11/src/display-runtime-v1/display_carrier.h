#ifndef TURBO_DISPLAY_CARRIER_H
#define TURBO_DISPLAY_CARRIER_H
#include "display_runtime.h"
/* Existing Launcher business / generic command-reply PB envelope. The private
 * command is OUR extension, not an official firmware command. No new bus ID. */
enum { TDP_UPLINK_BUSINESS=15, TDP_UPLINK_TYPE=6, TDP_UPLINK_MAX=192,
       TDP_NATIVE_PACKET_MAX=512, TDP_NATIVE_PIXELS_MAX=472 };
size_t tdp_carrier_reply(const TDPReply *,uint8_t *,size_t);
/* Strict, canonical decode of our encoder only. Foreign events pass through. */
bool tdp_carrier_decode(unsigned business,const uint8_t *,size_t,TDPReply *);
#endif
