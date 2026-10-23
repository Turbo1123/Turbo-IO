# Android Phase 4f — Always-on (全天智记) Audio Saving Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port iOS 1.0.7 "全天智记音频" (AlwaysOnAudio*). The user explicitly turns on the official app's own always-on debug audio dump (realtime + cached audio, no event-text log). The page lists the resulting session files and shares stable copies. Ogg/Opus copies are validated, and finalized if they need a granule repair.

**Architecture:**
- **Host side (verified 2026-10-23 in both hosts):**
  - The plugin `Lcom/rayneo/rayneo_venus_sdk_plugin/f;` holds the always-on controller in field `y` (1.0.6 `Ll8/l;`, 1.0.7 `Lm8/k;`).
  - Controller methods: `f(ZZZZ)V` = configureDump(enabled, realtime, cached, events) and `k()Ljava/util/LinkedHashMap;` = status (keys dumpEnabled, dumpRealtimeAudio, dumpCachedAudio, dumpEvents, realtimePackets, cachedPackets, alwaysOnRunning, sessionDir, …).
  - The dump root is `getExternalFilesDir(null)` (else `getFilesDir()`) + `/always_on_debug/sessions/<id>/`.
- **Capture:** the add-on gets the plugin instance through a guarded static call injected before every `return-void` of `f.<init>()V` (`package.mjs`). `verifyHost` gates the constructor, field and both methods.
- **Pure core:** `AlwaysOnAudio` covers listing, kind, stable copy, the Ogg/Opus scan/repair (port of AlwaysOnOgg.m), status parsing and set-verification.
- **Glue:** `AlwaysOnAudioUI` (switch with the consent text, status, list, share via `RecordingExports.share`).

**Spec:** `official-addon/ios107-edition/AlwaysOnAudioFiles.m`, `AlwaysOnOgg.m`, `AlwaysOnAudioNative.m`, `AlwaysOnAudioUI.m`.

## Global Constraints

- **Saving:** `configure(enabled, realtime=true, cached=true, events=false)`, then read the status back. Success needs dumpEnabled == enabled and, when enabling, dumpEvents false with realtime and cached true (iOS `TIOAOSetAudioSaving`). It is never on by default and never starts the always-on session itself.
- **Listing (TIOAOAudioFiles):**
  - Only files under `<root>/always_on_debug/sessions` at depth ≤ 2, with extension opus/ogg/pcm, regular, size 1 B..1 GiB, no symlinks, ≤ 4000 entries visited, ≤ 500 rows, newest first.
  - Kind: name contains "cached" → 缓存音频, "realtime" → 实时音频, else 智记调试音频（来源待核对）.
- **Copy (TIOAOAudioCopy):**
  - Only a listed file, which must be unchanged during the copy (size and mtime).
  - Copied to the add-on's no-backup `turboio/always-on-exports/<uuid>/全天智记音频.<ext>` (iOS: Documents/TurboIOAlwaysOnExports).
  - .ogg/.opus copies must pass the Ogg/Opus scan, and are rewritten when the granule positions need the iOS repair; otherwise the copy is refused and deleted.
- **Sharing:** refused while always-on is running ("请先停止官方全天智记，等音频落盘后刷新再分享。") or while saving is on ("请先关闭上方音频保存开关，让官方写完文件尾，再刷新分享。不会删除原件。").
- **UI copy:** the iOS strings verbatim (consent "保存之后的智记音频？" text, footers).

## Review Focus

1. Saving is only enabled after explicit consent and is verified by reading the status back.
2. The listing cannot escape the sessions dir (symlinks, depth).
3. A file still being written is never shared.
4. The Ogg repair never corrupts a valid file.
5. The injected constructor hook can never break plugin construction.

---

### Task 1: AlwaysOnAudio core

**Files:** Create `src/com/turboio/addon/AlwaysOnAudio.java` and `tests/AlwaysOnAudioTest.java`.

**Tests:**
- Listing: depth, extension, symlink skip, kind names, newest first.
- Copy: refuses an unlisted file, refuses a file that changes during the copy, copies a listed file.
- Ogg:
  - a synthetic valid Ogg Opus stream (OpusHead, OpusTags and three 20 ms packets, correct CRC and granules) passes unchanged;
  - a stream with legacy granules (count*960+skip) is repaired, and the CRCs then validate;
  - a truncated stream or a bad CRC is refused.
- `verify(status, enabled)` follows the iOS rule.

### Task 2: Host ABI + capture hook

**Files:** Modify `host-profiles.mjs` (`alwaysOn` descriptor per version plus the `verifyHost` gate), `tests/HostProfilesTest.mjs` (fixture plus a negative case), `package.mjs` (constructor tap) and `TurboAddon.java` (`sdkPlugin(Object)`, which keeps a WeakReference). Create `AlwaysOnHost.java` (reflection using the ABI names from `HostAbi`: field `y`, methods `f(ZZZZ)` and `k()`).

**Tests:**
- `HostProfilesTest`: both hosts pass; a host without `f(ZZZZ)V` is refused.
- The packaged 1.0.7 smali contains the tap before `return-void` in `f.<init>`.

### Task 3: AlwaysOnAudioUI

**Files:** Create `AlwaysOnAudioUI.java` and add an entry in the 录音与全天智记 area.

Verify: `build.sh` is green and package 1.0.7 is clean.
