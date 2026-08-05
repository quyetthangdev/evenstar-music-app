import Foundation

/// Turns whatever the user pasted into a Drive folder ID.
///
/// Separate from `DriveClient` and free of networking, because this is string
/// handling with many shapes and one of them — a *file* link rather than a
/// folder link — fails in a way that looks like an empty folder rather than
/// like an error. Cheap to test exhaustively; expensive to debug in the wild.
enum DriveLinkParser {
    /// Characters Drive uses in its IDs. Anything else ends the ID.
    private static let idCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
    )

    /// The folder ID, or `nil` if this is not a Drive *folder* reference.
    static func folderID(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // A file link deliberately fails rather than falling through to the
        // bare-ID branch below, which would otherwise accept its ID and query
        // it as a folder.
        if trimmed.contains("/file/d/") { return nil }

        // Only look for /folders/ or id= on an actual Drive host. Otherwise
        // e.g. "https://example.com/drive/folders/abc" would be accepted
        // just because its path happens to contain "/folders/".
        if trimmed.contains("drive.google.com") {
            if let range = trimmed.range(of: "/folders/") {
                return id(from: trimmed[range.upperBound...])
            }
            if let range = trimmed.range(of: "id=") {
                return id(from: trimmed[range.upperBound...])
            }
            return nil
        }

        // A bare ID: no scheme, no slashes, only ID characters, and long
        // enough not to be an ordinary word. Real Drive IDs run 25+
        // characters; this threshold just needs to clear short words like
        // "hello" without rejecting any real ID.
        if !trimmed.contains("/"), !trimmed.contains(":"), trimmed.count >= 10, isID(trimmed) {
            return trimmed
        }
        return nil
    }

    private static func id(from rest: Substring) -> String? {
        let candidate = rest.prefix { character in
            character.unicodeScalars.allSatisfy(idCharacters.contains)
        }
        return candidate.isEmpty ? nil : String(candidate)
    }

    private static func isID(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy(idCharacters.contains)
    }
}
