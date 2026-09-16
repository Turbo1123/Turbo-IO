import Foundation
import RayNeoProtocol

/// App-level choices. The native-follow value is a hardware trial candidate,
/// not a verified general RayNeo teleprompter protocol enum.
enum GlassesPrompterMode: String, CaseIterable {
    case constantSpeed
    case nativeFollowTrial

    var canAdjustSpeed: Bool { self == .constantSpeed }

    func preparationPayload(did: String, total: Int, speed: Int) -> [String: Any] {
        ["action": 1, "did": did, "total": total,
         "scroll": self == .constantSpeed ? 2 : 1, "speed": speed,
         "pageOffset": 0, "highLightOffset": 0]
    }

    static func isOpaqueAudio(business: UInt8, packet: Data) -> Bool {
        guard business == 20, let metadata = try? BusinessEnvelopeMetadata.inspect(packet) else { return false }
        return metadata.version == 1 && metadata.messageType == 9
    }
}
