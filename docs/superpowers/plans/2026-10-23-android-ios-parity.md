# Android ↔ iOS 1.0.7 Parity — Roadmap + Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring `android-addon` to feature parity with the latest iOS edition (`official-addon/ios107-edition`, APP107) on the newest firmware (TVP2), excluding the AirPlay receiver.

**Architecture:** The work splits into independent phases, one plan each. Phase 1 (detailed below) is the foundation every later phase needs: run on the newest Android host (1.0.7 / 230), flash TVP2 from Android, and make the dashboard path correct on TVP2. Phases 2–5 port iOS feature groups; each gets its own plan written after reading that group's iOS source, because their wire protocols are not yet mapped for Android.

**Tech Stack:** Java (source/target 8, Android platform 36), Node ESM build scripts (`*.mjs`), Python 3 packaging/tests, apktool + Android build-tools 36.0.0. Tests are plain `main()` programs and `node`/`python3` scripts wired into `android-addon/build.sh`.

**Spec:** No separate spec. The requirements are the user's request ("Android equivalent to the new iOS, AirPlay excluded"), plus the facts gathered in this session and recorded under Global Constraints.

## Global Constraints

- Branch `android-ios-parity`, created from `main` @ `40d92d8` with `android-106-port` merged in. Never commit to `main`.
- Host 1.0.7 (230) APK SHA-256 `30239f65d910cf7008cfdf6cfacd5c068c5877068b4a637027786377a9ce4f91`, MD5 `5086c401c506e071b532bdc342f5cea4`. Official overseas channel; domestic channel is still 1.0.6 (216).
- Host 1.0.7 ABI: transport `Y3`, sdk `j4`, core `k4`, listener `Lq8/c$c;`, queue `LY3/V;`, send method `t`, file method `u`, **message class `S`** (was `Q` on 1.0.5/1.0.6; `j4/Q` stays `Q`).
- Host 1.0.7 `libapp.so` SHA-256 `a35159a82c0916f62ed6c4da271a40217300cc6678b29c54f2591d9fb592a45c`; route strings at `0x88512e` (`/xrlauncherapi/v1/signApi/gray/upgrade`) and `0xe1e48` (`/xrlauncherhwapi/v1/signApi/gray/upgrade`).
- TVP2 ZIP `StrixOS-1.0.5.5-TurboIO-TVP2-CANDIDATE-NOT-APPROVED.zip`: 8861428 bytes, SHA-256 `154f0f8e68a69b8fb93f869e423081ee43969bf09c5174e8dbeac192c1047c11`.
- TVP2 AP: 7435336 bytes, SHA-256 `66a2d04faa751c87f830ff324c1d9f9eb96a969ba2c65b37170cc82585970586`, MD5 `29cbac86a2a698520fc5d9e5ea4e375f`.
- TVP2 `OtaFileInfo.json`: 2700 bytes, SHA-256 `843304cf0db0f6061002652952924867cf03051961db5d6dc7ddff043ea7d05b`. All other 14 members are byte-identical to the existing `TMIG1_PINS` rows.
- **TVP2 is the only supported firmware** (user decision, 2026-10-23). The TAP1 and TMIG1 candidates are removed. Hosts 1.0.6 (216) and 1.0.7 (230) are supported. Host 1.0.5 (201) is dropped: its candidate was TAP1, and it has no tested path to a 1.0.5.5-format package. Code that exists only for non-TVP2 firmware (legacy `dashboard_config` replies) is removed rather than kept.
- Safety rules are unchanged: one reviewed candidate per host, download-only window, single authorization with typed token, 2-minute preflight freshness, manual result-guard release. Never weaken a gate to make a test pass.
- AirPlay (`official-addon/tar2-airplay`) and Apple-only features (Apple Watch remote, iOS 26 Apple translation frameworks) are out of scope.
- Every user-visible string is Chinese, matching the surrounding UI copy.

## Review Focus

