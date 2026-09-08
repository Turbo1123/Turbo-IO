import Foundation

/// Only field names and a few explicitly selected control values. Never emits
/// serials, addresses, credentials, user texts or arbitrary JSON values.
enum LauncherStructure {
    static func inspect(_ data: Data) -> String {
        guard data.count <= 65536 else { return "oversize" }
        if let root = (try? JSONSerialization.jsonObject(with:data)) as? [String:Any] { return jsonKeys(root) }
        let bytes = [UInt8](data)
        var offset = 0, fields: [String] = []
        func varint() throws -> UInt64 {
            var value: UInt64 = 0
            for i in 0..<10 {
                guard offset < bytes.count else { throw ParseError.invalid }
                let byte = bytes[offset]; offset += 1
                if i == 9 && byte > 1 { throw ParseError.invalid }
                value |= UInt64(byte & 127) << (i*7)
                if byte & 128 == 0 { return value }
            }
            throw ParseError.invalid
        }
        do {
            while offset < bytes.count {
                guard fields.count < 64 else { throw ParseError.invalid }
                let tag = try varint(), field = tag >> 3, wire = tag & 7
                guard field > 0 && field <= 0x1fffffff else { throw ParseError.invalid }
                if wire == 0 {
                    let value = try varint()
                    fields.append("f\(field):varint="+(value <= 65535 ? String(value) : "large"))
                }
                else if wire == 2 {
                    let count = try varint()
                    guard count <= bytes.count-offset else { throw ParseError.invalid }
                    let value = Data(bytes[offset..<(offset+Int(count))]); offset += Int(count)
                    var detail = "f\(field):bytes=\(count)"
                    if let root = (try? JSONSerialization.jsonObject(with:value)) as? [String:Any] {
                        detail += " JSON{"+jsonKeys(root)+"}"
                    } else if let text = String(data:value,encoding:.utf8),
                        text.range(of:"^(general_|request_general_|set_ai_|glasses_)[a-z_]{1,48}$",options:.regularExpression) != nil {
                        detail += " control="+text
                    }
                    fields.append(detail)
                } else {
                    let count = wire == 1 ? 8 : wire == 5 ? 4 : -1
                    guard count >= 0 && offset+count <= bytes.count else { throw ParseError.invalid }
                    offset += count; fields.append("f\(field):fixed\(count)")
                }
            }
            return fields.joined(separator:";")
        } catch { return "unrecognized-container" }
    }
    private enum ParseError: Error { case invalid }
    private static func jsonKeys(_ root: [String:Any]) -> String {
        var result: [String] = [], controls: [String] = []
        func walk(_ value: [String:Any], _ path: String, _ depth: Int) {
            guard depth <= 2, result.count < 60 else { return }
            for key in value.keys.sorted().prefix(35) {
                guard key.range(of:"^[A-Za-z_][A-Za-z_0-9]{0,63}$",options:.regularExpression) != nil else { continue }
                let full = path.isEmpty ? key : path+"."+key
                result.append(full)
                if key == "rc", path.isEmpty, let scalar = value[key] as? NSNumber,
                   scalar.doubleValue >= 0 && scalar.doubleValue <= 255 {
                    controls.append("rc="+scalar.stringValue)
                }
                if ["type","cmd","command","action","method"].contains(key), let text = value[key] as? String,
                   text.range(of:"^[a-z_]{1,64}$",options:.regularExpression) != nil { result.append(full+"="+text) }
                if ["voiceWakeup","voice_wakeup","ai_voice_wakeup"].contains(key), let boolean = value[key] as? Bool {
                    controls.append(full+"="+String(boolean))
                }
                if ["mode","value"].contains(key), path == "payload", let scalar = value[key] as? NSNumber,
                   scalar.doubleValue >= 0 && scalar.doubleValue <= 255 { controls.append(full+"="+scalar.stringValue) }
                if key == "mode", path == "payload", let mode = value[key] as? String,
                   mode.range(of:"^[a-z_]{1,20}$",options:.regularExpression) != nil { controls.append(full+"="+mode) }
                if let nested = value[key] as? [String:Any] { walk(nested,full,depth+1) }
                else if key == "data", path == "payload", let text = value[key] as? String,
                        let data = text.data(using:.utf8), data.count <= 8192,
                        let nested = (try? JSONSerialization.jsonObject(with:data)) as? [String:Any] { walk(nested,full,depth+1) }
            }
        }
        walk(root,"",0)
        return controls.joined(separator:",")+" KEYS:"+String(result.joined(separator:",").prefix(650))
    }
}
