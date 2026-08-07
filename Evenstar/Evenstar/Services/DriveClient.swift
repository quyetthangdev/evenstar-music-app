import Foundation

struct DriveFile {
    let id: String
    let name: String
    let mimeType: String
}

enum DriveError: Error, Equatable, LocalizedError {
    case missingAPIKey
    case notShared
    case notFound
    case offline
    /// A transport failure that is not "the device has no connectivity" —
    /// DNS, TLS/certificate, timeouts, and anything else `URLSession` can
    /// throw that `.offline` would misdescribe. Kept apart from `.offline` so
    /// the message never claims something untrue about the user's connection
    /// on a device that is, in fact, online.
    case connectionFailed
    /// The server answered while the track was loading or playing, and the
    /// answer was not the bytes: a 403/404 for a file deleted from Drive or a
    /// folder whose sharing was revoked, a rejected range request, a body that
    /// is an error document rather than audio.
    ///
    /// Kept apart from `.connectionFailed` because the two ask for opposite
    /// things from the user. "Không thể kết nối tới Google Drive. Vui lòng thử
    /// lại sau." is advice for a connection that is down; here the connection is
    /// fine, the file is gone, and waiting fixes nothing. It is also the only
    /// classification `PlaybackService.handleFailure` skips forward on — see the
    /// spec's error table, "File deleted from Drive mid-playback → Skip to next,
    /// note it."
    ///
    /// **A 429 that arrives on the playback path lands here too, and that is a
    /// known limitation rather than a slip.** The listing path reads a real
    /// `HTTPURLResponse.statusCode` and distinguishes 429 from 403 exactly (see
    /// `DriveClient.check`); `AVPlayer` never hands one back, so on the playback
    /// path a quota rejection and a revoked share are the same shape and cannot
    /// honestly be told apart. Both mean "Drive refused to serve this file",
    /// which is what the message below says, and the two most likely causes are
    /// what it names.
    case fileUnavailable
    case quotaExceeded
    case server(Int)
    case malformedResponse