1. **Host misdetection.** On 1.0.6, `HostAbi` must still select `V106` even though it now probes `V107` first. Covered by forcing each host in `HostAbiTest` (Task 1).
2. **Wrong candidate.** Only the TVP2 ZIP is accepted. The TMIG1, TAP1 and stock 1.0.5.5 ZIPs must be refused, and the host 1.0.5 APK must be refused by `package.mjs`. Covered in `Tvp2CandidateTest` (Task 3) and `HostProfilesTest` (Task 1).
3. **Dashboard on non-TVP2 firmware.** A reply without `widgets_v2` must stop before anything is sent, with a status that says TVP2 is required, instead of waiting out a 20 s timeout. Covered in `CardFlowTest` (Task 4).
4. **Post-flash readback.** TVP2 still reports `Strix OS 1.0.5.5`, the same as stock and TMIG1, so the version alone cannot prove that TVP2 is installed. Success still needs the manual lens check (`MARKER`) before the result guard is released. `Tvp2CandidateTest` pins the version check, and the existing `OtaInstallGuardTest` keeps pinning the manual release.
5. **1.0.7 DEX split.** `classes2.dex` has 65,330 method refs, so the hook-class relocation must apply on 1.0.7 as it does on 1.0.6. Covered by an `ApkAssemblyTest`/`package.mjs` version check (Task 1).

---

## Roadmap (one plan per phase)

| Phase | Scope (iOS source → Android) | Depends on |
|---|---|---|
| **1 Foundation** (this plan) | Host 1.0.7 ABI + OTA routing; TVP2 upgrade candidate; dashboard correctness on TVP2 / legacy firmware | — |
| 2 Glasses-native features on TVP2 | `MenuLayout*` (2/3-row menu), `camera-v1` (TCM1 remote shutter), `NavigationRoadMap`/`RoadMap`/`nav_map` (TNR3 vector map; extends `NativeNav*`), `context-english-v1`, `Brightness*`, `DashboardPhone`/`DashboardCard` (TDC1 test card) | 1 |
| 3 Diagnostics | `diagnostics*` (TDG1 runtime), `GlassesLog*` (biz 11/15), `SubtitleHUD*`/`NavigationSubtitleHUD*` (biz 19), A2UI acceptance page, `Todo*` protocol test (biz 20/22) | 1 |
| 4 Phone-side features | `notification-archive-v1` (Android: `NotificationListenerService` instead of biz 21 host hook — verify), `enhanced-lifelog-v1`, `Ride*` (Didi sandbox), `Knowledge*` + agent tools (diff against existing `ToolClient`), `AlwaysOn*` audio, `Recording*` text/summary (diff against `RecordingExports`) | 1 |
| 5 Display | `DisplayPhone*`/`TDPhone*` flexible display, `ImageUpload*` single image, `tar2-display` TVP2 HD link with an Android `MediaProjection` source in place of AirPlay | 1 |
| Deferred | `dots-v1` (iOS UI itself unfinished, bridge not public), local translation (needs Android model choice), Watch remote (Apple-only) | — |

Phases 2–5 are independent of each other once Phase 1 lands. Before writing each phase plan, read that group's iOS files in full and its firmware module under `firmware-research/strix-1.0.5.5-tvp2/src/`.

---

## Phase 1 File Map

- `android-addon/host-profiles.mjs`: add `ABI_107` and a 1.0.7 profile; make the message class configurable (`abi.message`, default `'Q'`).
- `android-addon/src/com/turboio/addon/HostAbi.java`: add `V107`, a `message` constructor parameter, and probe order 1.0.7 → 1.0.6 → 1.0.5.
- `android-addon/ota-hooks.mjs`: add `OTA_107`.
- `android-addon/package.mjs`: accept 1.0.7; select the OTA ABI by profile; apply the 64K hook-DEX split for 1.0.6 **and** 1.0.7.
- `android-addon/official-ota-source.mjs`: add the 1.0.7 `libapp.so` source pins.
- `android-addon/src/com/turboio/addon/OtaPackage.java`: replace the TMIG1 candidate with TVP2 for hosts 1.0.6/1.0.7.
- `android-addon/src/com/turboio/addon/OtaSession.java`, `OtaUI.java`: rename the `TMIG1` flag to `TVP2`.
- `android-addon/src/com/turboio/addon/CardTransport.java`: refuse install/remove on legacy replies; fix the wrong comment.
- Tests: `tests/HostProfilesTest.mjs`, new `tests/HostAbiTest.java`, `tests/OtaHooksTest.mjs`, `tests/OfficialOtaSourceTest.mjs`, `tests/Tmig1CandidateTest.java` → `tests/Tvp2CandidateTest.java`, `tests/cardflow/CardFlowTest.java`.
- `android-addon/build.sh`: TVP2 paths and new tests.
- `android-addon/README.md`: host 1.0.7 + TVP2.

