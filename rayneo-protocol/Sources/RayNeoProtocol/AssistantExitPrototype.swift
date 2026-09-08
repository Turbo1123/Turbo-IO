import Foundation

/// iOS 1.0.2 sendAppExit selects type7; AssistantPhoneExitRc.normal is 1.
/// Normal session exit is distinct from type2 stop-recorder and type12 round-end.
public enum AssistantExitPrototype {
    public static func normalExit() -> Data {
        Data([8,1,16,7,26,8,123,34,114,99,34,58,49,125,34,0])
    }
}
