# Android Phase 2a — Menu Rows, Remote Camera, TDC1 Dev Card

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port three TVP2 glasses-native features from iOS 1.0.7 to `android-addon`: 2/3-row menu layout (TMG2/TMA2 protocol), remote camera (TCM1/TCA1), and the TDC1 developer dashboard card.

**Architecture:** Same pattern as the existing focus and navigation ports. A pure-Java codec is checked byte-for-byte against the iOS C source by a golden test (the C file compiled with `cc` in `build.sh`). A pure-Java link/state machine is tested against a fake transport. Thin Android glue (Camera2, UI) is kept outside the tested core. All three use business 15, through `NativeTransfer.acquireMessages`/`sendMessage`/`receive`.

**Tech Stack:** Java 8 source level, Android platform 36 APIs (Camera2, MediaStore), C golden generators, `build.sh`.

**Spec:** Parent roadmap `docs/superpowers/plans/2026-10-23-android-ios-parity.md` (Phase 2 row). iOS sources are the behavioral reference: `official-addon/ios107-edition/{MenuLayout.m,menu_config.c,camera-v1/*,DashboardPhone.m,DashboardCard.m,card.c}`.

## Global Constraints

- Firmware is TVP2 only. TVP2 contains the menu-grid-v2, camera-v1 and dashboard-v1 modules, so every feature may assume them, but it must time out cleanly when the glasses don't answer.
- Carrier for menu and camera (from `menu_config.c` / `camera.c`): bytes `08 01 10 7f 1a`, then a varint string length (1 or 2 bytes), then a 4-char tag (`TML:`/`TMA:` menu, `TCM:`/`TCA:` camera), then lowercase hex of the raw frame. Menu frames are exactly 32 raw bytes (74 wire bytes). Camera raw frames are 32 + ≤208 bytes (wire ≤492).
- CRC is CRC-32/ISO-HDLC (`0xedb88320` reflected, init/xorout `~0`). It covers bytes 0..27, plus the data region for camera.
- Menu: QUERY → reply carries a token (≠0); SET requires that token, the same client and generation, within 120 s on the glasses. The phone treats `ready` as valid for 110 s. The reply timeout is 3 s and there is no automatic retry. Rows are only 2 or 3. Reply bytes 24..26 must be `28, 2, 220`.
- Camera: profiles `{128×72×2, 192×108×4, 256×144×2, 256×144×4}`, default index 3. Frame budgets are 2.5/5.5/6.5/8.0 s. Packet reply timeout is 3 s; ping every 3 s when idle. A glasses event (op ≥ 32) whose age is outside −1000..1500 ms is ignored, so no late photo is ever taken. A rejected or late reply stops the preview, and the shutter is never resent.
- The host already declares `android.permission.CAMERA` (checked with `aapt2 dump permissions` on 1.0.7). No manifest change is needed. Runtime permission must be requested before opening the camera.
- Photos are saved via `MediaStore.Images` (`Pictures/TurboIO`) with no storage permission (API 29+). Saving never blocks the link.
- Never send while `NativeTransfer.busy()`, while an OTA guard is pending, or to a peer other than `NativeTransfer.connected()`.
- iOS `Brightness*` is an info page and writes nothing ("亮度实验仍暂停"), so it is out of scope (no behavior to port).

## Review Focus

1. **Stale shutter.** A glasses click delivered late (BLE backlog) must not take a photo. `CameraLinkTest` feeds an event older than 1500 ms and asserts no action fires.
2. **Peer switch mid-operation.** If a reply arrives from a different device, or `connected()` changes, the operation finishes with a note, with no send and no state change. Covered in both link tests.
3. **Menu SET without fresh QUERY.** `choose(rows)` with an expired token must query first and never send a SET carrying a stale token. Covered in `MenuLayoutTest`.
4. **Camera never released.** Leaving the screen, or the app going to the background, must send CLOSE once (when active) and release Camera2 and the message lease. Covered by `CameraLinkTest` (`close()` sends exactly one CLOSE, `invalidate` releases). The Camera2 release is checked in device testing.
5. **Oversized frame.** A compressed frame longer than 18576 bytes, or geometry outside the four profiles, is dropped before any send. Covered in `CameraCodecTest`.

