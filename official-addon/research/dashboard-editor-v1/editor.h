#ifndef TCE_EDITOR_H
#define TCE_EDITOR_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#define TCE_MAX_BYTES 2048
#define TCE_MAX_TEXT 2740
#define TCE_MAX_ITEMS 12
#define TCE_PIXEL_BUDGET 32768
enum {TCE_TEXT=1,TCE_IMAGE,TCE_PROGRESS,TCE_BAR,TCE_LINE,TCE_DIVIDER,TCE_FRAME};
typedef struct {uint8_t type,x,y,w,h,a,b;uint16_t length;const uint8_t *data;} TCEItem;
typedef struct {unsigned count,pixels;TCEItem items[TCE_MAX_ITEMS];} TCEDocument;
// Borrowed pointers: input must stay alive until rendering finishes.
bool tce_decode(const uint8_t *,size_t,TCEDocument *);
size_t tce_unbase64(const char *,size_t,uint8_t *,size_t);
bool tce_raster(const TCEItem *,uint8_t *,size_t);
#endif
