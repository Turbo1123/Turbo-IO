#pragma once
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct TIOHyMT TIOHyMT;
typedef struct TIOHyMTRequest TIOHyMTRequest;
enum { TIO_HY_OK = 0, TIO_HY_INVALID = 1, TIO_HY_LOAD = 2, TIO_HY_CONTEXT = 3,
       TIO_HY_CANCELLED = 4, TIO_HY_TIMEOUT = 5, TIO_HY_LIMIT = 6, TIO_HY_DECODE = 7,
       TIO_HY_BUSY = 8 };
typedef struct { double first_token_ms, total_ms; int32_t prompt_tokens, output_tokens; } TIOHyMTMetrics;
// Synchronous worker callback. Bytes are a cumulative, provisional UTF-8 prefix;
// a codepoint may straddle tokens. Never retain the pointer or treat it as final.
typedef void (*TIOHyMTPartial)(const char *bytes, size_t length, void *context);
// One owner serial queue for load/translate/free. Only request_cancel is cross-thread.
// Do not free a request until the corresponding load/translate has returned.
TIOHyMTRequest * tio_hymt_request_new(int32_t timeout_ms);
void tio_hymt_request_cancel(TIOHyMTRequest * request);
void tio_hymt_request_free(TIOHyMTRequest * request);
// Caller MUST verify the pinned adapted SHA before load. No download or networking here.
TIOHyMT * tio_hymt_load(const char * model_path, int32_t threads, TIOHyMTRequest * request, int32_t * status);
void tio_hymt_free(TIOHyMT * engine);
// Plain UTF-8 text, canonical target name (e.g. Chinese/English), <= 4 KiB.
// On any failure output is empty; token limit is NOT reported as a completed translation.
int32_t tio_hymt_translate(TIOHyMT * engine, TIOHyMTRequest * request,
    const char * text, const char * target_language, int32_t max_tokens,
    char * output, size_t output_capacity, TIOHyMTMetrics * metrics);
int32_t tio_hymt_translate_stream(TIOHyMT * engine, TIOHyMTRequest * request,
    const char * text, const char * target_language, int32_t max_tokens,
    char * output, size_t output_capacity, TIOHyMTMetrics * metrics,
    int32_t threads, TIOHyMTPartial partial, void *context);
#ifdef __cplusplus
}
#endif
