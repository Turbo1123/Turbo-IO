import Foundation
import Combine
import RayNeoDisplay
import RayNeoProtocol
import UIKit

@MainActor final class CompanionDeviceFeatures: ObservableObject {
    @Published private(set) var status = "连接后可使用眼镜功能；未自动开始采音"
    @Published private(set) var recordingStatus = "未启用眼镜录音接收"
    @Published private(set) var recordingID: String?
    @Published private(set) var recordingBytes = 0
    @Published private(set) var acceptsEyeRecording = false
    @Published private(set) var todoStatus = "尚未同步"
    @Published private(set) var battery: Int?
    @Published private(set) var brightness: Int?
    @Published private(set) var settings: [String: Any] = [:]
    @Published private(set) var completedRecording: URL?
    @Published private(set) var recoveryEntries: [GlassesRecordingInbox.Entry] = []
    @Published private(set) var recoveryBusy = false
    @Published private(set) var recoveryStatus = "仅扫描本机，不访问眼镜。"
    @Published var error: String?
    let voice: CompanionVoiceRuntime
    private weak var store: CompanionStore?
    private let inbox: GlassesRecordingInbox
    private let io = DispatchQueue(label: "companion.recording.inbox", qos: .utility)
    private let writeSlots = DispatchSemaphore(value:64)
    private var failedRecordings = Set<String>()
    private var captureDevice: String?
    private var recordTimeRaw: Int64?
    private var finishing = Set<String>()
    private var finalizationInFlight = false
    private var pendingSettings: [String: Date] = [:]
    private var observers: [NSObjectProtocol] = []
    var canControl: Bool { voice.ready && !recoveryBusy && store?.alwaysOn.occupied != true && !["recording", "processing", "displaying"].contains(voice.phase) }
    init(voice: CompanionVoiceRuntime, store: CompanionStore, root: URL) {
        self.voice = voice; self.store = store; inbox = GlassesRecordingInbox(root: root)
        voice.onBusiness = { [weak self] in self?.receive(device: $0, business: $1, data: $2) }
        voice.onBusinessLoss = { [weak self] in self?.lostMessages(); self?.store?.alwaysOn.lostMessages() }
        // One automatic weather owner. Legacy Weatherstack stays manual to avoid overwrites.
        voice.onRuntimeRefresh = { [weak self] in self?.store?.qweather.tick() }
        voice.featureIsBusy = { [weak self] in self?.recordingID != nil || self?.teleprompterID != nil || self?.store?.alwaysOn.occupied == true }
        voice.onConnectionChange = { [weak self] device in
            guard let self else { return }
            self.store?.notifications.connectionChanged()
            self.store?.alwaysOn.connectionChanged()
            self.pendingSettings.removeAll(); self.settings = [:]; self.battery = nil; self.brightness = nil
            if self.recordingID != nil { self.recordingStatus = device == self.captureDevice ? "连接恢复；等待同一录音状态/数据，不自动宣布补传完成" : "连接中断；原始录音保留，等待同一眼镜恢复" }
            if self.teleprompterID != nil, device != self.teleprompterDevice {
                self.teleprompterPrepared = false
                self.teleprompterStatus = "提词连接中断；停止自动操作，请恢复连接后退出并重新准备"
            }
        }
        for (name, foreground) in [(UIApplication.didEnterBackgroundNotification,false),(UIApplication.didBecomeActiveNotification,true)] {
            observers.append(NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.recordingID != nil, self.voice.deviceID == self.captureDevice else { return }
                    self.perform { try self.send(14,14,["isAppForeground":foreground]) }
                }
            })
        }
    }
    deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }
    func prepare() { voice.prepare(); voice.refresh() }
    private func send(_ business: UInt8, _ type: UInt32, _ json: [String: Any]) throws {
        guard voice.deviceID != nil else { throw DeviceFeatureError.disconnected }
        try voice.sendBusiness(business, payload: DeviceBusinessWire.encode(type: type, json: json))
    }
    func perform(_ body: () throws -> Void) {
        do { try body(); error = nil } catch { self.error = (error as? LocalizedError)?.errorDescription ?? "操作失败；未确认眼镜完成。" }
    }
    func enableEyeRecording(_ enabled: Bool) {
        guard recordingID == nil else { error = "请先停止录音并等待文件接收结束。"; return }
        acceptsEyeRecording = enabled
        recordingStatus = enabled ? "已允许接收：请在眼镜开始录音；只保存在本机" : "未启用眼镜录音接收"
    }
    func startRecording() {
        perform {
            guard canControl, recordingID == nil, teleprompterID == nil, let device = voice.deviceID else { throw DeviceFeatureError.busy }
            // Voice standby is explicitly suspended so an unsolicited wake cannot steal the microphone.
            if voice.enabled { voice.stop() }
            acceptsEyeRecording = true
            let id = UUID().uuidString
            captureDevice = device; recordingID = id; recordingBytes = 0; completedRecording = nil; recordTimeRaw = nil
            recordingStatus = "准备本机接收目录"
            io.async { [weak self, inbox] in
                do {
                    try inbox.begin(device: device, id: id)
                    DispatchQueue.main.async {
                        guard let self, self.recordingID == id, self.voice.deviceID == device else { return }
                        self.perform {
                            try self.send(14,14,["isAppForeground": true])
                            try self.send(14,1,["uuid":id,"action":1,"code":1])
                            self.recordingStatus = "已请求开始，等待眼镜回应"
                        }
                    }
                } catch { DispatchQueue.main.async { self?.error = "接收目录创建失败，未请求眼镜录音。"; self?.recordingID = nil } }
            }
        }
    }
    func recordingControl(_ type: UInt32) {
        perform {
            guard let id = recordingID, voice.deviceID == captureDevice, [4,8,9,11].contains(type) else { throw DeviceFeatureError.noSession }
            var body: [String: Any] = ["uuid": id, "action": type == 11 ? 2 : 1, "code": type == 4 ? 2 : 1]
            // Preserve a reported raw time; never invent an epoch/elapsed-time conversion.
            if type == 9, let time = recordTimeRaw { body["time"] = time }
            try send(14,type,body)
            recordingStatus = type == 4 ? "已请求停止，仍等待尾部音频和完成消息" : "控制已提交，等待眼镜回应"
        }
    }
    func receive(device: String, business: UInt8, data: Data) {
        guard voice.deviceID == device else { return }
        if business == 13 || business == 15 { store?.alwaysOn.receive(device: device, business: business, packet: data) }
        do {
            let wire = try DeviceBusinessWire(data)
            switch business {
            case 14: try recording(device,wire)
            case 22: try todo(device,wire)
            case 15:
                store?.qweather.receive(device:device,wire:wire)
                launcher(wire)
            case 20: try teleprompterReceive(device,wire)
            case 21: store?.notifications.receive(device: device, wire: wire)
            default: break
            }
        } catch {
            self.error = "收到未识别或不匹配的业务数据，未当成成功。"
            if business == 14 { lostMessages() }
        }
    }
    private func recording(_ device: String, _ wire: DeviceBusinessWire) throws {
        let j = wire.json, type = wire.type
        if type == 12 { recordingStatus = "收到同步列表；本版不自动导入或清理离线积压"; return }
        guard let id = DeviceBusinessWire.identifier(j,"uuid") else { return }
        if type == 3, finishing.contains(id), recordingID != id, captureDevice == device {
            error = "已封装录音仍收到迟到数据；请保留副本并复核，不能承诺完整。"
            io.async { [inbox] in inbox.invalidate(device:device,id:id) }
            return
        }
        let action = DeviceBusinessWire.integer(j,"action"), code = DeviceBusinessWire.integer(j,"code")
        if type == 1, action == 1 {
            guard acceptsEyeRecording, teleprompterID == nil, recordingID == nil || (recordingID == id && captureDevice == device), canControl else { return }
            if voice.enabled { voice.stop() }
            recordingID = id; captureDevice = device; recordingBytes = 0; completedRecording = nil
            io.async { [weak self, inbox] in
                do {
                    try inbox.begin(device: device,id: id)
                    DispatchQueue.main.async {
                        guard let self, self.recordingID == id, self.voice.deviceID == device else { return }
                        self.perform { try self.send(14,1,["uuid":id,"action":2,"code":1]); self.recordingStatus = "已接受眼镜录音，等待数据" }
                    }
                } catch { DispatchQueue.main.async { self?.error = "无法准备眼镜录音的本机存储。" } }
            }
            return
        }
        guard recordingID == id, captureDevice == device else { return }
        if let time = DeviceBusinessWire.integer(j,"time") { recordTimeRaw = time }
        if type == 1, action == 2 {
            if code == 1 { recordingStatus = "眼镜已确认开始录音" }
            else { recordingStatus = "眼镜拒绝开始，code=\(code ?? -1)；未自动绕过隐私/冲突"; recordingID = nil }
        } else if type == 3 {
            guard let offset = DeviceBusinessWire.integer(j,"offset"), offset >= 0,
                  offset <= GlassesRecordingInbox.limit, !wire.bytes.isEmpty else { throw DeviceFeatureError.invalidPacket }
            guard writeSlots.wait(timeout:.now()) == .success else { lostMessages(); return }
            io.async { [weak self, inbox, writeSlots] in
                defer { writeSlots.signal() }
                do { let count = try inbox.append(device:device,id:id,offset:Int(offset),data:wire.bytes)
                    DispatchQueue.main.async { self?.recordingBytes = count; self?.recordingStatus = "正在接收并保存原始音频" }
                } catch { inbox.invalidate(device:device,id:id); DispatchQueue.main.async { self?.error = "音频写入或完整性检查失败；原件保留，不能标完整。" } }
            }
        } else if type == 6, DeviceBusinessWire.boolean(j,"completed") == true, !finishing.contains(id) {
            // Persist the observed completion before queued finalization, so a restart cannot invent or lose it.
            io.async { [inbox] in
                do { try inbox.recordCompletion(device:device,id:id) }
                catch { inbox.invalidate(device:device,id:id) }
            }
            finishing.insert(id); recordingStatus = "眼镜已报告完成，核对接收覆盖并封装"
            // Small grace for callbacks delivered after completion. Late data is never silently merged into a published file.
            DispatchQueue.main.asyncAfter(deadline: .now()+1) { [weak self] in self?.finishRecording(device:device,id:id) }
        } else if type == 4 {
            if action == 1 { try send(14,4,["uuid":id,"action":2,"code":code ?? 1]) }
            recordingStatus = "停止事件已收到，等待音频完成"
        } else if type == 11 {
            if action == 1 { try send(14,11,["uuid":id,"action":2,"code":1]) }
            let time = DeviceBusinessWire.integer(j,"time") ?? 0
            io.async { [inbox] in try? inbox.mark(device:device,id:id,time:time) }
        } else if type == 8 || type == 9 {
            if action == 1 { try send(14,type,["uuid":id,"action":2,"code":1]) }
            recordingStatus = code == 1 ? (type == 8 ? "眼镜已暂停" : "眼镜已恢复") : "控制回应 code=\(code ?? -1)"
        } else if type == 5 { recordingStatus = "收到同一录音重连状态；继续按 offset 校验" }
    }
    private func finishRecording(device: String, id: String) {
        guard !finalizationInFlight else { return }
        finalizationInFlight = true
        io.async { [weak self, inbox] in
            do {
                _ = try inbox.finish(device:device,id:id)
                let output = try inbox.decodedDerivative(device:device,id:id)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.finalizationInFlight = false
                    self.completedRecording = output; self.recordingID = nil
                    self.recordingStatus = "接收覆盖和逐包解码通过；WAV 待归档，原始音频/Ogg 保留。不代表无线原音无损。"
                    // Archive copy + checksum, not ASR or upload. Ogg structure is not proof of acoustic completeness.
                    Task { await self.archiveReceivedRecording() }
                }
            } catch {
                DispatchQueue.main.async { self?.finalizationInFlight = false; self?.recordingStatus = "未能完成封装；原始字节和覆盖记录已保留"; self?.error = "录音未通过完整性检查，不标为完整音频。" }
            }
        }
    }
    private func lostMessages() {
        store?.notifications.lostMessages()
        if let id = recordingID, let device = captureDevice, failedRecordings.insert(id).inserted { io.async { [inbox] in inbox.invalidate(device:device,id:id) } }
        error = "业务接收队列溢出或录音格式不匹配；本次录音不可标完整。"
    }
    func archiveReceivedRecording() async {
        guard let file = completedRecording, let store else { return }
        let imported = await store.archive.importFile(file,title:"眼镜录音 " + Date().formatted(date:.abbreviated,time:.shortened))
        recordingStatus = imported ? "WAV 已校验归档；原始音频/Ogg 保留，未转写或上传" : "WAV 已保存，但归档未成功；可重试归档或分享文件"
    }
    func retryRecordingFinish() {
        guard let id = recordingID, let device = captureDevice, finishing.contains(id) else { error = "尚未收到眼镜完成消息，不能强行当作完成。"; return }
        finishRecording(device:device,id:id)
    }
    func loadRecoveryEntries() async {
        guard !recoveryBusy, recordingID == nil, !finalizationInFlight else { recoveryStatus = "当前有接收任务，请结束后再扫描。"; return }
        recoveryBusy = true; defer { recoveryBusy = false }
        do {
            let catalog: GlassesRecordingInbox.Catalog = try await withCheckedThrowingContinuation { continuation in
                io.async { [inbox] in continuation.resume(with:Result { try inbox.catalog() }) }
            }
            recoveryEntries = catalog.entries
            recoveryStatus = "本机 \(catalog.entries.count) 条；\(catalog.unreadable) 个无法读取的目录保留原位。扫描不等于完整性通过。"
        } catch { recoveryStatus = "本机接收目录无法读取；未清空、重建或删除。" }
    }
    func recoverRecording(_ entryID: String) async {
        guard !recoveryBusy, recordingID == nil, !finalizationInFlight else { return }
        recoveryBusy = true; defer { recoveryBusy = false }
        do {
            let file: URL = try await withCheckedThrowingContinuation { continuation in
                io.async { [inbox] in continuation.resume(with:Result { try inbox.recoverDecoded(entryID) }) }
            }
            guard let store else { return }
            let imported = await store.archive.importFile(file,title:"恢复的眼镜录音")
            recoveryStatus = imported ? "已重新核对、解码并归档；未转写、上传或删除原件。" : "WAV 已恢复，归档暂未成功；原始文件保留，可重试。"
        } catch { recoveryStatus = "未通过恢复校验或本构建不支持解码；原件保留，不能标完整。" }
    }
    func recoveryRawFile(_ entryID: String) async -> URL? {
        guard !recoveryBusy, recordingID == nil, !finalizationInFlight else { return nil }
        recoveryBusy = true; defer { recoveryBusy = false }
        do {
            let url: URL = try await withCheckedThrowingContinuation { continuation in
                io.async { [inbox] in continuation.resume(with:Result { try inbox.exportRawCopy(entryID) }) }
            }
            return url
        } catch { recoveryStatus = "原始文件不可读取，未生成分享入口。"; return nil }
    }
    func syncTodos(pendingOnly: Bool = false) {
        perform {
            guard canControl, let device = voice.deviceID, let store else { throw DeviceFeatureError.disconnected }
            let rows = try store.todoCandidates(device: device, pendingOnly: pendingOnly)
            guard rows.count <= 100 else { throw DeviceFeatureError.storageLimit }
            for row in rows { try sendTodo(row, device:device) }
            todoStatus = "已提交 \(rows.count) 条待办；等待眼镜状态/操作回执，不代表镜片已显示"
        }
    }
    func localTodoChanged(_ row: LocalTodo) {
        guard canControl, row.archivedAt == nil, row.wireDeviceID == voice.deviceID,
              row.wireID != nil, row.delivery?.conflict == nil else { return }
        perform { guard let device = voice.deviceID else { throw DeviceFeatureError.disconnected }; try sendTodo(row,device:device) }
    }
    private func sendTodo(_ row: LocalTodo, device: String) throws {
        guard let store else { throw DeviceFeatureError.noSession }
        let current = try store.prepareTodoSubmission(row.id, device: device)
        guard let id = current.wireID, let revision = current.delivery?.revision else { throw TodoDeliveryError.missing }
        let seconds = Int64(Date().timeIntervalSince1970)
        let body: [String:Any] = ["eventType":1,"eventID":id,"createTime":Int64(current.createdAt.timeIntervalSince1970),
            "title":current.title,"isImportant":current.important ?? false,"status":current.completed ? 1 : 0,"lastModifiedTime":seconds]
        try send(22,2,body)
        store.markTodoSubmitted(row.id, device: device, revision: revision)
    }
    private func todo(_ device: String, _ wire: DeviceBusinessWire) throws {
        if wire.type == 14 { todoStatus = "眼镜操作回执：成功 \(DeviceBusinessWire.integer(wire.json,"successCount") ?? 0)；不作为逐项镜片验收"; return }
        guard wire.type == 4 || wire.type == 10 else { return }
        let data = try JSONSerialization.data(withJSONObject:wire.json)
        let message = try TodoJSONCodec().decodeGlassesMessage(type:UInt16(wire.type),payload:data)
        var changes = 0
        switch message {
        case .status(let s): changes += store?.applyGlassesTodo(device:device,id:s.eventID,status:s.statusRaw,important:s.isImportant.value) == true ? 1 : 0
        case .batch(let b):
            for entry in b.eventList.value ?? [] { if case .todo(let s) = entry { changes += store?.applyGlassesTodo(device:device,id:s.eventID,status:s.statusRaw,important:s.isImportant.value) == true ? 1 : 0 } }
        default: break
        }
        todoStatus = "眼镜状态已应用 \(changes) 项；离线修改冲突请查看待发送列表，未知 ID 不导入"
    }
    func refreshSettings() {
        perform {
            try voice.sendBusiness(15,payload:LauncherControlPrototype.encode(.requestGeneralStatus))
            try send(15,4,["cmd":"request_general_settings","payload":["value":0,"mode":0,"data":""]])
            status = "已查询，等待眼镜状态"
        }
    }
    func setBrightness(_ value: Int) { command(type:2,cmd:"brightness_change",value:value,allowed:7...8) }
    func setHeadControl(_ enabled: Bool, mode: Int) {
        guard [0,1].contains(mode) else { return }; command(type:5,cmd:"head_gestures",value:enabled ? 1:0,mode:mode)
    }
    func setSleep(_ seconds: Int) { guard [15,25].contains(seconds) else { return }; command(type:5,cmd:"auto_lock_time",value:seconds) }
    func setDoubleTapTodo(_ todo: Bool) {
        guard let crown = settings["crownConfig"] as? [String:Any] ?? settings["crown_config"] as? [String:Any],
              let long = DeviceBusinessWire.integer(crown,"longPress") else { error = "请先读取完整旋钮设置，避免覆盖原长按配置。"; return }
        perform { let body = try JSONSerialization.data(withJSONObject:["double":todo ? 8:0,"longPress":long]); try submitCommand(type:5,cmd:"crown_config",value:0,mode:0,data:String(decoding:body,as:UTF8.self)) }
    }
    func setDisplay(height: Int? = nil, distance: Int? = nil) {
        guard let config = settings["displayConfig"] as? [String:Any] ?? settings["display_config"] as? [String:Any],
              let oldHeight = DeviceBusinessWire.integer(config,"height"), let oldDistance = DeviceBusinessWire.integer(config,"distance"),
              height == nil || [1,3,5].contains(height!), distance == nil || [1,2].contains(distance!) else {
            error = "请先读取显示配置；只支持已有证据的档位，未覆盖其他参数。"; return
        }
        perform {
            let data = try JSONSerialization.data(withJSONObject:["height":height.map(Int64.init) ?? oldHeight,"distance":distance.map(Int64.init) ?? oldDistance])
            try submitCommand(type:5,cmd:"display_config",value:0,mode:0,data:String(decoding:data,as:UTF8.self))
        }
    }
    func sendWeatherstack(_ snapshot: WeatherstackSnapshot, icon: Int) {
        perform { try submitWeatherstack(snapshot, icon: icon) }
    }
    func submitWeatherstack(_ snapshot: WeatherstackSnapshot, icon: Int) throws {
        guard snapshot.canSend(at:Date()) else { throw WeatherstackError.stale }
        guard (0...999).contains(icon) else { throw WeatherstackError.icon }
        try submitWeather(location:snapshot.city,temperature:snapshot.lensTemperature,icon:icon,description:snapshot.description)
    }
    func sendWeather(location: String, temperature: Int, icon: Int, description: String, current: Bool = true) {
        perform { try submitWeather(location:location,temperature:temperature,icon:icon,description:description,current:current) }
    }
    private func submitWeather(location: String, temperature: Int, icon: Int, description: String, current: Bool = true) throws {
            guard canControl, !location.isEmpty, location.utf8.count <= 80, (-80...60).contains(temperature), (0...999).contains(icon) else { throw DeviceFeatureError.invalidPacket }
            let update = SelectedCityWeatherRawUpdate(items:[CityWeatherRawItem(location:location,locationID:"companion-custom",temperatureRaw:Int64(temperature),iconRaw:Int64(icon),descriptionRaw:description,temperatureRangeRaw:"",hourly:[])],timestampRaw:String(Int64(Date().timeIntervalSince1970)))
            let msg = try current ? WeatherJSONCodec().encodeCurrentWeatherUpdate(CurrentWeatherRawUpdate(location:location,temperatureRaw:Int64(temperature),iconRaw:Int64(icon),timestampRaw:update.timestampRaw)) : CityWeatherJSONCodec().encodeUpdate(update)
            try voice.sendBusiness(15,payload:DeviceBusinessWire.encode(type:UInt32(msg.type),json:JSONSerialization.jsonObject(with:msg.payload) as! [String:Any]))
            pendingSettings[current ? "current_weather_update" : "weather_update"] = Date(); status = "自定义天气数据已提交；不更改看板组件布局，等待回执"
    }
    private func command(type: UInt32, cmd: String, value: Int, mode: Int = 0, allowed: ClosedRange<Int>? = nil) {
        perform { if let allowed, !allowed.contains(value) { throw DeviceFeatureError.invalidPacket }; try submitCommand(type:type,cmd:cmd,value:value,mode:mode,data:"") }
    }
    private func submitCommand(type: UInt32, cmd: String, value: Int, mode: Int, data: String) throws {
        guard canControl else { throw DeviceFeatureError.busy }
        if let since = pendingSettings[cmd], Date().timeIntervalSince(since) < 8 { throw DeviceFeatureError.busy }
        try send(15,type,["cmd":cmd,"payload":["value":value,"mode":mode,"data":data]])
        pendingSettings[cmd] = Date(); status = "设置已提交，等待眼镜回报；不提前改显示值"
    }
    private func launcher(_ wire: DeviceBusinessWire) {
        let j = wire.json
        if wire.type == 1 {
            let state = j["generalStatus"] as? [String:Any] ?? j
            if let n = DeviceBusinessWire.integer(state,"battery") { battery = Int(n) }
            if let n = DeviceBusinessWire.integer(state,"brightness") { brightness = Int(n) }
        }
        if wire.type == 4 { settings = j["generalSettings"] as? [String:Any] ?? j; status = "眼镜通用设置已收到" }
        guard let cmd = j["cmd"] as? String, let p = j["payload"] as? [String:Any] else { return }
        if wire.type == 3, cmd == "brightness_change", let n = DeviceBusinessWire.integer(p,"value") { brightness = Int(n) }
        if [3,6,17,19].contains(wire.type) {
            if wire.type == 6, let body = p["data"] as? String, let bytes = body.data(using:.utf8),
               let config = try? JSONSerialization.jsonObject(with:bytes) as? [String:Any],
               let key = ["display_config":"displayConfig","crown_config":"crownConfig","privacy_config":"privacyConfig"][cmd] {
                settings[key] = config
            }
            pendingSettings.removeValue(forKey:cmd)
            status = "眼镜回报 \(cmd.prefix(45))：\(DeviceBusinessWire.integer(p,"value") ?? -1)（未验证镜片效果）"
        }
    }

    // Teleprompter state/transport is implemented in the dedicated extension below.
    @Published private(set) var teleprompterStatus = "尚未发送稿件"
    @Published private(set) var teleprompterID: String?
    @Published private(set) var teleprompterOffset: Int64 = 0
    var teleprompterFile: URL?
    var teleprompterDevice: String?
    var teleprompterPrepared = false
    var teleprompterSentFile = false
    var teleprompterTransferTask: String?
}

