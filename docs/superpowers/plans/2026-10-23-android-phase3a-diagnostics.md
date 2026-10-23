# Android Phase 3a — Diagnostics: TDG1 Runtime Status + Model/Search Tests

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Android the iOS 1.0.7 diagnostics page: TDG1 glasses runtime status (memory, RX, render, errors; 10-minute sampled session with a saved and shareable report), plus one-tap model-interface and web-search tests. Settings → 诊断 becomes a screen instead of a notice.

**Architecture:**
- **Codec:** a pure-Java `TdgCodec` is checked byte-for-byte against `diagnostics-v1` `command.c`/`diagnostics.c` by a golden test.
- **Session:** `DiagnosticsRun` ports the iOS `TDPhoneRun` + `TDPhoneStore` session and report logic. It is tested on the JVM against a fake `NativeTransfer`.
- **Transport:** the start/stop command goes out as the 24-byte file `turbo-diagnostics.tdg` via `NativeTransfer.send` (the same route as focus and music). Samples come back as the type-6 envelope `turbo_diagnostics_v1` with 128 bytes of hex data, decoded with `CustomEnvelope.decode`.

**Spec:** Parent roadmap `docs/superpowers/plans/2026-10-23-android-ios-parity.md` (Phase 3 row). References: `official-addon/ios107-edition/{TDPhoneRun.m,TDPhoneStore.m,TDPhoneBridge.m,TDPhoneReply.m,TDPhoneUI.m,command.c,diagnostics.c}`; firmware `firmware-research/strix-1.0.5.5-tvp2/src/diagnostics-v1/diagnostics_service.c`, which requires the file name `turbo-diagnostics.tdg` and replies with `{"cmd":"turbo_diagnostics_v1","payload":{"data":"<256 hex>"}}`.

## Global Constraints

- **Command (TDQ1, 24 bytes):** `"TDQ1"`, version 1, `op` (1 = START, 2 = STOP), reserved 0, `session` ≠ 0, `sequence` ≠ 0, `lease_ms`, then CRC-32 over bytes 0..19. START needs `0 < lease ≤ 600000`; STOP needs `lease == 0`. iOS sends START with sequence 1 and lease 600000, and STOP with sequence 2.
- **Sample (TDG1, 128 bytes):** `"TDG1"`, v1, `p[6]==128`, `session`, `sequence`, `tick_ms`, `probe_ms`, a valid-mask (no bits at or above 19), `build`, 20 u32 metrics (a metric whose valid bit is clear must be 0), event_count ≤ 64, events_lost, flags ≤ 1, then CRC-32 over 0..123. The phone expects build `0x01000001`.
- **Session rules (TDPhoneRun):**
  - Lease 600 s.
  - Stop with `first_sample_timeout` if no sample arrives within 10 s.
  - Stop with `telemetry_silent` after 20 s without a new sample.
  - Stop with `probe_slow` when a sample has flags = 1.
  - Stop with `peer_context_changed` when the peer changes.
  - Stop with `submit_failed` / `transfer_failed` when the file transfer fails.
  - Samples must strictly increase in sequence and tick (32-bit wrap-aware), or they are rejected. Gaps are counted. At most 600 samples are kept (oldest evicted) and at most 512 events.
  - A checkpoint is saved every 5 s, plus at stop.
- **Reports:**
  - Saved under the app files dir `turboio/diagnostics/<uuid>/diagnostics.{json,md}`, at most 100 run directories, never auto-deleted.
  - JSON format `TurboIO-Diagnostics-1`, with the iOS field names (`lv_configured_bytes` …).
  - The device ID is never written to a report.
  - Unmeasured metrics are null, never 0.
- **No sending** while `NativeTransfer.busy()` or an OTA guard is pending. There is no automatic start or restart.
- All user-visible text is Chinese, copied from the iOS strings where they exist.

## Rulings carried from scoping

- iOS "自定义 UI 真机验收" (A2UI: text 7392 → layout 8642 → uninstall) is **not ported**. TVP2's `dashboard-compat-v1` only installs `turbo_ui_card_*` TCE1 or `turbo_ui_devcard_v1` TDC1 content, so those raw A2UI fixtures would be rejected. The TCE1 and TDC1 flows (Phase 1/2a) are the TVP2 acceptance path.
- Glasses log (business 11 + intercepted file share), the todo protocol test (business 20/22) and the subtitle-navigation HUD (business 19) are **Phase 3b**. Each needs host-side research first: Android file-share storage, and event interception beyond business 9.

## Review Focus

1. **Late or foreign samples.** A sample from another device, another session, or with sequence ≤ last is rejected, and a session is never revived after it stops. Covered by `DiagnosticsRunTest`.
2. **Stop always reaches the glasses.** User stop, timeout and peer change all send one STOP. If a START file transfer is still in flight, the STOP is queued until it settles, then sent once. Covered by `DiagnosticsRunTest`.
3. **Report privacy.** No device ID or name appears in either report. Covered by asserting that the report text does not contain the peer string.
4. **Disk bounds.** With 100 run directories already present, a new start is refused rather than deleting old reports. Covered by `DiagnosticsRunTest`.
5. **Settings → 诊断 still shows the old status text.** The new screen keeps `TurboAddon.status()` and `NativeTransfer.diagnostic()` at the top. Checked by reading the code.

---

### Task 1: TdgCodec

**Files:** Create `src/com/turboio/addon/TdgCodec.java`, `tests/tdg_golden.c`, `tests/TdgCodecTest.java`. Modify `build.sh` (after the camera block).