---

## File Map

- Create `src/com/turboio/addon/HexCarrier.java`: wrap/unwrap the type-127 hex carrier, parameterized by tag and raw-length bounds.
- Create `src/com/turboio/addon/MenuCodec.java`, `MenuLayout.java` (link state machine, port of `TIOMenuLayoutLink`), and `MenuUI.java` (settings row: 读取 / 两排 / 三排).
- Create `src/com/turboio/addon/CameraCodec.java` (packet/decode/compress/quantize), `CameraLink.java` (port of `TCCameraLink`), `CameraPreview.java` (Camera2 → gray plane → quantize/compress; capture JPEG → MediaStore) and `CameraUI.java`.
- Modify `src/com/turboio/addon/CardCodec.java`: add `devcard(String text)`, which builds the `turbo_ui_devcard_v1` install with a `TDC1;…` text validated per `card.c` `dc_parse`. Modify `CardUI.java`: add a "开发者仪表盘 · TDC1" entry using the existing `CardTransport.publish`.
- Modify `EditorialUI.java`: add entries (设置 → 眼镜菜单排数; 随身应用 → 遥控拍照; 诊断 → TDC1).
- Tests: `tests/hex_golden.c`, `tests/menu_golden.c`, `tests/camera_golden.c` (generators); `tests/MenuCodecTest.java`, `tests/menuflow/MenuLayoutTest.java`, `tests/CameraCodecTest.java`, `tests/cameraflow/CameraLinkTest.java`, plus additions to `tests/CardCodecTest.java`. Wire all of them into `build.sh` after the card tests.

### Task 1: HexCarrier + MenuCodec