---

### Task 0: Local toolchain and inputs (no commit)

**Files:** none in the repository; everything lives in ignored `build/` dirs or outside the repo.

- [ ] **Step 1:** Install the Android command-line tools under `~/Android/Sdk`, then `sdkmanager "platforms;android-36" "build-tools;36.0.0"`. Export `ANDROID_SDK_ROOT=~/Android/Sdk`.
- [ ] **Step 2:** Install apktool (pinned jar + wrapper on `PATH`). Run `apktool --version`; it must print a version.
- [ ] **Step 3:** Place the inputs (all ignored by `**/build*/`):
  - `official-addon/build/app-ap-20260927-test-01/StrixOS-1.0.4.12-TAP1-TEST-01-CANDIDATE-NOT-APPROVED.zip` (release `android-105-guard07-tap1-test01`)
  - `official-addon/build/strix-1.0.5.5-tmig1/StrixOS-1.0.5.5-TurboIO-TMIG1-CANDIDATE-NOT-APPROVED.zip` (release `firmware-strix-1.0.5.5-tmig1`) and `Strix-OS-1.0.5.5-original.zip` (copy from `firmware-research/strix-1.0.5.5/stock/`)
  - `official-addon/build/strix-1.0.5.5-tvp2/StrixOS-1.0.5.5-TurboIO-TVP2-CANDIDATE-NOT-APPROVED.zip` (release `tvp2-tar2-20261023`)
  - `apktool d --no-res -o android-addon/build/host-106 RayNeo_AI_1.0.6.apk` and `… -o android-addon/build/host-107 RayNeo_AI_1.0.7.apk`
- [ ] **Step 4:** Run `bash android-addon/build.sh`. Expected: it passes on the merged branch **before any change**. Record any pre-existing failure here, then stop and report it instead of fixing it inside a later task.

### Task 1: Host 1.0.7 (230) ABI

**Files:**
- Modify: `android-addon/host-profiles.mjs`, `android-addon/src/com/turboio/addon/HostAbi.java`, `android-addon/ota-hooks.mjs`, `android-addon/package.mjs:15-19,78-90`, `android-addon/tests/PrivateArtifactAudit.py:38` (comment only)
- Test: `android-addon/tests/HostProfilesTest.mjs`, `android-addon/tests/OtaHooksTest.mjs`, new `android-addon/tests/HostAbiTest.java`

**Interfaces:**
- Produces: `PROFILES['30239f65…4f91'] = {version:'1.0.7', code:230, directory:'host-107', abi:ABI_107}`; `ABI_107 = {transport:'Y3', sdk:'j4', core:'k4', listener:'Lq8/c$c;', queue:'LY3/V;', send:'t', file:'u', message:'S'}`; `verifyHost` uses `abi.message||'Q'` for the transport message class everywhere it now hard-codes `T+'Q;'` (constructor check, field check, `sendHeader`, `queueHeader`, returned `ota.message`).
- Produces: `HostAbi.V107` with `message == "Y3.S"`; `HostAbi(String version,String pkg,String sdk,String core,String msg,String send,String file)`.
- Produces: `OTA_107 = {queueClass:'LY3/V;', senderClass:'LY3/u;', message:'LY3/S;', core:'Lk4/q;', fileMethod:'u'}`.

