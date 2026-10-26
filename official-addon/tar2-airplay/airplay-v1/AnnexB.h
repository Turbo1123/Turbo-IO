#ifndef TAR_ANNEXB_H
#define TAR_ANNEXB_H
#include <stddef.h>
#include <stdint.h>
typedef struct { const uint8_t *data; size_t length; } TARNAL;
/* Complete access units from UxPlay. Reject malformed / unbounded input. */
int tar_nals(const uint8_t *,size_t,TARNAL *,size_t);
#endif
