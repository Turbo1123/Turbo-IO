import Combine
import Foundation
import HealthKit
import WatchConnectivity

struct LiveWorkoutMetric {
    let value: Double
    let date: Date
    func fresh(at now: Date) -> Bool { (0...15).contains(now.timeIntervalSince(date)) }
}

enum WorkoutDisplayMode: String, CaseIterable, Identifiable {
    case outdoorRun, indoorRun, heartRate
    var id: String { rawValue }
    var title: String { switch self { case .outdoorRun: return "室外跑步"; case .indoorRun: return "室内跑步"; case .heartRate: return "仅心率" } }
}

/// User-started outdoor run. HealthKit owns collection and saves the completed workout.
final class HeartRateModel: NSObject, ObservableObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate, WCSessionDelegate {
    @Published var mode: WorkoutDisplayMode = .outdoorRun
    @Published private(set) var heart: LiveWorkoutMetric?
    @Published private(set) var pace: LiveWorkoutMetric?
    @Published private(set) var cadence: LiveWorkoutMetric?
    @Published private(set) var stride: LiveWorkoutMetric?
    @Published private(set) var distance: LiveWorkoutMetric?
    @Published private(set) var energy: LiveWorkoutMetric?
    @Published private(set) var saveFailed = false
    @Published private(set) var saved = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var isRunning = false
    @Published private(set) var isPaused = false
    @Published private(set) var isBusy = false
    @Published private(set) var note = "打开手机 Turbo IO 运动看板，再开始采集"
    @Published private(set) var zoneState = "loading"
    @Published private(set) var zoneLabel = "—"
    @Published private(set) var zoneCount = 0
    @Published private(set) var zonePosition: Int?
    private var zoneConfiguration: [String: Any]?
    private var zoneIndex: Int?
    private var zoneDate: Date?

    private let store = HKHealthStore()
    private var cadenceWindow = WorkoutCadenceWindow()
    private var collectionEnded = false
    private var saveInProgress = false
    private var endDate: Date?
    private let heartType = HKQuantityType(.heartRate)
    private let speedType = HKQuantityType(.runningSpeed)
    private let strideType = HKQuantityType(.runningStrideLength)
    private let distanceType = HKQuantityType(.distanceWalkingRunning)
    private let stepsType = HKQuantityType(.stepCount)
    private let energyType = HKQuantityType(.activeEnergyBurned)
    private var workout: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var runID = ""
    private var timer: Timer?
    private var startedAt = Date.distantPast
    private var lastContact = Date.distantPast
    private var lastSentAt = Date.distantPast
    private var pendingMessage = false
    private var pendingSince = Date.distantPast
    private var startupID = UUID()
    private var pendingStartAt: Date?
    private var messageID = UUID()
    private var sequence = 0

    init(ownsConnectivity: Bool = true) {
        super.init()
        if ownsConnectivity, WCSession.isSupported() { WCSession.default.delegate = self; WCSession.default.activate() }
        // Old phone-entered zoneStarts are deliberately not loaded or applied.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.pump() }
    }

    var zoneNote: String {
        switch zoneState {
        case "ready": return "区间来自 HealthKit"
        case "unsupported": return "读取系统区间需 watchOS 27"
        case "error": return "系统区间读取失败"
        case "unavailable": return "HealthKit 暂无区间"
        default: return "正在读取系统区间"
        }
    }

