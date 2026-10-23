# Android Phase 4a — Model & Voice Parity (thinking switch, voice exit, cloud TTS)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Match three iOS 1.0.7 model and voice settings on Android:
- DeepSeek "关闭思考" as a switch (Android currently always sends it);
- "语音退出指令", where a spoken exit phrase stops the official assistant;
- the Ali Flash realtime cloud TTS engine (`qwen-audio-3.1-tts-flash`) as an alternative to the local Android TTS.

**Architecture:** Pure, JVM-testable cores carry the logic (exit-phrase matcher, TTS chunker, DashScope event builder and parser, PCM sink contract). Android glue does the I/O. Voice exit calls the official stop path the host's own ASR listener uses, reached from the listener the addon already hooks, and is gated at packaging time and at runtime.

**Spec:** Parent roadmap (Phase 4 row + "small gaps"). iOS references: `official-addon/ios107-edition/Addon.m` (`deepseekDisableThinking`, `voiceExitCommands`, `exitVoice`, `AsrHook`, TTS rows), `official-addon/ios107-edition/Core.m` (`TIOIsVoiceExitCommand`), `official-addon/ios107-edition/VoiceTTS.m`, `official-addon/VoiceTTSCore.m`.

## Global Constraints

- **Thinking:**
  - `thinking:{type:"disabled"}` is only sent when the switch is on (pref `disable_thinking`).
  - The default is **on**, because existing Android installs always sent it. Changing that silently would change answers for current users.
- **Exit phrases**, exactly as iOS `TIOIsVoiceExitCommand`:
  - Accept text of length 1..48.
  - Trim whitespace and `，。！？,.!?、：:`, strip a leading `小雷小雷`, trim again, then remove all inner whitespace.
  - Match exactly one of 退下吧, 退下, 关闭, 没事了, 关闭窗口, 关闭对话, 结束对话, 退出对话, 不用了, 就这样吧.
  - Only final ASR is considered. Never use substring matching.
  - The switch (pref `voice_exit`) defaults to off.
- **Official stop path:**
  - The hooked ASR listener (`p8/c$c` on 1.0.6, `q8/c$c` on 1.0.7) holds its outer `p8/c`/`q8/c` in field `a`.
  - The outer method `s(Ljava/lang/String;ZZ)V` is the official stop: it logs `stop_assistant` and calls `AssistantController.stopWorkflow(config)`.
  - The listener itself stops the assistant via `t(outer,false,null,…)` → `s(null,false,false)`. Voice exit makes exactly that call, `s(null,false,false)`, after cancelling the addon's own stream and TTS.
  - At packaging, `verifyHost` must find, in the outer class:
    - `.method public final s(Ljava/lang/String;ZZ)V`;
    - the string `"stop_assistant"` inside that method;
    - the listener field `.field public final synthetic a:L<outer>;`.
  - At runtime, the reflective lookup must resolve exactly that signature, or the switch shows "当前版本停止入口未通过校验，未启用" and is disabled (iOS `VoiceExitReady`).
- **Cloud TTS** (iOS `VoiceTTS.m`):
  - Endpoint `wss://dashscope.aliyuncs.com/api-ws/v1/inference`, or a custom `wss` endpoint that passes `TIOVoiceTTSServiceURLValid`: host `dashscope.aliyuncs.com` or `*.maas.aliyuncs.com`, path `/api-ws/v1/inference`, port 443, no user, query or fragment.
  - Headers: `Authorization: Bearer <key>` and `X-DashScope-DataInspection: enable`.
  - The task flow:
    - `run-task` (task_group audio, task tts, function SpeechSynthesizer, model `qwen-audio-3.1-tts-flash`, parameters text_type PlainText, voice `longanhuan_v3.1`, format pcm, sample_rate 24000, volume 50, rate 1, pitch 1, enable_ssml false);
    - `task-started`, then `continue-task` with `{text}` per chunk;
    - `finish-task`, then `task-finished`;
    - `task-failed` means failure.
  - Audio arrives as binary frames of PCM16 LE, mono, 24 kHz, each 2 B..512 KiB.
  - Limits: 1800 characters per turn and 18 segments. The chunker is `TIOVoiceTTSChunk` exactly: cut at `。！？!?；;\n` (i≥3), or at `，,、：: ` once i≥65; force a cut at 140 (max 180), or at final; never split a surrogate pair; trim.
  - No playback unless a Bluetooth output is connected ("眼镜音频未连接").
  - The key lives in `SecretStore` under `tts_key` and is never shown again after saving.
- Everything is explicit: nothing starts a network call except an answer being spoken with the cloud engine selected, or the user tapping "播放测试语音".

## Review Focus

1. **Exit on chat content.** A sentence that merely contains 关闭 (e.g. "帮我关闭空调的提醒") must not exit. Covered by `VoiceExitTest`.
2. **Exit when the stop entry is missing.** On an unknown host, or with a signature mismatch, the switch is disabled and the ASR path behaves as before. Covered by `VoiceExitTest` (resolver returns null → no call), `HostProfilesTest` (verifyHost fails without the method or string) and `OtaHooksTest` remaining green.
3. **TTS key leakage.** The key must not appear in logs, status text or the run-task JSON. Covered by `CloudTtsTest`.
4. **TTS after cancel.** Audio or events arriving after `cancel()` or a new turn are dropped. Covered by the generation check in `CloudTtsTest`.
5. **Thinking default for existing users.** An install with no pref keeps sending `thinking`. Covered by `ChatPolicyTest` / a body-builder test.

---

### Task 1: Thinking switch

