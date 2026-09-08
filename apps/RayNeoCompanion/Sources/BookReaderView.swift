import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct BookShelfView: View {
    @EnvironmentObject private var library: BookLibrary
    @State private var importing = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("把书变成提词稿").font(.title2.bold()).foregroundStyle(Palette.ink)
                Text("TXT · EPUB · 章节阅读 · 匀速滚动\n只在本机提取文字，不上传，不启动麦克风。").font(.subheadline).foregroundStyle(Palette.muted)
                PrimaryButton(title: library.busy ? "正在读取…" : "从文件导入书籍", icon: "square.and.arrow.down", enabled: !library.busy) { importing = true }
                    .accessibilityIdentifier("import-book")
                if library.allowsTestFixture {
                    Button("导入合成验收书籍") { Task { await library.importTestFixture() } }.disabled(library.busy).accessibilityIdentifier("book-import-fixture")
                }
                if library.books.isEmpty {
                    Card { EmptyState(icon: "books.vertical", title: "你的随身书架", detail: "在这里选文件，或在第三方 App 分享菜单选择“用Turbo IO打开”。支持无 DRM 的文字 EPUB；不保留图片与复杂排版。") }
                }
                ForEach(library.books) { book in
                    NavigationLink { BookReaderView(book: book) } label: {
                        Card {
                            HStack(spacing: 15) {
                                Image(systemName: "book.closed").font(.title).foregroundStyle(Palette.green)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(book.title).font(.headline).foregroundStyle(Palette.ink).lineLimit(2)
                                    Text("\(book.sourceExtension.uppercased()) · \(book.chapters.count) 个阅读分段").font(.caption).foregroundStyle(Palette.muted)
                                }
                                Spacer(); Image(systemName: "chevron.right").foregroundStyle(Palette.muted)
                            }
                        }
                    }.buttonStyle(.plain)
                        .accessibilityIdentifier("book-row-\(book.id.uuidString)")
                }
                Text("手机匀速预览已接入。眼镜传稿、滚动参数与旋钮进度同步仍需接线和真机验收；不会把手机像素速度当成镜片速度。")
                    .font(.caption).foregroundStyle(Palette.muted)
            }.padding(24)
        }.background(Palette.background).navigationTitle("书籍提词").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .preference(key: CompanionTabBarHiddenPreference.self, value: true)
            .task { await library.load() }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, UTType(filenameExtension: "epub") ?? .data]) { result in
                switch result { case .success(let url): Task { await library.importFile(url) }; case .failure: library.error = "未能打开所选文件。" }
            }
            .alert("书籍导入", isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) {
                Button("知道了", role: .cancel) {}
            } message: { Text(library.error ?? "") }
    }
}

struct BookReaderView: View {
    let book: ReadingBook
    @EnvironmentObject private var library: BookLibrary
    @EnvironmentObject private var store: CompanionStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var chapter: Int
    @State private var progress: Double
    @State private var speed: Double
    @State private var fontSize = 26.0
    @State private var playing = false
    @State private var jump = UUID()
    @State private var initialPosition: Double
    @State private var confirmDraft = false
    @State private var savedDraft = false
    init(book: ReadingBook) {
        self.book = book
        _chapter = State(initialValue: min(max(0, book.chapter), max(0, book.chapters.count - 1)))
        let position = book.progress.isFinite ? min(1, max(0, book.progress)) : 0
        _progress = State(initialValue: position); _initialPosition = State(initialValue: position)
        _speed = State(initialValue: book.speed.isFinite ? min(80, max(8, book.speed)) : 24)
    }
    var body: some View {
        VStack(spacing: 15) {
            Picker("章节", selection: $chapter) {
                ForEach(book.chapters) { item in Text(item.title).tag(item.id) }
            }.lineLimit(1).accessibilityIdentifier("book-chapter")
            HStack { Badge(text: "手机预览"); Spacer(); Text(String(format: "%.1f%%", progress * 100)).font(.caption.monospacedDigit()).accessibilityIdentifier("book-progress") }
            UniformReadingText(text: book.chapters[chapter].text, fontSize: fontSize, speed: speed,
                               playing: $playing, progress: $progress, jumpID: jump, jumpProgress: initialPosition)
                .clipShape(RoundedRectangle(cornerRadius: 20)).frame(maxHeight: .infinity)
                .accessibilityIdentifier("book-reading-text")
            HStack {
                Button { seek(max(0, progress - 0.1)) } label: { Image(systemName: "backward.end").frame(width: 50, height: 44) }.accessibilityLabel("向前翻阅")
                PrimaryButton(title: playing ? "暂停" : "匀速播放", icon: playing ? "pause.fill" : "play.fill") {
                    if progress >= 0.999 { seek(0) }
                    playing.toggle()
                }.accessibilityIdentifier("book-play")
                Button { seek(min(1, progress + 0.1)) } label: { Image(systemName: "forward.end").frame(width: 50, height: 44) }.accessibilityLabel("向后翻阅")
            }
            HStack { Text("慢"); Slider(value: $speed, in: 8...80, step: 2); Text("快"); Text("\(Int(speed)) pt/s").font(.caption.monospacedDigit()) }
            HStack { Text("字号").font(.caption); Slider(value: $fontSize, in: 18...40, step: 1); Text("\(Int(fontSize))").font(.caption) }
            Text("拖动即暂停 · 切章不自动播放 · 离页/锁屏暂停\n速度仅指手机滚动；到本段结尾自动停止。").font(.system(size: 10)).foregroundStyle(Palette.muted)
            Button(savedDraft ? "已复制到提词草稿" : "将当前分段用作提词稿") { confirmDraft = true }.font(.subheadline)
                .accessibilityIdentifier("book-use-draft")
        }.padding(.horizontal, 22).padding(.bottom, 18).background(Palette.background)
            .navigationTitle(book.title).navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .preference(key: CompanionTabBarHiddenPreference.self, value: true)
            .onChange(of: chapter) { _ in seek(0); savedDraft = false }
            .onChange(of: fontSize) { _ in seek(progress) }
            .onChange(of: playing) { _ in if !playing { save() } }
            .onChange(of: speed) { _ in if !playing { save() } }
            .onChange(of: scenePhase) { value in if value != .active { playing = false; save() } }
            .onDisappear { playing = false; save() }
            .confirmationDialog("会替换本机当前提词草稿，不会修改原书或发送到眼镜。", isPresented: $confirmDraft) {
                Button("替换本机草稿") { store.savePrompter(book.chapters[chapter].text); savedDraft = true }
            }
    }
    private func seek(_ value: Double) { playing = false; progress = value; initialPosition = value; jump = UUID(); save() }
    private func save() {
        let c = chapter, p = progress, s = speed
        Task { await library.savePosition(id: book.id, chapter: c, progress: p, speed: s) }
    }
}

