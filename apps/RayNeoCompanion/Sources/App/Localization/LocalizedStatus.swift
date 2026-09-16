import Foundation

/// Presentation-only helpers. Never write these display strings back into models,
/// tool definitions, payloads, persisted user content, or provider responses.
extension L10n {
    static func todoDelivery(_ todo: LocalTodo, locale: Locale) -> String {
        if todo.delivery?.conflict != nil { return text("Status Conflict · Local Edits Retained", locale: locale) }
        guard todo.wireID != nil else {
            return text(todo.completed ? "Completed Locally · Not Synced" : "Saved Only on Phone", locale: locale)
        }
        if todo.delivery?.pending == true { return text("Pending Send · Local Edits Saved", locale: locale) }
        if todo.delivery?.submittedAt != nil { return text("Submitted · Items Not Individually Confirmed", locale: locale) }
        return text("Linked to Glasses · Awaiting Report", locale: locale)
    }

    static func codexToolTitle(_ tool: CodexToolDescriptor, locale: Locale) -> String {
        switch tool.id {
        case "codex_message": return text("Start / Continue Task", locale: locale)
        case "codex_status": return text("Check Progress and Results", locale: locale)
        case "codex_stop": return text("Stop Current Task", locale: locale)
        default: return tool.title
        }
    }

    static func codexToolDescription(_ tool: CodexToolDescriptor, locale: Locale) -> String {
        switch tool.id {
        case "codex_message": return text("Call only when the user explicitly asks Codex to run or continue a coding task. Sends to the task selected in the app, creating one only if none is selected. Not for ordinary chat or permission approvals.", locale: locale)
        case "codex_status": return text("Call when the user asks about the progress or results of the current Codex task.", locale: locale)
        case "codex_stop": return text("Call only when the user explicitly asks to stop the current Codex task. Stopping spoken playback does not stop Codex.", locale: locale)
        default: return tool.description
        }
    }

    static func codexToolExample(_ tool: CodexToolDescriptor, locale: Locale) -> String {
        switch tool.id {
        case "codex_message": return text("Ask Codex to inspect this project’s directory structure", locale: locale)
        case "codex_status": return text("Has Codex finished? What are the results?", locale: locale)
        case "codex_stop": return text("Stop the current Codex task", locale: locale)
        default: return tool.example
        }
    }

    static func audioContainerOutcome(_ outcome: AudioContainerOutcome, locale: Locale) -> String {
        switch outcome {
        case .supported: return text("Declared Structure Subset Passed Inspection", locale: locale)
        case .unsupported: return text("Not Supported by This Inspector", locale: locale)
        case .invalid: return text("Container Structure Error Found", locale: locale)
        case .limited: return text("Inspection Budget Exceeded", locale: locale)
        }
    }

    /// Exact allowlist for known app-owned status fields only. Never call this on
    /// user text, transcripts, provider responses, or arbitrary error descriptions.
    /// Unknown and interpolated statuses are returned byte-for-byte unchanged.
    static func appStatus(_ source: String, locale: Locale) -> String {
        guard let key = appStatusKeys[source] else { return source }
        return text(key, locale: locale)
    }

