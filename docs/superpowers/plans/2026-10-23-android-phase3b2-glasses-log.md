# Android Phase 3b-2 — Glasses Log (local only) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the iOS 1.0.7 "眼镜日志 · 仅本机" (GlassesLogContract/Gate/Probe, log-local-v3).
1. The page asks the glasses once, over the stock LOG_REPORT business (11), for their log archive.
2. The add-on intercepts the ACK and the received-file events before the official Flutter app sees them, so its auto report never uploads.
3. It copies `venus_<n>_log.tar.lz4` into a private directory with SHA-256, and the user can share the copy.
4. Ownership persists across restarts, and nothing is ever retried automatically.

**Architecture:**
- Pure:
  - `A2uiFrame`: the RNLink A2UI envelope with sequence and mode fields.
  - `GlassesLogContract`: task id, ACK, file event and window.
  - `GlassesLogGate`: the ownership/quarantine state machine, with a snapshot.
- Files: `GlassesLogFiles` (no-symlink local path check, stable copy, SHA-256, receipts).
- Hooks:
  - Pre-delivery `GlassesLog.consume(kind,map)` in the `j.z` event wrapper (fail-open).
  - `QueueTap.allow(message)` first in the SDK queue hook (fail-open). It records recent official LAUNCHER traffic and blocks an official type-16 log request while we own one.
- Glue: `GlassesLog` and `GlassesLogUI` under 诊断与测试.

**Spec:**
- `official-addon/ios107-edition/GlassesLog{Contract,Gate,Probe}.{h,m}` and their `*Tests.m`.
- Digest §1 at `/tmp/claude-1000/-home-chemhack-Code-turbo-Turbo-IO/827a6319-cfb8-421f-a111-fa831dc25a35/scratchpad/phase3b-digest.md`.

## Global Constraints

- **Request (type 16, random seq 1..0x3fffffff):** `{"cmd":"start_log_task","payload":{"data":"","mode":0,"value":0}}`, sorted keys.
- **ACK (type 17):**
  - cmd is `start_log_task_ack`; payload `value` is integral (not a bool), `mode` is 0, and `data` is empty or a task id.
  - The task id is 36-char or 32-hex, canonicalised to dashed lowercase.
- **File (`fileShareSuccess`):**
  - The event is role receiver and comes from our device.
  - Its taskId is canonically equal to ours.
  - fileName matches `^venus_[0-9]{1,20}_log\.tar\.lz4$`, and filePath is absolute, with no NUL and no `..`, and its last component equals fileName.
- **Window:** 180 s. **Size:** ≤ 32 MiB. **Quarantine:** at most 32 rounds.
- **Storage:** `noBackupFilesDir/turboio/glasses-log/` holds `owner.json`, `archive.json`, `receipt-<task>.json` and `research-<uuid>.tar.lz4` (0600).
- **Ready:**
  - Official LAUNCHER traffic was observed within the last 120 s.
  - The page is in the foreground.
  - Not copying or restoring.
  - The snapshot is empty or renewable.
- **Copy:** the source is under the host `cc_transfer` sandbox (`getExternalFilesDir(null)/cc_transfer` or `getFilesDir()/cc_transfer`) and passes the no-symlink walk. Size and mtime must stay stable, and the copy is fsynced. The original is never deleted or extracted.
- **Copy text:** the iOS strings verbatim (digest §1).

## Review Focus

1. Hook failures never block or swallow official traffic (both hooks fail open).
2. Only our owned task's ACK and file events are consumed; everything else reaches Flutter.
3. No retry after a timeout or an unknown result; an unsettled round blocks restarts.
4. A symlink or path escape can never make the copy read outside the receive sandbox.
5. A restored receipt can never revive a retired task.

---

### Task 1: A2uiFrame + GlassesLogContract + GlassesLogGate

**Files:** Create `src/com/turboio/addon/{A2uiFrame,GlassesLogContract,GlassesLogGate}.java` and `tests/GlassesLogTest.java`.

**Tests:** Ports of GlassesLogContractTests (excluding the iOS md5 cache branch) and GlassesLogGateTests 1–5, plus the A2UI round trip and refusals.

### Task 2: GlassesLogFiles

**Files:** Create `GlassesLogFiles.java` and `tests/GlassesLogFilesTest.java`.

**Tests:** Using a temp dir: localPath is OK under the root and refused above the limit; the copy is identical and keeps the original; limit 1 refuses; a different root refuses; a symlinked dir refuses both the path and the copy; restore validates SHA and size.

### Task 3: Hooks + glue + page

**Files:**
- Modify `ota-hooks.mjs` (`LOG_CONSUME` export; `QueueTap` in `queueHook`), `tests/OtaHooksTest.mjs`, `package.mjs`, `HostBusiness` (11, 22) with its test, `host-profiles.mjs` (enum names) with its test.
- Create `QueueTap.java`, `GlassesLog.java` and `GlassesLogUI.java`, plus the DiagnosticsUI entry.

Verify: `build.sh` is green, packages 1.0.7 and 1.0.6 are clean, and the packaged smali contains both hook calls.
