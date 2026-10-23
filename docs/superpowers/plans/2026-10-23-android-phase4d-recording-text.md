# Android Phase 4d — Recording Text Summary and Lifelog Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Match iOS 1.0.7 "录音与智记" additions:
- "转写文字 → 自有模型整理" (RecordingText*): the user pastes or imports a full transcript; it is split into bounded chunks, each summarised in order with the user's own model after one confirmation, and saved as an independent Markdown file with the input appended.
- "全天智记导出": the lifelog transcript cached on the phone, exported as Markdown. iOS exports its side-captured final text; Android exports the official cached transcript via `CeLifelog`.

**Architecture:**
- **Pure core:** `RecordingText` ports chunking, payload, answer and Markdown assembly.
- **UI:** `RecordingTextUI` is an editor plus `DocumentPicker` import, a confirm dialog and a sequential `ModelCall` per chunk, with cancel. It saves the result in the no-backup dir and shares it through the host share provider (`RecordingExports.share`).

**Spec:** `official-addon/ios107-edition/RecordingText.m`, `RecordingTextUI.m`, `RecordingTextMenu.m`.

## Global Constraints

- **Chunks (TIORecordingTextChunks):**
  - The text must be non-blank and ≤ 300000 UTF-16 units, otherwise null.
  - Windows are 6000 units. Cut after the last "\n" in the window if it lies past start+3000; otherwise cut at the window end, extended so a surrogate pair is never split.
- **Payload (TIORecordingSummaryPayload):** model 1..160 chars with no control characters; text 1..8000. The exact iOS system prompt, max_tokens 4096, stream false, and the optional `thinking` disabled.
- **Answer (TIORecordingSummaryAnswer):** exactly 1 choice; finish_reason "stop"; no tool_calls/function_call; content a non-blank string ≤ 64000. Otherwise "模型没有完整结束、返回空内容或非文字结果；未把半截摘要保存为成功。".
- **Markdown:**
  - Header `# 自有模型整理\n\n模型：%s\n\n来源：用户确认的转写文字；保留官方 ASR。共 %d 段，全部处理完成。以下是逐段整理，不冒充全文综合结论；行动项仅为建议，未自动创建待办。\n\n`.
  - Then `## 第 %d 段\n\n%s\n\n` per chunk.
  - Then `\n---\n\n# 输入转写（原样保留）\n\n%s\n`.
  - Written only when every chunk succeeded.
- **Import:** a UTF-8 TXT/MD file ≤ 2 MB and ≤ 300000 chars, otherwise "需要非空 UTF-8 TXT/MD，最多 30 万字符 / 2 MB；不会悄悄截断全文。". The clipboard is never read automatically.
- **Confirm text:** iOS "发送转写文字？" with the service host, model, character count and chunk count.
- **Lifelog export:**
  - The rows of one chosen day from `CeLifelog.read`, oldest first: `# 全天智记文字\n\n来自官方 App 本机缓存的逐句正文，不是完整历史或原音频。时间为片段开始时间。\n\n` then `- HH:mm:ss text` lines.
  - Shared as `全天智记.md`; no network.

## Review Focus

1. Nothing is sent before confirmation, and cancel stops further chunks.
2. A partial run never produces a "success" file.
3. The text is never silently truncated.
4. The key never reaches UI text (`ModelCall` fixed texts).
5. Exported files go only through the host share provider.

---

### Task 1: RecordingText core

**Files:** Create `src/com/turboio/addon/RecordingText.java` and `tests/RecordingTextTest.java`.

**Tests:**
- Chunks:
  - blank → null; 300001 chars → null;
  - 10000 chars with a newline at 4500 → the cut lands after the newline;
  - a newline at 2000 → cut at 6000;
  - a surrogate pair straddling 6000 is not split;
  - the chunks concatenate back to the original.
- Payload: the prompt equals iOS; `thinking` is present only when the switch is on; text over 8000 → null.
- Answer: finish "length" → null; tool_calls → null; blank → null; OK text is returned.
- Markdown: exact header and sections.
- Lifelog Markdown: exact header and line format.

### Task 2: RecordingTextUI + lifelog export

**Files:** Create `RecordingTextUI.java`; add entries in TurboAddon's "录音与全天智记" area or the 设置 tab.

Verify: `build.sh` is green and package 1.0.7 is clean.
