# Wake-source investigation

## Evidence and limits

The official iO help page documents Hey RayNeo / OK RayNeo and the configured
crown shortcut. The repository records `set_ai_wakeup_word` with one observed
payload (`mode=1`, `value=0`, empty `data`). This does not establish arbitrary
keyword support or support for multiple simultaneous keywords. Guessed writes
are excluded from normal operation. The separately authorized single-candidate
experiment below is an explicit exception, not a supported setter API.

The diagnostic build observes assistant business 13, message type 1. It preserves
the existing wake/audio handshake. It reports message/audio byte counts and a
bounded JSON summary; it never retains raw audio, message text, arbitrary field
names, device identifiers or credentials in the new diagnostic output. Only
fixed candidate source field names and integral values from 0 through 255 are
shown. These are unverified values, not a documented source mapping. Other
values are represented by type; unknown keys are counted, not printed. JSON
inspection is limited to 8 KiB, nesting depth two and 16 visible fields.

The conversation page retains the latest six summaries in memory, oldest first,
under “唤醒诊断 · 最近六次”. They also pass through the existing sanitized device
log. Restarting the app clears the on-screen history, not necessarily OS logs.
An opaque, absent or identical payload does not prove the firmware lacks source
information or custom keywords; it only limits what this observer establishes.

## Owner-operated comparison

Owner report on 2026-09-12: crown double-click and “小雷小雷” open the
assistant; Hey RayNeo and OK RayNeo do not on this device. The two displayed
type-1 rows were both produced by crown double-click. They do not establish a
voice-versus-button source mapping or the firmware's custom-keyword support.

1. Keep the existing app installation, Bundle ID, signing and glasses binding.
   Install the diagnostic update in place; do not uninstall or pair again.
2. Open the conversation page, confirm authentication and enable standby.
   Cloud conversation can remain off for a local random-response test: waking
   still requests audio, but the local mode does not send it to ASR/DeepSeek.
3. Trigger one crown double-click, then wait for the round to finish or select
   “结束本轮，保留待命”. Wait for “等待眼镜唤醒”.
4. Say “小雷小雷”, finish that round and return to idle; then compare English
   phrases only if needed. Public English help is not evidence that every
   regional firmware recognizes those phrases.
5. Expand the diagnostic section. Note which action produced each new row, and
   share only these sanitized rows. Repeat the sequence once if practical.
   A phrase that produces no new row has not supplied an observable wake event.

Do not change the app's cloud credentials or enable an always-recording mode for
this comparison. Firmware writes are a separate experiment with explicit scope
and a recovery procedure; the original read-only comparison does not authorize
arbitrary parameter changes.

## Decision after hardware evidence

- Different, repeatable source values: establish their mapping before using them
  for routing. This alone still does not prove Hey Norman can be added.
- No distinguishable source: use the existing wake mechanism plus an ASR command
  such as “Hey Norman” to select Hermes, or an explicit phone-side mode selector.
- True Hey Norman wake: requires confirmed custom-keyword support and a reliable
  way for the app to select Hermes. Hermes bridge implementation remains separate.

## Read-only wake-settings query

The conversation page now offers “唤醒词设置 · 只读诊断” → “读取眼镜唤醒设置”.
It sends only the existing `request_general_status` (type 1) and
`request_general_settings` (type 4) commands, with mode/value zero and empty
data. It does not send `set_ai_wakeup_word`, modify firmware settings, or start
audio. It requires the current authenticated device and no active voice,
recording or teleprompter task. It does not modify the user's standby preference.

For eight seconds, the existing authenticated business-15 receive path observes
types 1, 3, 4, 6 and 17. The UI retains at most six sanitized summaries. Only a
fixed allowlist of wake-control fields, booleans, integers 0–255 and four known
test phrases can be printed. Arbitrary strings, field names and audio are not
printed. JSON inspection is bounded to 8 KiB, depth three, 128 visited fields and
16 output fields; JSON-encoded `data` objects are inspected within those bounds.
These sanitized summaries also appear under `[WakeSettingsDiagnostic]` in OS
logs. Missing fields, unknown response shapes and numeric codes establish no
capability result; an overlapping status event is not a correlated command ACK.

The explicit launch argument `--wake-settings-diagnostic` makes this query once
when the app has an authenticated idle connection. It is not saved, never retries
on reconnect and is not part of ordinary startup. `--ui-tab 1` opens the page.
With that argument, authenticated initialization responses may also be observed
in the first 30 seconds before the query. They are labeled `startup` and must not
be mistaken for replies to the later read-only query.

Public discovery on 2026-09-12 found no iO arbitrary wake-word API in the official
help page or the visible developer-platform SDK catalog (X/Air/V). The recovered
Swift interface in this repo is a declaration-only shim, not the full SDK API;
its lack of a setter cannot prove that no private setter exists. The one observed
`set_ai_wakeup_word` payload has empty data: writing “Hey Norman” there remains
an unverified parameter hypothesis, not a documented test command.

