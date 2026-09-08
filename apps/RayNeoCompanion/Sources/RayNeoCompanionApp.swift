import SwiftUI

@main
struct RayNeoCompanionApp: App {
    @StateObject private var store = CompanionStore.forCurrentLaunch()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(store.archive)
                .environmentObject(store.archive.audioInspection)
                .environmentObject(store.books)
                .environmentObject(store.voice)
                .environmentObject(store.codex)
                .environmentObject(store.codexPush)
                .environmentObject(store.timeline)
                .environmentObject(store.recordingASR)
                .environmentObject(store.features)
                .environmentObject(store.notifications)
                .environmentObject(store.automaticWeather)
                .environmentObject(store.qweather)
                .tint(Palette.green)
                .preferredColorScheme(.light)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: CompanionStore
    @State private var hideTabBar = false
    @State private var didApplyLaunchArguments = false
    @State private var incomingBook: URL?
    @State private var confirmBook = false
    @State private var showBooks = false

    var body: some View {
        Group {
            switch store.selectedTab {
            case 1: ConversationView()
            case 2: ArchiveView()
            case 3: ToolsView()
            default: DeviceView()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !hideTabBar {
            HStack(spacing: 0) {
                tabButton(0, "设备", "eyeglasses")
                tabButton(1, "会话", "bubble.left")
                tabButton(2, "归档", "folder")
                tabButton(3, "工具", "case")
            }
            .padding(.horizontal, 16).padding(.top, 9).padding(.bottom, 2)
            .background(.white)
            .overlay(alignment: .top) { Rectangle().fill(Palette.line.opacity(0.45)).frame(height: 0.5) }
            }
        }
        .onPreferenceChange(CompanionTabBarHiddenPreference.self) { hideTabBar = $0 }
        .task {
            while !Task.isCancelled {
                await store.codexPush.tick()
                do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { break }
            }
        }
        .onOpenURL { url in
            guard url.isFileURL, ["txt", "epub"].contains(url.pathExtension.lowercased()) else { return }
            incomingBook = url; confirmBook = true
        }
        .confirmationDialog("将这份书籍复制为Turbo IO本地文字？不上传、不修改原文件。", isPresented: $confirmBook) {
            Button("导入书籍") {
                guard let url = incomingBook else { return }
                incomingBook = nil
                Task { await store.books.importFile(url); showBooks = true }
            }
            Button("取消", role: .cancel) { incomingBook = nil }
        }
        .sheet(isPresented: $showBooks) {
            NavigationStack { BookShelfView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showBooks = false } } } }
        }
        .onAppear {
            guard !didApplyLaunchArguments else { return }
            didApplyLaunchArguments = true
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "--ui-tab"), arguments.indices.contains(index + 1) {
                store.selectedTab = Int(arguments[index + 1]) ?? 0
            }
        }
    }

    private func tabButton(_ index: Int, _ title: String, _ icon: String) -> some View {
        Button { store.selectedTab = index } label: {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 21, weight: .regular))
                Text(title).font(.system(size: 11, weight: store.selectedTab == index ? .semibold : .regular))
            }
            .foregroundStyle(store.selectedTab == index ? Color.white : Palette.muted)
            .frame(width: 70, height: 54)
            .background(store.selectedTab == index ? Palette.ink : .clear, in: RoundedRectangle(cornerRadius: 16))
            .frame(maxWidth: .infinity)
        }.accessibilityIdentifier("tab-\(index)").accessibilityLabel(title)
            .accessibilityAddTraits(store.selectedTab == index ? .isSelected : [])
    }
}

struct CompanionTabBarHiddenPreference: PreferenceKey {
    static var defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}