    /// QWeather owns these status templates. Captured place names and weather
    /// descriptions remain untouched; unmatched server/diagnostic text stays raw.
    static func qweatherStatus(_ source: String, locale: Locale) -> String {
        if let values = captures(source, #"^获取(.+)实时天气，目标为仪表盘首页。$"#) {
            return format("Fetching live weather for %@ to show on the dashboard home page.", locale: locale, values[0])
        }
        if let values = captures(source, #"^(.+) (-?[0-9]+)°C · (.+) 已获取；请测试候选图标 ([0-9]+)，尚未自动下发。$"#) {
            return format("%@ %@°C · %@ fetched. Test candidate icon %@; nothing was sent automatically.", locale: locale, values[0], values[1], values[2], values[3])
        }
        if let values = captures(source, #"^仪表盘已提交：(.+) (-?[0-9]+)°C · (.+)；图标 ([0-9]+) 为待验候选。不是天气卡片更新。$"#) {
            return format("Dashboard update submitted: %@ %@°C · %@; icon %@ is an unverified candidate. This does not update the weather card.", locale: locale, values[0], values[1], values[2], values[3])
        }
        if let values = captures(source, #"^仪表盘已提交：(.+) (-?[0-9]+)°C · (.+)；图标 ([0-9]+) 已人工核对。不是天气卡片更新。$"#) {
            return format("Dashboard update submitted: %@ %@°C · %@; icon %@ was manually verified. This does not update the weather card.", locale: locale, values[0], values[1], values[2], values[3])
        }
        if let values = captures(source, #"^已记录用户确认：天气码 ([0-9]+) 的同号图标；后续认证连接可自动下发此类型。$"#) {
            return format("Confirmed matching icon for weather code %@. Future authenticated connections can send this type automatically.", locale: locale, values[0])
        }
        if let values = captures(source, #"^眼镜回报 current_weather_update value=(-?[0-9]+)（协议成功值）；回执没有请求 ID，镜片内容仍需确认。$"#) {
            return format("Glasses reported current_weather_update value=%@ (protocol success value). The receipt has no request ID; confirm the displayed content.", locale: locale, values[0])
        }
        if let values = captures(source, #"^眼镜回报 current_weather_update value=(-?[0-9]+)；回执没有请求 ID，镜片内容仍需确认。$"#) {
            return format("Glasses reported current_weather_update value=%@. The receipt has no request ID; confirm the displayed content.", locale: locale, values[0])
        }
        return appStatus(source, locale: locale)
    }

    static func headControlStatus(_ source: String, locale: Locale) -> String {
        if let values = captures(source, #"^测试卡已发送；等待点头或摇头（([0-9]+) 秒）$"#) {
            return format("Test card sent; waiting for nod or shake (%@ seconds)", locale: locale, values[0])
        }
        return appStatus(source, locale: locale)
    }

    static func deviceFeatureStatus(_ source: String, locale: Locale) -> String {
        for (pattern, key) in deviceFeaturePatterns {
            guard let values = captures(source, pattern) else { continue }
            switch values.count {
            case 1: return format(key, locale: locale, values[0])
            case 2: return format(key, locale: locale, values[0], values[1])
            default: break
            }
        }
        return appStatus(source, locale: locale)
    }