Hardware observation on 2026-09-12, from the current authenticated target:

```text
startup type=17: payload.data.ai_voice_wakeup=1, payload.data.ai_wakeup_word=1
query type=1: wakeFields=0, unknownFields=13
query type=4: wakeFields=0, unknownFields=25
```

Both wake values are JSON numbers, not returned keyword strings. Their meaning
is still unverified: this does not prove they are booleans, preset selectors, or
custom-keyword capability flags. The startup response precedes the two explicit
read-only queries. That read-only run performed no `set_ai_wakeup_word` write or
“Hey Norman” firmware wake test. The subsequent owner request explicitly permits
testing the data-field hypothesis without an official operation sample.

Software validation: 105 protocol tests passed (including five added settings
diagnostic tests); the device build succeeded and was installed over the existing
matching app identifier. `artifacts/wake-settings/` holds this change's exact
diff, test output and sanitized hardware results. No device pairing, signing
configuration, cloud credentials or vendor framework contents were changed.

## Owner-authorized single-candidate write

Hypothesis: the existing `set_ai_wakeup_word` command might accept a phrase in
`payload.data`. The owner explicitly asked to test this without waiting for an
official sample. `WakeWordDataTrial` therefore emits exactly one candidate:

```json
{"cmd":"set_ai_wakeup_word","payload":{"data":"Hey Norman","mode":1,"value":0}}
```

Business remains 15 and message type remains 16. Only data changes; no mode
enumeration, alternate encodings, firmware update or pairing operation is tried.
The command is experimental. A transport callback or status response cannot
establish that the phrase works; the owner must test it from idle without first
using the crown or “小雷小雷”. Hermes routing is outside this experiment.

The app saves a recovery target and an attempted flag under new
`norman.wakeWordDataTrial.v1.*` UserDefaults keys before sending. The target is
used only to avoid restoring another device and is never logged. Existing
pairing records, voice preferences and credentials are not changed. This version
allows only one candidate attempt; reconnecting/restarting never repeats it.

After 120 seconds, or on reconnect after interruption, the app submits the
observed original packet (`data=""`, `mode=1`, `value=0`) to the same authenticated
target. “恢复原参数” can submit it earlier or retry a failed restoration. Timers
depend on the app running: keep it in the foreground. On a new launch, an
outstanding marker triggers one restoration submission when that target is ready.
No automatic restoration retry loop is used. The marker stays until the owner
actually verifies “小雷小雷” and selects “已确认小雷小雷可唤醒”. An empty-data
packet is a recovery attempt, not proof of successful restoration.

The launch argument `--wake-word-data-trial` runs the existing read-only query,
then this single write when idle. Normal launches never initiate the candidate.
`--wake-word-confirm-restored` represents an explicit owner confirmation already
obtained by the operator; do not use it based only on a device ACK. The UI offers
the same actions under “Hey Norman · 单次试写”. Sanitized responses are labeled
`trial` or `restore`, with observation windows ending 128 seconds after trial
start or eight seconds after a restoration submission. Wake-event diagnostics
still contain no phrase/source mapping; correlate them with the owner's report.

Six lifecycle/packet tests cover the fixed candidate, original packet,
single-attempt limit, timed/manual restoration, wrong-device rejection,
interrupted-run recovery and owner confirmation. Test/build results and the
exact incremental diff are recorded under `artifacts/wake-word-trial/`.

Hardware result on 2026-09-12: the 87-byte candidate was submitted and a type-17
status response again reported `ai_voice_wakeup=1` and `ai_wakeup_word=1`. The
owner reported no response to “Hey Norman”. One type-1 wake event appeared during
the trial; the owner clarified that “小雷小雷” caused the successful wake and
the other phrases did not. Therefore the event is not evidence for the candidate.
The operator ended the trial early and submitted the original 77-byte packet;
the returned wake values remained 1. The owner confirmed “小雷小雷” works.
The operator then recorded that owner confirmation and cleared the experiment's
recovery target. The attempted latch remains set, so this candidate is not resent.
This data-field hypothesis did not produce a working custom wake word on the
tested device. It does not rule out other private APIs or firmware support.

Validation for the write experiment: 111 protocol tests passed, device build
succeeded, and the app was installed in place with its existing identifier.
The prior read-only diagnostics and this explicitly authorized write are
separate results; neither means Hermes routing has been implemented.

## Reproduce software checks

From the repository root:

```sh
xcrun swift test --package-path rayneo-protocol \
  --scratch-path artifacts/wake-diagnostics/swift-build
xcrun swift test --package-path rayneo-session \
  --scratch-path artifacts/wake-diagnostics/session-build
```

Build using the existing device Xcode project and owner-managed signing setup;
do not regenerate or rewrite the local device spec or vendor binaries for this
task. Build success is not evidence that wake phrases or routing work on hardware.

Source: https://www.rayneo.com/pages/support-rayneo-io-ai-glasses