- [ ] **Step 1: Failing tests.**
  - `HostProfilesTest.mjs`: build a synthetic smali tree for 1.0.7 that mirrors the existing 1.0.6 fixture but uses the 1.0.7 names, with message class `Y3/S` and constructor `([BLjava/lang/String;Ljava/lang/String;Lj4/h;Lj4/Q;LY3/b;ZZLk4/p;Lkotlin/jvm/functions/Function2;)V`. Assert that `verifyHost(dir, PROFILES['30239f65…4f91'])` returns `ota.message === 'LY3/S;'` and `ota.queueHeader === '.method public static o(LY3/S;)V'`. Also assert that the same tree is rejected under the 1.0.6 profile.
  - `HostAbiTest.java`: for each `-Dturboio.host` value `1.0.5`/`1.0.6`/`1.0.7`, assert `HostAbi.get().message()` equals `E3.Q`/`X3.Q`/`Y3.S` and `send()` equals `u`/`t`/`t`. Run as three JVM invocations from `build.sh`.
  - `OtaHooksTest.mjs`: `queueHook` over `'.class public LY3/V;\n.method public static o(LY3/S;)V …'` with `OTA_107` yields exactly one `turboioOriginal_o`.
- [ ] **Step 2:** Run `node android-addon/tests/HostProfilesTest.mjs` and the new Java test. Expected: FAIL (no 1.0.7 profile, no `V107`).
- [ ] **Step 3: Implement.**
  - `HostAbi.get()`: forced `"1.0.7"` → `V107`; otherwise probe `matches(V107)`, then `matches(V106)`, then fall back to `V105`.
  - `package.mjs`: allow `'1.0.7'`. Choose `otaAbi` from `{ '1.0.5':OTA_105, '1.0.6':OTA_106, '1.0.7':OTA_107 }`. Change the 64K split guard to `['1.0.6','1.0.7'].includes(profile.version)`. Update the error text to list `1.0.7 (230)`.
- [ ] **Step 4: Verify on the real host.**
  - Unit tests now PASS.
  - `node -e` call to `verifyHost('android-addon/build/host-107', PROFILES['30239f65…'])` returns without throwing. This was already demonstrated this session with a patched copy of the verifier.
  - `node android-addon/package.mjs <1.0.7 APK>` produces `build/TurboIO-RayNeo-1.0.7-unsigned.apk`.
  - `python3 android-addon/verify_apk.py` on it passes.
- [ ] **Step 5: Commit** `feat(android): support RayNeo AI 1.0.7 (230) host ABI`.

### Task 2: 1.0.7 official-OTA source routing

**Files:**
- Modify: `android-addon/official-ota-source.mjs:8-16`, `android-addon/tests/OfficialOtaSourceTest.mjs:5`

**Interfaces:**
- Produces: `SOURCES['a35159a8…a45c'] = [{offset:0x88512e, text:'/xrlauncherapi/v1/signApi/gray/upgrade'}, {offset:0xe1e48, text:'/xrlauncherhwapi/v1/signApi/gray/upgrade'}]`.

- [ ] **Step 1: Failing test.** In `OfficialOtaSourceTest.mjs`, search `['host-107','host-106','host-105']`. When `host-107` exists, assert that `patchAndroidSource(input).report.changes.length === 2`, that both changed offsets equal the pins, and that the output length equals the input length.
- [ ] **Step 2:** Run `node android-addon/tests/OfficialOtaSourceTest.mjs`. Expected: FAIL with `Unsupported Android libapp.so`.
- [ ] **Step 3:** Add the pin and update the header comment to `1.0.5 / 1.0.6 / 1.0.7`. `patchAndroidSource` keeps its existing checks: uniqueness, length/CID byte `0x80+(len<<1)`, hash-preserving replacement, and no byte changed outside the strings.
- [ ] **Step 4:** Test PASSES. Then run `python3 android-addon/package-official-ota-preparation.py --guarded <1.0.7 APK> <unsigned> <patched libapp.so> <out>`. Expected: it succeeds.
- [ ] **Step 5: Commit** `feat(android): route 1.0.7 official OTA source`.

