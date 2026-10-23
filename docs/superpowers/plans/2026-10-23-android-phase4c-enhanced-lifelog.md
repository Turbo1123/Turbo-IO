# Android Phase 4c — Enhanced Lifelog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port iOS 1.0.7 "增强智记" (`enhanced-lifelog-v1`) to Android. The user picks one day, includes the official cached lifelog transcript, ticks notifications from the local notification archive, previews exactly what will be sent, approves one model call, and gets a source-cited summary saved locally.

**Architecture:**
- **Pure core:**
  - `TnlCore` ports TNLContext.m: candidates, context, preview, model body, answer validation and rendering.
  - `TnlStore` ports TNLStore.m: results file, 30 days / 30 results / 512 KiB.
- **Thin glue:** `EnhancedLifelogUI` reuses:
  - `CeLifelog.read` / `CeBridge.dirs` for speech;
  - `NotificationTap.runtime(...).store().search("",2000)` for notifications;
  - the model config and fixed-text HTTP handling of `CeBridge`, factored as `ModelCall`.

**Tech Stack:** Java 8, plain JVM tests in `build.sh`.

**Spec:** `official-addon/ios107-edition/enhanced-lifelog-v1/` (TNLContext.m, TNLClient.m, TNLStore.m, TNLUI.m, TNLUIFixture.m).

## Global Constraints

- **Notification candidates (TNLNotificationCandidates):**
  - Use only archive records from the selected half-open range [start, end), which is at most 25 h (90000 s).
  - Only eventId 0/1 (a removal is not a message), deduplicated to the latest per (session, appId, uid).
  - Rejected: text `title\nsubtitle\ncontent` that is unclean (a control character other than \n\r\t), sensitive (iOS regex), or over 4096 UTF-8 bytes.
  - Output: `{id:"n-"+sha256(json[id]), kind:"notification", app, appId, text, at (ISO), timeMeaning:"phone_received_at", originalTimestamp}`.
  - Android ruling: archive origin is "phone-nls", and the identity drops `deviceHash` (there is no glasses peer).
- **Context (TNLBuildContext):**
  - ≤ 64 selected notifications, which must be a subset of the current candidates, otherwise "选中的通知已变化，请重新读取和预览。".
  - Their bytes are reserved first (≤ 32768 total, otherwise an error).
  - Then speech rows in time order: clean, not sensitive, ≤ 4096 bytes, deduplicated by id "s-"+sha256(json[at,text]), ≤ 64. Rows that don't fit are counted in `speechOmitted`.
  - Schema 1 with keys start, end, timezone, rows, speechCount, notificationCount, speechOmitted, partial:true.
  - The identity hash is SHA-256 of the add-on's canonical JSON array (ids are only compared on the phone).
- **Model body (TNLModelBody):** re-validates every row and field. Uses the exact iOS system prompt, temperature 0.2, max_tokens 2500, sorted-key user JSON ≤ 40000 bytes, and the optional `thinking` disabled.
- **Answer (TNLValidateAnswer):**
  - Response ≤ 128 KiB; one choice; finish_reason "stop" or absent; no tool calls.
  - Content ≤ 24000, optionally wrapped in ```json fences.
  - `{items:[{text ≤800, clean, not sensitive, sources: 1..16 known ids}]}`, 1..20 items, ≤ 16384 text bytes.
  - Otherwise "模型返回格式或来源引用无效；没有保存，也不会自动重试。".
- **Render/preview:** the exact iOS texts (TNLPreview, TNLRenderAnswer), with local times in the chosen zone ("MM-dd HH:mm:ss").
- **Store:** `files/turboio/enhanced-lifelog/results.json`; ≤ 30 results, newest first; trimmed to ≤ 480 KiB on save; file ≤ 512 KiB; results older than 30 days are deleted on read. Each result stores only id, createdAt, text, provider host, model, start, end and counts — never the inputs or the key.
- **Privacy:** nothing is sent without the preview and an explicit approval. The scope (account cache hash) and the config are re-checked at approval. Synthetic demo results are never saved.

## Review Focus

1. Only explicitly selected notifications are sent, and a selection that went stale is refused.
2. Sensitive or oversized text is excluded, not truncated.
3. Model answers citing unknown sources are rejected.
4. The key never reaches status or results.
5. Stored results are bounded and expired results are deleted on read.

---

### Task 1: TnlCore

**Files:** Create `src/com/turboio/addon/TnlCore.java` and `tests/TnlCoreTest.java`.

**Tests:**
- Candidates:
  - range limit (90001 s → empty);
  - removed events excluded;
  - latest update wins;
  - a 验证码 text is excluded;
  - a duplicate text is collapsed.
- Context:
  - a stale selection gives the iOS error;
  - more than 32 KiB of notifications gives an error;
  - speech is sorted and capped at 64, with omitted counted;
  - no rows gives the iOS error.
- Body: extra keys are refused; the system prompt starts and ends exactly as iOS; temperature 0.2.
- Answer:
  - a fenced JSON answer is accepted;
  - an unknown source is refused;
  - 21 items are refused;
  - finish_reason "length" is refused.
- Render and preview: expected text.

### Task 2: TnlStore

**Files:** Create `src/com/turboio/addon/TnlStore.java` and `tests/TnlStoreTest.java`.

**Tests:**
- save then read, newest first;
- 31 saves keep 30;
- a 31-day-old result is deleted on read (the file is rewritten);
- a corrupt file → error, and saving does not overwrite it;
- clear.

### Task 3: ModelCall + EnhancedLifelogUI

**Files:**
- Create `ModelCall.java`: shared config from `CeBridge.config()`, the POST with fixed error texts, a response cap parameter, cancel.
- Make `CeBridge.generate` use it.
- Create `EnhancedLifelogUI.java`: date, include-speech switch, read day, notification checkboxes, preview, approval dialog, generate, history, clear, synthetic demo.
- Add the entry in 设置.

Verify: `build.sh` is green and package 1.0.7 is clean.
