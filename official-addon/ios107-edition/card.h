#ifndef TURBO_DASHBOARD_CARD_H
#define TURBO_DASHBOARD_CARD_H
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#define DC_SURFACE "turbo_ui_devcard_v1"
#define DC_COMPONENT "root"
/* Versioned test template. RAM is tenths of GB, disk is GB. No credentials. */
typedef struct {unsigned weekly,claude5h,claudeWeek,ramFree,ramTotal,diskFree,diskTotal,icons[3];} DCValues;
bool dc_parse(const char *,size_t,DCValues *);
typedef struct {
 void *(*root)(void *parent);
 bool (*text)(void *,int,int,int,int,unsigned,const char *);
 bool (*icon)(void *,int,int,unsigned);
 bool (*bar)(void *,int,int,int,unsigned);
 bool (*line)(void *,int);
 void (*destroy)(void *);
} DCAPI;
void *dc_render(const DCAPI *,void *parent,const DCValues *);
#endif