**Interfaces — Produces:**
- `TdgCodec.command(int op,long session,long sequence,long leaseMs) -> byte[24]`. It throws `IllegalArgumentException` on anything `td_command_encode` would refuse.
- `TdgCodec.Sample TdgCodec.sample(byte[] raw128)`, which returns null unless `td_decode` would accept the bytes. Fields: `session, sequence, tickMs, probeMs, valid, build, long[] values (20), eventCount, eventsLost, flags`.
- `static final String[] NAMES`: the 19 report names in iOS order.

- [ ] **Step 1:** The golden generator writes:
  - `start.bin` (START, session 0x12345678, seq 1, lease 600000) and `stop.bin` (STOP, seq 2), via `td_command_encode`;
  - `sample.bin`, a `td_encode` of a sample with valid mask 0x7FFFF, values i*1000+7, event_count 3 and flags 0;
  - `sample-partial.bin`, with valid mask 0x5 (other values 0).
  
  The test asserts byte equality for both commands, a full field decode of both samples, and that every single-bit flip of `sample.bin` is rejected. It also asserts these are rejected: a value with its valid bit clear and non-zero, flags 2, event_count 65. And `command` throws for lease 600001, for STOP with lease > 0, and for session 0.
- [ ] **Step 2:** RED.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `build.sh` passes.
- [ ] **Step 5: Commit** `feat(android): TDG1 diagnostics codec`.

### Task 2: DiagnosticsRun (session, store, report)

**Files:** Create `src/com/turboio/addon/DiagnosticsRun.java` and `tests/diagflow/{DiagnosticsRunTest.java,NativeTransfer.java}`. Reuse `tests/musicflow/SystemClock.java`.

**Interfaces:**
- Consumes: `TdgCodec`, `CustomEnvelope.decode(bytes,"turbo_diagnostics_v1",128)`, `NativeTransfer.{send,connected,busy,receive}`.
- Produces:
  - `DiagnosticsRun(java.io.File root)`, `boolean start()`, `void stop(String reason)`, `void poll()`, `boolean active()`.
  - `String status()` (iOS Chinese reasons), `int count()`, `Map<String,Object> latest()`.
  - `String reportMarkdown()`, `byte[] reportJSON()`, `java.io.File reportDirectory()`.
  - `static DiagnosticsRun current(java.io.File root)`, a process singleton re-created when the peer changes.

- [ ] **Step 1: `DiagnosticsRunTest`.** The fake `NativeTransfer.send` records `(name, bytes, completion)`, and the test completes transfers explicitly. Assertions:
  - start sends `turbo-diagnostics.tdg` with a START that decodes to lease 600000 and seq 1;
  - samples (fed as a type-6 envelope) increase `count()`;
  - samples from a foreign device or session, or with a repeated sequence, are ignored;
  - 10 s with no sample gives "10 秒未收到首条采样" and exactly one STOP (seq 2);
  - 20 s of silence after the first sample gives `telemetry_silent`;
  - a flags=1 sample gives `probe_slow`;
  - a failed START transfer gives `submit_failed` and no STOP while the transfer is unsettled;
  - a user stop while START is in flight sends STOP once after the START transfer settles;
  - a peer change gives `peer_context_changed`;
  - 601 samples keep 600, with evicted 1;
  - the report JSON/MD has format `TurboIO-Diagnostics-1`, null for unmeasured metrics, and does not contain `"test-peer"`;
  - with 100 existing run dirs, `start()` returns false and nothing is sent.
- [ ] **Step 2:** RED.
- [ ] **Step 3:** Implement as a port of `TDPhoneRun.m` + `TDPhoneStore.m`. Checkpoints write `diagnostics.json`/`diagnostics.md` atomically (temp file + rename) on a single-thread executor.
- [ ] **Step 4:** PASS.
- [ ] **Step 5: Commit** `feat(android): TDG1 diagnostics session and report`.

### Task 3: Diagnostics screen + model/search tests

**Files:** Create `src/com/turboio/addon/DiagnosticsUI.java`. Modify `EditorialUI.java` (诊断 → `DiagnosticsUI.show(a)`). Reuse the existing chat request path in `TurboAddon` and `ToolClient` for search, discovered at implementation time; record a ruling if a test hook is needed.

The screen has three sections:
- **Status:** the existing `TurboAddon.status()` and `NativeTransfer.diagnostic()` text.
- **眼镜运行状态 · TDG1:**
  - start/stop buttons and a 1 s refresh;
  - the latest 19 metrics, labelled with the iOS Chinese names (LVGL 配置容量 …);
  - sample count, remaining time and reason;
  - share as Markdown text (and JSON) via `ACTION_SEND` with `EXTRA_TEXT`.
- **测试:**
  - "测试模型接口": one short request to the configured endpoint, showing latency and the first 80 characters of the reply or the error;
  - "测试联网搜索": one TinyFish query, showing the result count or the error.
  - Neither ever runs automatically.

- [ ] **Step 1:** Extend `DiagnosticsRunTest` with `DiagnosticsRun.label(String name) -> String`, mapping each of the 19 names to its Chinese label from `TDPhoneUI.m`. Unknown names return the name itself. RED.
- [ ] **Step 2:** Implement `label`, the screen and the entry. `build.sh` passes (it compiles against `android.jar`). `node package.mjs` on 1.0.7 reports `unexpected_paths` empty.
- [ ] **Step 3: Commit** `feat(android): diagnostics screen with TDG1 and model/search tests`.

Device checks for the user: on TVP2, start TDG1, see the first sample within 10 s, stop, and share the report; run the model and search tests with a configured endpoint.
