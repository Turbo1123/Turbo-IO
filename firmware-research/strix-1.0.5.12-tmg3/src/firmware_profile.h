#ifndef TIO_FIRMWARE_1055_PROFILE_H
#define TIO_FIRMWARE_1055_PROFILE_H
/* Confirmed from stock allocation callsites and constructors. This header
 * describes source layout only; it does not approve function bindings. */
#define TIO_STOCK_MENU_BYTES 0xfcu
#define TIO_STOCK_HEAD_BYTES 0x68u
#define TIO_MENU_SCROLL_POSITION_OFFSET 0xb0u
#define TIO_MENU_EXTERNAL_ACTION_OFFSET 0xf0u
#define TIO_SYS_TIMEZONE_OFFSET 0x10u
#endif
