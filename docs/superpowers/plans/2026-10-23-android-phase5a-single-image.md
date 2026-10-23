# Android Phase 5a — Single Image to Glasses (TIMG) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the iOS 1.0.7 "图片传输 · 实验" lab (ImageUpload*) for TVP2's built-in Turbo Image RX page.

TVP2 builds `image-upload-test` with `TIO_IMAGE_RX_WIDE=1`: TIMG v2, 512×128 8-bit gray, 65536 pixels plus a 32-byte header, file `turbo-photo.timg`.

The flow:
1. The user picks a PNG or JPEG.
2. The phone shows a 512×128 preview: aspect fit, black bars, gray.
3. The user opens Turbo Image RX on the glasses and types the decimal session ID shown there.
4. Within 30 s the phone sends one frame.

**Architecture:**
- `Timg` (pure): fit rectangle, luma, the TIMG v2 packet with CRC, golden-checked against the firmware receiver.
- `ImageUpload` (pure): port of the iOS state machine.
- Glue: `ImageUploadUI` decodes through Android `ImageDecoder`/`BitmapFactory` and a Canvas, and sends through `NativeTransfer`.

The receiver sends no app-level ACK; the Android carrier self-acks right after submission, so CONFIRMED means file delivery only (iOS: "文件成功回执已收到；没有自动显示 ACK").

**Spec:** `official-addon/ios107-edition/ImageUpload.m`, `ImageUploadUI.m`, `ImageUploadTransport.m`, `ImageWireFormat.h`; firmware `firmware-research/strix-1.0.5.5-tvp2/src/image-upload-test/` (image_receiver.c: name, session, frame > last, ≥1 s apart, 30 s window).

## Global Constraints

- **Packet:**
  - Header: `"TIMG",2,1,32,0`, then w 512, h 128, stride 512 (LE16 each), 0,0, pixels 65536 (LE32), frame (LE32) at 20, session (LE32) at 24, CRC-32 of the pixels at 28. The pixels follow.
  - Session and frame are non-zero.
- **Pixels:** aspect fit into 512×128, centered, with black bars. Luma = (299R+587G+114B)/1000. The source is decoded with a bounded sample size (≤ 16 MP, ≤ 20 MiB file).
- **State (TIOImageUpload):**
  - `authorize(device, session, now)` opens a 30 s window.
  - One send at a time, at least 1 s between frames.
  - File success means "file_received_waiting_renderer".
  - Failure means "file_failed"; 15 s, or the window ending, means "timeout_result_unknown" with no retry.
  - A disconnect while pending means "disconnected_result_unknown".
- **One frame per window. No OTA, no upload.**

## Review Focus

1. Nothing is sent without a manually entered session in the 30 s window.
2. No blind retries.
3. An oversized or invalid image is refused.
4. The packet matches the firmware's validation exactly.
5. Nothing can crash the host while decoding large images.

---

### Task 1: Timg + ImageUpload core

**Files:** Create `src/com/turboio/addon/{Timg,ImageUpload}.java`, `tests/TimgTest.java` and `tests/timg_golden.c`.

**Tests:**
- The golden harness compiles `image_receiver.c` and `image_mailbox.c` with `-DTIO_IMAGE_RX_WIDE=1` and feeds it the Java packet. Accepted: session 77, frame 1. Refused: frame 0; frame not increasing; the wrong session; the wrong name length.
- The header bytes and CRC are checked against hand-derived values.
- fit: a 1024×1024 source gives a 128×128 area centered at x 192.
- luma: pure white is 255.
- The state machine:
  - authorize, then send, then file success gives "file_received_waiting_renderer";
  - a second send inside 1 s is refused;
  - a send after 30 s gives "session_expired";
  - pending past 15 s gives "timeout_result_unknown";
  - a disconnect while pending gives an unknown result.

### Task 2: ImageUploadUI

**Files:** Create `ImageUploadUI.java`, plus an entry in 设置 ("图片传输 · 实验").

Verify: `build.sh` is green and package 1.0.7 is clean.
