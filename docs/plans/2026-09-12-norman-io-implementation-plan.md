# Norman IO Implementation Plan

> **For Codex:** Work inside this repository only. Implement the tasks in order, preserve the existing RayNeo protocol and device connection path, and never print, commit, copy, or request secrets in chat/logs/source control.

**Goal:** Turn the current Turbo IO research client into **Norman IO**: English-first bilingual iPhone companion for RayNeo iO glasses, with an Obsidian knowledge-capture pipeline and a unified, user-controlled bridge to Hermes, Codex, and Claude Code.

**Architecture:** Glasses remain the voice/display peripheral; the iPhone owns pairing, permission prompts, local state and Keychain secrets; a Mac-side HTTPS bridge owns agent execution and access to the local Obsidian vault. A single agent-router protocol lets the iPhone use the existing Codex bridge first, then Hermes and Claude adapters without exposing arbitrary shell/RPC endpoints.

**Tech stack:** SwiftUI, Swift Package Manager, iOS 16+, CoreBluetooth, URLSession/WebSocket, iOS Keychain, Node.js ESM, Codex app-server, Claude Code CLI, Hermes CLI/webhooks, Obsidian Markdown files.

**Upstream base:** `main` at `9382ec6` when this plan was written.

---

## 0. Current local state — preserve it

This local checkout already has working device setup and deliberately local-only changes:

- Repository: `~/Developer/Turbo-IO`
- XcodeGen is installed.
- A device build has succeeded and the app is installed on the owner’s iPhone.
- The device project has a local Bundle ID and signing team configured in `apps/RayNeoCompanion/project-device.yml`.
- The app display name has been changed to **Norman IO** in `project-device.yml`.
- `core-probe/Frameworks/RayneoNet.framework` had the upstream publisher signature removed so Xcode can re-sign it for the local development team. The original framework was backed up under `.local-backups/`.

### Rules for local signing material

- Do **not** commit `.local-backups/`, `build*/`, `DerivedData`, `.swiftpm/`, provisioning profiles, certificates, device IDs, `xcuserdata`, `.xcresult`, or App containers.
- Do **not** restore the upstream framework signature unless intentionally undoing local device support.
- Do **not** change the local Bundle ID casually: it isolates Keychain data and existing device pairing state.
- Keep product signing settings in ignored local configuration or an explicitly documented user-owned settings file; never publish a personal Team ID.

Before any code work, create/update `.gitignore` for generated local artifacts and inspect `git status --short`.

---

## 1. Product decisions already approved

### Name and identity

- User-facing app name: **Norman IO**.
- Design language: graphite/near-black background; an ultra-simple glasses outline; a luminous **N** with a blue-to-cyan signal arc.
- Do not put small text inside the App Icon.
- Generate a high-resolution master and export a complete iOS asset catalog; do not use a single raster image for every slot.

### Language

- English is the default language.
- Simplified Chinese is a fully supported selectable language.
- Support `System Default`, `English`, and `简体中文` in Settings.
- Use Xcode String Catalogs (`.xcstrings`), not hard-coded bilingual branching throughout Swift views.

### Voice and models

- Default voice pipeline: **voice activity detection → streaming ASR → text → selected model/agent**.
- Default cloud ASR implementation must stay compatible with the repository’s DashScope streaming protocol and `qwen-audio-3.0-asr-flash-streaming` assumptions.
- Do not make ASR mandatory for non-voice features. Pairing, notifications, Obsidian export, agent bridges and typed input must work without ASR keys.
- Add an opt-in future `raw audio analysis` capability, but do not implement it by silently shipping audio to a multimodal model.
- Model router defaults: DeepSeek for quick text chat; Claude for long-form reasoning; user-selectable manual routing; no unannounced fallback that changes provider/cost/privacy.

### Agent policy

- Support three named agents:
  - **Hermes**: personal OS, messaging, memory, Obsidian and scheduled workflows.
  - **Codex**: coding and workspace operations using the existing `codex-bridge` architecture.
  - **Claude Code**: coding/research agent via local CLI adapter.
- The owner wants full DIY capability, including opt-in workspace write access.
- Full capability does not mean invisible execution: every agent task must show target agent, workspace, requested capability and resulting status in the iPhone UI.
- Never auto-approve file writes, shell commands, credential use, or external messages based only on a voice transcript. Approval happens visibly on the iPhone.

### Obsidian policy

Vault root on this Mac: `~/Documents/Obsidian Vault`.

Capture destinations:

