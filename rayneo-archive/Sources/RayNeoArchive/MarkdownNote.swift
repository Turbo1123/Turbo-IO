import Foundation
import CryptoKit

func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func transcriptInputDigest(title: String, text: String) throws -> String {
    // Length-safe canonical encoding prevents ambiguous concatenations.
    digest(try JSONEncoder().encode([title, text]))
}

func markdownNote(recording: ArchivedRecording, revision: Int, title: String, text: String, date: Date) throws -> Data {
    func quoted(_ value: String) throws -> String {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }
    func plain(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let punctuation = Set("\\`*_{}[]()#+-.!|~")
        return escaped.map { punctuation.contains($0) ? "\\\($0)" : String($0) }.joined()
    }
    let iso = ISO8601DateFormatter()
    var lines = [
        "---",
        "title: \(try quoted(title))",
        "recording_id: \(try quoted(recording.id.uuidString.lowercased()))",
        "imported_at: \(try quoted(iso.string(from: recording.importedAt)))",
        "note_created_at: \(try quoted(iso.string(from: date)))",
        "sha256: \(try quoted(recording.sha256))",
        "audio_bytes: \(recording.byteCount)",
        "revision: \(revision)",
        "transcript_source: \"host_provided\"",
        "audio_decoding: \"not_assessed\"",
        "speech_recognition: \"not_performed_by_archive\"",
        "server_upload: \"not_performed\""
    ]
    if let recordedAt = recording.recordedAt {
        lines.append("recorded_at: \(try quoted(iso.string(from: recordedAt)))")
    }
    lines += ["---", "", "# \(plain(title))", "", "[打开本地音频](../\(recording.audioRelativePath))", "",
              "文字由宿主应用提供；本归档包未执行语音识别、音频解码或上传。", "", "## 转写文本", ""]
    lines += text.components(separatedBy: "\n").map {
        "> " + plain($0.replacingOccurrences(of: "\t", with: "    "))
    }
    lines.append("")
    return Data(lines.joined(separator: "\n").utf8)
}