### Task 3: TVP2 as the single upgrade candidate

TVP2-only scope applies here: delete `TAP1_PINS`, `TMIG1_PINS`, the host-conditional ternaries and the `TMIG1` flag outright, so that `OtaPackage` holds exactly one candidate. Remove `PROFILES` entries for 1.0.4/1.0.5 and `OTA_105`/`ABI_105`/`HostAbi.V105` in Task 1. Delete or convert tests that only exercise TAP1 (`OtaTest`, `OtaControllerTest`, `OtaInstallGuardTest` feed TAP1 inputs) so they run against the TVP2 ZIP, and keep every safety assertion they contain. Where the steps below say "TMIG1 → TVP2", read that as "the one candidate".

**Files:**
- Modify: `android-addon/src/com/turboio/addon/OtaPackage.java:8-47`, `OtaSession.java:26`, `OtaUI.java:5`, `android-addon/build.sh:44-51`
- Rename + modify: `android-addon/tests/Tmig1CandidateTest.java` → `android-addon/tests/Tvp2CandidateTest.java`

**Interfaces:**
- Produces: `OtaPackage.TVP2` (boolean, true when the host version is `1.0.6` or `1.0.7`), replacing `OtaPackage.TMIG1`. On TVP2: `TOKEN="TVP2"`, `CODE="TVP2"`, `NAME="TVP2 · 清晰投屏与仪表盘兼容"`, `MARKER="显示 Turbo IO 三排菜单"`, `VERSION="Strix OS 1.0.5.5"`. `BASES`/`BASE_CODES`/`FEED_*`/`DIRECTORY` stay as they were for TMIG1. `ZIP_SIZE=8861428`, `AP_SIZE=7435336`, `ZIP_SHA`/`AP_SHA` per Global Constraints. The stock-restore constants (`STOCK_AP_SIZE=7208648`, `STOCK_AP_MD5=0246c12a…`, `STOCK_MANIFEST=db67ff62…`) are unchanged. `TVP2_PINS` equals `TMIG1_PINS` except `OtaFileInfo.json 2700 843304cf…d05b` and `nuttx_ap.bin 7435336 "+AP_SHA`.

- [ ] **Step 1: Failing test.** Port `Tmig1CandidateTest` to `Tvp2CandidateTest` with these assertions:
  - `OtaPackage.TVP2 && "TVP2".equals(OtaPackage.TOKEN) && OtaPackage.PIN_COUNT==16`.
  - `verify(tvp2Zip)` passes, with `size("nuttx_ap.bin")==7435336`.
  - The TMIG1 ZIP, the stock 1.0.5.5 ZIP, the TAP1 ZIP and a 1-bit-flipped TVP2 ZIP are each **rejected**.
  - `arm(pkg,"peer","TMIG1",…)` is rejected.
  - The feed serves the TVP2 bytes for base codes `01.00.04.0012` and `01.00.05.0005`, and null for `01.00.04.0011`.
  - `freshBoot` is false after a `Strix OS 1.0.4.12` readback and true only after `Strix OS 1.0.5.5`. The manual result-guard release stays covered by the existing `OtaInstallGuardTest`, which `build.sh` keeps running unchanged.
  - Run under both `-Dturboio.host=1.0.6` and `-Dturboio.host=1.0.7`.
- [ ] **Step 2:** Run it. Expected: FAIL on the size/SHA check.
- [ ] **Step 3: Implement** per the Interfaces block. Rename the `TMIG1` uses in `OtaSession.java:26` and `OtaUI.java:5`. Update the `OtaUI` copy to describe TVP2 in one line: 540×220 HD screen-casting runtime, dashboard compatibility, AP only, other 14 payloads unchanged. In `build.sh`, point `tvp2_candidate=../official-addon/build/strix-1.0.5.5-tvp2/StrixOS-1.0.5.5-TurboIO-TVP2-CANDIDATE-NOT-APPROVED.zip`. Pass the TMIG1 ZIP, the stock ZIP and the TAP1 ZIP as must-reject inputs. Run `OfficialOtaFeedTest`, `OfficialOtaDirectoryTest` and `OfficialOtaGateTest` with `$tvp2_candidate` under both host values.
- [ ] **Step 4:** `bash android-addon/build.sh`. Expected: all suites PASS.
- [ ] **Step 5: Commit** `feat(android): TVP2 OTA candidate for hosts 1.0.6/1.0.7`.