```text
00-inbox/glasses/              raw/unclassified captures
journal/YYYY-MM-DD.md          confirmed journal entries
wiki/ideas/                    confirmed ideas
wiki/sources/                  source notes and material provenance
wiki/concepts/                 durable concepts
wiki/projects/                 project-scoped notes
assets/glasses/YYYY-MM-DD/     optional retained original audio/image assets
```

- Short voice captures must be shown as text and classified by the user before writing.
- Long recordings remain local until the owner explicitly requests transcription/export.
- Every exported Markdown note must preserve provenance: timestamp, input type, source device, and (when applicable) source audio filename.
- Never automatically ingest ambient recordings, private conversations or raw API responses into the journal.

---

## 2. Secret handling and user-only actions

### Never ask the owner to paste a key into chat

Secrets must be entered only in the iPhone app’s Settings UI and stored in the iOS Keychain. They must never appear in:

- Git files, sample configs, `Info.plist`, `UserDefaults`, or exported Markdown;
- terminal command lines, command history, crash reports or test fixtures;
- an agent prompt, WhatsApp, screenshots, or browser URLs.

Use a dedicated Keychain service namespace per endpoint/provider. Make delete/replace explicit in the UI.

### User actions needed later

1. Create an Alibaba Cloud Model Studio / DashScope key dedicated to Norman IO ASR. Do not send it to Codex or chat.
2. Enter ASR and model keys locally in the app after the settings UI exists.
3. If the Mac prompts for login, the owner personally completes Codex and Claude authentication in their official CLI/browser flow.
4. For remote iPhone-to-Mac agent access, the owner must trust the chosen HTTPS certificate / private network path on the iPhone. Do not bypass iOS trust warnings.
5. The owner must complete physical glasses pairing and grant iOS runtime permissions when prompted.

---

## 3. Target repository layout

Create a small, testable feature layer rather than placing all logic in SwiftUI views.

```text
apps/RayNeoCompanion/
  Sources/
    App/
      NormanIOApp.swift
      AppSettings.swift
      Localization/
      Branding/
    Features/
      Settings/
      Capture/
      Obsidian/
      Agents/
      Voice/
    Services/
      Keychain/
      AgentBridge/
      ObsidianExport/
      Diagnostics/
  Resources/
    Localizable.xcstrings
    Assets.xcassets/
      AppIcon.appiconset/
      NormanIOMark.imageset/
  Tests/
    ...

agent-bridge/                 # new Node ESM package, separate from codex-bridge
  src/
    server.mjs
    auth.mjs
    protocol.mjs
    adapters/
      codex.mjs
      claude.mjs
      hermes.mjs
    obsidian.mjs
  test/
  README.md

docs/
  plans/
  NORMAN-IO-SECURITY.md
  NORMAN-IO-OPERATOR-GUIDE.md
```

If the actual app source layout differs, adapt paths but keep the separation: views do not contain Keychain/HTTP/filesystem/agent process logic.

---

## 4. Shared agent bridge contract

Do not expose the native Codex app-server, Claude CLI, Hermes gateway, shell, filesystem, or arbitrary JSON-RPC directly to the iPhone.

### Transport

- Mac bridge binds to loopback by default.
- Remote access must be HTTPS plus an independent high-entropy bearer token stored in a mode-`0600` file.
- Do not reuse ASR, LLM, Apple, Codex, Claude or Hermes credentials as bridge tokens.
- Use explicit allowlisted workspaces. Reject paths outside the selected root after resolving symlinks.
- Keep task ledger data private (`0600`) and do not persist transcripts, secret text, approval bodies or raw prompts.

### API v1

Use a common payload so the iPhone does not need provider-specific behavior.

```json
{
  "agent": "codex | claude | hermes",
  "workspaceId": "research-vault",
  "text": "Summarize the selected note",
  "requestId": "uuid",
  "mode": "read-only | workspace-write"
}
```

Endpoints:

```text
GET  /v1/health
GET  /v1/agents
GET  /v1/workspaces
GET  /v1/tasks/:taskId
POST /v1/tasks
POST /v1/tasks/:taskId/stop
POST /v1/tasks/:taskId/decision
POST /v1/obsidian/capture
```

Every response should include a bounded status event shape:

```json
{
  "taskId": "uuid",
  "agent": "codex",
  "status": "queued | running | awaiting_approval | completed | failed | cancelled",
  "summary": "bounded plain text",
  "approval": null,
  "updatedAt": "ISO-8601"
}
```

### Adapter requirements

#### Codex adapter

Refactor/reuse `codex-bridge/bridge.mjs`; do not duplicate an unreviewed server. Preserve:

- app-server stdio transport;
- task idempotency;
- 16 KiB request bounds;
- task/approval expiry;
- `on-request` approval policy;
- read-only default and explicit workspace-write switch;
- no transcript persistence and no credential logging.

