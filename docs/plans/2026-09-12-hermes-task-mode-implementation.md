# Hermes Task Mode Implementation Plan

> **For agentic workers:** Use subagent-driven-development for the independent gateway adapter and reviews; integrate in this session. User approved the design and execution on 2026-09-12. Preserve existing changes; do not commit, alter credentials, pairing, signing, generated projects or vendor binaries.

**Goal:** Give IO a persistent, independent Hermes session that executes real computer tasks and survives phone disconnection.

**Architecture:** Keep v1 conversation code for compatibility, add explicitly negotiated v2 task endpoints backed by a persistent official Hermes stdio gateway. The Mac owns execution; Swift owns a persistent request reference and polls bounded snapshots. User decisions use separate endpoints and cannot originate from voice callbacks.

**Tech Stack:** Node built-ins, installed Hermes Python runtime, Swift/Foundation/SwiftUI, Node test runner and Swift Package tests.

## Task 1: Official gateway adapter

- [x] Add `agent-bridge/gateway.test.mjs` with a subprocess fixture: fragmented JSON, response correlation, session mapping, progress, prompt expiration, final/idle ordering, RPC errors, transport exit, output limits.
- [x] Run `node --test agent-bridge/gateway.test.mjs`, preserve red output under `artifacts/hermes-tasks/`.
- [x] Implement `agent-bridge/gateway.mjs`, `agent-bridge/hermes_gateway.py`, and focused Python configuration tests. Use `tui_gateway.entry`, the installed runtime and process-local WhatsApp tool resolution. No `all` fallback or global config changes.
- [x] Adapter contract: `createHermesGateway({python,cwd,onEvent,onExit})`, then `start()`, `createSession()`, `resumeSession(storedSessionId)`, `submit(sessionId,text)`, `interrupt(sessionId)`, `respond(sessionId,prompt,decision)`, `history(sessionId)`, `close()`. Session objects contain `sessionId` (live) and `storedSessionId` (durable).
- [x] Events use `{sessionId,type,...}` with text/progress/prompt/promptExpired/done/failed/idle. Prompts carry `{id,kind,title,options}`; kind is approval, clarify or localAction. Do not forward reasoning, credentials, unrestricted tool logs or raw errors.
- [x] Verify adapter tests and review spec compliance, then quality.

## Task 2: Durable task bridge

- [x] Add `agent-bridge/tasks.test.mjs`. Test durable admission before execution, duplicate/conflicting IDs, no replay after restart, connection-independent lifetime, pending prompts, stale/duplicate decisions, stop/final races and session ownership.
- [x] Implement `agent-bridge/tasks.mjs` and `agent-bridge/task-http.mjs`; integrate explicit `--tasks` mode in existing server without modifying old v1 behavior.
- [x] v2 API: GET `/v2/health`; POST `/v2/tasks` with `{requestId,conversationId,text}`; GET `/v2/tasks/:id`; POST stop with `{conversationId}`; POST decision with `{conversationId,promptId,decisionId,choice?,text?}`. IDs are UUIDs. Create returns immediately with a snapshot.
- [x] Snapshot: `{requestId,conversationId,status,answer,summary,revision,prompt}`. Status is running/waiting/stopping/completed/failed/cancelled/unknown. Prompt is null or `{id,kind,title,options}`. One active task globally for this bridge; bounded metadata ledger and bounded output.
- [x] Persist IDs, input digests, owned session mapping and states atomically before external effects. Never auto-replay uncertain work. Keep completion evidence in Hermes history; report unknown honestly on missing evidence.
- [x] Run Node bridge tests, including HTTP authentication/version rejection, and inspect results.

## Task 3: Swift task client and UI

- [x] Add `rayneo-session/Sources/RayNeoSession/HermesTasks.swift` and `rayneo-session/Tests/RayNeoSessionTests/HermesTaskTests.swift`. Test snapshots, endpoint-scoped persistent references, unknown submission, restoration, prompt decisions and cancellation without a remote stop.
- [x] Implement `HermesTaskClient` with injected HTTP and persistence; no total execution deadline. Persist request before create, poll original ID, bind decisions to current prompt, preserve reference on network error.
- [x] Integrate into `CompanionVoiceRuntime.swift` and `VoiceConversationView.swift` (existing app source files only). Retain independent session ID, publish task status, polling, approval/clarify UI, reconnect and explicit stop.
- [x] Voice submits and returns a short receipt. Text input submits the same way. Closing voice/text listening does not stop the Mac task. Show later results in task card and available live conversation delivery.
- [x] Run `xcrun swift test --package-path rayneo-session --scratch-path artifacts/hermes-tasks/swift-build` and build the existing device scheme.

## Task 4: Live validation and delivery

- [x] Start a temporary task bridge with the existing installed Hermes runtime; no profile/WhatsApp configuration change. Exercise new fixture files only under `artifacts/hermes-tasks/live-work/`.
- [x] Submit real file creation and a follow-up modification, verify actual bytes. Run a task beyond 30 seconds, detach/reconnect, inspect same request, test explicit stop without premature completion claims.
- [x] Replace only the existing IO Hermes bridge process after checks, retaining port 8788/HTTPS 8443 and its token. Do not restart WhatsApp or Codex.
- [x] Build existing device scheme with separate derived output, capture only errors/warnings without signing details. Install in place using existing safe installer.
- [x] Update README, mark design status, create precise incremental diff against scoped baseline, and provide test outputs and any remaining device verification limits.

## Delivery state

All implementation steps above are complete. Automated tests: Node 49, Python 17, Swift 107, all passing. Existing device scheme built and installed in place. Production HTTPS 8443 uses v2 with its original token; a real file task through that endpoint passed. The user reported “手机任务成功” during device acceptance, and the requested file's bytes match. Separate phone/glasses display details have not been independently confirmed. See `../../artifacts/hermes-tasks/review.md` for exact evidence and limits.
