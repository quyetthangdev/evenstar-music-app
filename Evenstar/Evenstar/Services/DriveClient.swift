import Foundation

// ⚠️ TEMPORARY STUB — REPLACE IN TASK 4 (Drive networking).
//
// This file sits at the exact path Task 4's brief says to *create*
// (`Evenstar/Evenstar/Services/DriveClient.swift`), so that step is an
// overwrite rather than a second declaration. It deliberately does not live
// beside `DriveLinkParser` under `Features/Drive/`, even though that would be
// the tidier home: with Xcode 16 synced folders both files would join the
// target and Task 4 would hit `invalid redeclaration of 'DriveClient'` — an
// error naming neither file's real problem, whose obvious "fix" (rename one)
// leaves `Playable.playbackURL()` still calling this stub with the suite green.
//
// Task 3 needs `DriveTrack.playbackURL()` to hand `AVPlayer` an https URL, but
// the real `DriveClient` — folder listing, redirect/confirm-token handling,
// error surface — is Task 4's deliverable. This file exists only so Task 3
// compiles and its tests can assert that a Drive track reports an https URL
// rather than a file URL.
//
// What Task 4 must replace:
//   • the whole type. `mediaURL(fileID:)` here is a bare string template with
//     no verification that the URL actually streams: Google answers a
//     `/uc?export=download` request for a large file with an HTML interstitial
//     carrying a confirm token, not with bytes, and this stub knows nothing
//     about that. Do not assume the URL below is correct simply because the
//     Task 3 tests are green — they only check the scheme.
//   • the `enum` shape, if Task 4 needs instance state (a `URLSession`, a
//     cache). Nothing outside `Playable.swift` calls into this yet, so the
//     shape is free to change.

/// Placeholder for the Task 4 Google Drive client.
enum DriveClient {
    /// The address `AVPlayer` should stream a public Drive file from.
    ///
    /// **Stub.** See the file header: this is the well-known direct-download
    /// form and nothing has confirmed it serves audio bytes for the files this
    /// app will meet.
    static func mediaURL(fileID: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "drive.google.com"
        components.path = "/uc"
        components.queryItems = [
            URLQueryItem(name: "export", value: "download"),
            URLQueryItem(name: "id", value: fileID)
        ]
        // `URLComponents` with a scheme, host and absolute path always yields a
        // URL; the fallback only exists because the property is optional. It is
        // deliberately unplayable rather than a plausible-looking address, so a
        // regression here fails loudly instead of streaming the wrong thing.
        return components.url ?? URL(fileURLWithPath: "/dev/null")
    }
}
