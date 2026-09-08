import SwiftUI

enum Palette {
    static let background = Color(red: 0.985, green: 0.984, blue: 0.973)
    static let ink = Color(red: 0.08, green: 0.17, blue: 0.14)
    static let green = Color(red: 0.12, green: 0.37, blue: 0.28)
    static let mint = Color(red: 0.74, green: 0.92, blue: 0.73)
    static let muted = Color(red: 0.43, green: 0.49, blue: 0.45)
    static let line = Color(red: 0.87, green: 0.90, blue: 0.86)
    static let amber = Color(red: 0.53, green: 0.36, blue: 0.11)
}

struct Screen<Content: View>: View {
    @EnvironmentObject private var store: CompanionStore
    let title: String
    let eyebrow: String
    var headerIcon: String? = nil
    var headerAction: (() -> Void)? = nil
    @ScaledMetric private var titleSize = 28.0
    @ViewBuilder var content: () -> Content

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(title).font(.system(size: titleSize, weight: .bold)).foregroundStyle(Palette.ink)
                            Text(eyebrow).font(.system(size: 12)).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        if let headerIcon {
                            Button { headerAction?() } label: { Image(systemName: headerIcon).font(.system(size: 23)).foregroundStyle(Palette.ink).frame(width: 42, height: 42) }
                                .accessibilityLabel(headerIcon == "gearshape" ? "偏好设置" : "归档链路")
                        }
                    }
                    if store.demoMode {
                        Label("演示模式 · 示例数据，不连接眼镜", systemImage: "sparkles")
                            .font(.caption.weight(.medium)).foregroundStyle(Palette.amber)
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(red: 0.98, green: 0.92, blue: 0.77), in: RoundedRectangle(cornerRadius: 12))
                    }
                    content()
                }
                // NavigationStack can extend its scroll area beneath the root's custom tab inset.
                // Keep the last row reachable above the 63pt tab controls on iOS 16 and 26.
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 100)
            }
            .background(Palette.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16, content: content)
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Palette.line.opacity(0.5), lineWidth: 0.75))
    }
}

struct SectionLabel: View {
    let title: String
    var trailing: String = ""
    var body: some View {
        HStack {
            Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.ink)
            Spacer()
            Text(trailing).font(.caption).foregroundStyle(Palette.muted)
        }
    }
}

struct Badge: View {
    let text: String
    var active = false
    var body: some View {
        Text(text).font(.system(size: 10, weight: .semibold))
            .foregroundStyle(active ? Palette.green : Palette.muted)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(active ? Palette.mint.opacity(0.5) : Palette.background, in: Capsule())
    }
}

struct PrimaryButton: View {
    let title: String
    var icon = "arrow.right"
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                Text(title).font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity).padding(16).foregroundStyle(enabled ? .white : Palette.muted.opacity(0.65))
            .background(enabled ? Palette.ink : Palette.line.opacity(0.36), in: RoundedRectangle(cornerRadius: 14))
        }.disabled(!enabled)
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var status: String = "待接入"
    var active = false
    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12).fill(Palette.background).frame(width: 42, height: 42)
                .overlay(Image(systemName: icon).font(.system(size: 17)).foregroundStyle(Palette.green))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.ink)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Badge(text: status, active: active)
        }.padding(.vertical, 2).contentShape(Rectangle())
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 27, weight: .light)).foregroundStyle(Palette.green)
                .frame(width: 68, height: 68).background(Palette.background, in: RoundedRectangle(cornerRadius: 22))
            Text(title).font(.system(size: 19, weight: .semibold)).foregroundStyle(Palette.ink)
            Text(detail).font(.system(size: 13)).foregroundStyle(Palette.muted).multilineTextAlignment(.center).lineSpacing(5)
        }.frame(maxWidth: .infinity).padding(.vertical, 22)
    }
}

struct GlassesIllustration: View {
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let lens = width * 0.37
            ZStack {
                Ellipse().fill(Palette.mint.opacity(0.06)).frame(width: width * 0.9, height: 85).blur(radius: 12).offset(y: 25)
                Path { path in
                    path.move(to: CGPoint(x: 12, y: 67)); path.addLine(to: CGPoint(x: 3, y: 19)); path.addQuadCurve(to: CGPoint(x: 37, y: 9), control: CGPoint(x: 11, y: 0))
                    path.move(to: CGPoint(x: width - 12, y: 67)); path.addLine(to: CGPoint(x: width - 3, y: 19)); path.addQuadCurve(to: CGPoint(x: width - 37, y: 9), control: CGPoint(x: width - 11, y: 0))
                }.stroke(Palette.mint.opacity(0.45), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                HStack(spacing: 23) {
                    ForEach(0..<2) { _ in
                        RoundedRectangle(cornerRadius: 20)
                            .fill(LinearGradient(colors: [Palette.mint.opacity(0.12), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: lens, height: 70)
                            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Palette.mint, lineWidth: 5))
                            .overlay(alignment: .topLeading) {
                                Capsule().fill(.white.opacity(0.45)).frame(width: 28, height: 3).rotationEffect(.degrees(-30)).offset(x: 15, y: 19)
                            }
                    }
                }.offset(y: 11)
                Path { path in
                    path.move(to: CGPoint(x: width / 2 - 12, y: 52)); path.addQuadCurve(to: CGPoint(x: width / 2 + 12, y: 52), control: CGPoint(x: width / 2, y: 39))
                }.stroke(Palette.mint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }.frame(width: width, height: geometry.size.height)
        }.frame(height: 130).accessibilityHidden(true)
    }
}
