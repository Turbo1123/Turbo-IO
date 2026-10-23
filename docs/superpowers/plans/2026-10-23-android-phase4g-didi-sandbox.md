# Android Phase 4g — Didi Sandbox Ride Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port iOS 1.0.7 "滴滴出行" (Ride*), which is sandbox only.
- **Flow:** search places, estimate, prepare a confirmation card on the glasses (TDR1 to the TVP2 `didi-v1` runtime), commit exactly once on a glasses or phone confirmation, then poll status or prepare a cancel.
- **Model tool:** the same flow is exposed as `didi_ride`.
- **Demo:** a demo card cycle with no network.

**Architecture:** Pure, JVM-tested cores:
- `DrWire`: TDR1 encode/decode and scene rules, DRA1 reply decode, golden against firmware `didi-v1/ride.c`.
- `DrText`: SafeMessage, normalizeOrder, messageLines, bounded field text.
- `DrTool`: spec and argument validation.
- `DrRpc`: the JSON-RPC body, SSE/JSON response parse, unwrap and error texts.
- `DrService`: the RideService state machine, with injected rpc, bridge, clock, store, peer and key.

The Android glue is `DrBridge` (NativeTransfer `turbo-ride.tdr`, replies `turbo_ride_v1` 32 B), `DrHttp` and `RideUI`. `ToolClient` registers `didi_ride` when a sandbox key is saved.

**Spec:** `official-addon/ios107-edition/ride.c/.h`, `RideRPC.m`, `RideService.m`, `RideStatus.m`, `RideTool.m`, `RideBridge.m`, `RideTransport.m`, `RideUI.m`; firmware `firmware-research/strix-1.0.5.5-tvp2/src/didi-v1/`.

## Global Constraints

- **TDR1 (392 B):**
  - Header: "TDR1", v1, op (SNAPSHOT 1 / CLOSE 2 / QUERY 3), sandbox byte 1, sid, seq, length 360, CRC (`tn_crc`, standard CRC-32 over the packet with the CRC field zero) at 20.
  - Scene: phase ≤ ERROR, flags ⊆ {SHOW 1, CONFIRM 2}, ttl 15..120; CONFIRM needs a nonce and phase QUOTE or CANCEL_CONFIRM.
  - Text fields NUL-terminated strict UTF-8 without controls: metric 32, title 64, line1 96, line2 96, footer 64.
- **DRA1 (32 B):** result ≤ NO_SESSION; event ≤ CLOSED (ACK 0, OPENED 1, CONFIRMED 2, CLOSED 3); byte 7 == 1; phase ≤ ERROR; consumed ≤ 1; bytes 22..27 zero; CRC at 28.
- **Bridge:**
  - One packet in flight with a 15 s deadline. The sid is persisted as max(now, last+1); seq is per session.
  - Success needs the file done plus an ACK with result OK.
  - CONFIRMED is accepted only with result OK, the nonce sent, consumed, and the pinned peer.
  - A peer change emits CLOSED.
- **RPC:**
  - `POST https://mcp.didichuxing.com/mcp-servers-sandbox?key=<key>` with `{"jsonrpc":"2.0","id","method":"tools/call","params":{name,arguments}}`.
  - Only these tools: maps_textsearch, taxi_estimate, taxi_create_order, taxi_query_order, taxi_cancel_order.
  - 25 s, no redirects, 200 only, ≤ 1 MiB. The body is JSON or SSE `data:` lines matched by id.
  - Error -32001 gives the rate-limit text. The key is never shown, and errors use the iOS fixed texts.
- **Service (RideService.m):**
  - Places are kept under random ids (≤ 8 shown; lookup cleared above 48).
  - The estimate keeps products (≤ 8); a quote is valid 60 s for prepare and 120 s for commit.
  - Prepare creates a random nonce with a 60 s consent, bound to the peer and key.
  - Commit runs once; the "unknown" flag is persisted until a definitive result, and blocks new orders.
  - Order id persisted. Poll every 30 s while matching/pickup, otherwise 60 s, with backoff to 300 s on error.
  - Status codes map to phases (0 MATCHING, 1 PICKUP, 2 ARRIVED, 4 TRIP, 5 DONE, else ERROR).
  - Text responses go through SafeMessage and are never interpreted as a state change.
- **Tool:** the exact iOS spec text. Arguments are per action: search(city,query), estimate(from_id,to_id), prepare(product_id), status, prepare_cancel. Each value is 1..120 chars with no controls; raw JSON ≤ 2000.
- **Key:** `SecretStore` `didi_sandbox_key`, 1..512 chars, no whitespace; never echoed.

## Review Focus

1. The order is committed at most once per confirmation; an unknown result blocks new orders.
2. Only a CONFIRMED event with the right nonce, from the pinned peer, commits.
3. The key never appears in UI text or logs, and redirects are refused.
4. Status prose never changes order state.
5. Malformed glasses replies are ignored.

---

### Task 1: DrWire + DrText + DrTool

**Files:** Create `src/com/turboio/addon/{DrWire,DrText,DrTool}.java`, `tests/DrCoreTest.java` and `tests/ride_golden.c`.

**Tests:**
- Golden snapshot/close/query packets and a DRA1 reply match the C output, and every DRA1 bit flip is rejected.
- Scene rules: ttl 14 refused; CONFIRM without a nonce refused; CONFIRM with phase TRIP refused.
- `text()` truncation keeps whole characters, under cap−1 bytes.
- SafeMessage drops lines containing phone or order-id fields, hides URLs and 11-digit numbers, and caps at 2000.
- messageLines splits 18+18 characters, with an ellipsis on overflow.
- Tool argument rules.

### Task 2: DrRpc + DrService

**Files:** Create `DrRpc.java` and `DrService.java`, plus `tests/DrServiceTest.java`.

**Tests:**
- RPC: parse JSON, SSE and errors (-32001 text), and unwrap structuredContent, text JSON, an array to rows, and a serverMessage.
- Service, with fake rpc and bridge:
  - search keeps ≤ 8 places with random ids;
  - estimate needs two different known ids;
  - prepare sends a CONFIRM scene with the nonce;
  - a CONFIRMED with a wrong nonce is ignored;
  - the right nonce commits once, and a second confirm doesn't commit;
  - a create failure sets unknown and blocks the next estimate;
  - a status code maps to its phase, and code 5 clears the order;
  - text status keeps the phase;
  - a peer change invalidates consent;
  - consent expires after 60 s.

### Task 3: Android glue

**Files:** Create `DrBridge.java`, `DrHttp.java` and `RideUI.java`; modify `ToolClient.java` (the `didi_ride` spec and a call through a main-thread latch, ≤ 35 s) and add an entry in 设置 ("滴滴出行（沙箱）").

Verify: `build.sh` is green and package 1.0.7 is clean.
