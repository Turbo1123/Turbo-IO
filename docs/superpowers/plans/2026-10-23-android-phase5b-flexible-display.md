# Android Phase 5b — Flexible Display (TDP1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the iOS 1.0.7 "灵活显示" lab (DisplayPhone*) for TVP2's `display-runtime-v1` (Turbo Display SID page). The lab offers:
- query the SID;
- renew the lease automatically;
- a 20×20 test mark;
- a full 512×128 gray canvas (139 chunks of 472 px);
- delta updates (24×16 tiles, ≤32 rects);
- close.

**Architecture:**
- `Tdp` (pure): TDP1 client encoders, TDR1 reply codec, the exact `turbo_display_v1` business-15 carrier, canonical packet validation, delta planning.
- `TdpSession` (pure): port of TDPPhoneSession and TDPDisplayReplyObserver, with an injected clock, sender and wake poster.
- Glue: `DisplayBridge` and `DisplayUI`.
  - Each packet is the file `turbo-display.tdp` (≤512 B) through `NativeTransfer.send(…, 5000 ms)`.
  - A matching TDR1 reply self-acks the shared gate: 0 if accepted, 1 if rejected.
  - The gate's terminal state is the session's file terminal.

**Tech Stack:** Java 8 add-on, C oracle for golden tests.

**Spec:**
- iOS: `official-addon/ios107-edition/{display_client.c,display_carrier.c,display_runtime.c,DisplayDelta.c,DisplayPhoneSession.m,DisplayReplyObserver.m,DisplayPhoneTransport.m,DisplayPhoneUI.m}`, tests `DisplayPhoneTests.m` and `DisplayFramePacingTests.m`.
- Firmware: `firmware-research/strix-1.0.5.5-tvp2/src/display-runtime-v1/` (`native_display_file.c`: name `turbo-display.tdp`, 32..512 B).

## Global Constraints

- **Packet:**
  - Header: "TDP1", v1, op@5, bytes 6/7 zero, sid@8, request@12 (non-zero), base@16, base+inc@20 (inc = 1 for RECT/BEGIN..ABORT), payload length@24, CRC-32 (reflected 0xEDB88320) of the payload@28.
  - QUERY: sid 0, length 0. KEEPALIVE/CLOSE: base = rev, length 0.
  - RECT: x,y,w,h LE16, then w·h px (w·h ≤ 16384).
  - BEGIN: tx, 65536, frame CRC. CHUNK: tx, offset, px. COMMIT/ABORT: tx.
  - Every packet sent is ≤512 B.
- **Reply TDR1 (40 B):** result ≤ ABORTED(10), bytes 6/7 zero, sid@8, request@12, revision@16, w@20, h@22, maxRect@24, lease@28, bytes 32..35 zero, CRC of 0..35 @36.
- **Carrier:** exactly `08 01 10 06 1a <len varint 2 B>` + `{"cmd":"turbo_display_v1","payload":{"value":0,"mode":0,"data":"<80 lowercase hex>"}}`, business 15.
- **Observer:**
  - CAPS is accepted only for the pending QUERY, with sid≠0, 512×128, 0 < maxRect ≤ 16384 and lease 120000.
  - max px/packet = min(maxRect, 472). The lease is held 110 s, with a 5 s pending deadline.
  - An unsolicited (request 0) CLOSED for our sid drops the session.
- **Session (TDPPhoneSession):**
  - One packet in flight. Each packet needs both the file terminal AND the expected reply (QUERY→CAPS, KEEPALIVE→ALIVE, CLOSE→CLOSED, RECT/COMMIT→UI_SUBMITTED with rev+1, BEGIN/CHUNK→STAGED with the same rev).
  - Deadlines: 5 s per packet, 25 s per full frame, 10 s per delta.
  - Lease: renew after QUERY, then every 30 s.
  - Timing: next packet 0.15 s after a single command, immediately inside a frame or delta (queued wake, never re-entered from a callback).
  - Pixel baseline is set only by a confirmed COMMIT and updated by confirmed RECTs.
  - Delta plans have ≤32 rects; if more, nothing is sent ("变化超过32个小区域…").
  - Losing the foreground stops the session. Any failure stops with no retry, and file packet count ≤512 per session.