    func start() {
        guard !isRunning, !isBusy, builder == nil else { return }
        mode = .outdoorRun; saved = false; saveFailed = false
        #if targetEnvironment(simulator)
        note = "模拟器不提供真实运动数据，请安装到 Apple Watch"; return
        #else
        guard HKHealthStore.isHealthDataAvailable() else { note = "此设备不能读取健康数据"; return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { note = "手机未连接，请打开 Turbo IO 运动看板"; return }
        isBusy = true; note = "正在连接手机"
        let attempt = UUID(); startupID = attempt
        runID = UUID().uuidString; pendingStartAt = Date()
        session.sendMessage(["version": 1, "kind": "start", "runID": runID, "requestedAt": Date().timeIntervalSince1970], replyHandler: { [weak self] answer in
            DispatchQueue.main.async {
                guard let self, self.startupID == attempt else { return }
                self.pendingStartAt = nil
                guard answer["displayOpen"] as? Bool == true, answer["captureAllowed"] as? Bool == true else { self.isBusy = false; self.note = "请打开手机 Turbo IO 运动看板"; return }
                self.authorizeAndStart(attempt: attempt)
            }
        }, errorHandler: { [weak self] _ in
            DispatchQueue.main.async { guard let self, self.startupID == attempt else { return }; self.pendingStartAt = nil; self.isBusy = false; self.note = "手机连接失败，请重试" }
        })
        #endif
    }

    private func authorizeAndStart(attempt: UUID) {
        note = "请允许读取本次运动所需的健康数据"
        let types: Set<HKObjectType> = [heartType, HKObjectType.workoutType(), speedType, strideType, distanceType, stepsType, energyType]
        store.requestAuthorization(toShare: [HKObjectType.workoutType(), heartType, speedType, strideType, distanceType, stepsType, energyType], read: types) { [weak self] completed, _ in
            Task { @MainActor [weak self] in
                guard let self, self.startupID == attempt else { return }
                guard completed else { self.isBusy = false; self.note = "健康授权未完成，请重试"; return }
                guard self.store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else {
                    self.isBusy = false; self.note = "需要允许运动会话才能连续采集"; return
                }
                self.zoneConfiguration = nil; self.zoneIndex = nil; self.zoneDate = nil; self.zoneLabel = "—"; self.zoneCount = 0; self.zonePosition = nil
                if #available(watchOS 27.0, *) {
                    do {
                        let config = try await self.store.preferredWorkoutZoneConfiguration(for: self.heartType)
                        guard self.startupID == attempt else { return }
                        if let config { self.applyZoneConfiguration(config) } else { self.zoneState = "unavailable" }
                    } catch { guard self.startupID == attempt else { return }; self.zoneState = "error" }
                } else { self.zoneState = "unsupported" }
                guard self.startupID == attempt else { return }
                self.beginWorkout()
            }
        }
    }

    @available(watchOS 27.0, *)
    private func applyZoneConfiguration(_ config: HKWorkoutZoneConfiguration) {
        guard config.quantityType == heartType else { return }
        let unit = HKUnit.count().unitDivided(by: .minute())
        let zones: [[String: Any]] = config.zones.map { zone in
            var item: [String: Any] = ["index": zone.index]
            if let minimum = zone.minimum { item["minimum"] = minimum.doubleValue(for: unit) }
            if let maximum = zone.maximum { item["maximum"] = maximum.doubleValue(for: unit) }
            return item
        }
        let source: String
        switch config.source { case .system: source = "system"; case .user: source = "user"; case .app: source = "app"; @unknown default: zoneState = "unavailable"; return }
        zoneConfiguration = ["source": "healthkit", "configurationSource": source, "zones": zones]
        zoneCount = zones.count; zoneState = zones.isEmpty ? "unavailable" : "ready"
    }

    private func beginWorkout() {
        do {
            let config = HKWorkoutConfiguration()
            config.activityType = .running
            config.locationType = .outdoor
            let workout = try HKWorkoutSession(healthStore: store, configuration: config)
            let builder = workout.associatedWorkoutBuilder()
            workout.delegate = self; builder.delegate = self
            let dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            for type in [heartType, speedType, strideType, distanceType, stepsType, energyType] { dataSource.enableCollection(for: type, predicate: nil) }
            builder.dataSource = dataSource
            self.workout = workout; self.builder = builder
            startedAt = Date(); lastContact = startedAt; lastSentAt = .distantPast
            sequence = 0; pendingMessage = false; clearMetrics(); elapsed = 0
            cadenceWindow.reset(); collectionEnded = false; saveInProgress = false; endDate = nil
            isPaused = false; isRunning = true; isBusy = false
            note = "正在采集，等待新的运动数据"
            workout.startActivity(with: startedAt)
            builder.beginCollection(withStart: startedAt) { [weak self] success, _ in
                DispatchQueue.main.async {
                    guard let self, self.workout === workout else { return }
                    if !success { builder.discardWorkout(); workout.end(); self.builder = nil; self.workout = nil; self.isRunning = false; self.isBusy = false; self.note = "采集未启动，请检查健康授权" }
                }
            }
        } catch { isBusy = false; note = "无法开启采集，请结束其他体能训练后重试" }
    }

    private func clearMetrics() { heart = nil; pace = nil; cadence = nil; stride = nil; distance = nil; energy = nil }

    func pauseOrResume() {
        guard let workout, isRunning, !isBusy else { return }
        isPaused ? workout.resume() : workout.pause()
    }

    func stop(reason: String) {
        startupID = UUID(); pendingStartAt = nil
        guard let workout, builder != nil, !saveInProgress else { return }
        guard endDate == nil else { if saveFailed { retrySave() }; return }
        endDate = Date(); isBusy = true; isRunning = false; isPaused = false
        elapsed = builder?.elapsedTime(at: endDate!) ?? elapsed
        note = "正在结束并保存室外跑步"
        if workout.state == .stopped || workout.state == .ended { finishCollection() }
        else { workout.stopActivity(with: endDate!) }
        // Saving starts from the .stopped delegate callback, after HealthKit's final samples.
    }

