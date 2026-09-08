import Foundation

/// Local bookkeeping only. These versions and observation times are never wire timestamps/ACKs.
struct TodoDelivery: Codable, Equatable {
    struct Observation: Codable, Equatable {
        var completed: Bool
        var important: Bool?
    }
    var revision = UUID()
    var pending = true
    var submittedRevision: UUID?
    var submittedAt: Date?
    var conflict: Observation?

    mutating func edited() { revision = UUID(); pending = true }
}

enum TodoDeliveryError: LocalizedError {
    case differentDevice, conflict, missing
    var errorDescription: String? {
        switch self {
        case .differentDevice: return "列表含已关联其他眼镜的待办，未发送任何条目。暂不支持跨眼镜迁移。"
        case .conflict: return "请先在待发送与冲突页面确认状态冲突；本次未继续发送。"
        case .missing: return "待办已移除或版本已变化，请重新检查后发送。"
        }
    }
}

extension LocalTodo {
    var deliveryDescription: String {
        if delivery?.conflict != nil { return "状态冲突 · 本机修改已保留" }
        guard wireID != nil else { return completed ? "本机已完成 · 未同步" : "仅保存在手机" }
        if delivery?.pending == true { return "待发送 · 本机修改已保存" }
        if delivery?.submittedAt != nil { return "已提交 · 未逐项确认" }
        return "已关联眼镜 · 以回报为准"
    }
}
