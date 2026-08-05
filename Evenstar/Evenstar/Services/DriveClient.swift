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
    case quotaExceeded
    case server(Int)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Chưa cấu hình API key cho Google Drive."
        case .notShared:
            "Thư mục này chưa được chia sẻ công khai. Trên Drive, đổi quyền thành “bất kỳ ai có liên kết”."
        case .notFound:
            "Không tìm thấy thư mục. Link có thể sai hoặc thư mục đã bị xoá."
        case .offline:
            "Không có kết nối mạng."
        case .connectionFailed:
            "Không thể kết nối tới Google Drive. Vui lòng thử lại sau."
        case .quotaExceeded:
            "Đã vượt hạn ngạch truy cập Google Drive. Thử lại sau ít phút."
        case .server(let status):
            "Google Drive trả về lỗi \(status)."
        case .malformedResponse:
            "Không đọc được dữ liệu Google Drive trả về."
        }
    }
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
    func listAudioFiles(inFolder folderID: String) async throws -> [DriveFile] {
        guard !apiKey.isEmpty else { throw DriveError.missingAPIKey }

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
        } catch let urlError as URLError where Self.isConnectivityFailure(urlError.code) {
            throw DriveError.offline
        } catch {
            // Everything else `URLSession` can throw — DNS failure, TLS/
            // certificate failure, timeout, and any error this client does
            // not specifically recognize. Distinct from `.offline`: the
            // device can be fully online while one of these happens, and
            // saying "no internet" would be flatly wrong.
            throw DriveError.connectionFailed
        }
    }

    /// Whether a `URLError` genuinely means "this device has no network
    /// connectivity" as opposed to some other transport failure (DNS, TLS,
    /// timeout) that can happen on a fully-online device.
    private static func isConnectivityFailure(_ code: URLError.Code) -> Bool {
        switch code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            return true
        default:
            return false
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
