#ifndef TURBO_ENGLISH_PROGRESS_H
#define TURBO_ENGLISH_PROGRESS_H
#include "english_store.h"
#define CE_PROGRESS_BYTES 72u
#define CE_PROGRESS_ENVELOPE_MAX 256u
size_t ce_progress_encode(const CEProgress *,uint32_t tx,uint8_t *,size_t);
bool ce_progress_decode(const uint8_t *,size_t,CEProgress *,uint32_t *tx);
size_t ce_progress_envelope(const CEProgress *,uint32_t tx,uint8_t *,size_t);
#endif
