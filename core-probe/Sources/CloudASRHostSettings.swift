import Foundation

/// No developer tenant is compiled into a source distribution.
enum CloudASRHostSettings {
    static let preferenceKey = "turboio.cloudASR.host.v1"
    static func normalize(_ value: String) -> String? {
        let host = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard host.utf8.count <= 253, host.hasSuffix(".aliyuncs.com"),
              host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ label in
                  !label.isEmpty && label.count <= 63 && label.first != "-" && label.last != "-" &&
                  label.unicodeScalars.allSatisfy { (97...122).contains($0.value) || (48...57).contains($0.value) || $0.value == 45 }
              }) else { return nil }
        return host
    }
    static func current(defaults: UserDefaults = .standard) -> String {
        normalize(defaults.string(forKey: preferenceKey) ?? "") ?? ""
    }
    static func service(for host: String) -> String { "RayNeo.CloudASR.https." + host }
    @discardableResult static func save(_ host: String, defaults: UserDefaults = .standard) -> Bool {
        guard let normalized = normalize(host) else { return false }
        defaults.set(normalized, forKey: preferenceKey); return true
    }
}
