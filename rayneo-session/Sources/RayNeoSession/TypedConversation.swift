import Foundation

public enum ConversationBackendRouter {
    @MainActor public static func respond(backend: ConversationBackend,
        deepSeek: () async throws -> Void, hermes: () async throws -> Void) async throws {
        switch backend {
        case .deepSeek: try await deepSeek()
        case .hermes: try await hermes()
        }
    }
}

public enum DeepSeekTypedConversation {
    public enum Failure: Error { case invalidInput, invalidResponse }
    /// Typed requests have no ASR, glasses or tool-execution dependency. Voice keeps
    /// its existing streaming/tool path; typed replies are displayed on completion.
    public static func respond(text: String, key: String, history: [[String: String]],
        send: (URLRequest) async throws -> Data = HermesBridgeHTTP.send) async throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 8192,
              key.hasPrefix("sk-"), key.utf8.count <= 512, !key.contains(where: { $0.isWhitespace }) else { throw Failure.invalidInput }
        let instruction = """
        你是 Norman IO，用户的研究助理。用自然、平等、专业的语气交流，直接回应问题，不奉承用户。默认中文，先给结论，再补必要理由；跟随用户指定的语言和篇幅。
        区分已知事实、推测和建议。不编造论文、DOI、实验数据或引用；未验证的信息要明确说明。不把未经计算或验证的公式推导、数值结论说成已验证。
        当前回答由 DeepSeek 提供，你不是用户的 Hermes 实例。此文字入口没有工具执行能力，不能声称已读取本地文件、创建任务、提醒或执行操作。
        """
        let boundedHistory = history.suffix(6).compactMap { message -> [String: String]? in
            guard let role = message["role"], ["user", "assistant"].contains(role), let content = message["content"] else { return nil }
            return ["role": role, "content": String(content.prefix(1000))]
        }
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
        request.httpMethod = "POST"; request.timeoutInterval = 25
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": "deepseek-v4-flash", "thinking": ["type": "disabled"],
            "stream": false, "max_tokens": 1024,
            "messages": [["role": "system", "content": instruction]] + boundedHistory + [["role": "user", "content": text]]])
        let data = try await send(request)
        try Task.checkCancellation()
        guard data.count <= 65_536, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]], choices.count == 1,
              let message = choices[0]["message"] as? [String: Any], let answer = message["content"] as? String,
              !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, answer.utf8.count <= 8192,
              let finish = choices[0]["finish_reason"] as? String, ["stop", "length"].contains(finish) else { throw Failure.invalidResponse }
        return answer
    }
}
