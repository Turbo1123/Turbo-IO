import Foundation

/// Main-queue owned, one round at a time. Credentials/audio/text never logged.
/// ASR/LLM use fixed origins. Optional tools are provided by the consented host;
/// there is no arbitrary URL, shell, or approval tool. No redirects.
final class CloudVoicePipeline {
    var log: ((String) -> Void)?
    var onEndpoint: ((UUID) -> Void)?
    var onTranscript: ((UUID,String,Bool) -> Void)?
    var onArchiveTranscript: ((UUID,String,Bool) -> Void)?
    var onText: ((UUID,String,Bool) -> Void)?
    var onError: ((UUID) -> Void)?
    var onUtteranceBegan: ((UUID,UUID) -> Void)?
    var onEmptyUtterance: ((UUID) -> Void)?
    var continuousASR = false // Set only while stopped; experimental opt-in.
    var toolDefinitions: (() -> [[String: Any]])?
    var executeTool: ((String, String, UUID) async -> String)?
    private(set) var id: UUID?
    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var receiver: Task<Void,Never>?, sender: Task<Void,Never>?, modelTask: Task<Void,Never>?
    private var queue: [Data] = [], queueBytes = 0, totalBytes = 0
    private var ready = false, finishing = false, asrDone = false
    private var parts: [Int:String] = [:]
    private var history: [[String:String]] = []
    private var lastTranscript = ""
    private var lastTranscriptUpdate = 0.0
    private var turns = StreamingASRTurns()
    private var modelID: UUID?
    private let noRedirect = NoCloudRedirect()

