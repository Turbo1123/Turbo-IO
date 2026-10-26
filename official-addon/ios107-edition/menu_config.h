#ifndef TURBO_MENU_CONFIG_H
#define TURBO_MENU_CONFIG_H
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
enum { TML_QUERY=0,TML_SET=1,TML_OK=0,TML_BLOCKED=1,TML_SESSION=2,TML_STORAGE=3,TML_UNAVAILABLE=4 };
typedef struct {uint32_t request,token,generation,client;uint8_t op,rows;} TMLCommand;
typedef struct {uint32_t generation;unsigned rows,bank;bool readable;} TMLStored;
typedef struct {uint32_t token,client,issued;TMLStored stored;} TMLState;
typedef struct {void *ctx;int (*read)(void *,unsigned,uint8_t *,size_t);bool (*write)(void *,unsigned,const uint8_t *,size_t);} TMLIO;
uint32_t tml_crc(const uint8_t *,size_t);
bool tml_decode(const uint8_t *,size_t,TMLCommand *);
void tml_encode(uint8_t *,const TMLCommand *);
size_t tml_carrier(uint8_t *,const uint8_t *,bool);
bool tml_uncarrier(const uint8_t *,size_t,uint8_t *,bool);
TMLStored tml_load(const TMLIO *);
bool tml_store(const TMLIO *,TMLStored *,unsigned);
unsigned tml_accept(TMLState *,const TMLCommand *,uint32_t,uint32_t,bool,const TMLIO *);
void tml_reply(uint8_t *,const TMLState *,const TMLCommand *,unsigned);
unsigned fm_menu_rows(void);
void fm_relayout(unsigned);
#endif