- **UI copy:** the iOS strings verbatim (titles, notes, states). Diagnostics JSON files are not ported (status is shown on the page).

## Review Focus

1. A reply from a foreign peer, a stale request, or a sid that doesn't match is never accepted.
2. Neither the reply alone nor the file terminal alone advances the frame.
3. Leaving the page or backgrounding the app stops sending and lease renewal.
4. No packet is resent after an unknown result.
5. A display session in progress blocks other glasses features and OTA from interleaving.

---

### Task 1: Tdp wire + delta

**Files:** Create `src/com/turboio/addon/Tdp.java`, `tests/TdpTest.java` and `tests/tdp_golden.c`.

**Tests:**
- The C harness writes reference packets for fixed inputs from `display_client.c`: query(7); keepalive and close(sid 7392, req 9, rev 3); rect(4,4,20,20 X-pattern); begin(tx 5, crc of i%251); chunk(offset 472, 472 px); commit; abort. It also writes a carrier reply envelope from `tdp_carrier_reply` and a delta rect list from `tdp_delta_plan`/`tdp_delta_batch(limit 8)` for two fixed frames.
- Java must match these byte for byte.
- `carrierDecode` accepts the C envelope, and rejects any single-byte change of the envelope and the wrong business.
- `valid()` rejects a packet with byte 6 = 1 or a CRC flip.
- Encoders return null for out-of-range geometry.

### Task 2: TdpSession

**Files:** Create `TdpSession.java`, `tests/TdpSessionTest.java` and `tests/tdp_oracle.c`.

The oracle is a C process wrapping the unchanged `tdp_open(sid 7392)`/`tdp_handle`. It reads frames `[now_ms u32][len u32][bytes]` from stdin. For each, it writes the 40-byte TDR1 reply, then a CRC-32 of the active pixels and the revision. `len=0` re-emits only the status.

**Tests (ports of DisplayPhoneTests/FramePacing):**
- QUERY is refused while not in foreground.
- QUERY, then the reply and the file success, then the automatic KEEPALIVE; ready with sid 7392.
- A reply from a foreign peer is ignored.
- Test rect gives revision 1.
- A full frame is 141 packets, 139 chunks, revision 2, and the oracle pixel CRC equals the frame CRC.
- In every packet, neither ACK alone sends the next one; the order of the two ACKs alternates.
- CLOSE leads to not ready.
- A timeout while a file is pending gives busy with no new query until the file terminal arrives.
- Slow packets (0.30 s each) stop the frame at 25 s with fewer than 139 chunks.
- A file failure stops with no new send.
- Losing the foreground mid-frame stops it.
- Delta: after a full frame, changing one tile gives exactly 1 RECT, and the oracle CRC matches the new frame. Resending the same image is 0 packets. More than 32 tiles changed refuses with nothing sent.

### Task 3: Glue

**Files:**
- Create `DisplayBridge.java`. It owns the session per peer: a NativeTransfer sender, biz-15 replies, self-ack, a 50 ms tick while the page is open, a peer change disconnects, and `active()`.
- Create `DisplayUI.java`. It has the nav sample image via Canvas (arrow, metres, road text, mini map), PNG/JPEG pick (≤20 MiB, ≤16 MP, aspect fit), the confirm dialog for a full canvas, the delta buttons (80/60 m, left/right, same image), test rect, close, and a link to the 图片传输 lab.
- Modify `NativeTransfer` (`blocked`/`acquireMessages` honor `DisplayBridge.active()` except for `turbo-display.tdp`), the OTA idle checks, and add an entry in 设置 ("灵活显示 · 实验").

Verify: `build.sh` is green and package 1.0.7 is clean.