**Files:**
- Modify `src/com/turboio/addon/ChatPolicy.java`: add `static boolean sendThinkingDisabled(android.content.SharedPreferences p)` → `p.getBoolean("disable_thinking",true)`. If `ChatPolicy` must stay Android-free for its JVM test, add a pure `static boolean thinkingDisabled(Boolean stored)` (null → true) and test that instead.
- Modify `TurboAddon.java` around line 250 so `thinking` is added only when the switch is on.
- Add a switch "DeepSeek：关闭思考扩展参数" to the settings next to the model configuration.

**Test:** `tests/ChatPolicyTest.java`: `thinkingDisabled(null)==true`, `thinkingDisabled(true)==true`, `thinkingDisabled(false)==false`.

- [ ] RED.
- [ ] Implement.
- [ ] `build.sh` green.
- [ ] **Commit** `feat(android): DeepSeek thinking switch (default on, as before)`.

### Task 2: Voice exit

**Files:**
- Create `src/com/turboio/addon/VoiceExit.java`, containing:
  - `static boolean matches(String text)`;
  - `interface Stopper{boolean stop(Object listener);}`;
  - `static Stopper resolve(Object listener)`, which reflects field `a` and then `s(String,boolean,boolean)`, returning null on any mismatch;
  - `static boolean ready()`.
- Modify `TurboAddon.dispatchAsr`: when final, the switch is on, `matches` holds and `resolve(listener)` succeeds, do `cancel()` + `VoiceSpeech.stop(...)`, invoke the stop, record a diagnostic and return before normal handling. Afterwards, ignore further text from the same session until a new audio start. Mirror iOS `_voiceExited`; if no clean "new turn" signal exists, use a new session id.
- Modify `host-profiles.mjs` `verifyHost`: require the outer stop method, its `"stop_assistant"` string and the listener field `a`. Extend `HostProfilesTest` fixtures with them, and add a negative test.
- Settings: switch "语音退出指令", with the detail text from iOS ("退下吧 / 关闭 / 没事了 / 关闭窗口；完整短句匹配") or the disabled-entry text.

**Tests:** `tests/VoiceExitTest.java`:
- every iOS phrase matches, including with `小雷小雷，`, punctuation and spaces;
- "帮我关闭空调的提醒", "关闭吗", "不用了谢谢" and a 49-character text do not match;
- `resolve` on a fake listener whose class has field `a` → outer with `s(String,boolean,boolean)` calls it with `(null,false,false)` exactly once;
- `resolve` on a fake without the method returns null.

- [ ] RED.
- [ ] Implement.
- [ ] `build.sh` green; `verifyHost` passes on the real `build/host-106` and `build/host-107`; `package.mjs` 1.0.7 reports `unexpected_paths` empty.
- [ ] **Commit** `feat(android): voice exit phrases stop the official assistant`.

### Task 3: Ali Flash cloud TTS

**Files:**
- Create `src/com/turboio/addon/CloudTts.java`, containing:
  - the pure core: `static String chunk(String pending,boolean fin,int[] consumed)`, `static boolean endpointValid(String)`, `static String runTask(String taskId)`, `static String continueTask(String taskId,String text)`, `static String finishTask(String taskId)`, `static String event(String json)` (returns the header.event or "");
  - a session class: `CloudTts(Transport t, Pcm sink, KeyProvider k)` with `beginTurn()`, `append(String full,boolean fin)`, `cancel()`, `status()`;
  - the interfaces `Transport{void open(String url,String key,Listener l);boolean send(String json);void close();}` and `Pcm{boolean write(byte[] pcm16le);void stop();}`.
- Modify `BoundedWebSocket.java`: add `default void binary(byte[] b){}` to `Listener` and deliver binary frames (op 2, reassembled, ≤512 KiB) to it. Add an optional extra-headers parameter for `X-DashScope-DataInspection`.
- Modify `VoiceSpeech.java`: engine selection (pref `tts_engine`: `local` default | `cloud`). The cloud engine uses `CloudTts` with an `AudioTrack` PCM sink (24 kHz mono 16-bit, `USAGE_ASSISTANT`) routed like the current local TTS. It refuses without Bluetooth output.
- Modify the settings rows: "朗读引擎" (本机 / 阿里 Flash 云端), "阿里 Flash TTS 配置" (key + optional endpoint, key not echoed), and "播放测试语音" (a fixed short sentence).

**Tests:** `tests/CloudTtsTest.java`, with a fake Transport and PCM sink:
- `chunk` matches `TIOVoiceTTSChunk` on these cases: a stop char before index 3 doesn't cut; a soft cut at 65; a force cut at 140; final flush; a surrogate pair at the boundary;
- `endpointValid` accepts the default and `x.maas.aliyuncs.com`, and rejects http, other hosts, a query, a port 8443 and user info;
- `runTask` JSON has the exact model, voice, format and sample rate, and does not contain the key;
- the flow: `continue-task` is only sent after `task-started`; `finish-task` is sent once after a final append;
- binary audio after `cancel()` is dropped (generation);
- `task-failed` gives status "TTS 服务返回失败" and closes;
- the 1800-character / 18-segment caps hold;
- an empty key gives status "未配置 TTS Key" and nothing is opened.

- [ ] RED.
- [ ] Implement.
- [ ] `build.sh` green; package 1.0.7.
- [ ] **Commit** `feat(android): Ali Flash realtime cloud TTS engine`.

Device checks for the user:
- toggle thinking and ask a question;
- enable voice exit, say "退下吧", and the official assistant closes;
- choose the cloud engine with a key, play the test sentence through the glasses, then ask a question and hear the answer.
