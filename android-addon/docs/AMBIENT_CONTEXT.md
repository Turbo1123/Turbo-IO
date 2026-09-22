# Android ambient context bridge

This source-only feature aligns the Android official-app extension with the ambient-memory integration role of the iOS V2 extension. It is not an iOS port. It preserves the official finalized-transcription callback, stores text with stable source/segment/revision identities, and can deliver explicitly enabled windows to a service implementing [rayneo-context/v1](../../docs/contracts/b-rayneo-context-v1.json).

## Configuration and consent boundaries

Build the addon with `bash android-addon/build.sh`. For the verified Android host input **1.0.5 (201)**, run `node android-addon/package-105.mjs /path/to/official.apk` after building. The packager requires the exact supported official SHA256 encoded in the script, checks callback targets, and preserves official resources as raw ZIP entries. Set `APKTOOL` to an executable path if it is not on PATH. Obtain your own authorized host input and use your own signing identity; no APK, signing key or service credential is distributed here. The existing 1.0.4 packaging entry is unchanged and does not install the new AlwaysOn callback.

Tools and services accepts your HTTPS **root** URL and a source-scoped Bearer token, stored with the existing Android Keystore-backed SecretStore. Upload and context query are separate controls, initially off. A blank token field preserves the existing value. The server must implement the supplied contract; this PR does not deploy a backend. The saved-authentication check uses the same saved root, SecretStore and HTTP client, requires upload off, disables redirects and queries one new random exact segment ID. Unexpected matches are a failure and no text is shown. It displays only an empty successful result or a sanitized status. It does not enable upload.

Before a recording test, check capacity and create a new window explicitly. All existing pending records become retained and cannot be uploaded or ACK-deleted by that window. Active and retained partitions each have a 256-record bound. A new window is refused if retention cannot hold existing rows. Do not clear records to make room: explicitly resume the current generation only when its pending records are authorized for delivery. Upload stops on the first error; ordinary Save does not clear held state. Close upload after the intended window. The visible first authentication error is historical evidence and remains after a successful later check.

The v4 queue reads v2/v3, preserves exact legacy bytes before migration and stages writes. A failed migration/commit fails closed. Restoring an old APK alone is unsafe after v4 migration; prefer a v4-compatible forward fix. A pre-migration snapshot must not overwrite newer records or ACKs. Retained records are not automatically expired or drained; repeated unacknowledged windows can intentionally block further capture.

## Main conversation and external agents

The existing main-conversation `ToolClient` registers `rayneo_context_query` only when the query setting and saved endpoint/credential are configured. A disabled or missing remote transport returns an empty result without falling back to retained local text. The tool is selected for a current question, not invoked by the finalized-transcription callback. Returned context is labeled untrusted data with `instruction_eligible=false`; it is not system instructions, user authorization, or an official answer. Existing unrelated model, web-search and knowledge-base routing is unchanged.

An external agent can implement the same HTTP query contract or call the dependency-free Node.js example:

```sh
# Supply your own URL/token through your agent's existing secret mechanism.
# Do not put a real token in command-line arguments or commit an environment file.
node android-addon/examples/query-context.mjs --segment-id synthetic-example
node android-addon/examples/query-context.mjs --topic 'the current user question'
```

The example reads `RAYNEO_CONTEXT_URL` and `RAYNEO_CONTEXT_TOKEN` from its environment. It only calls `/v1/rayneo/query`, limits returned context, rejects redirects and oversized responses, and never uploads, retries, records or invokes control endpoints. Feed the returned envelope as untrusted contextual data. This is a generic integration example, not a hosted agent or a new Android HTTP server.

## Evidence and extraction mapping

The installed development source `ec911bc55dfdbd12905bd5a5450b9efbf2804d5e` was tested on **Samsung SM-S9280, Android 16 / API 36**, with host 1.0.5 (201). Windows used JDK 17, Android SDK/build-tools 36 and official ADB 37.0.1; the reference HTTPS service ran on macOS. That source passed 50 authentication checks and full Android compilation, was signed with the same local certificate, installed with data preserved, and read back. No claim covers all S24 variants or iPhone.

Observed phone sequence: an earlier real recording produced a POST rejected with 401 and no accepted ingestion. After the diagnosis update, a saved-credential App query returned 401; normal SecretStore UI correction and Save were followed by App query **200 with no matching records**, independently observed at the service. Upload remained off, held remained true, and four current pending records plus 256 retained records were not replayed. This proves the query credential path, not successful ingestion, main-conversation usage or recording-to-external-agent end-to-end acceptance.

This PR is a clean extraction onto upstream `8b5df1f22ec8a5232dafb1b6088e619b317034f6`, not the installed branch/history. It keeps the callback, queue, ACK and window implementation from the validated source, while removing personal paths/host restrictions and private handoff material. Differences include: saved HTTPS root instead of a private fixed diagnostic host; portable packager/test inputs; query-disabled tool gating and no implicit local fallback; the generic external-agent example; and public documentation/contract metadata. These differences are candidate-only until separately installed and verified. Exact tests executed on the extracted candidate are reported in the PR; prior device evidence must not be transferred to it as a fresh device test.

Extracted-candidate validation: 118 context checks, 81 contract/tool-gating checks, 87 window/recovery checks and 50 auth checks passed; four external-adapter tests and three packaging tests passed. All addon Java sources compiled with SDK 36, jar/d8 succeeded, and actual 1.0.5 packaging restored 1,605 official resources with zero missing/unauthorized entries. The candidate was not signed or installed. Full adversarial author self-review (not independent) covered migration/data loss, retained-row disclosure, disabled-query fallback, error sanitization and endpoint changes; the disabled-tool fallback finding was fixed and checked. Timestamp-only filtering, raising the single queue bound and clearing retained data were rejected because they do not preserve consent and bounded recovery. Contract event examples are synthetic fixtures.
