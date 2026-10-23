# Android Phase 2b-2 — Context English (TEL1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port iOS 1.0.7 "情境英语" to Android. The phone:
- reads the official app's locally cached lifelog transcript;
- lets the user pick excerpts and approve a model call;
- validates the AI study cards;
- sends them to TVP2's `context-english-v1` runtime over the TEL1 file carrier;
- records progress replies for review;
- offers the opt-in daily automation.

**Architecture:** Pure, JVM-tested Java ports of the iOS/C cores:
- `CeWire`: CED1 bundle, TEL1 packet, TEA1 ack, TEP1 progress, card rules.
- `CeTransfer`: the sender state machine.
- `CeHive` + `CeLifelog`: the read-only Hive snapshot and transcript rows.
- `CeCore`: selection, model request, response validation.
- `CeHistory`: the local review record.
- `CeAuto`: the daily automation state machine.

Android glue (`CeBridge` on `NativeTransfer`, `ContextEnglishUI`) stays thin. The C sources are the golden reference via `tests/english_golden.c`.

**Tech Stack:** Java 8 sources (Android platform 36), plain `main()` tests in `android-addon/build.sh`, clang for the golden harness.

**Spec:** the iOS sources are the behavioural spec:
- `official-addon/ios107-edition/context-english-v1/`: `ContextEnglish*.m`, `CE*.m`, `english_wire.c`, `english_transfer.c`, `english_progress.c`, `english_view.c` (`ce_card_valid`) and `README.md`;
- the TVP2 runtime in `firmware-research/strix-1.0.5.5-tvp2/src/context-english-v1/`;
- the parent roadmap `2026-10-23-android-ios-parity.md` (Phase 2 row).

## Global Constraints

- **Wire (`english_wire.c`, byte-exact):**
  - **CED1 bundle:** a 20-byte header, then per card `generated` u8 and four u16-length UTF-8 fields (english, quote, meaning, example). Total ≤ 4608 bytes.
  - **TEL1 packet:** 36 + payload bytes, with the CRC (`ce_crc32`, the standard reflected 0xEDB88320) over n−4 bytes. Chunks are ≤ 384 bytes. Ops: QUERY 1, BEGIN 2, CHUNK 3, COMMIT 4, ABORT 5.
  - **TEA1 ack:** 44 bytes.
  - **TEP1 progress:** 72 bytes.
  - **Card rules (`ce_card_valid`):** english ≤ 24 scalars (ASCII letters, space, `-`, `'`, with at least one letter); quote ≤ 49; meaning ≤ 22; example ≤ 60 scalars. Byte caps are 31/159/71/191. No control, bidi or line/paragraph separators.
- **Carrier:** file `turbo-english.tel` through `NativeTransfer`. Replies come as custom envelopes `turbo_english_v1` (44 B) and `turbo_english_progress_v1` (72 B).
  - QUERY uses request = query sequence and session 0.
  - Transfer packets use request = seq and session = tx.
  - The TEA1 result is fed to `NativeTransfer.ack`.
- **Transfer (`english_transfer.c`):**
  - BEGIN, then CHUNKs, then COMMIT.
  - Advance only on file completion plus a matching ack.
  - 12 s per packet. At most 2 retries, and only after definitive file completion. 110 s overall.
- **Bridge (`ContextEnglishBridge.m`):**
  - QUERY first. If the reply is busy/receiving, refuse.
  - tx = max(lastTX+1, highwater+1, unix now), persisted.
  - Plan: day = local date as days since the epoch; expires = local midnight tomorrow; minute 0..1439; reminder flag; target index CET4/CET6/TOEFL/IELTS.
  - A synthetic test never touches history.
  - A peer change, or OTA protection, stops the session. There is no automatic resend.
- **Source (`CEHiveSnapshot.m`, `CEOfficialLifelog.m`):**
  - Read-only.
  - Exactly one `api_cache_user_<digits>.hive` (Android: search the host `files` and `app_flutter` dirs; more than one match → "多个官方账号缓存" error). ≤ 32 MiB, and the file must be stable during the read.
  - Hive frames: length u32, key, value, CRC32. Value types 0–5, 9, 10, 11; anything else is refused. Limits: 200000 nodes, 100000 frames, depth 24.
  - Only `https://xr-api-p.rayneo.cn/lifelog/api/v1/events/<n>/full` entries with code 0/200, taking the latest `createdAt`. Only `clipType == "speech"` clips.
  - Merge contiguous clips from the same speaker, same day, gap ≤ 30 s, ≤ 400 chars. Keep ≤ 20000 rows, newest first.
- **Core (`ContextEnglish.m`, `ContextEnglishClient.m`):**
  - Selection: ≤ 32 sources, ≤ 12000 UTF-8 bytes; ids `s0001…`.
  - The exact iOS system prompt.
  - Validation exactly as `CEValidateResponse`, with its error texts.
  - The request needs an https endpoint with no user, query or fragment, and `/chat/completions` appended. Optional `thinking` disabled (Android pref `disable_thinking`). Body ≤ 64 KiB, response ≤ 64 KiB, no redirects, 60 s.
- **History (`ContextEnglishHistory.m`):**
  - ≤ 40 rows, ≤ 128 KiB, 30-day window.
  - word = crc32(lowercase english) (0 → 1).
  - Progress results: remembered → due +3, else +1. A late "reserved" report doesn't overwrite a same-day answer.
