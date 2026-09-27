#ifndef TURBO_NAV_RUNTIME_H
#define TURBO_NAV_RUNTIME_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
/* New, private protocol. NOT accepted by the currently flashed TDP1 firmware.
 * Call only on the Launcher/UI executor, after paired-source validation. */
#define TN_PACKET_MAX 512u
#define TN_POINTS_MAX 32u
#define TN_ROAD_MAX 96u
#define TN_TURN_MAX 48u
#define TN_IDLE_MS 60000u
#define TN_LINK_MS 30000u
enum TNOp { TN_START=1,TN_UPDATE=2,TN_HEARTBEAT=3,TN_STOP=4,TN_MODE=5,TN_QUERY=6 };
enum TNResult { TN_OK=0,TN_BAD_PACKET=1,TN_UNAUTHORIZED=2,TN_BUSY=3,TN_STALE=4,TN_UI_FAILED=5,TN_NO_SESSION=6 };
enum TNPower { TN_POWER_RELEASE=0,TN_POWER_WAKE_HOLD=1,TN_POWER_SLEEP=2 };
enum TNMode { TN_SMART=0,TN_ALWAYS=1 };
enum TNIcon { TN_UNKNOWN=0,TN_STRAIGHT,TN_LEFT,TN_RIGHT,TN_SLIGHT_LEFT,TN_SLIGHT_RIGHT,
 TN_SHARP_LEFT,TN_SHARP_RIGHT,TN_UTURN,TN_ROUNDABOUT,TN_ARRIVE,TN_ICON_COUNT };
typedef struct { uint16_t x,y; } TNPoint; /* normalized 0..1023, not GPS coordinates */
typedef struct {
 uint32_t distance_m,remaining_m,remaining_s;
 uint16_t heading;TNPoint position;
 uint8_t icon,point_count,mode;
 char road[TN_ROAD_MAX+1],turn[TN_TURN_MAX+1];
 TNPoint points[TN_POINTS_MAX];
} TNScene;
typedef struct {
 void *ctx;
 bool (*available)(void *); /* native business/OTA/recording/assistant conflict gate */
 bool (*enter)(void *,const TNScene *); /* prepare and enter navigation, NOT test page */
 bool (*render)(void *,const TNScene *,bool stale); /* complete update in one UI turn */
 bool (*power)(void *,enum TNPower); /* own token only; never unlock another app */
 void (*leave)(void *); /* release native view ownership; no forced global screen off */
} TNUI;
typedef struct {
 TNScene scene;
 uint32_t sid,sequence,digest,last_sid,last_link,last_update,last_button;
 bool active,connected,awake,held,stale,button_valid;
 uint8_t last_result;
} TNRuntime;
typedef struct { enum TNResult result;uint32_t sid,sequence;bool active,awake,stale;uint8_t mode; } TNReply;
void tn_init(TNRuntime *);
TNReply tn_receive(TNRuntime *,const TNUI *,const uint8_t *,size_t,uint32_t now,bool paired);
void tn_tick(TNRuntime *,const TNUI *,uint32_t now);
bool tn_button_wake(TNRuntime *,const TNUI *,uint32_t now);
void tn_disconnect(TNRuntime *,const TNUI *);
void tn_local_exit(TNRuntime *,const TNUI *);
size_t tn_encode(uint8_t *,size_t,enum TNOp,uint32_t sid,uint32_t sequence,const TNScene *);
size_t tn_reply_encode(uint8_t *,size_t,TNReply);
uint32_t tn_crc(const uint8_t *,size_t);
bool tn_packet_valid(const uint8_t *,size_t);
#endif
