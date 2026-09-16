import Foundation
import Combine
import RayNeoSession

/// Optional, generic glasses reminders for task transitions. Task text and
/// approval decisions stay on the iPhone; this class never sends either.
@MainActor final class HermesPush: ObservableObject {
    @Published private(set) var enabled: Bool
    @Published private(set) var status = "Hermes alerts are off."

    private let defaults: UserDefaults
    private let endpoint: () -> String
    private let snapshot: () -> HermesTaskState?
    private let hasUnfinishedTask: () -> Bool
    private let canDeliver: () -> Bool
    private let deliver: (String, String) -> String?
    private let prefix = "companion.hermes.push.v1."
    private var observedEndpoint: String
    private var observedKey: String?
    private var pendingKey: String?

    init(defaults: UserDefaults, endpoint: @escaping () -> String,
         snapshot: @escaping () -> HermesTaskState?, hasUnfinishedTask: @escaping () -> Bool,
         canDeliver: @escaping () -> Bool,
         deliver: @escaping (String, String) -> String?) {
        self.defaults = defaults
        self.endpoint = endpoint
        self.snapshot = snapshot
        self.hasUnfinishedTask = hasUnfinishedTask
        self.canDeliver = canDeliver
        self.deliver = deliver
        enabled = defaults.bool(forKey: prefix + "enabled")
        observedEndpoint = defaults.string(forKey: prefix + "endpoint") ?? ""
        observedKey = defaults.string(forKey: prefix + "observed")
        pendingKey = defaults.string(forKey: prefix + "pending")
        if enabled { status = "Hermes alerts enabled. Only new task updates will be announced." }
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        defaults.set(value, forKey: prefix + "enabled")
        baseline(endpoint: endpoint(), state: snapshot())
        status = value ? "Hermes alerts enabled. Only new task updates will be announced." : "Hermes alerts are off."
    }

    func tick(locale: Locale) {
        guard enabled else { return }
        let currentEndpoint = endpoint()
        guard !currentEndpoint.isEmpty, let state = snapshot() else { return }
        if observedEndpoint != currentEndpoint {
            if observedEndpoint.isEmpty && observedKey == "no-task" {
                // The owner enabled alerts before adding the first bridge.
                // Preserve that empty baseline so a fast first task is new.
                observedEndpoint = currentEndpoint
                defaults.set(currentEndpoint, forKey: prefix + "endpoint")
            } else {
                baseline(endpoint: currentEndpoint, state: state)
                return
            }
        }
        let key = Self.key(for: state)
        guard let observedKey else {
            baseline(endpoint: currentEndpoint, state: state)
            return
        }
        if observedKey != key {
            self.observedKey = key
            defaults.set(key, forKey: prefix + "observed")
            pendingKey = Self.message(for: state, locale: locale) == nil ? nil : key
            defaults.set(pendingKey, forKey: prefix + "pending")
        }
        guard pendingKey == key, let message = Self.message(for: state, locale: locale) else { return }
        guard canDeliver() else {
            status = "Waiting for glasses connection and notification settings to allow a Hermes alert."
            return
        }
        // Persist before transport: an uncertain SDK result must never trigger
        // an automatic repeat of a task notification.
        pendingKey = nil
        defaults.removeObject(forKey: prefix + "pending")
        status = deliver("Hermes", message) == nil
            ? "Hermes alert delivery is uncertain. It will not be retried automatically."
            : "Hermes alert submitted. Confirm on the glasses; approval stays on iPhone."
    }

    private func baseline(endpoint: String, state: HermesTaskState?) {
        observedEndpoint = endpoint
        // A fresh task can complete before the first UI timer fires. Mark the
        // empty state explicitly, but suppress an unresolved pre-existing task
        // until its first state has been observed.
        observedKey = state.map(Self.key) ?? (hasUnfinishedTask() ? nil : "no-task")
        pendingKey = nil
        defaults.set(endpoint, forKey: prefix + "endpoint")
        defaults.set(observedKey, forKey: prefix + "observed")
        defaults.removeObject(forKey: prefix + "pending")
    }

    private static func key(for state: HermesTaskState) -> String {
        state.requestId + "|" + state.status.rawValue + "|" + (state.prompt?.id ?? "")
    }

    private static func message(for state: HermesTaskState, locale: Locale) -> String? {
        switch state.status {
        case .waiting:
            guard let prompt = state.prompt else { return nil }
            switch prompt.kind {
            case .approval: return L10n.text("Hermes needs approval. Review on your iPhone.", locale: locale)
            case .clarify: return L10n.text("Hermes needs an answer. Review on your iPhone.", locale: locale)
            case .localAction: return L10n.text("Hermes needs an action on your computer. Review on your iPhone.", locale: locale)
            }
        case .completed: return L10n.text("Hermes task finished. Open Norman IO for the result.", locale: locale)
        case .failed: return L10n.text("Hermes task failed. Open Norman IO for details.", locale: locale)
        case .unknown: return L10n.text("Hermes task needs verification on your computer.", locale: locale)
        case .running, .stopping, .cancelled: return nil
        }
    }
}
