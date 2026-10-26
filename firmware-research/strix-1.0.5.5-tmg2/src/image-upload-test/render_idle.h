#ifndef TIO_RENDER_IDLE_H
#define TIO_RENDER_IDLE_H
#include <stdbool.h>
#include <stdint.h>
typedef bool (*TIOReadWord)(uint32_t address,uint32_t *value);
typedef uint32_t (*TIONextDisplay)(uint32_t display);
/* Pinned 1.0.4.12, UI executor only. Conservative graph check, not a GPU reset
 * or flush-complete notification. Unknown units, malformed/cyclic lists and
 * any pending task are BUSY. Hardware fault recovery remains native. */
bool tio_render_graph_idle(TIOReadWord,TIONextDisplay);
#endif