#### Claude adapter

Use the locally installed CLI only through a spawned child process in an explicitly selected workspace. Prefer:

```bash
claude --print --output-format stream-json --permission-mode plan
```

for read-only/planning tasks. Add workspace-write only after an iPhone approval and with an explicit allowed tool list. Do not use `--dangerously-skip-permissions` or `bypassPermissions` as a default.

Parse stream JSON defensively. Bound output size and task duration. Kill child processes when clients cancel or the bridge exits.

#### Hermes adapter

Do not scrape WhatsApp/GUI sessions. Use Hermes’s documented programmatic interface: a private local `hermes chat -q` adapter for one-shot tasks and/or a private webhook/API route with an explicit response/event contract.

Initial Hermes capabilities:

- Obsidian capture request;
- list/check a named task or scheduled reminder;
- submit a bounded personal-assistant question;
- return a short answer/status to Norman IO.

Do not grant a generic shell passthrough. Any Hermes capability that can send messages, modify files, control devices or create scheduled jobs must surface an iPhone approval request.

---

## 5. Implementation tasks

### Task 1: Establish a clean local development baseline

**Files:**
- Modify: `.gitignore`
- Create: `docs/NORMAN-IO-SECURITY.md`
- Create: `docs/NORMAN-IO-OPERATOR-GUIDE.md`

1. Add generated device build directories, `.swiftpm/`, `.local-backups/`, `xcuserdata/`, `*.xcresult`, private token/cert paths and local state ledgers to `.gitignore`.
2. Add a concise security document describing secrets, HTTPS, agent approvals, local signing and vendor binary limitations.
3. Add an operator guide with non-secret instructions for build, pairing, permissions, ASR setup and bridge startup.
4. Run source scanning against a clean source-only checkout or exclude generated local artifacts deliberately. Do not claim a scanner is a full security audit.

**Verify:** `git status --short` contains only intentional source/docs changes.

### Task 2: Add Norman IO branding assets

**Files:**
- Create/modify: `apps/RayNeoCompanion/Resources/Assets.xcassets/...`
- Modify: the relevant XcodeGen project spec(s)
- Test: asset catalog build verification

1. Generate/author a square 1024×1024 master without text: dark graphite background, minimal glasses line, luminous N, blue/cyan signal arc.
2. Export all Apple-required AppIcon PNGs using Xcode asset catalog metadata.
3. Add a reusable in-app `NormanIOMark` asset.
4. Do not alter the technical target name or Bundle ID merely to change visible branding.

**Verify:** device and simulator builds succeed; iPhone home screen displays `Norman IO` and the new icon.

### Task 3: Build the localization foundation

**Files:**
- Create: `Resources/Localizable.xcstrings`
- Create: `Sources/App/Localization/AppLanguage.swift`
- Create: `Sources/Features/Settings/LanguageSettingsView.swift`
- Test: `Tests/AppLanguageTests.swift`

1. Create string keys for existing visible UI, not English/Chinese literals embedded in views.
2. Supply English base values and Simplified Chinese translations.
3. Implement a persisted `system | en | zh-Hans` selection, with English as first-launch default.
4. Make date/number formatting follow the selected locale where practical.
5. Do not retroactively translate user-created text, transcripts, titles or note bodies.

**Verify:** unit test locale selection; run the app once in English and once in Chinese; ensure changing language does not erase configuration.

### Task 4: Create secure configuration storage

**Files:**
- Create: `Sources/Services/Keychain/KeychainStore.swift`
- Create: `Sources/App/AppSettings.swift`
- Create: `Sources/Features/Settings/ModelSettingsView.swift`
- Test: Keychain abstraction unit tests using an injected fake store

Store only references/non-secret preferences in `UserDefaults`; store actual values in Keychain:

```text
norman-io.asr.<host>
norman-io.model.deepseek
norman-io.model.anthropic
norman-io.bridge.<endpoint-hash>
```

Required settings UI:

- ASR enabled toggle, host validation, key entry/delete/test;
- DeepSeek key entry/delete/test;
- Anthropic/Claude key entry/delete/test only if direct API chat is implemented;
- Mac Bridge HTTPS base URL and dedicated token;
- a diagnostic page that reports only “configured / not configured / connection failed”, never secret values.

**Verify:** secret values do not occur in source, logs, debug descriptions, exported settings or screenshots.

### Task 5: Add a model and agent router UI

**Files:**
- Create: `Sources/Features/Agents/AgentKind.swift`
- Create: `Sources/Features/Agents/AgentRouter.swift`
- Create: `Sources/Features/Agents/AgentTaskView.swift`
- Test: router selection/state tests