struct UniformReadingText: UIViewRepresentable {
    let text: String, fontSize: Double, speed: Double
    @Binding var playing: Bool
    @Binding var progress: Double
    let jumpID: UUID, jumpProgress: Double
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView(); view.isEditable = false; view.isSelectable = false
        view.backgroundColor = UIColor(Palette.ink); view.textColor = UIColor(Palette.mint)
        view.textContainerInset = UIEdgeInsets(top: 35, left: 20, bottom: 80, right: 20)
        view.delegate = context.coordinator; context.coordinator.view = view
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        let c = context.coordinator; c.owner = self
        let changed = view.text != text || view.font?.pointSize != CGFloat(fontSize)
        if changed {
            let style = NSMutableParagraphStyle(); style.lineSpacing = 14
            view.attributedText = NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: fontSize, weight: .medium), .foregroundColor: UIColor(Palette.mint), .paragraphStyle: style])
        }
        if c.jumpID != jumpID || changed {
            c.jumpID = jumpID
            DispatchQueue.main.async { [weak c, weak view] in
                guard let c, let view, c.jumpID == jumpID else { return }
                view.layoutIfNeeded()
                view.setContentOffset(CGPoint(x: 0, y: max(0, view.contentSize.height - view.bounds.height) * jumpProgress), animated: false)
            }
        }
        c.setPlaying(playing)
    }
    static func dismantleUIView(_ view: UITextView, coordinator: Coordinator) { coordinator.setPlaying(false); view.delegate = nil }
    final class Coordinator: NSObject, UITextViewDelegate {
        var owner: UniformReadingText
        weak var view: UITextView?
        var link: CADisplayLink?
        var jumpID: UUID?
        var last: CFTimeInterval?
        init(_ owner: UniformReadingText) { self.owner = owner }
        func setPlaying(_ value: Bool) {
            if value && link == nil {
                last = nil
                let link = CADisplayLink(target: self, selector: #selector(tick)); link.preferredFramesPerSecond = 30
                self.link = link; link.add(to: .main, forMode: .common)
            } else if !value { link?.invalidate(); link = nil; last = nil }
        }
        @objc func tick(_ link: CADisplayLink) {
            guard let view else { setPlaying(false); return }
            let elapsed = last.map { link.timestamp - $0 } ?? 0; last = link.timestamp
            let maximum = max(0, view.contentSize.height - view.bounds.height)
            let y = ReadingMotion.next(offset: view.contentOffset.y, maximum: maximum, speed: owner.speed, elapsed: elapsed)
            view.setContentOffset(CGPoint(x: 0, y: y), animated: false)
            owner.progress = maximum > 0 ? y / maximum : 1
            if y >= maximum { owner.playing = false; setPlaying(false) }
        }
        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { owner.playing = false; setPlaying(false) }
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            if scrollView.isDragging || scrollView.isDecelerating {
                let maximum = max(0, scrollView.contentSize.height - scrollView.bounds.height)
                owner.progress = maximum > 0 ? min(1, max(0, scrollView.contentOffset.y / maximum)) : 1
            }
        }
    }
}
