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
    }

    /// A track with no cover and no licence link must still decode. Dropping the
    /// whole row because one optional field is absent would hide music for a
    /// reason the user cannot see or fix.
    func testATrackMissingOptionalFieldsStillDecodes() async throws {
        StubURLProtocol.responses = [.init(status: 200, body: body("""
        {"id":"2","name":"Bare","artist_name":"Beta","album_name":"",
         "duration":60,"audio":"https://example.com/2.mp3"}
        """))]

        let results = try await client().search("bare", commercialOnly: true)

        XCTAssertEqual(results.count, 1)
        XCTAssertNil(results[0].coverURL)
        XCTAssertNil(results[0].licenceURL)
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

    /// **The assertion that matters legally.** The filter has to reach the wire,
    /// not merely exist in `JamendoLicencePolicy`.
    func testTheLicenceFilterReachesTheRequestURL() async throws {
        StubURLProtocol.responses = [.init(status: 200, body: body(oneTrack))]

        _ = try await client().search("x", commercialOnly: true)

        let url = try XCTUnwrap(StubURLProtocol.lastRequestURL?.absoluteString)
        XCTAssertTrue(url.contains("ccnc=false"), "licence filter missing from \(url)")
    }

    func testAllowingEverythingOmitsTheFilter() async throws {
        StubURLProtocol.responses = [.init(status: 200, body: body(oneTrack))]

        _ = try await client().search("x", commercialOnly: false)

        let url = try XCTUnwrap(StubURLProtocol.lastRequestURL?.absoluteString)
        XCTAssertFalse(url.contains("ccnc"))
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
}
