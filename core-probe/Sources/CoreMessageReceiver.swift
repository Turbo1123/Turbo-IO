import Foundation
import RayneoNet
import RayNeoProtocol

extension CoreHandle {
    @_silgen_name("$s9RayneoNet13RNCoreConnectC3add15messageDelegateyAA09RNMessageG0_p_tF")
    func addMessageDelegate(_ delegate: any RNMessageDelegate)
    @_silgen_name("$s9RayneoNet13RNCoreConnectC6remove15messageDelegateyAA09RNMessageG0_p_tF")
    func removeMessageDelegate(_ delegate: any RNMessageDelegate)
    @_silgen_name("$s9RayneoNet13RNCoreConnectC4send7messageyAA9RNMessageC_tKF")
    func sendMessage(_ message: MessageHandle) throws
}

/// Own App's native callback. No hook, copying official state, raw memory reads,
/// disk audio storage. Native RNMessage getters return the owned payload.
final class CoreMessageReceiver: RNMessageDelegate {
    var onMetadata: ((String) -> Void)?
    var onVoiceEnvelope: ((String, BusinessEnvelopeMetadata, Data?, TimeInterval) -> Void)?
    var onBusinessEnvelope: ((String, UInt8, Data) -> Void)?
    var onBusinessLoss: (() -> Void)?
    private let businessSlots = DispatchSemaphore(value: 128)
    private var businessLossQueued = false
    private func reportBusinessLoss() {
        lock.lock()
        guard !businessLossQueued else { lock.unlock(); return }
        businessLossQueued = true; lock.unlock()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock(); self.businessLossQueued = false; self.lock.unlock()
            self.onBusinessLoss?()
        }
    }
    private let audioSlots = DispatchSemaphore(value:32)
    private let lock = NSLock()
    private var counts: [String:Int] = [:]
    private func emit(_ text: String) {
        DispatchQueue.main.async { [weak self] in self?.onMetadata?(text) }
    }
    func message(_ core: RNCoreConnect, receive: RNMessage) {
        let handle = unsafeBitCast(receive, to:MessageHandle.self)
        let business = handle.businessIndex(), payload = handle.payload() ?? Data()
        let metadata = [13,15,21].contains(business) ? try? BusinessEnvelopeMetadata.inspect(payload) : nil
        let alwaysOn = business == 13 && metadata?.messageType.map { (161...168).contains($0) } == true
        if ([14,15,20,21,22].contains(business) || alwaysOn), onBusinessEnvelope != nil {
            if payload.count <= 131_100, businessSlots.wait(timeout: .now()) == .success {
                let id = handle.deviceID(), slots = businessSlots
                DispatchQueue.main.async { [weak self] in
                    defer { slots.signal() }
                    self?.onBusinessEnvelope?(id, business, payload)
                }
            } else { reportBusinessLoss() }
        }
        if business == 13, !alwaysOn, let metadata {
            let deviceID = handle.deviceID()
            let isAudio = metadata.messageType == 3
            // Bound retained audio even if the UI queue stalls. Never log bytes.
            if !isAudio || audioSlots.wait(timeout:.now()) == .success {
                let audio = isAudio ? try? BusinessEnvelopeMetadata.assistantAudio(payload) : nil
                let arrival = ProcessInfo.processInfo.systemUptime
                let slots = audioSlots
                DispatchQueue.main.async { [weak self] in
                    defer { if isAudio { slots.signal() } }
                    self?.onVoiceEnvelope?(deviceID, metadata, audio, arrival)
                }
            }
        }
        let key = "business=\(business) type=\(metadata?.messageType.map(String.init) ?? "unknown") bytes=\(payload.count)"
        lock.lock()
        if counts[key] == nil && counts.count >= 256 { lock.unlock(); return }
        let count = (counts[key] ?? 0) + 1; counts[key] = count
        lock.unlock()
        if count <= 3 || count % 50 == 0 || (business == 13 && ![3,163,164].contains(metadata?.messageType ?? 0)) {
            emit("眼镜→本 App \(key) audioBytes=\(metadata?.dataBytes.map(String.init) ?? "none") count=\(count)")
            if business == 15 && (count == 1 || metadata?.messageType == 17) {
                emit("Launcher结构 \(LauncherStructure.inspect(payload))")
            }
            if business == 13, let type = metadata?.messageType, [8,48].contains(type) {
                emit("助手退出/离线状态 type=\(type) \(LauncherStructure.inspect(payload))")
            }
        }
    }
    func message(_ core: RNCoreConnect, deviceListChanged: [RNDevice], _ reason: String) {
        emit("消息接口设备变更 count=\(deviceListChanged.count)")
    }
    func message(_ core: RNCoreConnect, sendSuccess: RNMessage) {
        emit("SDK sendSuccess 回调（不等于眼镜实际显示）")
    }
    func message(_ core: RNCoreConnect, sendError: RNMessage, _ code: Int, _ reason: String) {
        emit("SDK sendError code=\(code)（不记录原始错误正文）")
    }
    func messageDecryptFail(_ core: RNCoreConnect, device: RNDevice, sourceData: Data, sourceLen: Int, destLen: Int) {
        emit("SDK 解密失败 sourceLen=\(sourceLen) destLen=\(destLen)")
    }
}
