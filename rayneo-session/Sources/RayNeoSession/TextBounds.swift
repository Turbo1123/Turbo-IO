import Foundation

enum TextBounds {
    /// Cap UTF-8 traversal before grapheme counting: a single grapheme can contain many scalars.
    static func contains(_ text: String, maximumCharacters: Int, maximumUTF8Bytes: Int) -> Bool {
        guard text.utf8.prefix(maximumUTF8Bytes + 1).count <= maximumUTF8Bytes else { return false }
        return text.count <= maximumCharacters
    }

    static func boundedPrefix(_ text: String, maximumCharacters: Int, maximumUTF8Bytes: Int) -> String {
        var scalars = String.UnicodeScalarView()
        var byteCount = 0
        for scalar in text.unicodeScalars {
            let bytes = scalar.utf8.count
            guard byteCount + bytes <= maximumUTF8Bytes else { break }
            scalars.append(scalar); byteCount += bytes
        }
        return String(String(scalars).prefix(maximumCharacters))
    }
}