    /// Localised at the point of use, like every other `errorDescription` in
    /// the app — a plain `String` never reaches the catalogue. See
    /// `ImportError`.
    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            String(localized: "Chưa cấu hình API key cho Google Drive.")
        case .notShared:
            String(localized: "Thư mục này chưa được chia sẻ công khai. Trên Drive, đổi quyền thành “bất kỳ ai có liên kết”.")
        case .notFound:
            String(localized: "Không tìm thấy thư mục. Link có thể sai hoặc thư mục đã bị xoá.")
        case .offline:
            String(localized: "Không có kết nối mạng.")
        case .connectionFailed:
            String(localized: "Không thể kết nối tới Google Drive. Vui lòng thử lại sau.")
        case .fileUnavailable:
            String(localized: "Không phát được bài này. Tệp có thể đã bị xoá khỏi Drive hoặc thư mục không còn được chia sẻ.")
        case .quotaExceeded:
            String(localized: "Đã vượt hạn ngạch truy cập Google Drive. Thử lại sau ít phút.")
        case .server(let status):
            String(localized: "Google Drive trả về lỗi \(status).")
        case .malformedResponse:
            String(localized: "Không đọc được dữ liệu Google Drive trả về.")
        }
    }

    /// Maps a transport-layer error onto the case whose `errorDescription` says
    /// something true about it, in Vietnamese.
    ///
    /// Lives here rather than inside `DriveClient.fetch` because it now has two
    /// callers: `fetch`, and `StreamingAudioPlayer`, which hands on whatever
    /// `AVPlayerItem` reports. Without this the streaming path would surface a
    /// raw `URLError` and the banner would read "The Internet connection appears
    /// to be offline" — English, in an app whose copy is Vietnamese throughout.
    /// One implementation, so the two paths cannot drift into describing the
    /// same failure differently.
    ///
    /// Bridges through `NSError` rather than casting to `URLError`, because
    /// `AVPlayerItem.error` is an `AVFoundationErrorDomain` error that carries
    /// the real cause under `NSUnderlyingErrorKey` — a plain `as? URLError`
    /// misses it and reports every streaming failure as `.connectionFailed`,
    /// including a genuinely offline device.
    /// The order matters, and connectivity has to be tested first: a device
    /// with no network can report `.badServerResponse` on a retry, and calling
    /// that "the file is gone" would send the user hunting for a file that is
    /// still there.
    static func classify(_ error: Error) -> DriveError {
        let chain = underlyingChain(error as NSError)
        if chain.contains(where: isConnectivityFailure) { return .offline }
        // The server answered, and the answer was not the file. Its own case and
        // its own message, because "thử lại sau" is wrong advice for it — see
        // `.fileUnavailable`.
        if chain.contains(where: isFileUnavailable) { return .fileUnavailable }
        // Everything else `URLSession` or `AVFoundation` can report — DNS
        // failure, TLS/certificate failure, timeout, a malformed stream, and
        // anything unrecognised. Deliberately distinct from `.offline`: the
        // device can be fully online while one of these happens, and saying
        // "no internet" would be flatly wrong.
        return .connectionFailed
    }

    /// The error and everything nested under `NSUnderlyingErrorKey`, outermost
    /// first.
    ///
    /// `AVPlayerItem.error` is an `AVFoundationErrorDomain` wrapper whose real
    /// cause hangs underneath, and on the streaming path that nesting is
    /// sometimes two deep rather than one — an `AVFoundationErrorDomain` error
    /// wrapping an `NSOSStatusErrorDomain`/`CoreMediaErrorDomain` one wrapping
    /// the `URLError`. The previous single-level unwrap read the outer two and
    /// stopped, so a genuinely offline device three levels down was reported as
    /// a generic connection failure.
    ///
    /// Bounded rather than a plain `while`: nothing stops a framework from
    /// handing back an error whose underlying error is itself, and an unbounded
    /// walk over that hangs the failure path.
    private static func underlyingChain(_ error: NSError) -> [NSError] {
        var chain: [NSError] = []
        var current: NSError? = error
        while let next = current, chain.count < 8 {
            chain.append(next)
            current = next.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return chain
    }

    /// Whether an error genuinely means "this device has no network
    /// connectivity" as opposed to some other transport failure (DNS, TLS,
    /// timeout) that can happen on a fully-online device.
    private static func isConnectivityFailure(_ error: NSError) -> Bool {
        guard error.domain == NSURLErrorDomain else { return false }
        switch URLError.Code(rawValue: error.code) {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            return true
        default:
            return false
        }
    }

    /// Whether an error means the server replied and the reply was not the file.
    ///
    /// Two shapes, because the streaming path can report the same HTTP answer
    /// through either:
    ///
    /// 1. **`NSURLErrorDomain`**, when `URLSession` itself judged the response.
    ///    `.fileDoesNotExist` and `.resourceUnavailable` are the direct 404
    ///    shapes; `.userAuthenticationRequired` and `.noPermissionsToReadFile`
    ///    are the 401/403 ones a folder whose sharing was revoked produces;
    ///    `.badServerResponse` and `.cannotParseResponse` are what a Drive JSON
    ///    error document delivered where audio was expected looks like; and
    ///    `.zeroByteResource` is an empty body.
    /// 2. **`CoreMediaErrorDomain`** (bridged into `NSOSStatusErrorDomain` on
    ///    some paths), when AVFoundation's own HTTP loader judged it. These
    ///    codes are not in any header Apple publishes; they are the ones
    ///    consistently observed for an HTTP error status behind a progressive
    ///    download — `-12660` for a 403, `-12661` for an unusable response,
    ///    `-12938`/`-12939` for a range request the server answered with an
    ///    error document instead of bytes, and `-12937` for a truncated one.
    ///
    /// **Undocumented and unverified against real Drive traffic.** Reaching this
    /// list needs a live API key and a folder whose file is deleted mid-track,
    /// which this repository has neither of. The failure mode if a code is
    /// missing is the old behaviour — the message says "connection failed" —
    /// rather than anything new breaking, so the list is kept to codes with a
    /// specific HTTP meaning rather than widened speculatively. In particular
    /// `AVFoundationErrorDomain`'s "file format not recognized" is deliberately
    /// *not* here: a genuinely corrupt audio file produces it too, and telling
    /// the user their file was deleted from Drive when it is sitting there is a
    /// worse answer than the generic one.
    private static func isFileUnavailable(_ error: NSError) -> Bool {
        if error.domain == NSURLErrorDomain {
            switch URLError.Code(rawValue: error.code) {
            case .fileDoesNotExist, .resourceUnavailable, .badServerResponse,
                 .cannotParseResponse, .userAuthenticationRequired,
                 .noPermissionsToReadFile, .zeroByteResource:
                return true
            default:
                return false
            }
        }
        if error.domain == coreMediaDomain || error.domain == NSOSStatusErrorDomain {
            return httpRejectionCodes.contains(error.code)
        }
        return false
    }

    private static let coreMediaDomain = "CoreMediaErrorDomain"
    private static let httpRejectionCodes: Set<Int> = [-12660, -12661, -12937, -12938, -12939]
}