### Task 4: Dashboard correctness on TVP2 and legacy 1.0.5.5

**Files:**
- Modify: `android-addon/src/com/turboio/addon/CardTransport.java:20-31`
- Test: `android-addon/tests/cardflow/CardFlowTest.java:33-41`

**Interfaces:**
- Consumes: the existing `legacy(Map)` predicate (true when the reply has `widgets` but no `widgets_v2`).
- Produces: the status string `"此固件不支持自定义卡片（原厂 1.0.5.5 已移除安装命令）；需刷 TVP2"` on legacy install/remove.

- [ ] **Step 1: Failing test.** Replace the legacy install/remove block in `CardFlowTest` with three checks:
  - `publish(doc,true)` followed by `config(legacy)`: no further packet is sent, `!busy()`, and the status contains `需刷 TVP2`.
  - `remove(...)` followed by `config(legacy)`: same three conditions.
  - The read-only inspect on legacy still lists the native ids (unchanged).
  Keep the existing TVP2-shaped flow, where replies carry `widgets_v2` and the flow goes install → verify → pin → verify, as the positive path.
- [ ] **Step 2:** Run the card-flow suite from `build.sh`. Expected: FAIL, because the current code sends `widget_install` on legacy.
- [ ] **Step 3: Implement (TVP2-only).** Delete `legacy`, `sameLegacy`, `UNVERIFIED` and every legacy branch. This reverts `737ce07`'s behavior, so a reply without `widgets_v2` again fails in `CardCodec.rows`. Change that exception text to `"眼镜未返回 widgets_v2：需刷 TVP2（键="+keys+"）"` so the existing `end(...)` path shows it before anything is sent. Replace the comment at line 21 with: `Only TVP2's dashboard-compat-v1 accepts widget_install/uninstall and reports widgets_v2; stock 1.0.5.5 removed both.` The read-only legacy inspect test is deleted along with the branch.
- [ ] **Step 4:** The suite PASSES. Also run `CardCodecTest`. Expected: PASS. The install payload is unchanged, and this session already checked it against `dashboard-compat-v1/native.c` (`package()`): it requires a single `root` Text component, the `TCE1:` prefix, the fixed catalog URL and the `turbo_ui_card_` prefix.
- [ ] **Step 5: Commit** `fix(android): refuse dashboard edits on firmware without TVP2 compat`.

### Task 5: Docs and full verification

**Files:** Modify `android-addon/README.md` (header block, "包含与不包含", source-build section).

- [ ] **Step 1:** README: supported hosts 1.0.6 (216) / 1.0.7 (230) with their SHA-256s; TVP2 is the only firmware, and 1.0.5/TAP1/TMIG1 are no longer supported; TVP2 dashboard note; parity status table linking this plan, with Phases 2–5 marked "未移植". Make no device-verification claims: nothing in Phase 1 has run on hardware.
- [ ] **Step 2:** `bash android-addon/build.sh` from a clean `android-addon/build/test`. Expected: every suite prints its PASS line and the script exits 0.
- [ ] **Step 3:** Package both hosts. `node android-addon/package.mjs` on the 1.0.6 and the 1.0.7 APK each produce an unsigned APK, and `python3 android-addon/tests/PrivateArtifactAudit.py` passes on each after a throwaway debug signature.
- [ ] **Step 4: Commit** `docs(android): host 1.0.7, TVP2 candidate, parity roadmap`.

Phase 1 ends here. Device checks the user must run: install the 1.0.7 build, confirm the host hooks load, flash TVP2 via the guarded flow, then publish one TCE1 card and confirm it on the lens.
