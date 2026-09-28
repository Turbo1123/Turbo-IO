import SwiftUI
import WatchConnectivity
import WatchKit

struct CueWatchProject: Identifiable, Hashable {
    let id: String
    let title: String
    let count: Int
    let offset: Int

    init?(_ row: [String: Any]) {
        guard let id = row["id"] as? String, let title = row["title"] as? String else { return nil }
        self.id = id
        self.title = title
        self.count = row["count"] as? Int ?? 0
        self.offset = row["offset"] as? Int ?? 0
    }
}

@MainActor
final class CueCardsRemote: NSObject, ObservableObject, WCSessionDelegate {
    let heartRate = HeartRateModel(ownsConnectivity: false)
    @Published private(set) var state: [String: Any] = [:]
    @Published private(set) var projects: [CueWatchProject] = []
    @Published private(set) var browseCard: [String: Any]?
    @Published private(set) var nextProjectOffset: Int?
    @Published private(set) var sending = false
    @Published private(set) var connectionNote = "连接手机以读取提词卡项目"
    private var channel: WCSession?
    private var requestID: UUID?
    private var lastHapticRevision: String?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        channel = .default
        channel?.delegate = self
        channel?.activate()
    }

    var active: Bool { state["active"] as? Bool == true }
    var ready: Bool { active && state["ready"] as? Bool == true && !sending }
    var reachable: Bool { channel?.activationState == .activated && channel?.isReachable == true }
    var index: Int { state["index"] as? Int ?? 0 }
    var count: Int { state["count"] as? Int ?? 0 }
    var lines: [String] { state["lines"] as? [String] ?? [] }

    func isLive(projectID: String) -> Bool { active && state["projectID"] as? String == projectID }

    func card(for project: CueWatchProject) -> [String: Any]? {
        if isLive(projectID: project.id) { return state }
        guard let card = browseCard, card["projectID"] as? String == project.id else { return nil }
        return card
    }

    func cardCount(for project: CueWatchProject) -> Int {
        // A running presentation has a fixed snapshot; new library cards are
        // included the next time the user starts it.
        if isLive(projectID: project.id) { return count }
        if let current = projects.first(where: { $0.id == project.id }) { return current.count }
        return card(for: project)?["count"] as? Int ?? project.count
    }

    func refresh() {
        if active { send(["action": "refresh"]) }
        else { loadProjects(offset: state["projectOffset"] as? Int ?? 0) }
    }

    func loadProjects(offset: Int) {
        send(["action": "listProjects", "offset": max(0, offset)])
    }

    func loadCard(project: CueWatchProject, index: Int) {
        let currentCount = cardCount(for: project)
        guard index >= 0, index < currentCount else { return }
        send(["action": "showCard", "projectID": project.id, "index": index, "offset": project.offset])
    }

    func move(project: CueWatchProject, index: Int, direction: Int) {
        let target = index + direction
        guard target >= 0 else { return }
        if isLive(projectID: project.id) {
            guard ready, target < count,
                  let session = state["session"] as? String,
                  let card = state["card"] as? String,
                  let revision = state["revision"] as? Int else { return }
            send([
                "action": direction > 0 ? "next" : "previous",
                "session": session,
                "card": card,
                "revision": revision,
                "issuedAt": Date().timeIntervalSince1970
            ])
        } else {
            let currentCount = cardCount(for: project)
            guard target < currentCount else { return }
            loadCard(project: project, index: target)
        }
    }

    func start(project: CueWatchProject) {
        send(["action": "start", "projectID": project.id, "issuedAt": Date().timeIntervalSince1970, "offset": project.offset])
    }

    func stop() {
        send(["action": "stop", "issuedAt": Date().timeIntervalSince1970])
    }

    func addCard(project: CueWatchProject, title: String, copy: String, afterCardID: String, requestID: String, completion: ((Bool, String) -> Void)? = nil) {
        send([
            "action": "addCard",
            "projectID": project.id,
            "title": title,
            "copy": copy,
            "afterCardID": afterCardID,
            "requestID": requestID,
            "offset": project.offset,
            "issuedAt": Date().timeIntervalSince1970
        ], completion: completion)
    }

    private func send(_ message: [String: Any], completion: ((Bool, String) -> Void)? = nil) {
        guard !sending, let channel, channel.activationState == .activated, channel.isReachable else {
            connectionNote = "手機暫不可達，沒有保存或排隊"
            completion?(false, connectionNote)
            return
        }
        let id = UUID()
        requestID = id
        sending = true
        channel.sendMessage(message, replyHandler: { [weak self] reply in
            Task { @MainActor in
                guard let self, self.requestID == id else { return }
                self.requestID = nil
                self.sending = false
                self.apply(reply)
                let accepted = reply["accepted"] as? Bool == true
                completion?(accepted, (reply["note"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (accepted ? "已添加到项目" : "操作未完成"))
            }
        }, errorHandler: { [weak self] _ in
            Task { @MainActor in
                guard let self, self.requestID == id else { return }
                self.requestID = nil
                self.sending = false
                self.connectionNote = "连接中断，操作结果尚未确认；重连后刷新或重试"
                self.state["ready"] = false
                completion?(false, self.connectionNote)
            }
        })
    }

    private func apply(_ snapshot: [String: Any]) {
        let oldSession = state["session"] as? String
        let previousRevision = state["revision"] as? Int
        let newSession = snapshot["session"] as? String
        let newRevision = snapshot["revision"] as? Int
        let oldRevision = state["revision"] as? Int ?? -1
        let revision = snapshot["revision"] as? Int ?? -1
        if oldSession != nil, oldSession == newSession, revision < oldRevision { return }
        if oldSession != nil, oldSession == newSession, revision == oldRevision,
           state["ready"] as? Bool == true, snapshot["ready"] as? Bool != true { return }

        var merged = state
        for (key, value) in snapshot { merged[key] = value }
        if snapshot["active"] as? Bool == false {
            for key in ["session", "revision", "projectID", "project", "card", "title", "lines", "index", "count"] {
                merged.removeValue(forKey: key)
            }
        }
        state = merged
        if let rows = snapshot["projects"] as? [[String: Any]] {
            projects = rows.compactMap(CueWatchProject.init)
            let next = snapshot["nextProjectOffset"] as? Int ?? -1
            nextProjectOffset = next >= 0 ? next : nil
        }
        if let card = snapshot["browseCard"] as? [String: Any] { browseCard = card }
        if let note = snapshot["note"] as? String, !note.isEmpty { connectionNote = note }
        else if snapshot["accepted"] as? Bool == true { connectionNote = "已同步" }
        if snapshot["ready"] as? Bool == true,
           let newSession,
           let newRevision,
           (oldSession != newSession || previousRevision != newRevision),
           lastHapticRevision != "\(newSession):\(newRevision)" {
            lastHapticRevision = "\(newSession):\(newRevision)"
            WKInterfaceDevice.current().play(.click)
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let snapshot = session.receivedApplicationContext
        Task { @MainActor in
            self.heartRate.session(session, activationDidCompleteWith: activationState, error: error)
            if let heartContext = snapshot["heartRate"] as? [String: Any] {
                self.heartRate.session(session, didReceiveApplicationContext: heartContext)
            }
            self.apply(snapshot)
#if TIO_WATCH_CUE
            self.loadProjects(offset: self.state["projectOffset"] as? Int ?? 0)
#endif
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            if let heartContext = applicationContext["heartRate"] as? [String: Any] {
                self.heartRate.session(session, didReceiveApplicationContext: heartContext)
            }
            self.apply(applicationContext)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.heartRate.session(session, didReceiveMessage: message) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            if session.isReachable {
#if TIO_WATCH_CUE
                self.refresh()
#endif
            }
            else {
                self.state["ready"] = false
                self.connectionNote = "手机暂不可达；手表不会积压翻页或新增内容"
            }
        }
    }
}

private struct CueProjectListView: View {
    @ObservedObject var remote: CueCardsRemote

    var body: some View {
        List {
#if TIO_WATCH_RUN
            NavigationLink {
                HeartRateWatchView(model: remote.heartRate)
            } label: {
                Label("运动看板", systemImage: "figure.run").foregroundStyle(.red)
            }
#endif
#if TIO_WATCH_CUE
            if remote.projects.isEmpty {
                Text(remote.sending ? "正在读取项目…" : "打开 iPhone 上的提词卡并连接手机")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(remote.projects) { project in
                NavigationLink {
                    CueCardReaderView(project: project, remote: remote)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(project.title).font(.headline).lineLimit(2)
                        Text("\(project.count) 张卡片").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            if let offset = remote.nextProjectOffset {
                Button("更多项目") { remote.loadProjects(offset: offset) }
            }
#endif
        }
        .navigationTitle("Turbo IO")
#if TIO_WATCH_CUE
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { remote.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("刷新项目")
            }
        }
        .onAppear {
            if remote.projects.isEmpty { remote.loadProjects(offset: 0) }
        }
#endif
    }
}

private struct CueCardReaderView: View {
    let project: CueWatchProject
    @ObservedObject var remote: CueCardsRemote
    @State private var index = 0

    private var card: [String: Any]? { remote.card(for: project) }
    private var cardIndex: Int { card?["index"] as? Int ?? index }
    private var cardCount: Int { remote.cardCount(for: project) }
    private var lines: [String] { card?["lines"] as? [String] ?? [] }
    private var canAdvance: Bool { card != nil && cardIndex + 1 < cardCount && !remote.sending && (!remote.isLive(projectID: project.id) || remote.ready) }
    private var canGoBack: Bool { cardIndex > 0 && card != nil && !remote.sending && (!remote.isLive(projectID: project.id) || remote.ready) }

    var body: some View {
        VStack(spacing: 6) {
            // Keep secondary controls inside the scrollable content. Multiple
            // fixed watchOS button rows can otherwise collapse the card to zero.
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(cardIndex + 1) / \(cardCount)")
                        .font(.caption2.monospacedDigit())
                    if let card {
                        Text(card["title"] as? String ?? "")
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("cue-card-title")
                        ForEach(Array(lines.enumerated()), id: \.offset) { item in
                            Text(item.element)
                                .font(.system(size: 11, weight: item.element.hasPrefix("★") ? .semibold : .regular))
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        NavigationLink {
                            CueCardEditorView(project: project, remote: remote, nextIndex: cardIndex + 1, afterCardID: card["card"] as? String ?? "", index: $index)
                        } label: {
                            Label("在这张卡后添加", systemImage: "plus")
                                .font(.caption)
                        }
                        .accessibilityIdentifier("cue-card-add")
                    } else if remote.cardCount(for: project) == 0 {
                        Text("这个项目还没有卡片")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        NavigationLink {
                            CueCardEditorView(project: project, remote: remote, nextIndex: 0, afterCardID: "", index: $index)
                        } label: {
                            Label("添加第一张卡", systemImage: "plus")
                        }
                        .accessibilityIdentifier("cue-card-add")
                    } else {
                        Text(remote.sending ? "正在读取卡片…" : "连接手机以读取这张卡")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button(remote.isLive(projectID: project.id) ? "结束眼镜提词" : "在眼镜上开始") {
                        if remote.isLive(projectID: project.id) { remote.stop() }
                        else { remote.start(project: project) }
                    }
                    .disabled(remote.cardCount(for: project) == 0 || !remote.reachable || (remote.active && !remote.isLive(projectID: project.id)))

                    Button { remote.loadCard(project: project, index: cardIndex) } label: {
                        Label("刷新卡片", systemImage: "arrow.clockwise")
                    }
                    .font(.caption)

                    Text(remote.connectionNote)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityIdentifier("cue-card-content")

            HStack(spacing: 6) {
                Button("上一张") { remote.move(project: project, index: cardIndex, direction: -1) }
                    .disabled(!canGoBack)
                    .accessibilityIdentifier("cue-card-previous")
                Button(cardIndex + 1 >= cardCount ? "最后一张" : "下一张") {
                    remote.move(project: project, index: cardIndex, direction: 1)
                }
                .handGestureShortcut(.primaryAction)
                .disabled(!canAdvance)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("cue-card-next")
            }
            .font(.caption)
            .controlSize(.small)
        }
        .padding(.horizontal, 5)
        .navigationTitle(project.title)
        .onAppear {
            if remote.isLive(projectID: project.id) { index = remote.index }
            else { remote.loadCard(project: project, index: index) }
        }
        .onChange(of: remote.isLive(projectID: project.id) ? remote.index : (remote.browseCard?["projectID"] as? String == project.id ? remote.browseCard?["index"] as? Int ?? index : index)) { _, value in
            index = value
        }
    }
}

private struct CueCardEditorView: View {
    let project: CueWatchProject
    @ObservedObject var remote: CueCardsRemote
    let nextIndex: Int
    let afterCardID: String
    @Binding var index: Int
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var copy = ""
    @State private var requestID = UUID().uuidString
    @State private var message = "每行输入一个要点；行首 * 表示重点"
    @State private var saving = false

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !copy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (remote.cardCount(for: project) == 0 ? afterCardID.isEmpty : !afterCardID.isEmpty) && !saving && remote.reachable
    }

    var body: some View {
        List {
            TextField("卡片标题", text: $title)
                .onChange(of: title) { _, _ in requestID = UUID().uuidString }
            TextField("卡片文案，每行一个要点", text: $copy, axis: .vertical)
                .lineLimit(2...5)
                .onChange(of: copy) { _, _ in requestID = UUID().uuidString }
            Text(message).font(.caption2).foregroundStyle(.secondary)
            Button(saving ? "正在保存…" : "插在当前卡片之后") {
                saving = true
                remote.addCard(project: project, title: title, copy: copy, afterCardID: afterCardID, requestID: requestID) { accepted, note in
                    saving = false
                    message = note
                    if accepted {
                        if !remote.isLive(projectID: project.id) { index = nextIndex }
                        dismiss()
                    }
                }
            }
            .disabled(!canSave)
        }
        .disabled(saving)
        .navigationTitle("添加卡片")
    }
}

@main
struct CueCardsWatchApp: App {
    @StateObject private var remote = CueCardsRemote()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                CueProjectListView(remote: remote)
            }
            .onChange(of: phase) { _, value in if value == .active { remote.refresh() } }
        }
    }
}