    func start(id: UUID) {
        precondition(Thread.isMainThread)
        cancel()
        self.id = id
        guard let key = CloudVoiceKeys.get(CloudVoiceKeys.asrService), CloudVoiceKeys.get(CloudVoiceKeys.llmService) != nil else { fail(id,"缺少Keychain凭证"); return }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = continuousASR ? 135 : 35
        config.urlCache = nil; config.httpCookieStorage = nil
        let session = URLSession(configuration:config,delegate:noRedirect,delegateQueue:nil)
        self.session = session
        var request = URLRequest(url:URL(string:"wss://\(CloudVoiceKeys.asrHost)/api-ws/v1/inference")!)
        request.setValue("bearer " + key,forHTTPHeaderField:"Authorization")
        let ws = session.webSocketTask(with:request); ws.maximumMessageSize = 32768
        socket = ws; ws.resume()
        let taskID = id.uuidString.replacingOccurrences(of:"-",with:"").lowercased()
        let command: [String:Any] = ["header":["action":"run-task","task_id":taskID,"streaming":"duplex"],
            "payload":["task_group":"audio","task":"asr","function":"recognition",
                       "model":"qwen-audio-3.0-asr-flash-streaming",
                       "parameters":["format":"pcm","sample_rate":16000],"input":[:]]]
        receiver = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await ws.send(.dataJSON(command))
                guard self.id == id else { return }
                self.log?("云ASR run-task已发；PCM16/16k/mono；服务默认VAD")
                var events = 0
                while !Task.isCancelled, self.id == id {
                    let message = try await ws.receive()
                    guard self.id == id else { return }
                    let data: Data
                    switch message { case .data(let d): data = d; case .string(let s): data = Data(s.utf8); @unknown default: throw CloudError.invalid }
                    guard data.count <= 32768, let object = try JSONSerialization.jsonObject(with:data) as? [String:Any],
                          let header = object["header"] as? [String:Any], header["task_id"] as? String == taskID else { throw CloudError.invalid }
                    events += 1; guard events <= (self.continuousASR ? 10000 : 2000) else { throw CloudError.limit }
                    switch header["event"] as? String {
                    case "task-started":
                        self.ready = true; self.log?("云ASR task-started，开始发送内存音频")
                        self.drain(id)
                    case "result-generated":
                        let payload = object["payload"] as? [String:Any]
                        let output = payload?["output"] as? [String:Any]
                        if let sentence = output?["sentence"] as? [String:Any],
                           let text = sentence["text"] as? String {
                            guard text.utf8.count <= 8192 else { throw CloudError.limit }
                            let final = sentence["sentence_end"] as? Bool == true
                            if self.continuousASR {
                                if sentence["heartbeat"] as? Bool == true { continue }
                                guard let number = sentence["sentence_id"] as? NSNumber,
                                      number.doubleValue == Double(number.intValue) else { throw CloudError.invalid }
                                self.log?("持续ASR事件 sentence=\(number.intValue) characters=\(text.count) begin=\(sentence["sentence_begin"] as? Bool ?? false) end=\(final)；正文不入日志")
                                let turnEvents = try self.turns.accept(sentenceID:number.intValue,text:text,
                                    begin:sentence["sentence_begin"] as? Bool ?? false,end:final,
                                    heartbeat:false,now:ProcessInfo.processInfo.systemUptime)
                                for event in turnEvents {
                                    guard self.id == id else { return }
                                    switch event {
                                    case .began(let turn):
                                        self.modelID = nil; self.modelTask?.cancel(); self.modelTask = nil
                                        self.log?("持续ASR有效文字新句，取消旧模型发送代际；忽略空BOS，非本地VAD")
                                        self.onUtteranceBegan?(turn,id)
                                    case .transcript(let turn, let transcript, let isFinal):
                                        self.onArchiveTranscript?(turn,transcript,isFinal)
                                        self.onTranscript?(turn,Self.lensText(transcript),isFinal)
                                    case .ended(let turn, let transcript):
                                        if transcript.isEmpty { self.onEmptyUtterance?(turn); continue }
                                        self.onEndpoint?(turn)
                                        guard self.id == id else { return }
                                        self.log?("持续ASR分句完成 characters=\(transcript.count)；不发finish-task，并行启动模型")
                                        self.startModel(id,transcript:transcript,turnID:turn)
                                    }
                                }
                                continue
                            }
                            self.log?("云ASR文字事件 characters=\(text.count) sentenceEnd=\(final)")
                            let visible = Self.lensText(text)
                            self.onArchiveTranscript?(id,text,final)
                            let now = ProcessInfo.processInfo.systemUptime
                            if !self.finishing, !visible.isEmpty,
                               final || (visible != self.lastTranscript && now - self.lastTranscriptUpdate >= 0.5) {
                                self.onTranscript?(id,visible,final)
                                guard self.id == id else { return }
                                self.lastTranscript = visible; self.lastTranscriptUpdate = now
                            }
                            if final, !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
                                let index = (sentence["sentence_id"] as? NSNumber)?.intValue ?? 0
                                guard self.parts.count < 16 || self.parts[index] != nil else { throw CloudError.limit }
                                self.parts[index] = text
                                if !self.finishing {
                                    self.finishing = true
                                    self.log?("云ASR自然句末已到；非本地900ms截断")
                                    self.onEndpoint?(id)
                                    guard self.id == id else { return }
                                    self.drain(id)
                                }
                            }
                        }
                    case "task-finished":
                        if self.continuousASR { throw CloudError.remote }
                        self.asrDone = true
                        let transcript = self.parts.keys.sorted().compactMap { self.parts[$0] }.joined()
                        guard self.finishing, !transcript.isEmpty, transcript.utf8.count <= 8192 else { throw CloudError.invalid }
                        ws.cancel(with:.normalClosure,reason:nil)
                        self.log?("云ASR task-finished characters=\(transcript.count)；转交DeepSeek，仅文字")
                        self.startModel(id,transcript:transcript)
                        return
                    case "task-failed": throw CloudError.remote
                    default: break
                    }
                }
            } catch { if self.id == id && !Task.isCancelled { self.fail(id,"ASR连接或协议失败") } }
        }
    }
    func appendPCM(_ data: Data) {
        precondition(Thread.isMainThread)
        guard let id, !finishing, !data.isEmpty else { return }
        guard data.count <= 3840, data.count % 2 == 0, queueBytes + data.count <= 96000,
              totalBytes + data.count <= (continuousASR ? 3_900_000 : 704000) else { fail(id,"音频队列/总量超限"); return }
        queue.append(data); queueBytes += data.count; totalBytes += data.count
        drain(id)
    }
    private func drain(_ current: UUID) {
        guard id == current, ready, sender == nil, !asrDone, let ws = socket else { return }
        sender = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if self.id == current { self.sender = nil } }
            do {
                while self.id == current && !Task.isCancelled {
                    if !self.queue.isEmpty {
                        let data = self.queue.removeFirst(); self.queueBytes -= data.count
                        try await ws.send(.data(data))
                    } else {
                        if self.finishing {
                            let taskID = current.uuidString.replacingOccurrences(of:"-",with:"").lowercased()
                            try await ws.send(.dataJSON(["header":["action":"finish-task","task_id":taskID,"streaming":"duplex"],"payload":["input":[:]]]))
                            if self.id == current { self.ready = false; self.log?("云ASR finish-task已发，等待最终完成") }
                        }
                        return
                    }
                }
            } catch { if self.id == current && !self.asrDone && !Task.isCancelled { self.fail(current,"ASR音频发送失败") } }
        }
    }
    private func startModel(_ current: UUID, transcript: String, turnID: UUID? = nil) {
        guard id == current, let session, let key = CloudVoiceKeys.get(CloudVoiceKeys.llmService) else { fail(current,"缺少模型凭证"); return }
        let responseID = turnID ?? current
        modelTask?.cancel(); modelID = responseID
        var request = URLRequest(url:URL(string:"https://api.deepseek.com/chat/completions")!)
        request.httpMethod = "POST"; request.timeoutInterval = 20
        request.setValue("Bearer " + key,forHTTPHeaderField:"Authorization")
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        let tools = toolDefinitions?() ?? []
        let allowed = Set(tools.compactMap { ($0["function"] as? [String: Any])?["name"] as? String })
        let toolPolicy = tools.isEmpty ? "没有工具执行能力，不能声称已创建提醒、待办或执行操作。" : "仅在用户明确要求时调用提供的Codex工具，每轮最多一个。普通聊天直接回答。不得编造执行成功，不得替用户批准权限。用户要求停止朗读或换聊天话题不等于停止Codex任务。任务可后台运行；问进度用codex_status，审批请用户在Turbo IO确认。待办天气等其他工具尚未接入，不能声称执行。"
        let messages = [["role":"system","content":"你是眼镜上的中文语音助手。用纯文本回答，不用Markdown。默认简洁；用户明确要求篇幅时遵循，例如约300字。" + toolPolicy]] + history.suffix(6) + [["role":"user","content":transcript]]
        var body: [String: Any] = ["model":"deepseek-v4-flash","thinking":["type":"disabled"],"stream":true,"max_tokens":1024,"messages":messages]
        if !tools.isEmpty { body["tools"] = tools; body["tool_choice"] = "auto"; body["parallel_tool_calls"] = false }
        do { request.httpBody = try JSONSerialization.data(withJSONObject:body) }
        catch { fail(current,"模型请求编码失败"); return }
        modelTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let (bytes,response) = try await session.bytes(for:request)
                guard self.id == current, self.modelID == responseID else { return }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw CloudError.remote }
                self.log?("DeepSeek HTTP200；flash/thinking disabled/stream true")
                var line = Data(), text = "", received = 0
                var coalescer = AnswerDeltaCoalescer()
                var finishReason = "unreported"
                var toolCall = VoiceToolCallAccumulator()
                var done = false, reasoning = 0
                for try await byte in bytes {
                    guard self.id == current, self.modelID == responseID, !Task.isCancelled else { return }
                    received += 1; guard received <= 262144 else { throw CloudError.limit }
                    if byte != 10 { line.append(byte); guard line.count <= 32768 else { throw CloudError.limit }; continue }
                    defer { line.removeAll(keepingCapacity:true) }
                    guard let string = String(data:line,encoding:.utf8), string.hasPrefix("data:") else { continue }
                    let value = string.dropFirst(5).trimmingCharacters(in:.whitespacesAndNewlines)
                    if value == "[DONE]" { done = true; break }
                    guard let object = try JSONSerialization.jsonObject(with:Data(value.utf8)) as? [String:Any],
                          let choices = object["choices"] as? [[String:Any]] else { throw CloudError.invalid }
                    for choice in choices {
                        if let reason = choice["finish_reason"] as? String {
                            finishReason = ["stop","length","content_filter","tool_calls"].contains(reason) ? reason : "other"
                        }
                        let delta = choice["delta"] as? [String:Any]
                        try toolCall.append(delta?["tool_calls"])
                        if let extra = delta?["reasoning_content"] as? String { reasoning += extra.count }
                        let addition = delta?["content"] as? String ?? ""
                        text += addition
                        guard text.utf8.count <= 8192 else { throw CloudError.limit }
                        for chunk in try coalescer.append(addition,now:ProcessInfo.processInfo.systemUptime) {
                            guard self.id == current, self.modelID == responseID else { return }
                            self.onText?(responseID,chunk.text,chunk.final)
                        }
                    }
                }
                guard self.id == current, self.modelID == responseID else { return }
                guard done else { throw CloudError.invalid }
                if toolCall.present {
                    let (name, arguments) = try toolCall.validated(allowed: allowed, finishReason: finishReason)
                    guard let execute = self.executeTool, self.id == current, self.modelID == responseID, !Task.isCancelled else { throw CloudError.invalid }
                    self.log?("Codex工具提交；不记录参数/正文，不含自动审批")
                    let result = await execute(name, arguments, responseID)
                    guard self.id == current, self.modelID == responseID, !Task.isCancelled else { return }
                    let addition = (text.isEmpty ? "" : "\n") + result
                    text += addition
                    for chunk in try coalescer.append(addition, now: ProcessInfo.processInfo.systemUptime) {
                        self.onText?(responseID, chunk.text, chunk.final)
                    }
                }
                guard !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw CloudError.invalid }
                self.log?("DeepSeek流完成 characters=\(text.count) reasoningCharacters=\(reasoning) finishReason=\(finishReason)；正文不入日志")
                self.history.append(["role":"user","content":String(transcript.prefix(1000))])
                self.history.append(["role":"assistant","content":String(text.prefix(1000))])
                self.history = Array(self.history.suffix(6))
                for chunk in try coalescer.append("",final:true,now:ProcessInfo.processInfo.systemUptime) {
                    guard self.id == current, self.modelID == responseID else { return }
                    self.onText?(responseID,chunk.text,chunk.final)
                }
            } catch { if self.id == current && self.modelID == responseID && !Task.isCancelled { self.fail(current,"模型请求或流式响应失败") } }
        }
    }
    static func lensText(_ source: String) -> String {
        let text = source.trimmingCharacters(in:.whitespacesAndNewlines)
        var result = ""
        for char in text {
            let item = String(char)
            if result.utf8.count + item.utf8.count > 500 { return result + "…" }
            result += item
        }
        return result
    }
    func cancel(clearHistory: Bool = false) {
        precondition(Thread.isMainThread)
        id = nil
        modelID = nil; turns = StreamingASRTurns()
        receiver?.cancel(); sender?.cancel(); modelTask?.cancel()
        receiver = nil; sender = nil; modelTask = nil
        socket?.cancel(with:.goingAway,reason:nil); socket = nil
        session?.invalidateAndCancel(); session = nil
        queue.removeAll(); queueBytes = 0; totalBytes = 0; parts.removeAll()
        ready = false; finishing = false; asrDone = false
        lastTranscript = ""; lastTranscriptUpdate = 0
        if clearHistory { history.removeAll() }
    }
    private func fail(_ current: UUID, _ reason: String) {
        guard id == current else { return }
        log?("云链路失败：\(reason)；未记录服务端错误正文")
        cancel(); onError?(current)
    }
    private enum CloudError: Error { case invalid, remote, limit }
}
private final class NoCloudRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
private extension URLSessionWebSocketTask.Message {
    static func dataJSON(_ object: [String:Any]) throws -> Self {
        .string(String(decoding:try JSONSerialization.data(withJSONObject:object),as:UTF8.self))
    }
}
