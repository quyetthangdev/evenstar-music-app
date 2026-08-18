import XCTest
@testable import Evenstar

/// `JamendoClient` against a stubbed `URLProtocol`, never the network.
@MainActor
final class JamendoClientTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    private func client(id: String = "test-id") -> JamendoClient {
        JamendoClient(clientID: id, session: StubURLProtocol.session())
    }

    private func body(_ tracks: String) -> Data {
        Data("""
        {"headers":{"status":"success","code":0,"results_count":1},"results":[\(tracks)]}
        """.utf8)
    }

    private let oneTrack = """
    {"id":"1886179","name":"Sunrise","artist_name":"Alpha","album_name":"Dawn",
     "duration":184,"audio":"https://prod-1.storage.jamendo.com/1886179.mp3",
     "image":"https://usercontent.jamendo.com/1886179.jpg",
     "license_ccurl":"http://creativecommons.org/licenses/by/3.0/",
     "shareurl":"https://www.jamendo.com/track/1886179"}
    """

    // MARK: - Decoding

    func testSearchDecodesATrack() async throws {
        StubURLProtocol.responses = [.init(status: 200, body: body(oneTrack))]

        let results = try await client().search("sunrise", commercialOnly: true)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].id, "1886179")
        XCTAssertEqual(results[0].title, "Sunrise")
        XCTAssertEqual(results[0].artistName, "Alpha")
        XCTAssertEqual(results[0].albumTitle, "Dawn")
        XCTAssertEqual(results[0].durationSeconds, 184)
        XCTAssertEqual(results[0].audioURL.absoluteString,
                       "https://prod-1.storage.jamendo.com/1886179.mp3")
        XCTAssertEqual(results[0].coverURL?.absoluteString,
                       "https://usercontent.jamendo.com/1886179.jpg")
        XCTAssertEqual(results[0].licenceURL?.absoluteString,
                       "http://creativecommons.org/licenses/by/3.0/")
        XCTAssertEqual(results[0].shareURL?.absoluteString,
                       "https://www.jamendo.com/track/1886179")
    }

    /// A track with no cover and no licence link must still decode. Dropping the
    /// whole row because one optional field is absent would hide music for a
    /// reason the user cannot see or fix.
    ///
    /// `commercialOnly: false` here on purpose: a `nil` licence is rejected by
    /// the policy when the setting is on (see `JamendoLicencePolicyTests`),
    /// which is a licence-filter concern, not a decoding one. This test is
    /// about decoding.
    func testATrackMissingOptionalFieldsStillDecodes() async throws {
        StubURLProtocol.responses = [.init(status: 200, body: body("""
        {"id":"2","name":"Bare","artist_name":"Beta","album_name":"",
         "duration":60,"audio":"https://example.com/2.mp3"}
        """))]

        let results = try await client().search("bare", commercialOnly: false)

        XCTAssertEqual(results.count, 1)
        XCTAssertNil(results[0].coverURL)
        XCTAssertNil(results[0].licenceURL)
        // An empty `album_name` must become the same placeholder an untagged
        // local file gets, so `PlayerSubtitle`'s collapse rule behaves
        // identically across all three sources.
        XCTAssertEqual(results[0].albumTitle, MetadataPlaceholder.album)
    }

    /// A row with no playable URL is not a track. It is dropped rather than
    /// surfaced as a row that fails only once tapped.
    func testARowWithNoAudioURLIsDropped() async throws {
        StubURLProtocol.responses = [.init(status: 200, body: body("""
        {"id":"3","name":"Broken","artist_name":"Gamma","album_name":"","duration":10}
        """))]

        let results = try await client().search("broken", commercialOnly: true)

        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - The licence filter

    /// **The assertion that matters legally, part one.** `include=licenses` is
    /// what makes `license_ccurl` non-empty on the live API — measured 30/30
    /// tracks empty without it (task-9-brief.md). Without this parameter
    /// reaching the wire, every track's licence decodes as `nil` and
    /// `JamendoLicencePolicy` has nothing to judge.
    func testIncludeLicensesReachesTheRequestURL() async throws {
        StubURLProtocol.responses = [.init(status: 200, body: body(oneTrack))]

        _ = try await client().search("x", commercialOnly: true)

        let url = try XCTUnwrap(StubURLProtocol.lastRequestURL?.absoluteString)
        XCTAssertTrue(url.contains("include=licenses"), "include=licenses missing from \(url)")
    }

    /// **The assertion that matters legally, part two.** Jamendo's `ccnc`
    /// parameter cannot exclude NC tracks server-side — measured live, it
    /// only ever narrows to NC-only or does nothing (task-9-brief.md) — so the
    /// filter has to run against the decoded page. A page mixing an NC row
    /// with a non-NC row must come back with only the non-NC one when the
    /// setting is on.
    func testAMixedPageIsFilteredWhenCommercialOnly() async throws {
        StubURLProtocol.responses = [.init(status: 200, body: mixedLicencePageBody())]

        let results = try await client().search("x", commercialOnly: true)

        XCTAssertEqual(results.map(\.id), ["11"])
    }

    /// The same mixed page, setting off: nothing is excluded.
    func testAMixedPageIsUnfilteredWhenNotCommercialOnly() async throws {
        StubURLProtocol.responses = [.init(status: 200, body: mixedLicencePageBody())]

        let results = try await client().search("x", commercialOnly: false)

        XCTAssertEqual(Set(results.map(\.id)), ["10", "11"])
    }

    /// One row under a `by-nc-sa` licence, one under a plain `by` licence —
    /// the exact live string forms from task-9-brief.md.
    private func mixedLicencePageBody() -> Data {
        let nc = """
        {"id":"10","name":"NC Track","artist_name":"Delta","album_name":"",
         "duration":100,"audio":"https://example.com/10.mp3",
         "license_ccurl":"http://creativecommons.org/licenses/by-nc-sa/2.0/"}
        """
        let free = """
        {"id":"11","name":"Free Track","artist_name":"Epsilon","album_name":"",
         "duration":100,"audio":"https://example.com/11.mp3",
         "license_ccurl":"http://creativecommons.org/licenses/by/3.0/"}
        """
        return Data("""
        {"headers":{"status":"success","code":0,"results_count":2},"results":[\(nc),\(free)]}
        """.utf8)
    }

    // MARK: - Errors

    func testAnEmptyClientIDFailsBeforeAnyRequest() async {
        do {
            _ = try await client(id: "").search("x", commercialOnly: true)
            XCTFail("expected missingClientID")
        } catch {
            XCTAssertEqual(error as? JamendoError, .missingClientID)
        }
    }

    func testA429BecomesRateLimited() async {
        StubURLProtocol.responses = [.init(status: 429, body: Data())]
        do {
            _ = try await client().search("x", commercialOnly: true)
            XCTFail("expected rateLimited")
        } catch {
            XCTAssertEqual(error as? JamendoError, .rateLimited)
        }
    }

    /// A cancelled request — the ordinary case is the discovery screen's
    /// `.task(id: query)` cancelling the in-flight search on every keystroke
    /// — must not surface as `.connectionFailed`. That would show "Không thể
    /// kết nối tới Jamendo. Vui lòng thử lại sau." while the user is simply
    /// still typing.
    func testACancelledRequestDoesNotSurfaceAsConnectionFailed() async {
        StubURLProtocol.nextError = URLError(.cancelled)
        do {
            _ = try await client().search("x", commercialOnly: true)
            XCTFail("expected the cancellation to propagate as an error")
        } catch let error as JamendoError {
            XCTFail("a cancelled request must not surface as a user-facing JamendoError, got \(error)")
        } catch let urlError as URLError {
            XCTAssertEqual(urlError.code, .cancelled)
        } catch {
            XCTFail("expected a URLError, got \(error)")
        }
    }

    // MARK: - C3: Jamendo's own success/failure envelope

    /// **The exact live response body** for a revoked/invalid client id,
    /// captured with a bad credential against the real API (see the fix
    /// report). Jamendo does not use HTTP status for this — this comes back
    /// as a plain 200 — so before this fixture existed, every test in this
    /// suite hardcoded `"status":"success"` and nothing ever exercised the
    /// failure envelope at all. Undetected, this decoded as zero results:
    /// indistinguishable from a query that legitimately matched nothing, and
    /// the discovery screen showed a blank list with no explanation.
    func testAnInvalidClientIdEnvelopeDoesNotSurfaceAsAnEmptyResultList() async {
        StubURLProtocol.responses = [.init(status: 200, body: Data("""
        {"headers":{"status":"failed","code":5,
         "error_message":"Jamendo Api Invalid Client Id Error: Your credential is not authorized."},
         "results":[]}
        """.utf8))]

        do {
            _ = try await client().search("x", commercialOnly: true)
            XCTFail("expected an error, not a silent empty result")
        } catch {
            XCTAssertEqual(error as? JamendoError, .connectionFailed)
        }
    }

    /// Code 6 is Jamendo's documented "Rate Limit Exceeded"
    /// (developer.jamendo.com/v3.0/response-codes) — the one place throttling
    /// is actually reported for this endpoint. Measured live, a bad client id
    /// still comes back as HTTP 200; nothing suggests quota errors are any
    /// different. `.rateLimited` was reachable only from HTTP 429 before this,
    /// which this suite never saw Jamendo actually return.
    func testARateLimitEnvelopeBecomesRateLimited() async {
        StubURLProtocol.responses = [.init(status: 200, body: Data("""
        {"headers":{"status":"failed","code":6,
         "error_message":"This requester app or the requester IP have exceeded the permitted rate limit"},
         "results":[]}
        """.utf8))]

        do {
            _ = try await client().search("x", commercialOnly: true)
            XCTFail("expected rateLimited")
        } catch {
            XCTAssertEqual(error as? JamendoError, .rateLimited)
        }
    }

    func testAnUndecodableBodyBecomesDecodingFailed() async {
        StubURLProtocol.responses = [.init(status: 200, body: Data("not json".utf8))]
        do {
            _ = try await client().search("x", commercialOnly: true)
            XCTFail("expected decodingFailed")
        } catch {
            XCTAssertEqual(error as? JamendoError, .decodingFailed)
        }
    }

    // MARK: - The other two endpoints

    func testTrendingAsksForPopularity() async throws {
        StubURLProtocol.responses = [.init(status: 200, body: body(oneTrack))]

        _ = try await client().trending(commercialOnly: true)

        let url = try XCTUnwrap(StubURLProtocol.lastRequestURL?.absoluteString)
        XCTAssertTrue(url.contains("order=popularity_total"))
    }

    func testAGenreQueryPassesTheTag() async throws {
        StubURLProtocol.responses = [.init(status: 200, body: body(oneTrack))]

        _ = try await client().tracks(inGenre: "jazz", commercialOnly: true)

        let url = try XCTUnwrap(StubURLProtocol.lastRequestURL?.absoluteString)
        XCTAssertTrue(url.contains("tags=jazz"))
    }

    // MARK: - I5: paging past a single 200-row page

    /// `targetResultCount`/`maxPages` are injected small here rather than
    /// left at production's 60/5 — the point under test is the paging
    /// *mechanism*, and a fixture with 60 rows across several pages would
    /// prove nothing this doesn't.
    private func pagingClient(targetResultCount: Int, maxPages: Int) -> JamendoClient {
        JamendoClient(
            clientID: "test-id", session: StubURLProtocol.session(),
            targetResultCount: targetResultCount, maxPages: maxPages
        )
    }

    private func row(id: String) -> String {
        """
        {"id":"\(id)","name":"Track \(id)","artist_name":"Artist","album_name":"",
         "duration":100,"audio":"https://example.com/\(id).mp3",
         "license_ccurl":"http://creativecommons.org/licenses/by/3.0/"}
        """
    }

    private func page(ids: [String], next: String? = nil) -> Data {
        let rows = ids.map(row(id:)).joined(separator: ",")
        let nextField = next.map { ",\"next\":\"\($0)\"" } ?? ""
        return Data("""
        {"headers":{"status":"success","code":0\(nextField)},"results":[\(rows)]}
        """.utf8)
    }

    /// Two pages, each below target on its own, combine into one result —
    /// this is the behaviour that turns "16 of thousands of matches" into a
    /// full screen instead of a stub the user has no way to see more of.
    func testPagingFollowsNextUntilTheTargetIsReached() async throws {
        StubURLProtocol.responses = [
            .init(status: 200, body: page(ids: ["1", "2"], next: "https://api.jamendo.com/v3.0/tracks?offset=2")),
            .init(status: 200, body: page(ids: ["3", "4"]))
        ]
        let results = try await pagingClient(targetResultCount: 3, maxPages: 5)
            .search("x", commercialOnly: true)

        XCTAssertEqual(results.map(\.id), ["1", "2", "3", "4"])
        XCTAssertEqual(StubURLProtocol.requestedURLs.count, 2)
    }

    /// The first page alone clears the target: `next` exists but must not be
    /// followed. Issuing a request nobody asked for is the exact waste the
    /// debounce on the typing side exists to avoid.
    func testPagingStopsAsSoonAsTheTargetIsReached() async throws {
        StubURLProtocol.responses = [
            .init(status: 200, body: page(ids: ["1", "2", "3"], next: "https://api.jamendo.com/v3.0/tracks?offset=3"))
        ]
        let results = try await pagingClient(targetResultCount: 3, maxPages: 5)
            .search("x", commercialOnly: true)

        XCTAssertEqual(results.map(\.id), ["1", "2", "3"])
        XCTAssertEqual(StubURLProtocol.requestedURLs.count, 1)
    }

    /// `next` keeps offering more pages, but `maxPages` caps requests
    /// regardless — a query that stays almost entirely filtered out on every
    /// page must not paginate indefinitely against Jamendo's own catalogue.
    func testPagingStopsAtMaxPagesEvenBelowTarget() async throws {
        StubURLProtocol.responses = [
            .init(status: 200, body: page(ids: ["1"], next: "https://api.jamendo.com/v3.0/tracks?offset=1")),
            .init(status: 200, body: page(ids: ["2"], next: "https://api.jamendo.com/v3.0/tracks?offset=2"))
        ]
        let results = try await pagingClient(targetResultCount: 10, maxPages: 2)
            .search("x", commercialOnly: true)

        XCTAssertEqual(results.map(\.id), ["1", "2"])
        XCTAssertEqual(StubURLProtocol.requestedURLs.count, 2)
    }

    /// A later page failing (rate-limited three pages in, say) must not
    /// discard the pages that already succeeded — that is still a real,
    /// usable result, unlike a first-page failure, which has nothing to fall
    /// back to and is still expected to throw (`testA429BecomesRateLimited`).
    func testALaterPageFailureReturnsWhatAlreadySucceeded() async throws {
        StubURLProtocol.responses = [
            .init(status: 200, body: page(ids: ["1", "2"], next: "https://api.jamendo.com/v3.0/tracks?offset=2")),
            .init(status: 429, body: Data())
        ]
        let results = try await pagingClient(targetResultCount: 10, maxPages: 5)
            .search("x", commercialOnly: true)

        XCTAssertEqual(results.map(\.id), ["1", "2"])
    }
}