/// Reads a link-shared Drive folder with a plain API key. No OAuth, no SDK.
///
/// Deliberately knows nothing about SwiftData: it answers questions about
/// Drive and returns plain values, which is what lets every test here run
/// against a stubbed `URLProtocol` instead of the network.
struct DriveClient {
    private let apiKey: String
    private let session: URLSession
    private static let base = "https://www.googleapis.com/drive/v3/files"

    /// The key is injected rather than read from `DriveAPIKey` inside, so tests
    /// can supply one without making the real key a mutable global that every
    /// test in the suite shares.
    init(apiKey: String = DriveAPIKey.value, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    /// Every audio file directly inside `folderID`.
    ///
    /// **Follows `nextPageToken` to the end.** Drive returns at most 100 files
    /// per page, so stopping at the first page turns a 300-song folder into a
    /// 100-song folder with no error anywhere — a bug that looks exactly like a
    /// smaller folder.
    ///
    /// **Cannot loop forever.** If a page's `nextPageToken` is the same token
    /// that was just used to fetch it — a backend hiccup, eventual-consistency
    /// skew — that is not a next page; following it would refetch the same
    /// page indefinitely, an unbounded hang with no error. Treated the same as
    /// any other response shape the client cannot make sense of.
    ///
    /// **`folderID` is validated here rather than trusted.** It is interpolated
    /// into a quoted Drive query string — `q='<folderID>' in parents and
    /// trashed=false` — where an apostrophe would close the quote early and the
    /// rest of the value would be read as query syntax. Today every caller's ID
    /// has come through `DriveLinkParser`, which already restricts it to
    /// `[A-Za-z0-9_-]`, so nothing is exploitable in the shipping app; that is a
    /// property of one caller, not of this method, and a second caller — a
    /// deep link, a restored row, a future import — would inherit the hole
    /// silently. Checking it where the interpolation happens closes it for good.
    func listAudioFiles(inFolder folderID: String) async throws -> [DriveFile] {
        guard !apiKey.isEmpty else { throw DriveError.missingAPIKey }
        // `.notFound` rather than a new case: an ID that cannot be a Drive
        // folder ID names no folder, and "Link có thể sai hoặc thư mục đã bị
        // xoá." is exactly what the user needs to hear about it.
        guard Self.isPlausibleFolderID(folderID) else { throw DriveError.notFound }

        var files: [DriveFile] = []
        var pageToken: String?

        repeat {
            let (data, response) = try await fetch(page: pageToken, folderID: folderID)
            try Self.check(response)
            let page = try Self.decodePage(data)
            files.append(contentsOf: page.files.filter { $0.mimeType.hasPrefix("audio/") })

            if let next = page.nextPageToken, next == pageToken {
                throw DriveError.malformedResponse
            }
            pageToken = page.nextPageToken
        } while pageToken != nil

        return files
    }

    /// The character set a Google Drive folder ID is drawn from, and the same
    /// one `DriveLinkParser` accepts. Deliberately a whitelist: a blacklist of
    /// "characters that break the query" has to enumerate the ways a quoted
    /// string can be escaped, and a whitelist does not.
    private static let folderIDCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"
    )

    static func isPlausibleFolderID(_ folderID: String) -> Bool {
        !folderID.isEmpty
            && folderID.unicodeScalars.allSatisfy(folderIDCharacters.contains)
    }