Supported choices:

```text
Quick Chat: DeepSeek
Long Reasoning: Claude
Personal OS: Hermes
Coding: Codex
Claude Code: Claude Code
Auto: classify only from user-visible rules; show routing result before dispatch
```

A task screen must show agent name, workspace, access mode, request text, connection status, streamed status and any approval request. Eye-glass notifications may show only bounded summaries; the iPhone remains the full control surface.

**Verify:** typed tasks work when ASR is disabled; selecting an unconfigured agent produces a useful local setup message, not a generic error.

### Task 6: Implement the Mac agent bridge skeleton

**Files:**
- Create: `agent-bridge/package.json`
- Create: `agent-bridge/src/{server,auth,protocol,workspace-store}.mjs`
- Create: `agent-bridge/test/*.test.mjs`

1. Write failing Node tests for authentication, loopback-only default, TLS requirement for non-loopback listeners, body bounds, workspace allowlist and task idempotency.
2. Implement the common API contract from section 4.
3. Use constant-time bearer-token comparison.
4. Configure task/state data paths outside the Git repository, mode `0600`.
5. Provide a `--dry-run` backend for iPhone UI integration testing without invoking any agent.

**Verify:** run Node tests; confirm unauthenticated/cross-origin/oversized requests fail closed.

### Task 7: Reuse the existing Codex adapter

**Files:**
- Modify or import from: `codex-bridge/bridge.mjs`
- Create: `agent-bridge/src/adapters/codex.mjs`
- Test: adapter contract tests

1. Extract a narrow adapter interface from the existing bridge rather than duplicating its security code.
2. Start Codex app-server as a private stdio child.
3. Maintain per-task status and user approvals.
4. First release supports one explicit workspace selected from the iPhone.
5. Enable workspace-write only after the iPhone sends a matching approval for that operation.

**Verify:** use a throwaway test workspace; issue a read-only request, observe status, then issue a deliberately harmless approved write request. Confirm no access outside the workspace.

### Task 8: Add Claude Code adapter

**Files:**
- Create: `agent-bridge/src/adapters/claude.mjs`
- Create: `agent-bridge/test/claude-adapter.test.mjs`

1. Provide an adapter interface matching Codex task events.
2. Start with `claude --print --output-format stream-json --permission-mode plan` for no-write tasks.
3. Parse only known JSON event shapes; treat malformed/oversized output as a failed task.
4. For workspace writes, use an explicit iPhone approval and allowlisted tool policy. Do not enable dangerous permission bypass defaults.
5. Do not test against a paid account until the owner explicitly requests it; use a fake spawned CLI in unit tests.

**Verify:** fake CLI tests cover stream parsing, timeout, cancellation and approval gating.

### Task 9: Add Hermes adapter

**Files:**
- Create: `agent-bridge/src/adapters/hermes.mjs`
- Create: `agent-bridge/test/hermes-adapter.test.mjs`
- Optionally create: a dedicated Hermes webhook route/config, documented but without credentials

1. Use a bounded command or documented webhook input/output contract; do not automate messaging UI.
2. First actions: capture an Obsidian idea/journal/material request; retrieve a short task status; answer a bounded personal query.
3. Map side-effect requests to the same iPhone approval model.
4. Keep a strict action allowlist, not arbitrary natural-language shell execution.

**Verify:** test with a fake Hermes endpoint/command. Then manually test one non-secret Obsidian capture in a dedicated test note.

### Task 10: Add Obsidian connector and capture classification

**Files:**
- Create: `agent-bridge/src/obsidian.mjs`
- Create: `Sources/Features/Obsidian/CaptureComposerView.swift`
- Create: `Sources/Features/Obsidian/CaptureKind.swift`
- Test: Node vault-path and Markdown-generation tests; Swift capture classification tests

Capture categories:

```text
idea
journal
knowledge-material
source
project-note
reminder
```

1. The iPhone sends structured capture text and category; the Mac bridge owns vault file writing.
2. Resolve and enforce the vault root; reject traversal/symlink escapes.
3. Write atomic Markdown files and append only safe structured content.
4. For `idea`, create/update `wiki/ideas/` and its README index.
5. For `journal`, append a timestamped section to `journal/YYYY-MM-DD.md`.
6. For `knowledge-material`, create an inbox capture under `00-inbox/glasses/` with a provenance frontmatter block.
7. For source material, preserve the URL/reference instead of inventing metadata.
8. Keep raw audio only as a local optional asset; link it only after explicit user choice.

