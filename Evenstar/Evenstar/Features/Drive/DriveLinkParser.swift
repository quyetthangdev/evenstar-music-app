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

        // A file link is rejected here as an explicit, named first line of
        // defense. It is not actually what keeps a file link out of the
        // bare-ID branch below — that branch requires no "/" at all, and any
        // full URL fails that on its own — nor is it the only thing that
        // rejects it: the domain-scoped block below also falls through to
        // nil for a file link, since "/file/d/.../view" matches neither
        // "/folders/" nor "id=". This guard is kept anyway so the rejection
        // is explicit and doesn't silently depend on those other branches'
        // shapes staying exactly as they are.
        if trimmed.contains("/file/d/") { return nil }

        // /uc is Drive's direct-download endpoint and is only ever a file —
        // "https://drive.google.com/uc?id=FILEID" and its
        // "...&export=download" variant are the commonest direct-download
        // links Google hands out. Reject it before the id= branch below
        // would otherwise treat the file ID as a folder ID.
        //
        // /open?id= is different and deliberately NOT rejected here: Google
        // genuinely uses /open?id= for both files and folders, so no amount
        // of string parsing can tell them apart, and the brief requires
        // accepting it. /uc, unlike /open, is unambiguous — it never means
        // a folder — which is what makes it safe to reject outright.
        if trimmed.contains("/uc?") { return nil }

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
        // enough to be a real Drive ID rather than an ordinary word. Real
        // Drive folder IDs run 28-44 characters; 28 is the floor, pinned by
        // testRejectsBareIDsShorterThanRealDriveIDs so it can't quietly
        // drift down and start accepting words like "screenshot1" again.
        if !trimmed.contains("/"), !trimmed.contains(":"), trimmed.count >= 28, isID(trimmed) {
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
