#ifndef TURBO_ENGLISH_SESSION_H
#define TURBO_ENGLISH_SESSION_H
#include <stdbool.h>
#include <stdint.h>
#define CE_MAX_CARDS 10u
enum CEPhase { CE_CLOSED, CE_INVITE, CE_QUESTION, CE_ANSWER, CE_DONE };
enum CEResult { CE_UNSEEN, CE_REMEMBERED, CE_FORGOTTEN, CE_SKIPPED };
enum CEAction { CE_YES=1, CE_NO=2, CE_STOP=3 };
typedef struct {
    uint32_t epoch, since, now;
    uint8_t phase, count, index, results[CE_MAX_CARDS];
    bool available;
} CESession;
void ce_init(CESession *s);
// Called on the UI thread only. Time is monotonic milliseconds, not wall time.
bool ce_invite(CESession *s, unsigned count, uint32_t now, bool available);
void ce_tick(CESession *s, uint32_t now);
// `epoch` is captured when the UI event is queued. Unknown/stale events fail shut.
bool ce_action(CESession *s, unsigned action, uint32_t epoch, uint32_t now);
void ce_availability(CESession *s, bool available, uint32_t now);
bool ce_wants_gesture(const CESession *s);
// Official UI callback already applies the user's inverse-mode setting.
// Restore PHYSICAL nod/ shake mapping locally; never change global preferences.
unsigned ce_head_action(unsigned mapped_event, unsigned current_mode);
#endif
