#include "command.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
int main(void){
 uint8_t raw[24],bad[24];TDCommand q={TDQ_START,17,1,180000},got;
 assert(td_command_encode(q,raw,24));assert(td_command_decode(raw,24,&got));
 assert(got.op==q.op&&got.session==q.session&&got.sequence==q.sequence&&got.lease_ms==q.lease_ms);
 for(unsigned i=0;i<24;i++)for(unsigned bit=0;bit<8;bit++){
  memcpy(bad,raw,24);bad[i]^=1u<<bit;assert(!td_command_decode(bad,24,&got));
 }
 for(unsigned n=0;n<24;n++)assert(!td_command_decode(raw,n,&got));
 assert(!td_command_decode(NULL,24,&got));assert(!td_command_decode(raw,24,NULL));
 q=(TDCommand){TDQ_START,1,1,600000};assert(td_command_encode(q,raw,24));
 q.lease_ms++;assert(!td_command_encode(q,raw,24));q.lease_ms=0;assert(!td_command_encode(q,raw,24));
 q=(TDCommand){TDQ_STOP,17,2,0};assert(td_command_encode(q,raw,24)&&td_command_decode(raw,24,&got));
 q.lease_ms=1;assert(!td_command_encode(q,raw,24));q.lease_ms=0;q.session=0;assert(!td_command_encode(q,raw,24));
 q.session=17;q.sequence=0;assert(!td_command_encode(q,raw,24));q.sequence=1;q.op=3;assert(!td_command_encode(q,raw,24));
 puts("TD command PASS: roundtrip, bit corruption, lengths, lease and operation bounds");return 0;
}
