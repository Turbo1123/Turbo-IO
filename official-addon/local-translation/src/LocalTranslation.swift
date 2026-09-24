import Foundation
import Translation
import SwiftUI
import UIKit

// Local text translation only: the caller's ASR can still be cloud based.
@available(iOS 26.0, *)
@MainActor final class CaptionLocalTranslation {
    private var current: Task<String, Error>?
    private var busy = false
    private var generation = 0
    func translate(_ text: String, source: String, target: String) async throws -> String {
        guard !busy, !text.isEmpty, text.utf8.count <= 16384, !source.isEmpty, !target.isEmpty else { throw CaptionFailure.configuration }
        if source == target { return text }
        busy = true; defer { busy = false }
        let epoch = generation
        let task = Task { try await Self.translateOnce(text, source: source, target: target) }
        current = task; defer { current = nil }
        let result = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
        guard epoch == generation, !Task.isCancelled else { throw CancellationError() }
        return result
    }
    func cancel() { generation += 1; current?.cancel() }
    // Own the non-Sendable system session within one async operation, not across actors.
    nonisolated private static func translateOnce(_ text: String, source: String, target: String) async throws -> String {
        try Task.checkCancellation()
        let from = Locale.Language(identifier: source), to = Locale.Language(identifier: target)
        guard await LanguageAvailability().status(from: from, to: to) == .installed else { throw CaptionFailure.unavailable }
        try Task.checkCancellation()
        let session = TranslationSession(installedSource: from, target: to)
        defer { session.cancel() }
        let result = try await session.translate(text)
        try Task.checkCancellation()
        return result.targetText
    }
    // User must explicitly open preparation and approve system language downloads.
    static func preparationController(source: String, target: String) -> UIViewController {
        UIHostingController(rootView: CaptionLanguagePreparation(source: source, target: target))
    }
}

@available(iOS 26.0, *)
private struct CaptionLanguagePreparation: View {
    let source: String
    let target: String
    @State private var configuration: TranslationSession.Configuration?
    @State private var status = "系统翻译需要先下载对应语言。仅文字翻译在本机执行，云端 ASR 不因此变为离线。"
    var body: some View {
        VStack(spacing: 24) {
            Text("本地翻译语言包").font(.title2)
            Text(source + " → " + target).font(.headline)
            Text(status)
            Button("检查并准备语言包") {
                configuration = .init(source: Locale.Language(identifier: source), target: Locale.Language(identifier: target))
                configuration?.invalidate()
            }
        }.padding().translationTask(configuration) { @Sendable session in
            do { try await session.prepareTranslation(); await MainActor.run { status = "语言包准备完成，可以使用本机翻译。" } }
            catch { await MainActor.run { status = "语言包尚未就绪，请确认系统下载授权与语种支持。" } }
        }
    }
}
