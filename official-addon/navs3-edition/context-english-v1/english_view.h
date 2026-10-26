#ifndef TURBO_ENGLISH_VIEW_H
#define TURBO_ENGLISH_VIEW_H
#include "english_session.h"
#include "../navigation-runtime-v1/nav_view.h"
// Owned, bounded UTF-8 text. No pointers into a transient BLE file buffer.
typedef struct {
    char english[32], quote[160], meaning[72], example[192];
    uint8_t generated;
} CECard;
typedef struct { uint8_t count; CECard cards[CE_MAX_CARDS]; } CEDeck;
#define CE_VIEW_LABELS 8u
#define CE_VIEW_TEXT_BYTES 256u
typedef struct {
    TNWidgets api;void *root,*labels[CE_VIEW_LABELS];
    char text[2][CE_VIEW_LABELS][CE_VIEW_TEXT_BYTES];
    unsigned bank;bool open;
} CEView;
bool ce_card_valid(const CECard *);
bool ce_deck_valid(const CEDeck *);
bool ce_view_open(CEView *,const TNWidgets *,void *parent);
bool ce_view_draw(CEView *,const CESession *,const CEDeck *);
bool ce_view_close(CEView *);
// Parent deletion callback: invalidates handles; does NOT touch freed LVGL objects.
void ce_view_detached(CEView *);
#endif