**Verify:** test each category in a temporary vault; verify no path escape and no secret leakage; manually inspect generated Markdown in Obsidian.

### Task 11: Connect voice pipeline to capture/router actions

**Files:**
- Modify: existing voice/session feature(s)
- Create: `Sources/Features/Capture/CaptureReviewView.swift`
- Test: voice-result-to-action reducer tests

1. Retain the existing DashScope ASR path as the implementation baseline.
2. After ASR, present transcript with action chips: `Ask`, `Save idea`, `Add journal`, `Save material`, `Send to Codex`, `Send to Claude`, `Send to Hermes`.
3. Do not automatically submit/record a transcript without visible state.
4. Add a clear disabled/offline path when ASR is not configured.
5. Add optional future interface for raw audio analysis but do not silently send audio to a new provider.

**Verify:** use a fixture transcript; ensure every action produces the correct structured request and approval behavior.

### Task 12: Device integration and operational validation

**Files:**
- Modify: `docs/NORMAN-IO-OPERATOR-GUIDE.md`
- Create: `docs/NORMAN-IO-VALIDATION.md`

Perform these checks in order:

1. Simulator: English UI, Chinese UI, no-key path, local capture composition.
2. iPhone: launch, app icon, language persistence, Keychain settings save/delete.
3. Glasses: Bluetooth permission, pairing/authentication, a harmless custom notification.
4. ASR: owner enters own key locally; one short spoken sentence; confirm transcript and model response.
5. Obsidian: save one test idea, one test journal item and one inbox material; inspect exact files.
6. Agent bridge: dry-run, Codex read-only, Hermes safe capture action, Claude fake/plan task.
7. Only after all prior checks: owner opts in to a write-enabled task in a disposable workspace.

Record only statuses and sanitized errors in validation docs. Never record device identifiers, secrets, personal transcript content, full file trees or account emails.

---

## 6. Required test commands

Run existing checks before and after relevant changes:

```bash
node --test codex-bridge/bridge.test.mjs display-observer/*.test.mjs
xcrun swift test --package-path rayneo-protocol
xcrun swift test --package-path rayneo-session
```

Run new bridge tests:

```bash
cd agent-bridge
node --test test/*.test.mjs
```

Simulator build:

```bash
cd ~/Developer/Turbo-IO
xcodegen generate --spec apps/RayNeoCompanion/project-source.yml
xcodebuild \
  -project apps/RayNeoCompanion/RayNeoCompanion.xcodeproj \
  -scheme RayNeoCompanion \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/norman-io-simulator-build \
  build
```

Device build uses the locally configured device spec and the owner’s signing environment. Do not include personal signing values in this document or in Git.

---

## 7. Commit discipline

- Make small conventional commits after each completed task, e.g.:
  - `docs: add Norman IO security and operator guides`
  - `feat(branding): add Norman IO icon assets`
  - `feat(i18n): add English and Simplified Chinese localization`
  - `feat(bridge): add authenticated agent bridge skeleton`
  - `feat(obsidian): add classified glass capture export`
- Never commit generated build files, secrets, local certificate files or personal device settings.
- Before every commit, run `git diff --check`, inspect `git status --short`, and search staged content for secret-like values.

---

## 8. Definition of done

Norman IO is ready for owner acceptance only when all of the following are true:

- The iPhone home screen shows the Norman IO icon and name.
- English is the first-launch default; Chinese can be selected and persists.
- The owner can pair the glasses and receive a harmless custom notification.
- No cloud key is required for local pairing/notification/capture composition.
- ASR, DeepSeek/Claude model keys and bridge token are entered only via the iPhone and stored in Keychain.
- A short spoken sentence can become a reviewed transcript, then an explicit idea/journal/material capture in the existing Obsidian vault.
- Codex, Hermes and Claude are presented as distinct, named agents with visible workspace/access mode/status.
- No agent gets arbitrary host access, automatic write approval, or credentials from chat.
- Read-only and deliberately approved workspace-write flows have been tested in a disposable workspace.
- Existing protocol/session/Codex bridge test suites continue to pass.

---

## 9. Suggested Codex kickoff prompt

Use this from the repository root in a fresh Codex session:

```text
Read docs/plans/2026-09-12-norman-io-implementation-plan.md in full. Work only in this repository. First inspect the current source layout and git status; do not touch secrets, signing identities, provisioning profiles, .local-backups, vendor framework binaries, generated build files, or the existing device pairing state. Implement only Task 1, using tests where applicable. Show the exact diff and test output, then stop for review.
```

For each next task, replace `Task 1` with the next approved task. Do not ask Codex to implement the entire plan in one pass.
