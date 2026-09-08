import Foundation

/// Official iOS 1.0.2: VadStatus(start,stop,timeout) index+1 -> rc;
/// AssistantType internal index3 -> wire4. Runtime callbacks rc1/2/3 observed.
/// These are speech-boundary notifications, not microphone start/stop commands.
public enum AssistantVADPrototype {
    public enum Status: Int, CaseIterable { case start = 1, stop = 2, timeout = 3 }
    public static func status(_ status: Status) -> Data {
        let body = Data("{\"rc\":\(status.rawValue)}".utf8)
        return Data([8,1,16,4,26,UInt8(body.count)]) + body + Data([34,0])
    }
}
