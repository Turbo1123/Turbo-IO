#ifndef TURBO_ENGLISH_SCHEDULE_H
#define TURBO_ENGLISH_SCHEDULE_H
#include <stdbool.h>
#include <stdint.h>
// local_day = Gregorian local date expressed as days from a fixed epoch.
// Convert using the selected timezone on the phone; never use monotonic ticks.
typedef struct {uint32_t offered_day,highest_day;} CEReminderHistory;
typedef struct {uint32_t day,expires_unix;uint16_t minute;bool enabled;} CEReminderPlan;
typedef struct {uint32_t day,unix_time;uint16_t minute;bool worn,free_ui,dnd,content_ready;} CEReminderNow;
enum CEDue {CE_NOT_DUE,CE_MAY_INVITE};
enum CEDue ce_reminder_due(const CEReminderPlan *,const CEReminderHistory *,const CEReminderNow *);
// Call storage synchronously BEFORE showing. Failure must prevent the invitation.
// The caller serializes check+persist+publish on one executor.
bool ce_reminder_commit(const CEReminderPlan *,CEReminderHistory *,const CEReminderNow *,
                        bool (*persist)(void *,const CEReminderHistory *),void *);
#endif
