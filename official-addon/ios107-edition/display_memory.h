#ifndef TURBO_DISPLAY_MEMORY_H
#define TURBO_DISPLAY_MEMORY_H
#ifdef TDP_FREESTANDING
#include <stddef.h>
/* Resolved to hash-pinned native AP symbols by a future firmware adapter. */
void *memcpy(void *,const void *,size_t);
void *memset(void *,int,size_t);
int memcmp(const void *,const void *,size_t);
#else
#include <string.h>
#endif
#endif
