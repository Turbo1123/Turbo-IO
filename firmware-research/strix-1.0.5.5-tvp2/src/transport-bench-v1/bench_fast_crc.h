#ifndef TB_FAST_CRC_H
#define TB_FAST_CRC_H
#include <stdint.h>
#include <stddef.h>
static inline uint32_t tb_crc_byte(uint32_t c,uint8_t b){static const uint32_t t[16]={0x0u,0x1db71064u,0x3b6e20c8u,0x26d930acu,0x76dc4190u,0x6b6b51f4u,0x4db26158u,0x5005713cu,0xedb88320u,0xf00f9344u,0xd6d6a3e8u,0xcb61b38cu,0x9b64c2b0u,0x86d3d2d4u,0xa00ae278u,0xbdbdf21cu};c^=b;c=(c>>4)^t[c&15];return (c>>4)^t[c&15];}
static inline uint32_t tb_fast_crc(const uint8_t *p,size_t n){uint32_t c=~0u;for(size_t i=0;i<n;i++)c=tb_crc_byte(c,p[i]);return ~c;}
#endif
