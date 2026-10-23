# Android Phase 4e — Knowledge Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Match the iOS 1.0.7 knowledge page (KnowledgeUI.m / KnowledgeClient.m). Android already registers the `knowledge_query` / `knowledge_query_status` model tools (ToolClient). This adds:
- the executor-Agent selector (only Codex is wired);
- the connection and data-source status from `/sources`;
- a manual read-only query with 3 s polling up to 80 s;
- "refresh last result" and the cited source list.

**Architecture:**
- `KnowledgeView` (pure): the agent list and gate, the terminal-poll rule, and the exact iOS row texts.
- `ToolClient` gains `query(String)` (source "all", persists the job id) and `job(String id)`. Tool registration also requires the Codex agent.
- `KnowledgeUI` (glue): the page, with HTTP on a background thread and callbacks guarded against a destroyed Activity.

**Spec:** `official-addon/ios107-edition/KnowledgeUI.m`, `KnowledgeClient.m`.

## Global Constraints

- **Agents:** Codex, Claude Code, Hermes, WorkBuddy, OpenClaw (pref `knowledge_agent`, default Codex). The tools and the page query need Codex ("请先配置连接，并选择 Codex。"); the other agents can be selected but aren't connected ("未连接执行器").
- **Poll:** `GET /jobs/<uuid>` every 3 s. Stop on completed/failed/interrupted, or when more than 80 s have passed since the query started. A refresh of the last job polls once.
- **Query:** 2–200 characters, otherwise "请输入2至200字。". The body is `{query, source:"all", requestId}`. A missing job id gives "服务未返回查询编号。".
- **Errors:** "知识库连接失败（HTTP n）。请检查 Mac 服务、网络与令牌。". The token is never shown. The add-on's existing `http()` already maps errors to this.
- **Row texts:**
  - source: `"%s · %s 条\n更新时间：%s\n%s%s"` (可读取/不可用, count or 0, updatedAt or 未知, scope, "\n存在范围限制或跳过文件" when partial);
  - job: `status \n answer|error`;
  - citation: `title` / `"sourceLabel · (messageAt|updatedAt)\nexcerpt"`.

## Review Focus

1. The query and tools only run with an explicit switch, the Codex agent and the configured HTTPS `/api/turbo-knowledge` URL plus token.
2. Polling stops at 80 s and on page close.
3. The token never reaches UI text.
4. Non-UUID job ids are refused.
5. Callbacks never touch a destroyed Activity.

---

### Task 1: KnowledgeView + ToolClient query/job

**Files:** Create `src/com/turboio/addon/KnowledgeView.java` and `tests/KnowledgeViewTest.java`; modify `ToolClient.java`.

**Tests:**
- The agent list and order.
- `gate(enabled,agent,url,token)`: only Codex passes.
- `terminal("running",0,79000)` is false; `terminal("running",0,80001)` is true; `terminal("completed",…)` is true.
- Source, job and citation texts are exact, including null `messageAt` falling back to `updatedAt` and missing fields falling back.
- `validJob("not-a-uuid")` is false.

### Task 2: KnowledgeUI

**Files:** Create `KnowledgeUI.java`, with an entry in 设置 ("知识库") and a button on the Tools settings dialog.

Verify: `build.sh` is green and package 1.0.7 is clean.