**Interfaces — Produces:**
- `HexCarrier.wrap(String tag, byte[] raw) -> byte[]` (`tag` is 4 chars incl. `:`; the raw length must fit the caller's bounds).
- `HexCarrier.unwrap(byte[] wire, String tag, int minRaw, int maxRaw) -> byte[]|null`.
- `MenuCodec.command(int op,int rows,long request,long token,long generation,long client) -> byte[32]`.
- `MenuCodec.Reply MenuCodec.reply(byte[] wire)` (null unless every check from `MenuLayout.m` `Reply()` passes), with fields `op, rows, result, request, token, generation, client`.

- [ ] **Step 1:** `tests/menu_golden.c` writes `query.bin` (op 0, request 0x11223344, client 0x55667788), `set3.bin` (op 1, rows 3, token 7, generation 2) and `reply-ok.bin` (from `tml_reply` with state token 9, rows 2, generation 5), each as carrier wire bytes via `tml_carrier`. `MenuCodecTest` asserts that `HexCarrier.wrap("TML:",MenuCodec.command(...))` equals `query.bin`/`set3.bin` byte for byte, and that `MenuCodec.reply(reply-ok.bin)` decodes to `rows==2, token==9, generation==5, result==0`. Rejected (null): flipped CRC byte, uppercase hex, wrong tag `TML:` on a reply, rows 4, `p[24]!=28`, length 73.
- [ ] **Step 2:** Wire into `build.sh` and run. Expected: FAIL (classes missing).
- [ ] **Step 3:** Implement both classes. They are pure Java with no Android imports.
- [ ] **Step 4:** `bash android-addon/build.sh`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(android): TMG2 menu-layout codec and hex carrier`.

### Task 2: MenuLayout link + UI

**Interfaces:**
- Consumes: `MenuCodec`, `HexCarrier`, `NativeTransfer.{acquireMessages,sendMessage,releaseMessages,connected,receive}`.
- Produces: `MenuLayout.query()`, `MenuLayout.choose(int rows)`, `MenuLayout.status()`, `MenuLayout.rows()` (0 when unknown), and `MenuLayout.listen(Runnable)`. Lease owner string `"menu-layout"`.

- [ ] **Step 1:** `tests/menuflow/MenuLayoutTest.java`, using a fake `NativeTransfer` and `SystemClock` patterned on `tests/cardflow` and `tests/musicflow`:
  - query → reply OK rows 3 gives `rows()==3`.
  - `choose(2)` sends SET with the query token, then reply OK rows 2 gives `rows()==2`, and the status contains "已保存".
  - `choose(2)` after 111 s first sends a QUERY.
  - No reply within 3 s: the status contains "未回执" and no second packet is sent.
  - A reply with a different request id is ignored.
  - A reply from another device is ignored.
  - Result codes 1/2/3 map to the three iOS notes.
  - A SET reply whose rows ≠ target gives "回执不一致".
  - The lease is released after every finish.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement `MenuLayout` (state as in `MenuLayout.m`; timeout via `Handler.postDelayed` 3000). Implement `MenuUI` (one screen: current rows, 读取, 两排, 三排) and add the entry in `EditorialUI` settings. Use the copy from iOS, with "TMG2" replaced by "TVP2".
- [ ] **Step 4:** `build.sh` PASS.
- [ ] **Step 5: Commit** `feat(android): choose 2/3-row glasses menu on TVP2`.

### Task 3: CameraCodec

**Interfaces — Produces:**
- `CameraCodec.packet(int op,long sid,long seq,long a,long b,long c,byte[] data) -> byte[]` (phone→glasses, `TCM1`).
- `CameraCodec.Packet CameraCodec.reply(byte[] wire)` (glasses→phone, `TCA1`, unwrapped and decoded, rejecting a non-empty data region exactly as `CameraLink.m` `Reply()` does).
- `CameraCodec.quantize(byte[] gray,int bits) -> byte[]`.
- `CameraCodec.compress(byte[] packed) -> byte[]|null`.
- `CameraCodec.budget(int w,int h,int bits) -> double`.
- `static final int[][] PROFILES`.

- [ ] **Step 1:** `tests/camera_golden.c` emits wire files for HELLO, BEGIN (a = w|(h<<16), b = len|(bits<<24), c = crc), CHUNK with 208 data bytes, and a TCA1 SHUTTER reply. It also emits `quant2.bin`/`quant4.bin` (a gradient 256×144 plane through `tc_quantize`) and `packbits.bin` (`tc_compress` of a buffer mixing runs ≥3, literals and 128-byte runs). `CameraCodecTest` asserts byte equality for all of them. It also asserts that `compress` returns null for input >18432 bytes, and that `packet` rejects data >208 bytes and `seq==0`.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** PASS.
- [ ] **Step 5: Commit** `feat(android): TCM1 camera codec`.

### Task 4: CameraLink state machine

**Interfaces:**
- Consumes: `CameraCodec`, `HexCarrier`.
- Produces: `CameraLink(String peer, Sender sender, Clock clock)` with `start()`, `close()`, `tick()`, `offer(byte[] compressed,int w,int h,int bits,boolean review)`, `state(int phase,int zoom,int remaining)`, `consume(String device, byte[] wire) -> boolean`, `invalidate(String)`, getters `ready()`, `active()`, `note()`, `frames()`, `dropped()`, and callback `interface Action{void fire(int op,long arg);}`.

- [ ] **Step 1:** `tests/cameraflow/CameraLinkTest.java`, a direct port of the assertions in `camera-v1/CameraLinkTests.m`, plus Review Focus 1, 2, 4 and 5:
  - HELLO → reply a=256, b=144 → OPEN → ready.
  - A frame offered goes BEGIN / CHUNK… / COMMIT.
  - BUSY on COMMIT retries at 100 ms for up to 8 s.
  - The frame budget expiring sends ABORT.
  - A stale event (>1500 ms) produces no action.
  - Late replies invalidate.
  - `close()` sends exactly one CLOSE.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement as a field-for-field port of `CameraLink.m`.
- [ ] **Step 4:** PASS.
- [ ] **Step 5: Commit** `feat(android): TCM1 camera link`.

### Task 5: Camera2 preview, capture and UI

**Files:** Create `CameraPreview.java` and `CameraUI.java`; modify `EditorialUI.java`.

- [ ] **Step 1:** Extend `CameraCodecTest` with `CameraCodec.fit(byte[] y,int yw,int yh,int rowStride,int w,int h) -> byte[w*h]`. It is a letterboxed, fit-not-fill downsample of a Y plane, mirroring `TCEncodeImage`. Test fixture: a 640×480 Y plane, fit into 256×144, must have black bars at the left and right columns 0..~31 and preserve the center sample.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement `fit`. Then implement `CameraPreview`:
  - Camera2 back camera, `ImageReader` in `YUV_420_888` at the smallest supported size ≥ 640×360 for preview, and a JPEG `ImageReader` for capture.
  - Sample at the profile's `sampleSeconds`, then `fit` → `quantize` → `compress` → `link.offer`.
  - Shutter (op 32) with the countdown from prefs `TCCameraDelay` (0/3/5 s) sends `state(COUNTDOWN…)`, then captures. The JPEG is saved via `MediaStore` `Pictures/TurboIO`. A 256×144 review thumbnail is offered with `review=true`. State goes to SAVED or ERROR.
  - Zoom (33) sets `CONTROL_ZOOM_RATIO` clamped to the camera range; the value is ×100 as in iOS. Cancel (34) aborts the countdown. Exit (35) closes.
  
  Implement `CameraUI`: open button, profile picker (4 profiles), delay picker, live status (frames/dropped/note). `onPause`/dismiss → `link.close()` → release the camera after the CLOSE reply or a 3 s timeout. Ask for the `CAMERA` runtime permission first. Add the "遥控拍照" entry.
- [ ] **Step 4:** `build.sh` PASS. Then `node package.mjs` on the 1.0.7 APK. Expected: it packages, with `unexpected_paths` empty.
- [ ] **Step 5: Commit** `feat(android): remote camera via glasses dial (TCM1)`.

### Task 6: TDC1 developer card

**Interfaces — Produces:** `CardCodec.devcard(String text) -> Map<String,Object>`, a `widget_install` for id `turbo_ui_devcard_v1` whose single `root` Text component carries `text`. It throws unless `text` passes the rules of `card.c` `dc_parse`, which the TVP2 `package()` path also enforces.

- [ ] **Step 1:** `CardCodecTest`:
  - `devcard("TDC1;99;90;85;375;1280;1400;2000;0;1;2")` gives id `turbo_ui_devcard_v1`, type `a2ui`, and extras with `widgetId`/`surfaceId` equal to that id plus the fixed catalog URL.
  - The alternate text `TDC1;25;50;75;640;1280;1000;2000;0;1;2` passes.
  - Rejected: a percentage >100, 9 or 11 numeric fields (exactly 10 are required), a field of 7 digits, `ramFree > ramTotal`, an icon value 3, and the `TDC2;` prefix.
  - Golden check: compile `official-addon/ios107-edition/card.c` in a tiny C harness (`tests/devcard_golden.c`) that runs `dc_parse` on the same strings and writes pass/fail flags, then assert Java and C agree on every case.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement `devcard` and its validation, porting `dc_parse`. Add a CardUI entry with two buttons (演示数值 A/B) that call `CardTransport.publish(devcard(...), true)`.
- [ ] **Step 4:** `build.sh` PASS.
- [ ] **Step 5: Commit** `feat(android): TDC1 developer dashboard card`.

Device checks the user must run after this phase: menu read and switch on TVP2; camera preview on the lens, shutter via the dial, photo appears in the gallery; TDC1 card shows on the lens.
