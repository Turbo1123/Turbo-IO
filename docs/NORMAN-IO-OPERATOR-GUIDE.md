# Norman IO operator guide

This is the Task 1 baseline. Existing app labels may still say Turbo IO. Branding,
language selection, the unified Codex/Claude/Hermes bridge and classified Obsidian
capture are later tasks. See [CONFIGURATION.md](CONFIGURATION.md) for the existing
client and [NORMAN-IO-SECURITY.md](NORMAN-IO-SECURITY.md) for security boundaries.

## Build when explicitly requested

Use Xcode with its selected command-line tools, XcodeGen and Node.js. From the
repository root, the source-only simulator workflow is:

```sh
node scripts/start.mjs --local
```

Select `RayNeoCompanion` and a simulator in Xcode, then Run. This generates a
project and opens Xcode; it does not connect glasses. Keep simulator ad-hoc
signing for Keychain checks. A compile-only run without signing does not verify
Keychain behavior. No builds or generated-file updates are part of Task 1.

For a separately authorized device build:

```sh
node scripts/start.mjs --device
```

This checks vendor dependencies, generates a declaration module and regenerates
the project using `project-device.yml`. Select `RayNeoCompanionDevice` and the
owner's iPhone. Preserve the existing local signing team and Bundle ID; never
copy signing values into documentation. Do not uninstall the existing app,
restore framework signatures or replace backups to obtain a clean Git status.

## Reconnect and permissions

For the already paired installation, use normal reconnect and wait for the app's
authenticated state. Do not unbind, forget the Bluetooth device or reset pairing.
Only for a separately requested first setup/migration, follow the official-app
unbinding sequence in [CONFIGURATION.md](CONFIGURATION.md); it changes pairing.

The owner accepts Bluetooth and other iOS permission prompts personally. Grant
local-network access when connecting the Mac bridge; allow microphone access if
the selected input requests it. Notification sharing and reminder access are
optional feature-specific permissions. Test one harmless custom notification
after authentication; receipt on the glasses is distinct from a protocol reply.

## ASR and models (optional)

Pairing and local features do not require cloud keys. In the existing device app,
open the conversation model/ASR configuration. The owner enters a compatible
DashScope host (hostname only, an allowed `aliyuncs.com` subdomain), their ASR key
and their DeepSeek key locally. Never send credentials to an assistant or put
them in a command/config file. Keys use the existing Keychain storage.

The current voice path expects DashScope streaming ASR with
`qwen-audio-3.0-asr-flash-streaming`, 16 kHz mono PCM16 and cloud VAD. A generic
API key does not establish protocol compatibility. Save configuration first;
enable voice only deliberately, speak a short non-sensitive test sentence, and
check the transcript and response. Keep recordings local unless explicitly
transcribing/exporting. The new settings UI and model router are not yet present.

## Existing Codex bridge (optional)

The owner completes Codex CLI login locally. Prepare a dedicated random Base64URL
token file (32–256 characters, mode `0600`) using a local secure workflow without
printing the token. Keep it and the private ledger outside this repository.
Replace these placeholder paths locally; command arguments contain paths only:

```sh
node codex-bridge/bridge.mjs \
  --workspace /absolute/your/allowed/project \
  --token-file /absolute/private/token-file \
  --state-file /absolute/private/task-ledger.json
```

Defaults are `127.0.0.1:8787` and read-only access. For phone access, configure a
trusted HTTPS proxy to that loopback listener, or use `--host` with `--tls-cert`
and `--tls-key` pointing to local files. Non-loopback listening requires TLS.
Never bypass iOS trust warnings. Enter the HTTPS root URL (without `/v1`) and
token locally on the phone, check connection, then try a harmless read-only task.
Do not start a live bridge or paid agent test as part of Task 1.

The current API is `/v1/state`, `/v1/message`, `/v1/stop`, `/v1/decision`;
`agent-bridge/`, its dry-run backend and the proposed `/v1/tasks` API are future
work. Do not add `--allow-workspace-write` for initial checks. Later write tests
require explicit owner opt-in, a disposable workspace and phone approval review.
Keep the same request ID when retrying an uncertain request. Stop the bridge
with Ctrl-C; do not expose Codex app-server directly.

## Review and validation

Use `git status --short` and inspect only the intended file diffs. Existing tracked
device-spec/framework changes remain visible; do not stage, revert or conceal
them. Stage Task 1 files explicitly after review. Ignored output is not safe to
publish merely because it no longer appears in status.

Run `node scripts/check-source.mjs /path/to/source-snapshot` on a deliberately
selected source snapshot, excluding private/generated material as described in
the security document. Source scanning is not a full security audit. For later
runtime changes, the plan's regression commands are:

```sh
node --test codex-bridge/bridge.test.mjs display-observer/*.test.mjs
xcrun swift test --package-path rayneo-protocol
xcrun swift test --package-path rayneo-session
```

Swift tests create build output; run them only when that is within the task's
scope. Record pass/fail counts and sanitized errors, never personal transcripts,
device IDs or credentials. Simulator results do not establish hardware success.
