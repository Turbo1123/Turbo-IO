import Foundation

/// iOS 1.0.2 sendResponseComplete: internal index11 -> wire12, JSON {}, empty data.
/// A response-completion notification, NOT a request to exit the page.
public enum AssistantResponseCompletePrototype {
    public static func complete() -> Data { Data([8,1,16,12,26,2,123,125,34,0]) }
}
