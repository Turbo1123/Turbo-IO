# Android Phase 3b-3 — Todo Protocol Test + create_todo Tool Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port iOS 1.0.7 "待办协议验收" (TodoRuntime/TodoProtocol) and the `create_todo` model tool (WebSearch.m batch rules). Creation always goes through the **official** voice path:
1. Capture a real official NLP `create_task` result (or the current voice chat context).
2. Replay it into the official listener with our title.
3. Prove creation only by the official full list push (biz 22 type 6, outgoing) gaining exactly one new item with that title.
4. Never retry; an unknown result blocks further tool writes, even across restarts.

**Architecture:**
- Pure:
  - `TodoProtocol`: envelope, snapshot, physical status, create intent, new candidate, tool title, turn gate.
  - `ToolTurn`: the iOS per-turn tool batch rules, tool_choice, and the sanitized todo result.
- Glue:
  - `TodoRuntime`: queue-tap snapshot observer, biz-22 physical route, NLP template capture in `TurboAddon.dispatchNlp`, NlpResult/NlpCommand construction by reflection, a 25 s timeout, and the unresolved flag in SharedPreferences.
  - `TodoUI` under 诊断与测试.
  - `TurboAddon.request` gains the turn gate, `create_todo` (voice turns only), `parallel_tool_calls:false`, the batch rules and 3 rounds.

**Spec:** `official-addon/ios107-edition/{TodoRuntime.m,TodoProtocol.m,TodoProtocolTests.m,TodoToolFlowTests.m,WebSearch.m}`; digest §2.

## Global Constraints

- **Snapshot (type 6):** `{total,isLastBatch,eventList:[{eventType:1,status:0|1,eventID:int64,title:1..240}]}`, ≤2000 rows, unique ids. It is full iff isLastBatch is true and total equals the count.
- **Physical (type 4, incoming):** `{eventType:1,status:0|1,eventID,lastModifiedTime}`. The device id matches `[A-Za-z0-9:_-]{1,200}`.
- **Integers:** non-negative Long (not Boolean, not a float, not a string).
- **Create intent:** domain `task`, intent `create_task`. Params are a map or JSON text; `task` is a map or JSON text. `content` is ≤240 chars and non-blank after trimming.
- **New candidate:** after = before + exactly one row. Old rows are identical, no old row has the title, and the new row has the title with status 0. Wire ids are canonical decimals ≤ int64 max.
- **Tool title:** a JSON object with exactly `{title}` as a String, ≤240 chars, no control chars, non-blank after trimming. ≤4000 raw.
- **Turn rules (WebSearch.m):**
  - At most 3 model rounds. `parallel_tool_calls:false`.
  - tool_choice is `none` once ride, todo or knowledge was attempted, or after ≥2 searches; otherwise `auto`.
  - Batch rules exactly as iOS lines 164–171, with the iOS texts.
- **Tool result:** exactly `{"status":S,"glasses_verified":false,"retry_allowed":false}` with S ∈ {created, not_ready, rejected, unknown}.
- **Unresolved flag:** pref `todo_unresolved_submission` is committed before injection and cleared only on `created`. While it is set every tool call gives `rejected`.
- **Timers:** template and snapshot freshness 120 s; result wait 25 s.
- **UI copy:** the iOS strings verbatim.

## Review Focus

1. A todo is never created twice: no retry after unknown or timeout, and the unresolved flag survives a restart.
2. `created` is reported only for exactly one new matching row from the same device.
3. Search results can never lead to a write in the same turn (batch rules).
4. Once the official todo flow owns a turn, our model never takes it over.
5. Host-thread observers (queue tap, events) never throw or block official traffic.

---

### Task 1: TodoProtocol + ToolTurn

**Files:** Create `src/com/turboio/addon/{TodoProtocol,ToolTurn}.java` and `tests/TodoProtocolTest.java`.

**Tests:**
- The TodoProtocolTests list from the digest: turn gate, physical, envelope prefixes, overflow and array body, snapshot, create intent, new candidate.
- Tool title examples.
- ToolTurn scenarios: batch, mixed, search-write, repeat, tool_choice transitions, ride and knowledge rules, and the sanitized result.

### Task 2: TodoRuntime + page

**Files:**
- Create `TodoRuntime.java` and `TodoUI.java`.
- Modify `QueueTap` (SCHEDULE_TODO observer, posted to main), `NativeTransfer.event` (route biz 22), `TurboAddon.dispatchNlp` (template observation, tool-dispatch bypass) and `DiagnosticsUI` (add the entry).

### Task 3: create_todo in the model loop

**Files:** Modify `TurboAddon` (turn gate; voice-only `create_todo` spec and system message; `ToolTurn` rules; a latch to `TodoRuntime.createFromTool` with a 30 s cap; 3 rounds; `parallel_tool_calls`) and `ToolClient` (spec helper).

Verify: `build.sh` is green, and packages 1.0.7 and 1.0.6 are clean.
