#ifndef TIO_UI_SCENE_H
#define TIO_UI_SCENE_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
enum { TUI_MAX_NODES=16,TUI_NODE_BYTES=64,TUI_HEADER_BYTES=32,TUI_TEXT_BYTES=40 };
enum { TUI_LABEL=1,TUI_BOX=2,TUI_ARROW=3,TUI_IMAGE=4,TUI_LINE=5 };
typedef struct {
 uint16_t id,x,y,w,h,action,text_len;uint8_t kind;
 uint32_t asset,value;char text[TUI_TEXT_BYTES+1];
} TUINode;
typedef struct {uint32_t session,scene,revision;unsigned count;TUINode nodes[TUI_MAX_NODES];} TUIScene;
typedef enum { TUI_OK,TUI_BAD_PACKET,TUI_BAD_NODE,TUI_STALE,TUI_MISSING_ASSET,TUI_BUSY,TUI_RENDER_ERROR } TUIResult;
typedef struct {
 void *ctx;
 bool (*asset_ready)(void *,uint32_t); // immutable/pinned resource ID, no path/address
 bool (*quiescent)(void *);
 // Transactional adapter: copy/retain inputs; on false dispose staging and
 // leave old root intact. On true replace old root only after render fence.
 // count=0 means detach/delete owned UI for close. No native implementation is
 // provided until lifetime contracts are verified.
 bool (*commit)(void *,const TUIScene *);
} TUISceneUI;
typedef struct {
 uint32_t session;uint16_t width,height;bool enabled;
 TUIScene active,staging; // persistent workspace: never allocate these on RTOS stack
} TUIRuntime;
// One verified UI executor only. Raw RX must first copy into a bounded queue.
bool tui_init(TUIRuntime *,uint32_t fresh_session,uint16_t width,uint16_t height);
TUIResult tui_apply(TUIRuntime *,const TUISceneUI *,const uint8_t *,size_t);
// Disables input/updates immediately; BUSY retains UI/assets for a later retry.
// Storage cannot be reinitialized/freed while close is incomplete.
TUIResult tui_close(TUIRuntime *,const TUISceneUI *);
// scene/revision prevents late input affecting the replacement scene.
uint16_t tui_action(const TUIRuntime *,uint32_t scene,uint32_t revision,uint16_t node);
#endif