    /// Returned by `mediaURL(fileID:)` instead of a URL with `key=` left blank
    /// when no API key is configured.
    ///
    /// `Playable.playbackURL() -> URL` (see `Playable.swift`) is non-throwing
    /// and has no `DriveClient` instance to hold — the real case is a saved
    /// `DriveTrack` resumed on relaunch, before the app has listed anything
    /// and without a client around to ask. `mediaURL` can't throw there and
    /// can't return `nil` without breaking that call site, so a missing key
    /// has to become a *distinguishable* URL instead of a googleapis URL that
    /// looks legitimate but silently carries an empty `key=`. Recognizable by
    /// a test, or by anything downstream that wants to check
    /// `url == DriveClient.missingAPIKeyURL` before handing a URL to
    /// `AVPlayer`.
    ///
    /// **Must keep the `https` scheme.** `DriveTrack.playbackURL()` reports
    /// this URL as-is, and `PlayableQueueTests.
    /// testEachSourceReportsItsOwnKindOfURL` — a Task 3 invariant, not
    /// negotiable here — asserts every Drive track's `playbackURL()` has
    /// scheme `"https"` regardless of whether it will actually play. `.invalid`
    /// is a reserved TLD (RFC 2606) that can never resolve to a real host, so
    /// this is distinguishable by host from a genuine googleapis URL while
    /// still satisfying that scheme check.
    static let missingAPIKeyURL = URL(string: "https://drive-error.invalid/missing-api-key")!

    /// Where the bytes of one file are. `alt=media` returns content rather than
    /// metadata, and supports the range requests `AVPlayer` streams with.
    ///
    /// `apiKey` defaults to `DriveAPIKey.value` so existing callers are
    /// unaffected, but — unlike before — is a parameter rather than a read of
    /// the global from inside the function: it can be exercised with any key,
    /// not only the empty one this repository ships.
    static func mediaURL(fileID: String, apiKey: String = DriveAPIKey.value) -> URL {
        guard !apiKey.isEmpty else { return missingAPIKeyURL }
        return URL(string: "\(base)/\(fileID)?alt=media&key=\(apiKey)")!
    }

    private func fetch(page: String?, folderID: String) async throws -> (Data, URLResponse) {
        var components = URLComponents(string: Self.base)!
        var items = [
            URLQueryItem(name: "q", value: "'\(folderID)' in parents and trashed=false"),
            URLQueryItem(name: "fields", value: "nextPageToken,files(id,name,mimeType)"),
            URLQueryItem(name: "pageSize", value: "100"),
            URLQueryItem(name: "key", value: apiKey),
        ]
        if let page { items.append(URLQueryItem(name: "pageToken", value: page)) }
        components.queryItems = items

        do {
            return try await session.data(from: components.url!)
        } catch let urlError as URLError where urlError.code == .cancelled {
            // A cancelled request — routinely, the caller's enclosing `Task`
            // being cancelled because the user navigated away mid-load — is
            // not a failure to report. Rethrown as itself, not wrapped as a
            // `DriveError`, so it never reaches `errorDescription` and is
            // never shown to the user.
            throw urlError
        } catch {
            // Classification moved to `DriveError.classify` so the streaming
            // player reaches the same conclusion about the same failure.
            throw DriveError.classify(error)
        }
    }

    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw DriveError.malformedResponse }
        switch http.statusCode {
        case 200..<300: return
        case 401, 403: throw DriveError.notShared
        case 404: throw DriveError.notFound
        case 429: throw DriveError.quotaExceeded
        default: throw DriveError.server(http.statusCode)
        }
    }

    private struct Page: Decodable {
        struct Item: Decodable {
            let id: String
            let name: String
            let mimeType: String
        }
        let files: [Item]
        let nextPageToken: String?
    }

    private static func decodePage(_ data: Data) throws -> (files: [DriveFile], nextPageToken: String?) {
        guard let page = try? JSONDecoder().decode(Page.self, from: data) else {
            throw DriveError.malformedResponse
        }
        return (page.files.map { DriveFile(id: $0.id, name: $0.name, mimeType: $0.mimeType) },
                page.nextPageToken)
    }
}
