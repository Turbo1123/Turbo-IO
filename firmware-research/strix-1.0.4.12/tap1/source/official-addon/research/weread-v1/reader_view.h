#ifndef TURBO_WEREAD_VIEW_H
#define TURBO_WEREAD_VIEW_H
#include "reader.h"
#include "../navigation-runtime-v1/nav_view.h"
typedef struct {char header[128],footer[128],titles[4][100],lines[5][WR_LINE_BYTES];} WRViewText;
typedef struct {
 TNWidgets api;void *root,*header,*footer,*cards[4],*covers[4],*titles[4],*body,*lines[5];
 WRViewText text[2];unsigned front;bool open;
} WRView;
bool wr_view_open(WRView *,const TNWidgets *,void *);
bool wr_view_draw(WRView *,WRReader *);
bool wr_view_close(WRView *);
#endif
