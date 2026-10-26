#ifndef TURBO_NAV_MAP_H
#define TURBO_NAV_MAP_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#define TNR_MAX_PATHS 96u
#define TNR_MAX_POINTS 768u
#define TNR_MAX_BYTES 4096u
#define TNR_W 192u
#define TNR_H 144u
#define TNR_STALE_MS 5000u
#define TNR_MAX_LABELS 4u
#define TNR_LABEL_BYTES 32u
#define TNR_BLEND_MS 180u
enum {TNR_SCENE=7,TNR_POSE=8,TNR_CLEAR=9,TNR_SCENE2=10};
typedef struct {int16_t x,y;} TNRPoint; /* quarter metres, east/north */
typedef struct {uint16_t first,count;uint8_t style,flags;int8_t layer;uint8_t reserved;} TNRPath;
typedef struct {TNRPoint p;char text[TNR_LABEL_BYTES];uint16_t width;} TNRLabel;
typedef struct {int16_t x,y;uint16_t width;char text[TNR_LABEL_BYTES];} TNRLabelView;
typedef struct {uint32_t generation;uint16_t range,path_count,point_count,label_count;TNRPath paths[TNR_MAX_PATHS];TNRPoint points[TNR_MAX_POINTS];TNRLabel labels[TNR_MAX_LABELS];} TNRScene;
typedef struct {TNRPoint p;uint16_t heading,age;uint32_t generation;} TNRPose;
typedef struct {
 TNRScene scenes[2];TNRPose from,target;
 uint32_t pose_at,last_draw;unsigned bank;bool valid,located,dirty,was_stale,pending;
} TNRState;
bool tnr_body_valid(unsigned op,const uint8_t *,size_t);
bool tnr_receive(TNRState *,unsigned op,const uint8_t *,size_t,uint32_t now);
bool tnr_position(const TNRState *,uint32_t now,TNRPose *);
bool tnr_stale(const TNRState *,uint32_t now);
bool tnr_needs_draw(const TNRState *,uint32_t now);
void tnr_draw(const TNRState *,uint32_t now,uint8_t out[TNR_W*TNR_H]);
void tnr_presented(TNRState *,uint32_t now);
unsigned tnr_labels(const TNRState *,uint32_t now,TNRLabelView out[TNR_MAX_LABELS]);
/* Horizontal map width in metres -> a bounded 1/2/5 scale bar. */
bool tnr_scale(unsigned range,unsigned *metres,unsigned *pixels);
size_t tnr_wrap(uint8_t *,size_t,unsigned op,uint32_t sid,uint32_t seq,const uint8_t *,size_t);
#endif
