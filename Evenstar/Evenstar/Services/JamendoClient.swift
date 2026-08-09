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
    /// Paging stops once this many licence-permitted rows have been
    /// collected. Injectable so tests can reach the "stop early" and
    /// "keep paging" branches without fixture pages hundreds of rows long;
    /// production code always takes the default. See `get(_:commercialOnly:)`.
    private let targetResultCount: Int
    /// A hard ceiling on requests per search, independent of
    /// `targetResultCount`: a query whose every page is almost entirely
    /// filtered out (an obscure tag under `commercialOnly`, say) must not
    /// paginate indefinitely against Jamendo's own catalogue.
    private let maxPages: Int

    init(
        clientID: String = JamendoAPIKey.value,
        session: URLSession = .shared,
        targetResultCount: Int = 60,
        maxPages: Int = 5
    ) {
        self.clientID = clientID
        self.session = session
        self.targetResultCount = targetResultCount
        self.maxPages = maxPages
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

    // 200 rather than 50: the licence filter now runs client-side (see
    // `JamendoLicencePolicy`) and drops roughly two thirds of a page (33 of 50
    // sampled tracks carry an NC licence — task-9-brief.md). A 50-row request
    // reads to the user as a search that returns almost nothing. 200 is also
    // Jamendo's own ceiling per request — asking for more is a `code: 3` type
    // error, measured live — which is why reaching further than one page's
    // worth of *filtered* results means paging (below), not a bigger `limit`.
    private static let limit = "200"

    /// Fetches one page, filters it, and — if the filtered total is still
    /// short of `targetResultCount` — follows Jamendo's own `headers.next`
    /// cursor for more, up to `maxPages` requests.
    ///
    /// **Paging, not a single giant request**, because Jamendo caps `limit`
    /// at 200 server-side (measured live: `limit=500` comes back `code: 3`,
    /// "must be an integer >= 1 and <= 200"). A query with thousands of
    /// matches has no single-request way to return more than 200 raw rows,
    /// and once the licence filter removes most of those — 77 of 200 on
    /// trending, 16 of 200 on a sampled `piano` search, both measured live —
    /// 200 raw rows routinely becomes fewer than 20 shown. Following `next`
    /// is what makes "search for something popular" return a screenful
    /// instead of a fraction of one.
    ///
    /// Stops early, once `targetResultCount` filtered rows are in hand,
    /// rather than always walking to `maxPages`: most queries clear the
    /// target on the first page (everything passes when `commercialOnly` is
    /// off, and most searches are not this narrow), and issuing requests
    /// nobody will see the results of is the same waste `.task(id: query)`'s
    /// debounce exists to avoid on the typing side.
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
            URLQueryItem(name: "audioformat", value: "mp32"),
            // Without this, `license_ccurl` is empty on every row (measured
            // live, 30/30 — task-9-brief.md): the attribution line never
            // renders and the licence filter below has nothing to filter.
            URLQueryItem(name: "include", value: "licenses")
        ] + items

        var nextURL: URL? = components.url!
        var collected: [JamendoCatalogueTrack] = []
        var page = 0

        while let url = nextURL {
            let payload: Payload
            do {
                payload = try await fetchPage(url)
            } catch let error as URLError where error.code == .cancelled {
                // Rethrown raw regardless of which page this is: a caller
                // that cancelled mid-pagination (the user typed another
                // character) is not owed a partial result, matching the
                // single-request behaviour this had before paging existed.
                throw error
            } catch {
                // A later page failing (rate-limited three requests in, say)
                // must not throw away the pages that already succeeded — the
                // first page's worth of results is still a real result. Only
                // a failure on the very first page, where there is nothing
                // to fall back to, is reported.
                if page == 0 { throw error }
                break
            }

            // The licence filter runs here, against each decoded track,
            // rather than as a query parameter: Jamendo's `ccnc` cannot
            // exclude NC tracks server-side (measured live — task-9-brief.md),
            // only select NC-only or nothing at all.
            collected += payload.results
                .compactMap(Self.track(from:))
                .filter { JamendoLicencePolicy.permits(licenceURL: $0.licenceURL, commercialOnly: commercialOnly) }

            page += 1
            guard collected.count < targetResultCount,
                  page < maxPages,
                  let next = payload.headers.next,
                  let url = URL(string: next)
            else { break }
            nextURL = url
        }

        return collected
    }

    /// One request: transport, HTTP status, JSON shape, and Jamendo's own
    /// success/failure envelope, in that order.
    private func fetchPage(_ url: URL) async throws -> Payload {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
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

        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            // Printed, not swallowed: a `try?` here used to discard the
            // `DecodingError` entirely, so a field-shape change on Jamendo's
            // side surfaced only as a generic "couldn't read the data"
            // message with nothing in a crash log to diagnose it from.
            print("JamendoClient: failed to decode response — \(error)")
            throw JamendoError.decodingFailed
        }

        // Jamendo does not use HTTP status codes for API-level errors: a
        // revoked, expired, or malformed client id comes back as HTTP 200
        // with `headers.status: "failed"` (measured live — a bad client id
        // returns exactly `{"headers":{"status":"failed","code":5,
        // "error_message":"...Invalid Client Id..."},"results":[]}`). Without
        // this check that response decoded as zero results, indistinguishable
        // from a query that legitimately matched nothing.
        //
        // Only `code: 6` ("Rate Limit Exceeded", per Jamendo's own response-code
        // reference) maps to `.rateLimited` — it is the one documented code
        // where the message means "wait and retry", which is what that case
        // promises callers. Every other non-zero code (invalid/suspended
        // client id, malformed request, ...) maps to `.connectionFailed`:
        // none of the existing `JamendoError` cases describes "the app's
        // configuration is wrong", and a generic "couldn't reach Jamendo,
        // try again later" is still a truthful improvement over a silent
        // empty list, even though the retry it invites will not help. A
        // more specific case is not added here — see the fix report for why.
        if payload.headers.code != 0 {
            throw payload.headers.code == 6 ? JamendoError.rateLimited : JamendoError.connectionFailed
        }

        return payload
    }

    private struct Payload: Decodable {
        let headers: Headers
        let results: [Row]
    }

    private struct Headers: Decodable {
        let code: Int
        /// The URL of the next page, exactly as Jamendo returns it — already
        /// carrying every query parameter this page's request had, `offset`
        /// included. `nil` once there is no further page. Present only on
        /// endpoints that page (the ones this client calls); absent, and
        /// therefore optional here, on an error envelope.
        let next: String?
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
