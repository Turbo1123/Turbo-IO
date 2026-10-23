# Android Phase 5c — TVP2 HD Casting (TVP1 HD strips) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the TVP2 "清晰投屏" phone side (tar2-display HDLink + FrameEncoder) to Android. It drives the glasses' native 540×220 HD window from a local video file or a test pattern.

**Architecture:**
- `Vp` (pure): player.c codec — TVP1/VPA1 32-byte header with wire CRC, PackBits-style compress/decompress, pixel CRC.
- `HdEncoder` (pure): FrameEncoder port from an 8-bit luma plane — fit or crop/zoom, 2/4/8/16 gray levels, 4 strips of 55 rows.
- `HdLink` (pure): TVPHDLink port — HELLO(HD_CAP)→OPEN→BEGIN/STRIP×4/COMMIT, PING, PAUSE/EXIT events, CLOSE.
- Glue:
  - `HdCast` holds the NativeTransfer message lease (business-15 binary through `sendMessage`), receives VPA1 replies, and runs the frame source on a worker.
  - `HdCastUI` is the page.

**Spec:**
- `official-addon/tar2-display/{HDLink.m,FrameEncoder.m,player.c,player.h,tests.m}` (root license; byte-identical to the GPL tar2-airplay copies, which are NOT used).
- Firmware `firmware-research/strix-1.0.5.5-tvp2/src/video-player-v1/{player.c,native.inc}`.

## Global Constraints

- **Wire:**
  - Header: "TVP1" (request) or "VPA1" (reply), v1, op@5, result@6, byte 7 zero, sid@8, seq@12, a@16, b@20, c@24, wire CRC@28 (CRC-32 over all bytes except 28..31), then data. ≤14999 B.
  - Ops: HELLO 1, OPEN 2, FRAME 3, PING 4, CLOSE 5, HD_BEGIN 6, HD_STRIP 7, HD_COMMIT 8, PAUSE 32, EXIT 33.
  - Results: OK 0, INVALID 1, BUSY 2, STALE 3, CRC 4, SESSION 5, RENDER 6.
  - The per-op validity rules are those of `valid()` in player.c.
- **HD:**
  - 540×220. Strips are 55 rows; `a = y | h<<16`, b = bits (2 or 4), c = CRC of the compressed data.
  - BEGIN: a = frameID, b = bits, c = pixelCRC (`vp_pixels_crc` at stride 540). COMMIT: a = frameID, c = pixelCRC.
  - HELLO a = 0x32445056. The glasses must answer a=540, b=220|1<<16 within 1 s, else "需要先刷 TVP2 清晰投屏固件；未打开眼镜页面". OPEN carries a = the glasses tick from the HELLO reply's c.
- **Link (HDLink.m):**
  - One packet in flight with a 3 s deadline. PING every 2 s while idle and ready.
  - BUSY on HD ops drops the frame (rejectedFrames++). Any other non-OK result stops the link.
  - The strip reply must have a = cumulative rows and c = cumulative bytes. The COMMIT reply must have a = frames+1 and c = verified+staged. The PING reply must have a ≤ 1, b = frames, c = verified.
  - A late reply never resumes. PAUSE/EXIT events need seq > lastEvent: PAUSE a=1 pauses and drops the frame, a=0 resumes, EXIT stops.
- **Encoder (FrameEncoder.m):**
  - Inputs are 1..4096 × 1..2160, zoom clamped to 1..4, centre clamped to 0..1.
  - Fit: scale = min(540/w, 220/h), centred, black bars. Crop: scale = max(…)·zoom, source window at the centre fraction.
  - Video-range luma becomes (v−16)·255/219 clamped. Quantize q = (v·(L−1)+127)/255; for L=8, q = (q·15+3)/7, shown as q·255/15; otherwise q·255/(L−1).
  - Bits are 2 for L ≤ 4, else 4, with q = gray·max/255 packed MSB-first.
  - Resampling is area-average (Android has no vImage); exact pixel match is checked against the player's decoding of our own strips, not against vImage.
- **Android lane:** `sendMessage` caps at 8192 B. A frame whose largest packet exceeds 8192 is re-encoded at 4 levels (2-bit strips always fit: ≤7484+32 B) and the note says so.
- **Source:** a local video file via `MediaMetadataRetriever.getScaledFrameAtTime` (no new permissions) or a moving test pattern. Target 1..10 fps; only the latest frame is kept and nothing is queued. Foreground page only.
- **Not in scope:** MediaProjection screen mirroring. The host manifest lacks a `mediaProjection` foreground service and the packager does not edit the manifest.

## Review Focus

1. Replies from a foreign peer or sid, stale sequence numbers, and late replies never advance the link.
2. A half-sent frame never displays (a strip error stops the frame or the link).
3. The lease is always released on stop, failure, page close or peer change, so other features are not blocked forever.
4. No packet sent exceeds the 8192 B lane.
5. The decode worker cannot pile up frames or leak the retriever.

---

### Task 1: Vp + HdEncoder

**Files:** Create `src/com/turboio/addon/{Vp,HdEncoder}.java`, `tests/HdTest.java` and `tests/hd_golden.c`.

**Tests:**
- The golden C writes `vp_encode` packets (HELLO with HD_CAP; HD_STRIP with a 100-byte payload; COMMIT; a VPA1 PING reply), `vp_compress` of three patterns (runs, literals, mixed 14850 B), and `vp_pixels_crc` of a gradient. Java must match byte for byte.
- `decode` rejects a CRC flip, byte 7 ≠ 0, op 9 request, and a reply with data.
- Encoder:
  - a 400×1000 fit gives content 88×220; crop with zoom 2 and the edge case both give width 540; levels 3 are refused;
  - 4 strips;
  - unpacking `decompress` of the strips reproduces `gray` exactly for levels 2/4/8/16;
  - pixelCRC equals `Vp.pixelsCrc(gray)`;
  - the 8 KiB fallback gives bits 2 when a strip is over 8160.

### Task 2: HdLink + oracle

**Files:** Create `HdLink.java`, `tests/HdLinkTest.java` and `tests/hd_oracle.c`.

The oracle is a minimal native.inc emulation over the real `vp_open`/`vp_hd` (stride 544): HELLO/OPEN/PING/CLOSE/HD ops. It reads `[now u32][len u32][bytes]` from stdin and writes `[n u32][reply]`, the active-pixel CRC (stride-aware `vp_pixels_crc`) and `displayed`.

**Tests (port of tests.m):**
- The handshake leads to ready. One frame is exactly 6 packets, gives frames 1 and verified = compressed bytes, and the oracle CRC equals the frame's pixelCRC.
- Close is clean. On old firmware (no HD flag) there is no OPEN, closedCleanly, and only 1 packet.
- A 3.1 s timeout leaves the link inactive and not clean.
- Pause event: the frame is dropped and the tick sends nothing; unpause, then a mismatched reply stops the link.
- A foreign peer or sid is ignored, and a BUSY on a strip drops the frame and increments rejectedFrames.

### Task 3: Glue

**Files:**
- Create `HdCast.java`: the lease, sendMessage, the receiver, a 50 ms tick, the worker with a MediaMetadataRetriever or the pattern, peer checks, and `active()`.
- Create `HdCastUI.java`: start/stop, pick video, levels, fit/crop with zoom, fps, stats.
- Add `DocumentPicker.pickUri`.
- Add an `OfficialOtaBridge` guard and an entry in 设置 ("清晰投屏 · 实验").

Verify: `build.sh` is green, and packages 1.0.7 and 1.0.6 are clean.
