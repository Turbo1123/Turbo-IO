# Android Phase 3b-1 — Subtitle HUD Lab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the iOS 1.0.7 "字幕导航 · 常亮与换文" research page (SubtitleHUD/SubtitleHUDCore, subtitle-hud-v1.1). It is a pure-display trial on the stock AI_SUBTITLE business (19):
- a temporary preview session under our own SID;
- three manual text frames A/B/C (mode 3, status 0);
- stop on subtitle audio;
- a user idle confirmation, valid 120 s, before every start.

**Architecture:**
- `SubtitleTrial` (pure): port of TIOSubtitleTrial with an injected sender and clock; it also provides StopContract.
- `SubtitleHud` (glue):
  - sends through the existing biz-19 host send, shared with NavGlasses via `NavGlasses.submit`;
  - receives through `NativeTransfer.event` (observe-only, like iOS);
  - is mutually exclusive with NavGlasses and the shared lane.
- `SubtitleHudUI`: the 8-row page under 诊断与测试.

**Spec:**
- `official-addon/ios107-edition/{SubtitleHUD.m,SubtitleHUDCore.m,SubtitleHUDTests.m}`.
- Digest at `/tmp/claude-1000/-home-chemhack-Code-turbo-Turbo-IO/827a6319-cfb8-421f-a111-fa831dc25a35/scratchpad/phase3b-digest.md` §3.

## Global Constraints

- **Packets:** `NavCore.packet` types 7 / 5 / 3.
- **Start (type 7):** `{sid:<32 hex>,force:false,scope:"temporary",config}`. The default config is `{"font_size":2,"content_width":100,"max_lines":5,"position":"center","is_display":true,"straight_view":"original"}`.
- **ACK (type 8):** must carry the same sid and a code that is 1 or 2 (integral, not a bool).
- **Text (type 5):** `{sid,mode:3,status:0,content:{source_transcript}}`.
- **Stop (type 3):** `{sid,reason_code:10,text:""}`.
- **Trial:**
  - Phases are idle, starting, ready, stopping and uncertain.
  - Timers: a 10 s ACK deadline, an 8 s stop deadline, 240 s of manual lifetime, and 3 frames at least 3 s apart.
  - Navigation limits are 80 frames / 240 s / 3 s; live-caption limits are 2400 frames / 1200 s / 0.5 s.
  - Text is at most 384 B UTF-8.
  - Incoming type 4 (audio) → audioPackets++ and a stop. Type 3 with our sid → stop.
- **Copy:** the frame texts, notes and page strings are verbatim from the digest.
- **Glue:**
  - Starting requires the idle confirmation within 120 s, the connected peer, the page in the foreground, `!NavGlasses.active()` and `!NativeTransfer.busy()`. Starting consumes the confirmation.
  - Text submit has an 8 s SDK-callback deadline.
  - Leaving the page or pausing the Activity stops the trial with `离开字幕测试页`.

## Review Focus

1. No text frame is sent before the ACK with the same SID arrives.
2. A subtitle audio packet stops the trial immediately, and nothing more is sent.
3. The trial and NavGlasses (navigation or caption) never run at the same time.
4. Leaving the page always requests the exit.
5. A refused or failed stop leaves the trial uncertain and blocks a restart until the user confirms the lens is idle.

---

### Task 1: SubtitleTrial

**Files:** Create `src/com/turboio/addon/SubtitleTrial.java` and `tests/SubtitleTrialTest.java`.

**Tests:** A port of the SubtitleHUDTests list in the digest: StopContract, start validation, the frame cadence of 13/14/16/19/25, the round trip, lifetime 249/250/258/259, audio, the ACK timeout, live caption and navigation.

### Task 2: Glue + page

**Files:**
- Create `SubtitleHud.java` and `SubtitleHudUI.java`.
- Modify `NavGlasses` (extract `submit`, refuse while `SubtitleHud.active()`), `NativeTransfer` (route `event` to `SubtitleHud`; `blocked`/`acquireMessages` honor `SubtitleHud.active()`), the HostEventTest stub, and `DiagnosticsUI` (add the entry).

Verify: `build.sh` is green, and packages 1.0.7 and 1.0.6 are clean.
