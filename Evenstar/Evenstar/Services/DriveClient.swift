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
    func listAudioFiles(inFolder folderID: String) async throws -> [DriveFile] {
        guard !apiKey.isEmpty else { throw DriveError.missingAPIKey }

        var files: [DriveFile] = []
        var pageToken: String?

        repeat {
            let (data, response) = try await fetch(page: pageToken, folderID: folderID)
            try Self.check(response)
            let page = try Self.decodePage(data)
            files.append(contentsOf: page.files.filter { $0.mimeType.hasPrefix("audio/") })
            pageToken = page.nextPageToken
        } while pageToken != nil

        return files
    }

    /// Where the bytes of one file are. `alt=media` returns content rather than
    /// metadata, and supports the range requests `AVPlayer` streams with.
    static func mediaURL(fileID: String) -> URL {
        URL(string: "\(base)/\(fileID)?alt=media&key=\(DriveAPIKey.value)")!
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
        } catch {
            throw DriveError.offline
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
