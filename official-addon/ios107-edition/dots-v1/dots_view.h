#ifndef TURBO_DOTS_VIEW_H
#define TURBO_DOTS_VIEW_H
#include "../navigation-runtime-v1/nav_view.h"
#define DOTS_COUNT 5u
#define DOTS_BODY 1024u
#define DOTS_ID 48u
#define DOTS_LABELS 8u
#define DOTS_TEXT 128u
enum DotsState { DOTS_SENT, DOTS_QUEUED, DOTS_WAITING, DOTS_RUNNING,
    DOTS_COMPLETED, DOTS_FAILED, DOTS_EXPIRED, DOTS_CANCELLED };
typedef struct {char id[DOTS_ID],body[DOTS_BODY];uint8_t role,state,truncated;} DotsMessage;
typedef struct {char conversation[DOTS_ID];uint64_t revision;uint8_t count;DotsMessage messages[DOTS_COUNT];} DotsSnapshot;
typedef struct {DotsSnapshot snapshot;uint8_t selected;uint16_t line;bool detail;} DotsModel;
typedef struct {TNWidgets api;void *root,*labels[DOTS_LABELS];char text[2][DOTS_LABELS][DOTS_TEXT];unsigned bank;bool open;} DotsView;
bool dots_snapshot_valid(const DotsSnapshot *);
// Caller has already validated the BLE peer/session. Never binds automatically
// from received data. Each connection/account/conversation change calls reset.
bool dots_model_reset(DotsModel *,const char *conversation);
bool dots_model_apply(DotsModel *,const DotsSnapshot *);
void dots_model_step(DotsModel *,int direction);
void dots_model_confirm(DotsModel *);
bool dots_model_back(DotsModel *); // true: detail->list; false: native owner exits
bool dots_view_open(DotsView *,const TNWidgets *,void *parent);
bool dots_view_draw(DotsView *,const DotsModel *);
bool dots_view_close(DotsView *);
void dots_view_detached(DotsView *);
#endif