extension CompanionDeviceFeatures {
    func prepareTeleprompter(_ text: String, speed: Int) {
        perform {
            guard canControl, recordingID == nil, teleprompterID == nil, let device = voice.deviceID else { throw DeviceFeatureError.busy }
            guard !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, text.count <= 12_000,
                  text.utf8.count <= 48_000, (60...240).contains(speed) else { throw DeviceFeatureError.invalidPacket }
            if voice.enabled { voice.stop() }
            let did = UUID().uuidString
            let dir = inbox.root.deletingLastPathComponent().appendingPathComponent("TeleprompterOutboxV1")
            try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
            guard try FileManager.default.contentsOfDirectory(atPath:dir.path).count < 100 else { throw DeviceFeatureError.storageLimit }
            let url = dir.appendingPathComponent(did + ".txt")
            try Data(text.utf8).write(to:url,options:[.withoutOverwriting,.completeFileProtectionUntilFirstUserAuthentication])
            teleprompterID = did; teleprompterDevice = device; teleprompterFile = url
            teleprompterOffset = 0; teleprompterPrepared = false; teleprompterSentFile = false
            // Optional layout fields intentionally omitted: never guess pixel/gear defaults.
            try send(20,2,["action":1,"did":did,"total":text.utf8.count,"scroll":2,"speed":speed,"pageOffset":0,"highLightOffset":0])
            teleprompterStatus = "已请求准备稿件，等待眼镜回应；本次不启用跟读/麦克风"
            DispatchQueue.main.asyncAfter(deadline:.now()+30) { [weak self] in
                guard let self, self.teleprompterID == did, !self.teleprompterPrepared else { return }
                self.teleprompterStatus = "准备超时；未确认收稿，不会自动开始滚动。可点退出取消本轮。"
            }
        }
    }
    func teleprompterControl(_ type: UInt32, speed: Int = 120) {
        perform {
            guard let did = teleprompterID, teleprompterDevice == voice.deviceID,
                  type == 6 || teleprompterPrepared else { throw DeviceFeatureError.noSession }
            guard [3,4,5,6,7].contains(type) else { throw DeviceFeatureError.invalidPacket }
            var body: [String:Any] = ["action":1,"did":did]
            if type == 4 { body["offset"] = teleprompterOffset; body["code"] = 1; body["isCompleted"] = false }
            if type == 7 { guard (60...240).contains(speed) else { throw DeviceFeatureError.invalidPacket }; body["scroll"] = 2; body["speed"] = speed }
            try send(20,type,body)
            if type == 6, let task = teleprompterTransferTask { voice.cancelFile(task); teleprompterTransferTask = nil }
            teleprompterStatus = "控制 type\(type) 已提交，等待眼镜回应"
        }
    }
    private func teleprompterReceive(_ device: String, _ wire: DeviceBusinessWire) throws {
        guard let did = DeviceBusinessWire.identifier(wire.json,"did"), did == teleprompterID, teleprompterDevice == device else { return }
        let action = DeviceBusinessWire.integer(wire.json,"action"), code = DeviceBusinessWire.integer(wire.json,"code")
        if wire.type == 2, action == 2 {
            guard code == 1 || code == 7 else { teleprompterStatus = "准备被拒绝 code=\(code ?? -1)，未自动处理冲突"; return }
            if !teleprompterSentFile {
                guard let file = teleprompterFile else { throw DeviceFeatureError.noSession }
                teleprompterTransferTask = try voice.sendFile(file,id:did)
                teleprompterSentFile = true
                teleprompterStatus = "专用文件通道已提交，等待业务收稿确认；尚未开始播放"
            } else { teleprompterPrepared = true; teleprompterStatus = "文件提交后收到业务成功回应，可测试开始；尚无独立文件校验/镜片证明" }
            return
        }
        if wire.type == 3, action == 2 { teleprompterStatus = "开始提词回应 code=\(code ?? -1)"; return }
        guard let control = TeleprompterControlType(rawValue: UInt16(clamping:wire.type)) else { return }
        let data = try JSONSerialization.data(withJSONObject:wire.json)
        if action == 1 {
            let event = try TeleprompterJSONCodec().decodeGlassesRequest(type:control.rawValue,payload:data)
            switch event {
            case .progress(let p): teleprompterOffset = p.pageOffset; teleprompterStatus = "眼镜进度回传：UTF-8 原始偏移 \(p.pageOffset)"
            case .pause: teleprompterStatus = "眼镜请求暂停"
            case .resume: teleprompterStatus = "眼镜请求恢复"
            case .stop: teleprompterStatus = "眼镜已请求退出"
            default: return
            }
            let ack = try TeleprompterJSONCodec().encodeAppResponse(type:control,did:did,code:.accepted)
            try voice.sendBusiness(20,payload:DeviceBusinessWire.encode(type:UInt32(ack.type),json:JSONSerialization.jsonObject(with:ack.payload) as! [String:Any]))
        } else if action == 2 { teleprompterStatus = "眼镜回应 type\(wire.type) code=\(code ?? -1)" }
        if control == .stop, action == 1 || code == 1 {
            if let task = teleprompterTransferTask { voice.cancelFile(task); teleprompterTransferTask = nil }
            teleprompterID = nil; teleprompterPrepared = false; teleprompterFile = nil
        }
    }
}