    private func finishCollection() {
        guard let builder, let workout, let endDate, !saveInProgress else { return }
        saveInProgress = true; isBusy = true; saveFailed = false
        if collectionEnded { saveWorkout(builder, session: workout); return }
        builder.endCollection(withEnd: endDate) { [weak self] success, _ in
            DispatchQueue.main.async {
                guard let self, self.builder === builder else { return }
                if success { self.collectionEnded = true; self.saveWorkout(builder, session: workout) }
                else { self.saveInProgress = false; self.isBusy = false; self.saveFailed = true; self.note = "运动结束，保存未完成；请点重试保存" }
            }
        }
    }

    private func saveWorkout(_ builder: HKLiveWorkoutBuilder, session: HKWorkoutSession) {
        builder.finishWorkout { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, self.builder === builder else { return }
                self.saveInProgress = false; self.isBusy = false
                guard result != nil, error == nil else { self.saveFailed = true; self.note = "保存失败，本次记录仍保留待重试"; return }
                self.saved = true; self.saveFailed = false; self.note = "室外跑步已保存到健康，健身 App 同步后可查看"
                session.end(); self.builder = nil; self.workout = nil; self.pendingMessage = false
                if WCSession.default.activationState == .activated {
                    let message: [String: Any] = ["version": 1, "kind": "finished", "runID": self.runID, "saved": true, "activity": "outdoorRun"]
                    WCSession.default.sendMessage(message, replyHandler: nil, errorHandler: nil)
                    // One terminal receipt only. Live samples are never queued for later replay.
                    WCSession.default.transferUserInfo(message)
                }
            }
        }
    }
    func retrySave() { guard saveFailed else { return }; finishCollection() }

    private func sendSnapshot(now: Date) {
        guard !pendingMessage, WCSession.default.activationState == .activated, WCSession.default.isReachable else { return }
        sequence += 1
        var message: [String: Any] = ["version": 1, "kind": "workout", "source": "healthkit-live-watch", "runID": runID,
            "snapshotAt": now.timeIntervalSince1970, "startedAt": startedAt.timeIntervalSince1970, "sequence": sequence,
            "mode": mode.rawValue, "elapsedSeconds": elapsed, "paused": isPaused, "zoneState": zoneState]
        for (valueKey, dateKey, metric) in [("heartRate", "heartRateAt", heart), ("paceSecondsPerKM", "paceAt", pace), ("cadenceSPM", "cadenceAt", cadence), ("strideMeters", "strideAt", stride), ("distanceMeters", "distanceAt", distance), ("activeEnergyKcal", "energyAt", energy)] {
            if let metric, (valueKey == "distanceMeters" || valueKey == "activeEnergyKcal") || (!isPaused && metric.fresh(at: now)) { message[valueKey] = metric.value; message[dateKey] = metric.date.timeIntervalSince1970 }
        }
        if let zoneConfiguration { message["zoneConfiguration"] = zoneConfiguration }
        if let zoneIndex, let zoneDate { message["zoneIndex"] = zoneIndex; message["zoneUpdatedAt"] = zoneDate.timeIntervalSince1970 }
        pendingMessage = true; pendingSince = now; lastSentAt = now
        let currentRun = runID, request = UUID(); messageID = request
        WCSession.default.sendMessage(message, replyHandler: { [weak self] answer in
            DispatchQueue.main.async {
                guard let self, self.isRunning, self.runID == currentRun, self.messageID == request else { return }
                self.pendingMessage = false
                if answer["stopRequested"] as? Bool == true { self.stop(reason: "手机请求结束并保存"); return }
                self.lastContact = Date(); self.note = "运动数据正在传到手机"
            }
        }, errorHandler: { [weak self] _ in
            DispatchQueue.main.async { guard let self, self.runID == currentRun, self.messageID == request else { return }; self.pendingMessage = false; self.note = "手机暂时断开，等待连接" }
        })
    }

    private func pump() {
        if let requestedAt = pendingStartAt, Date().timeIntervalSince(requestedAt) >= 8 {
            pendingStartAt = nil; startupID = UUID(); isBusy = false; note = "手机连接超时，请打开运动看板后重试"
        }
        guard isRunning else { return }
        let now = Date()
        if now.timeIntervalSince(lastContact) >= 30 { note = "手表继续记录；手机暂时断开，恢复后显示最新数据" }
        if pendingMessage, now.timeIntervalSince(pendingSince) >= 8 { pendingMessage = false }
        elapsed = builder?.elapsedTime(at: now) ?? 0
        if now.timeIntervalSince(lastSentAt) >= 2 { sendSnapshot(now: now) }
    }

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        // Read statistics on the delegate queue, publish values and their actual sample dates together.
        var collected: [(HKQuantityType, LiveWorkoutMetric)] = []
        for (type, unit) in [(heartType, HKUnit.count().unitDivided(by: .minute())), (speedType, HKUnit.meter().unitDivided(by: .second())), (strideType, HKUnit.meter())] where collectedTypes.contains(type) {
            if let stats = workoutBuilder.statistics(for: type), let value = stats.mostRecentQuantity(), let date = stats.mostRecentQuantityDateInterval()?.end {
                collected.append((type, LiveWorkoutMetric(value: value.doubleValue(for: unit), date: date)))
            }
        }
        for (type, unit) in [(distanceType, HKUnit.meter()), (stepsType, HKUnit.count()), (energyType, HKUnit.kilocalorie())] where collectedTypes.contains(type) {
            if let stats = workoutBuilder.statistics(for: type), let quantity = stats.sumQuantity() {
                collected.append((type, LiveWorkoutMetric(value: quantity.doubleValue(for: unit), date: stats.endDate)))
            }
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isRunning, !self.isPaused, self.builder === workoutBuilder else { return }
            for (type, metric) in collected where metric.value.isFinite && metric.date >= self.startedAt {
                if type == self.heartType, (30...240).contains(metric.value), metric.date > (self.heart?.date ?? .distantPast) { self.heart = metric }
                if type == self.speedType, metric.date > (self.pace?.date ?? .distantPast) {
                    self.pace = metric.value > 0 && (50...7200).contains(1000 / metric.value) ? LiveWorkoutMetric(value: 1000 / metric.value, date: metric.date) : nil
                }
                if type == self.strideType, (0.05...5).contains(metric.value), metric.date > (self.stride?.date ?? .distantPast) { self.stride = metric }
                if type == self.distanceType, (0...500000).contains(metric.value), metric.date > (self.distance?.date ?? .distantPast) { self.distance = metric }
                if type == self.energyType, (0...50000).contains(metric.value), metric.date > (self.energy?.date ?? .distantPast) { self.energy = metric }
                if type == self.stepsType { self.cadence = self.cadenceWindow.add(totalSteps: metric.value, date: metric.date).map { LiveWorkoutMetric(value: $0, date: metric.date) } }
            }
        }
    }

    @available(watchOS 27.0, *)
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didUpdateWorkoutZone zoneUpdate: HKLiveWorkoutZoneUpdate) {
        guard let group = zoneUpdate.zoneGroup, group.configuration.quantityType == heartType else { return }
        let index = zoneUpdate.currentZoneDuration?.zone.index, date = zoneUpdate.lastSampleProcessedDate
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isRunning, !self.isPaused, self.builder === workoutBuilder,
                  let date, date >= self.startedAt, date >= (self.zoneDate ?? .distantPast) else { return }
            self.applyZoneConfiguration(group.configuration)
            self.zoneIndex = index; self.zoneDate = date
            self.zonePosition = group.configuration.zones.firstIndex { $0.index == index }.map { $0 + 1 }
            self.zoneLabel = self.zonePosition.map { "Z\($0)" } ?? "—"
        }
    }
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.workout === workoutSession else { return }
            if toState == .stopped || toState == .ended {
                if self.endDate == nil { self.endDate = date; self.isRunning = false }
                self.finishCollection()
            }
            if toState == .paused { self.isPaused = true; self.heart = nil; self.pace = nil; self.cadence = nil; self.stride = nil; self.cadenceWindow.reset(); self.note = "室外跑步已暂停" }
            if toState == .running { self.isPaused = false; self.cadenceWindow.reset() }
        }
    }
    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in guard self?.workout === workoutSession else { return }; self?.stop(reason: "采集失败，请检查授权及其他体能训练") }
    }
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { [weak self] in if error != nil { self?.note = "手表通信未激活，请检查配对" } }
    }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            guard let self, message["version"] as? Int == 1 else { return }
            if message["kind"] as? String == "stop", let requested = message["runID"] as? String, requested.isEmpty || requested == self.runID { self.stop(reason: "手机已停止本次采集") }
        }
    }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        // Heart-rate zone preferences come only from HealthKit on this Watch.
    }
}