- **Auto (`CEAutoPlan.m`):**
  - Default off; consent dialog with the iOS text.
  - Binding is destination/model/scope (hash of the cache file name)/peer hash/zone.
  - One model request per day, from yesterday's text.
  - Send window: [minute, minute+15) on the same day; queued → sending → delivered or uncertain.
  - Sensitive filter regex exactly as iOS.
  - Android runs `tick` every 15 s only while the host process is alive.

## Review Focus

1. **Privacy:** nothing leaves the phone before the user approves the exact selection or enables automation. The key never appears in status, history or logs.
2. **A wrong or ambiguous account cache** (several `api_cache_user_*` files) is refused, never merged.
3. **Truncation:** an oversized or invalid card is refused, not cut.
4. **No blind resend:** an unknown file state or a peer change stops the transfer without retrying.
5. **Progress replies from another glasses peer** don't touch this peer's history.

---

### Task 1: CeWire (bundle, packet, ack, progress, card rules)

**Files:** Create `src/com/turboio/addon/CeWire.java`, `tests/CeWireTest.java` and `tests/english_golden.c`, and wire them into `build.sh`.

**Produces:**
- `crc32(byte[],int)`;
- `byte[] bundle(List<Card>,int target,long day,long expires,int minute,boolean reminder)` (null if invalid);
- `boolean cardValid(Card)`;
- `byte[] packet(int op,long tx,long seq,long offset,long total,long digest,byte[] payload,int from,int length)`;
- `Ack ack(byte[])`;
- `Progress progress(byte[])`;
- `Card{String english,quote,meaning,example;boolean generated}`.

**Tests:**
- The golden C harness compiles `english_wire.c`, `english_view.c` and `english_progress.c` and writes vector files: a 5-card bundle, a QUERY/BEGIN/CHUNK/COMMIT packet set, an ack and a progress record.
- Java output must be byte-identical. Java must decode the C ack and progress, and reject every single-bit flip.
- Card rule cases:
  - a 25-char english is refused;
  - U+202E in a quote is refused;
  - `don't-stop` is accepted;
  - `123` is refused.

### Task 2: CeTransfer + CeBridge session

**Files:** Create `CeTransfer.java` (port of `english_transfer.c`) and `CeSession.java` (port of the pure part of the bridge: query, tx choice, pump, completion; time and carrier injected), plus `tests/CeTransferTest.java`.

**Tests:**
- The golden harness runs a full C-receiver transfer of the 5-card bundle at tx 1000.
- Java emits identical packets and advances on the C acks.
- A lost commit ack retries once after file completion.
- An unknown file state fails without retrying.
- The 110 s overall limit fails.
- Session:
  - QUERY with the persisted sequence; a busy reply ends with the iOS text;
  - tx = max rule;
  - a peer change ends;
  - completion calls `history.remember` unless synthetic.

### Task 3: CeHive + CeLifelog (official cache source)

**Files:** Create `CeHive.java`, `CeLifelog.java` and `tests/CeLifelogTest.java`.

**Tests** (the test writes Hive frames itself):
- A map entry for a full-event URL with two transcripts produces merged speech rows.
- Non-speech clips and a 31 s gap split rows.
- An older `createdAt` for the same path is ignored.
- A non-matching host is ignored.
- A bad CRC, an unknown value type 6, or a deleted key (empty value) are handled as iOS does.
- Two `api_cache_user_*.hive` files → an error with the "多个官方账号缓存" text.
- No file → an empty list.

### Task 4: CeCore + CeHistory

**Files:** Create `CeCore.java` (prepareDay, modelRequest, validate, request URL builder, offline test cards) and `CeHistory.java`, plus `tests/CeCoreTest.java`.

**Tests:**
- prepareDay picks only the selected local day, dedupes, and caps at 32 / 12000 bytes.
- The request URL appends `/chat/completions` and rejects http, userinfo and query.
- The system prompt equals the iOS text.
- validate:
  - accepts a good card and adds sourceLabel/receivedAt;
  - fails with "第 1 张卡片 · quote：不是来源中的逐字片段…";
  - rejects an original_english card whose term is missing from the quote (provenance);
  - rejects a duplicate;
  - rejects `finish_reason` other than "stop".
- History:
  - remember → reviewsForPeer on day+1;
  - a progress record (remembered) moves due to +3;
  - another peer's progress doesn't change rows;
  - more than 40 rows are trimmed.

### Task 5: CeAuto (daily automation)

**Files:** Create `CeAuto.java` (port of `CEAutoPlan.m` with injected clock, context, read, generate, send and reviews) and `tests/CeAutoTest.java`.

**Tests:**
- enable without ready → refused.
- tick on a new day reads yesterday's text, generates once, then queues.
- Sending happens inside the window → delivered.
- Past minute+15 → missed.
- A binding change → consent_changed.
- A sensitive row is excluded and counted.
- A restart while sending → uncertain.
- disable clears the cards.

### Task 6: Android glue and UI

**Files:** Create `CeBridge.java` (NativeTransfer carrier, receivers, history file under the add-on's private files dir) and `ContextEnglishUI.java`. Add an entry in the research/settings list next to diagnostics.

The manual page follows iOS:
- target, count, source date, reminder time and reminder switch;
- refresh the cached excerpts; tick sources; generate after the consent dialog; review the cards; send;
- synthetic test cards; clear the page; clear the history.

The auto page has the switch, the consent dialog, status and "检查一次执行条件".

Verify: `build.sh` is green and `package.mjs` 1.0.7 reports `unexpected_paths` empty.