    private static let deviceFeaturePatterns: [(String, String)] = [
        (#"^眼镜拒绝开始，code=(-?[0-9]+)；未自动绕过隐私/冲突$"#, "Glasses rejected start, code=%@; privacy and conflict safeguards were not bypassed."),
        (#"^已提交 ([0-9]+) 条待办；等待眼镜状态/操作回执，不代表镜片已显示$"#, "Submitted %@ to-dos; waiting for glasses status or action receipt. Display on the lenses is unconfirmed."),
        (#"^眼镜操作回执：成功 ([0-9]+)；不作为逐项镜片验收$"#, "Glasses action receipt: %@ succeeded; individual display remains unverified."),
        (#"^眼镜状态已应用 ([0-9]+) 项；离线修改冲突请查看待发送列表，未知 ID 不导入$"#, "Applied %@ glasses status updates. Review offline conflicts in pending sends; unknown IDs were not imported."),
        (#"^眼镜回报 (.{1,45})：(-?[0-9]+)（未验证镜片效果）$"#, "Glasses reported %@: %@. Display on the lenses is unverified."),
        (#"^控制 type([0-9]+) 已提交，等待眼镜回应$"#, "Control type%@ submitted; waiting for glasses response."),
        (#"^准备被拒绝 code=(-?[0-9]+)，未自动处理冲突$"#, "Preparation rejected, code=%@; conflict was not resolved automatically."),
        (#"^开始提词回应 code=(-?[0-9]+)$"#, "Teleprompter start response code=%@"),
        (#"^眼镜进度回传：UTF-8 原始偏移 ([0-9]+)$"#, "Glasses progress: original UTF-8 offset %@"),
        (#"^眼镜回应 type([0-9]+) code=(-?[0-9]+)$"#, "Glasses response type%@ code=%@"),
    ]

    private static func captures(_ source: String, _ pattern: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)) else { return nil }
        return (1..<match.numberOfRanges).compactMap { index in
            Range(match.range(at: index), in: source).map { String(source[$0]) }
        }
    }

    private static let appStatusKeys: [String: String] = [
        "提词连接中断；停止自动操作，请恢复连接后退出并重新准备": "Teleprompter connection lost. Restore the connection, exit, and prepare again before using automatic controls.",
        "正在取消，原音频保留…": "Cancelling; original audio retained…",
        "校验本机音频…": "Verifying local audio…",
        "本机解码为 16 kHz 单声道…": "Decoding locally to 16 kHz mono…",
        "手动转写中，音频正在发往阿里云…": "Transcribing manually; audio is being sent to Alibaba Cloud…",
        "保存新文字修订…": "Saving a new text revision…",
        "识别已完成但笔记未保存，可复制下方文字；原音频保留。": "Recognition finished, but the note was not saved. You can copy the text below; the original audio remains.",
        "转写完成，已保存为新 Markdown 修订；请核对识别内容。": "Transcription saved as a new Markdown revision. Please review the recognized text.",
        "已取消后续处理；原音频和已提交修订保留。": "Further processing cancelled. The original audio and saved revisions remain.",
        "转写未完成，可能断网或已取消；原音频保留。": "Transcription did not finish; the connection may have dropped or the task was cancelled. Original audio remains.",
        "已关闭；不会导出观察数据": "Off; observation data is not exported",
        "启动中": "Starting",
        "USB 观察接口已开启 · 30分钟后自动关闭": "USB observer enabled · Turns off automatically after 30 minutes",
        "接口启动失败；未暴露局域网端口": "Observer failed to start; no LAN port was exposed",
        "观察接口不可用": "Observer interface unavailable",
        "已关闭并清空本轮观察数据": "Off; observation data from this session cleared",
        "尚未发送测试卡": "No test card sent yet",
        "已请求移除测试卡": "Test card removal requested",
        "连接变化；已停止等待这张测试卡": "Connection changed; no longer waiting for this test card",
        "已收到点头确认（仅测试回调）": "Nod confirmation received (test callback only)",
        "已收到摇头取消（仅测试回调）": "Shake cancellation received (test callback only)",
        "测试已超时；不执行任何操作": "Test timed out; no action taken",
        "准备本机接收目录": "Preparing local receiving folder",
        "已请求开始，等待眼镜回应": "Start requested; waiting for glasses response",
        "收到同步列表；本版不自动导入或清理离线积压": "Sync list received; offline backlog is not imported or cleared automatically",
        "已接受眼镜录音，等待数据": "Glasses recording accepted; waiting for data",
        "眼镜已确认开始录音": "Glasses confirmed recording started",
        "正在接收并保存原始音频": "Receiving and saving original audio",
        "眼镜已报告完成，核对接收覆盖并封装": "Glasses reported completion; checking received data and finalizing",
        "停止事件已收到，等待音频完成": "Stop event received; waiting for audio completion",
        "收到同一录音重连状态；继续按 offset 校验": "Recording reconnect status received; continuing offset verification",
        "接收覆盖和逐包解码通过；WAV 待归档，原始音频/Ogg 保留。不代表无线原音无损。": "Received data and packet decoding passed; WAV awaits archiving. Original audio and Ogg remain. Wireless source integrity is unverified.",
        "未能完成封装；原始字节和覆盖记录已保留": "Finalization failed; original bytes and receipt records retained",
        "已查询，等待眼镜状态": "Query sent; waiting for glasses status",
        "自定义天气数据已提交；不更改看板组件布局，等待回执": "Custom weather data submitted; dashboard layout unchanged. Waiting for receipt.",
        "设置已提交，等待眼镜回报；不提前改显示值": "Settings submitted; waiting for glasses report before updating displayed values",
        "眼镜通用设置已收到": "General glasses settings received",
        "已请求准备稿件，等待眼镜回应；本次不启用跟读/麦克风": "Script preparation requested; waiting for glasses response. Follow-along and microphone remain off.",
        "已请求原生跟读试验，等待眼镜回应；效果仍需真机验证": "Native follow trial requested; waiting for glasses response. Speech tracking still needs a hardware test.",
        "准备超时；未确认收稿，不会自动开始滚动。可点退出取消本轮。": "Preparation timed out; script receipt unconfirmed. Scrolling will not start automatically. Exit to cancel this turn.",
        "专用文件通道已提交，等待业务收稿确认；尚未开始播放": "File channel submitted; waiting for script receipt. Playback has not started.",
        "文件提交后收到业务成功回应，可测试开始；尚无独立文件校验/镜片证明": "Business success received after file submission; you can test start. File verification and glasses display remain unconfirmed.",
        "眼镜请求暂停": "Glasses requested pause",
        "眼镜请求恢复": "Glasses requested resume",
        "眼镜已请求退出": "Glasses requested exit",
        "仪表盘实时天气：待配置和风 Host / Key。": "Dashboard weather: configure your QWeather host and key.",
        "尚未发送仪表盘天气。": "Dashboard weather has not been sent yet.",
        "配置保存失败。": "Unable to save configuration.",
        "连接或配置已变化，旧回执不沿用。": "Connection or configuration changed. Previous acknowledgments are no longer used.",
        "8 秒内未观察到首页天气回执；未自动重发，不代表镜片一定未显示。": "No home weather acknowledgment observed within 8 seconds. Nothing was resent automatically; the glasses may still have displayed it.",
        "仪表盘自动天气已关闭。": "Automatic dashboard weather is off.",
        "等待眼镜认证连接，未查询或下发。": "Waiting for an authenticated glasses connection. Nothing has been fetched or sent.",
        "等待语音、录音或提词结束后更新仪表盘。": "Waiting for voice, recording, or teleprompter use to end before updating the dashboard.",
        "查询间隔保护，满 60 秒后再查询。": "Query interval limit: wait at least 60 seconds before fetching again.",
        "已获取天气，等待眼镜空闲。": "Weather fetched. Waiting for the glasses to become idle.",
        "天气请求或下发失败。": "Weather request or submission failed.",
        "已提交 current_weather_update，等待 type19 同命令回执。": "current_weather_update submitted. Waiting for a type 19 acknowledgment of the same command.",
        "SDK 发送失败，未确认眼镜接收。": "SDK send failed. Receipt by the glasses is unconfirmed.",
        "候选测试未发送：连接、数据时效或空闲状态不满足。": "Candidate test not sent: connection, data freshness, or idle requirements were not met.",
        "请输入有效的和风专属 Host（不带路径）、地点和两位小数经纬度。": "Enter a valid dedicated QWeather host without a path, a location, and coordinates with two decimal places.",
        "请保存该 Host 的和风 API Key；不会复用其他服务的密钥。": "Save the QWeather API key for this host. Keys from other services are not reused.",
        "和风响应字段、单位或归因信息不完整，未下发。": "QWeather response fields, units, or attribution are incomplete. Nothing was sent.",
        "天气获取时间已过期，需重新查询；未把响应时间当观测时间。": "The weather fetch has expired. Fetch again; response time is not treated as observation time.",
        "和风天气网络请求失败或超时，未下发；不自动降级或跟随重定向。": "QWeather request failed or timed out. Nothing was sent; no automatic downgrade or redirect following.",
        "尚未检查 Hermes 桥接": "Hermes bridge not checked yet",
        "尚未加载设备通信核心": "Glasses communication core not loaded yet",
        "尚未查询眼镜唤醒设置": "Glasses wake settings not queried yet",
        "尚未试写自定义唤醒词": "No custom wake word write test yet",
        "连接后可使用眼镜功能；未自动开始采音": "Glasses features are available after connecting. Audio capture has not started automatically.",
        "未启用眼镜录音接收": "Glasses recording reception is off",
        "尚未同步": "Not Synced Yet",
        "仅扫描本机，不访问眼镜。": "Scans this device only; does not access the glasses.",
        "尚未发送稿件": "No Script Sent Yet",
        "本机草稿；未读取或修改眼镜设置": "Local draft; glasses settings have not been read or changed",
        "共享通知状态未知": "Shared notification status unknown",
        "尚未发送；业务通知不经过 iOS 通知中心": "Not sent yet; business notifications do not pass through iOS Notification Center",
        "尚未连接电脑桥接": "Computer bridge not connected yet",
    ]
}
