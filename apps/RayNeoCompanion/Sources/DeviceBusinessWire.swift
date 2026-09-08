import Foundation
import CoreFoundation
import RayNeoProtocol

/// Version-pinned business envelope. Never a transport frame or authentication API.
struct DeviceBusinessWire {
    let type: UInt32
    let json: [String: Any]
    let bytes: Data
    static func encode(type: UInt32, json: [String: Any], bytes: Data = Data()) throws -> Data {
        let body = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        guard body.count <= 65_536, bytes.count <= 65_536 else { throw DeviceFeatureError.invalidPacket }
        var out = Data([8, 1, 16]); put(UInt64(type), into: &out)
        out.append(26); put(UInt64(body.count), into: &out); out.append(body)
        if !bytes.isEmpty { out.append(34); put(UInt64(bytes.count), into: &out); out.append(bytes) }
        return out
    }
    init(_ packet: Data) throws {
        let meta = try BusinessEnvelopeMetadata.inspect(packet)
        guard meta.version == 1, let type = meta.messageType,
              (meta.messageBytes ?? 0) <= 65_536, (meta.dataBytes ?? 0) <= 65_536 else { throw DeviceFeatureError.invalidPacket }
        self.type = type
        let a = [UInt8](packet); var i = 0; var body = Data(); var audio = Data()
        func read() -> UInt64 {
            var n: UInt64 = 0, shift = 0
            while i < a.count { let b = a[i]; i += 1; n |= UInt64(b & 127) << shift; if b < 128 { break }; shift += 7 }
            return n
        }
        // inspect above has already checked every varint, range and singular tag.
        while i < a.count {
            let key = read()
            switch key & 7 {
            case 0: _ = read()
            case 1: i += 8
            case 5: i += 4
            default:
                let n = Int(read()); let data = Data(a[i..<(i+n)]); i += n
                if key >> 3 == 3 { body = data }; if key >> 3 == 4 { audio = data }
            }
        }
        if body.isEmpty { json = [:] }
        else {
            guard let object = try JSONSerialization.jsonObject(with: body) as? [String: Any] else { throw DeviceFeatureError.invalidPacket }
            json = object
        }
        bytes = audio
    }
    private static func put(_ value: UInt64, into data: inout Data) {
        var n = value
        while n >= 128 { data.append(UInt8(n & 127) | 128); n >>= 7 }; data.append(UInt8(n))
    }
    static func integer(_ json: [String: Any], _ key: String) -> Int64? {
        guard let n = json[key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
              n.doubleValue.isFinite, n.doubleValue.rounded(.towardZero) == n.doubleValue,
              n.doubleValue >= -9_007_199_254_740_991, n.doubleValue <= 9_007_199_254_740_991 else { return nil }
        return n.int64Value
    }
    static func identifier(_ json: [String: Any], _ key: String) -> String? {
        guard let s = json[key] as? String, !s.isEmpty, s.utf8.count <= 128,
              s.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }; return s
    }
    static func boolean(_ json: [String:Any], _ key: String) -> Bool? {
        guard let n = json[key] as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return nil }
        return n.boolValue
    }
}

enum DeviceFeatureError: LocalizedError {
    case invalidPacket, disconnected, busy, noSession, incomplete, conflictingBytes, storageLimit, unsupportedFile
    var errorDescription: String? {
        switch self {
        case .invalidPacket: return "协议字段无效，未发送或应用。"
        case .disconnected: return "需要唯一已认证的眼镜连接；模拟器不会发包。"
        case .busy: return "请先结束语音会话或当前眼镜任务。"
        case .noSession: return "没有匹配的本机任务，未修改其他设备内容。"
        case .incomplete: return "录音缺少完成消息或存在数据空洞；原始文件已保留，不标完整。"
        case .conflictingBytes: return "同一录音位置收到不同字节，已停止封装并保留原件。"
        case .storageLimit: return "超过本机接收限制，已停止新增接收；没有删除眼镜文件。"
        case .unsupportedFile: return "音频包格式未通过验证；保留原始文件，不生成伪成功音频。"
        }
    }
}
