import Foundation

/// One track as the catalogue describes it. Not a stored row — see
/// `JamendoTrack` for what saving produces.
struct JamendoCatalogueTrack: Equatable, Identifiable {
    let id: String
    let title: String
    let artistName: String
    let albumTitle: String
    let durationSeconds: Double
    let audioURL: URL
    let coverURL: URL?
    let licenceURL: URL?
    let shareURL: URL?
}

/// Reads Jamendo's public catalogue.
///
/// A `struct` with an injected `URLSession`, exactly like `DriveClient`, so the
/// suite drives it through `StubURLProtocol` and no test touches the network.
struct JamendoClient {
    private let clientID: String
    private let session: URLSession

    init(clientID: String = JamendoAPIKey.value, session: URLSession = .shared) {
        self.clientID = clientID
        self.session = session
    }

    func search(_ query: String, commercialOnly: Bool) async throws -> [JamendoCatalogueTrack] {
        try await get([
            URLQueryItem(name: "search", value: query)
        ], commercialOnly: commercialOnly)
    }

    func trending(commercialOnly: Bool) async throws -> [JamendoCatalogueTrack] {
        try await get([
            URLQueryItem(name: "order", value: "popularity_total")
        ], commercialOnly: commercialOnly)
    }

    func tracks(inGenre genre: String, commercialOnly: Bool) async throws -> [JamendoCatalogueTrack] {
        try await get([
            URLQueryItem(name: "tags", value: genre),
            URLQueryItem(name: "order", value: "popularity_total")
        ], commercialOnly: commercialOnly)
    }

    // MARK: - Private

    private static let limit = "50"

    private func get(
        _ items: [URLQueryItem],
        commercialOnly: Bool
    ) async throws -> [JamendoCatalogueTrack] {
        guard !clientID.isEmpty else { throw JamendoError.missingClientID }

        var components = URLComponents(string: "https://api.jamendo.com/v3.0/tracks/")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "limit", value: Self.limit),
            URLQueryItem(name: "audioformat", value: "mp32")
        ] + items + JamendoLicencePolicy.queryItems(commercialOnly: commercialOnly)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: components.url!)
        } catch let error as URLError where error.code == .cancelled {
            // A cancelled request — routinely, the caller's enclosing `Task`
            // being cancelled because the user typed another character into
            // search — is not a failure to report. Rethrown as itself, not
            // wrapped as a `JamendoError`, so it never reaches
            // `errorDescription` and is never shown to the user. Mirrors
            // `DriveClient.fetch`.
            throw error
        } catch let error as URLError where error.code == .notConnectedToInternet {
            throw JamendoError.offline
        } catch {
            throw JamendoError.connectionFailed
        }

        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200...299: break
            case 429: throw JamendoError.rateLimited
            case 404: throw JamendoError.notFound
            default: throw JamendoError.connectionFailed
            }
        }

        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw JamendoError.decodingFailed
        }
        return payload.results.compactMap(Self.track(from:))
    }

    private struct Payload: Decodable {
        let results: [Row]
    }

    private struct Row: Decodable {
        let id: String
        let name: String
        let artist_name: String
        let album_name: String?
        let duration: Double
        let audio: String?
        let image: String?
        let license_ccurl: String?
        let shareurl: String?
    }

    /// `nil` for a row with no playable URL. Dropping it here is deliberate: a
    /// row that cannot be played is not a result, and surfacing it would put a
    /// track in the list that fails only once tapped.
    private static func track(from row: Row) -> JamendoCatalogueTrack? {
        guard let audio = row.audio, let audioURL = URL(string: audio) else { return nil }
        return JamendoCatalogueTrack(
            id: row.id,
            title: row.name,
            artistName: row.artist_name,
            albumTitle: row.album_name?.isEmpty == false ? row.album_name! : MetadataPlaceholder.album,
            durationSeconds: row.duration,
            audioURL: audioURL,
            coverURL: row.image.flatMap(URL.init(string:)),
            licenceURL: row.license_ccurl.flatMap(URL.init(string:)),
            shareURL: row.shareurl.flatMap(URL.init(string:))
        )
    }
}
