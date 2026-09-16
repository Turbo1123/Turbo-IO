import SwiftUI

@main
struct RayNeoCompanionApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var languageSettings = AppLanguageSettings.forCurrentLaunch()
    @StateObject private var store = CompanionStore.forCurrentLaunch()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(languageSettings)
                .environment(\.locale, languageSettings.locale)
                .environmentObject(store)
                .environmentObject(store.archive)
                .environmentObject(store.archive.audioInspection)
                .environmentObject(store.books)
                .environmentObject(store.voice)
                .environmentObject(store.codex)
                .environmentObject(store.codexPush)
                .environmentObject(store.hermesPush)
                .environmentObject(store.timeline)
                .environmentObject(store.recordingASR)
                .environmentObject(store.features)
                .environmentObject(store.notifications)
                .environmentObject(store.headControlTest)
                .environmentObject(store.automaticWeather)
                .environmentObject(store.qweather)
                .tint(Palette.green)
                .preferredColorScheme(.light)
                .onChange(of: scenePhase) { phase in
                    if phase == .active { languageSettings.refreshSystemLocale() }
                }
        }
    }
}

struct RootView: View {
    @Environment(\.locale) private var locale
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
                tabButton(0, L10n.text("Device", locale: locale), "eyeglasses")
                tabButton(1, L10n.text("Conversation", locale: locale), "bubble.left")
                tabButton(2, L10n.text("Archive", locale: locale), "folder")
                tabButton(3, L10n.text("Tools", locale: locale), "case")
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
                store.hermesPush.tick(locale: locale)
                do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { break }
            }
        }
        .onOpenURL { url in
            guard url.isFileURL, ["txt", "epub"].contains(url.pathExtension.lowercased()) else { return }
            incomingBook = url; confirmBook = true
        }
        .confirmationDialog(L10n.text("Copy this book into Turbo IO as local text? Nothing will be uploaded, and the original file will stay unchanged.", locale: locale), isPresented: $confirmBook) {
            Button(L10n.text("Import Book", locale: locale)) {
                guard let url = incomingBook else { return }
                incomingBook = nil
                Task { await store.books.importFile(url); showBooks = true }
            }
            Button(L10n.text("Cancel", locale: locale), role: .cancel) { incomingBook = nil }
        }
        .sheet(isPresented: $showBooks) {
            NavigationStack { BookShelfView().toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Done", locale: locale)) { showBooks = false } } } }
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
