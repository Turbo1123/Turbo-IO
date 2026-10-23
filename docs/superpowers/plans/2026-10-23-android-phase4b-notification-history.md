# Android Phase 4b — Notification History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Match iOS 1.0.7 "通知历史" (`notification-archive-v1`) on Android: an opt-in, local-only archive of notifications with search, detail, clear and bounded retention.

**Architecture:**
- **Different source from iOS.** iOS records biz-21 ANCS reports that the glasses send back. The Android host has no ANCS; it forwards phone notifications through its own `NotificationListenerService` (`im.zoe.labs.flutter_notification_listener.NotificationsHandlerService`).
- **Hook.** The add-on wraps that service's `onNotificationPosted` and `onNotificationRemoved` in "original first, then observe, swallow errors" mode (the existing `wrap()` patcher, `onPostResume` style).
- **Record.** It turns each `StatusBarNotification` into a bounded record.
- **Store.** Records go to a pure-Java append-only store with compaction, which is JVM-testable. The iOS store is SQLite.

**Tech Stack:** Java 8 sources, `package.mjs` smali wrapping, `host-profiles.mjs` `verifyHost`.

**Spec:** iOS `official-addon/ios107-edition/notification-archive-v1/` (NotificationArchive.m, NotificationRuntime.m, NotificationUI.m) and the parent roadmap Phase 4 row ("NotificationListenerService instead of biz 21 — verify"). Verified 2026-10-23: both hosts (1.0.6/1.0.7) have `NotificationsHandlerService.onNotificationPosted/onNotificationRemoved(Landroid/service/notification/StatusBarNotification;)V` in `smali_classes3`.

## Global Constraints

- **Default and opt-in:** default off (pref `notification_archive`). Enabling shows the iOS dialog text, adapted to "官方 App 通知监听". Turning it off keeps the history; clearing needs its own confirmation.
- **Never alter official behaviour:**
  - The original method always runs first, exactly once.
  - Any add-on exception is swallowed.
  - The observer does no work on the binder thread beyond a bounded copy; it uses one serial executor, with ≤ 64 pending events and the excess dropped and counted.
- **Record:** `uid` = sbn key (≤128); `appId` = package (≤256); `appName` = app label (≤2048); `title` = `android.title`; `subtitle` = `android.subText`; `content` = `android.bigText`, else `android.text` (≤32768); `timestamp` = postTime in ms as a string (≤128).
  - `eventId`: 0 added, 1 modified (key already seen in this session), 2 removed.
  - `session`: a UUID per process.
  - `receivedAt`: wall seconds.
  - `origin`: "phone-nls".
  - `id` = sha256 of the canonical record without `id`/`receivedAt` (iOS `TNAFingerprint`).
  - Strings containing NUL are rejected.
  - Notifications of the host's own package and ongoing/foreground-service notifications (`FLAG_ONGOING_EVENT|FLAG_FOREGROUND_SERVICE`) are skipped. They are status, not messages.
- **Store** (iOS `TNAStore` limits): keep 30 days, ≤ 2000 records, ≤ 8 MiB of record bytes, ≤ 64 KiB per record; duplicate ids are ignored. Search is case-insensitive over appName/appId/title/subtitle/content (≤ 200-char query, ≤ 2000 results, newest first). `clear()` removes everything.
  - Files live under `files/turboio/notifications/`, mode 0600, excluded from backup (the add-on already sets `allowBackup` per host).
- **Status** has counts only (observed, inserted, duplicates, invalid, overflow, writeFailures, pending), never content.
- **UI** (iOS NotificationUI strings, adapted source line): switch "保存官方 App 收到的通知", list with search, detail view, clear. Entry under 设置.

## Review Focus

1. Official notification forwarding still works with the archive on or off (the original is called first, and exceptions are swallowed).
2. Privacy: off by default, no network, no model, content never in status/logs.
3. A burst of notifications can't block the listener thread or grow memory without bound (pending ≤ 64, drops counted).
4. Corrupt store lines are skipped and compacted away, never crash.
5. Disabling stops new writes immediately (queued events are dropped on generation change).

---

### Task 1: NotificationArchive store + record (pure)

**Files:** Create `src/com/turboio/addon/NotificationArchive.java` and `tests/NotificationArchiveTest.java`.

**Produces:**
- `static Map<String,Object> record(String key,String pkg,String appName,String title,String subtitle,String content,long postTime,int eventId,String session,double receivedAt)` (null when invalid);
- `static String fingerprint(Map)`;
- `Store(File dir)` with `insert(record,now)` → "inserted"/"duplicate"/"error", `search(query,limit)`, `status()`, `prune(now)` and `clear()`.

**Tests:**
- The fingerprint ignores `receivedAt`.
- A NUL in the title → null.
- A duplicate insert → "duplicate".
- 2001 inserts keep 2000 (oldest evicted).
- An 8 MiB cap evicts oldest.
- Records 31 days old are pruned.
- Search is case-insensitive over content and app name, newest first.
- A corrupt line in the log is skipped and removed on compaction.
- `clear` empties.
- Reopening the store reads persisted records and dedupes against them.

### Task 2: Runtime + hook

**Files:**
- Create `NotificationRuntime.java`: the enable pref, generation, serial executor, pending cap, session, counters, and `posted(Object service,StatusBarNotification)` / `removed(...)`.
- Modify `package.mjs`: wrap both methods in after mode.
- Modify `host-profiles.mjs` `verifyHost`: require both method headers in `im/zoe/labs/flutter_notification_listener/NotificationsHandlerService`.
- Modify `tests/HostProfilesTest.mjs` (fixture plus a negative case) and `TurboAddon.java` (dispatch statics).

**Tests:**
- `NotificationRuntimeTest` (pure part via an injected extractor): disabled → nothing stored; enabled → stored; the 65th pending event is dropped and counted; a generation change drops queued work; the same key twice gives eventId 1; ongoing and host-package notifications are skipped.
- `HostProfilesTest`: a host without the listener methods is refused.
- `package.mjs` on 1.0.7 → `unexpected_paths` empty; the wrapped smali contains `turboioOriginal_onNotificationPosted`.

### Task 3: UI

**Files:** Create `NotificationHistoryUI.java` (switch with consent dialog, status line, search box, list, detail dialog, clear with confirmation) and add the entry in the 设置 tab.

Verify: `build.sh` green; package 1.0.7.
