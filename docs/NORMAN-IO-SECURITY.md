# Norman IO security boundaries

This document records security boundaries for the current app and planned work.
The dedicated Hermes task bridge and its settings UI are implemented. A unified
multi-agent bridge and Obsidian capture approvals remain planned; these policy
requirements are not a claim of completed security verification.

## Secrets and local data

- Enter cloud keys and the phone's bridge token only in the app's configuration
  UI; store secret values in iOS Keychain, isolated by provider/endpoint. Never
  paste them into chat, source, command arguments, logs, screenshots, exported
  notes, Info.plist or UserDefaults. Future settings must support explicit
  replacement/deletion without revealing values in diagnostics.
- On the Mac, keep a dedicated random bridge token and task ledger outside the
  repository in private files (mode `0600`). Never reuse provider credentials.
  Keep TLS private keys private too. Ignored `.private/` and `.local-state/`
  directories are accidental-commit protection, not secure storage.
- Keep recordings local until the owner explicitly requests transcription or
  export. Planned Obsidian writes require transcript review and classification;
  retain provenance without secrets or automatic ambient-conversation ingestion.

## Network and agent execution

- The existing Codex bridge defaults to loopback and a read-only workspace.
  Phone access requires trusted HTTPS and an independent bearer token, using
  either the bridge's TLS options or a trusted HTTPS proxy to loopback. Never
  bypass certificate validation or expose app-server/CLI/RPC directly.
- The existing bridge uses `on-request` approvals. Host opt-in to workspace-write
  increases capability; it is not permission to auto-approve requests. Review
  pending approvals on the phone. Voice transcripts cannot grant approval.
- The planned unified bridge must enforce explicit workspace allowlists after
  symlink resolution, bounded requests/results, cancellation and expiry. File
  writes, shell execution, credential use and external messages require visible
  owner approval. The dedicated Hermes task bridge is separate from that plan.
- Bridge ledgers must not retain raw prompts, transcripts, approval bodies or
  credentials. CLI authentication remains an owner-operated local flow.

## Signing, pairing and vendor dependencies

- Preserve the existing local Bundle ID, signing configuration, Keychain and
  device pairing. Do not reset, uninstall, re-pair or copy binding databases as
  part of source cleanup. Do not publish personal signing or device identifiers.
- `project-device.yml` and vendor framework files are already tracked. Ignore
  rules cannot hide their local modifications. Review them separately and never
  stage them with a blanket `git add .`; Task 1 leaves them unchanged.
- Do not restore the removed publisher signature or edit/re-sign vendor binaries
  during baseline cleanup. Leave `.local-backups/` untouched. Device builds use
  the owner's existing local signing setup in a separately authorized session.
- Vendor frameworks and the Opus static library remain binary dependencies.
  `DEPENDENCIES.json` records the distributed inventory, not proof of the current
  locally re-signed bytes, source availability, safety or redistribution rights.
  Preserve third-party notices and consult [LICENSING.md](LICENSING.md).

## Verification boundary

Run `scripts/check-source.mjs` on an explicitly selected source snapshot, not the
private device workspace. Exclude local signing configuration, vendor binaries,
generated output, backups, credentials and runtime state before copying/reading.
Include the intended new documentation and current source edits; report the
selection and exclusions with results. The scanner reports paths/rules, not
matching values. Pattern scanning is not a full security or license audit and
does not inspect excluded material or revoke previously exposed credentials.
