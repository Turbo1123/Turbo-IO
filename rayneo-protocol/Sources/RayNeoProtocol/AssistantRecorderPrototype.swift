import Foundation

/// iOS 1.0.2 RecorderControlMessage.init(start:) at 0x10177fa0c maps
/// true -> rc=1, false -> rc=2; sendRecorderControl selects AssistantType=2.
/// Statically recovered command. Device behavior is a separate acceptance gate.
public enum AssistantRecorderPrototype {
    public static func control(start: Bool) -> Data {
        let body = Data((start ? "{\"rc\":1}" : "{\"rc\":2}").utf8)
        return Data([8,1,16,2,26,UInt8(body.count)]) + body + Data([34,0])
    }
}
