import XCTest
@testable import Evenstar

final class DriveClientTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    private func page(_ files: [(String, String, String)], nextToken: String? = nil) -> Data {
        let items = files.map { #"{"id":"\#($0.0)","name":"\#($0.1)","mimeType":"\#($0.2)"}"# }
        let token = nextToken.map { #""nextPageToken":"\#($0)","# } ?? ""
        return Data(#"{\#(token)"files":[\#(items.joined(separator: ","))]}"#.utf8)
    }

    /// The whole point of pagination: Drive returns at most 100 files per page,
    /// so a folder of 150 songs arrives as 100 unless nextPageToken is followed.
    /// Without this test the bug looks exactly like a smaller folder.
    func testFollowsPaginationToTheEnd() async throws {
        StubURLProtocol.responses = [
            .init(status: 200, body: page([("1", "a.mp3", "audio/mpeg")], nextToken: "T2")),
            .init(status: 200, body: page([("2", "b.mp3", "audio/mpeg")])),
        ]
        let client = DriveClient(apiKey: "test-key", session: StubURLProtocol.session())

        let files = try await client.listAudioFiles(inFolder: "F1")

        XCTAssertEqual(files.map(\.id), ["1", "2"])
        XCTAssertEqual(StubURLProtocol.requestedURLs.count, 2)
        XCTAssertTrue(
            StubURLProtocol.requestedURLs[1].absoluteString.contains("pageToken=T2"),
            "the second request must carry the token from the first response"
        )
    }

    func testKeepsOnlyAudioFiles() async throws {
        StubURLProtocol.responses = [.init(status: 200, body: page([
            ("1", "song.mp3", "audio/mpeg"),
            ("2", "cover.jpg", "image/jpeg"),
            ("3", "notes.txt", "text/plain"),
            ("4", "song.m4a", "audio/mp4"),
        ]))]
        let client = DriveClient(apiKey: "test-key", session: StubURLProtocol.session())

        let files = try await client.listAudioFiles(inFolder: "F1")

        XCTAssertEqual(files.map(\.id), ["1", "4"])
    }

    func testAnEmptyFolderIsNotAnError() async throws {
        StubURLProtocol.responses = [.init(status: 200, body: page([]))]
        let client = DriveClient(apiKey: "test-key", session: StubURLProtocol.session())

        let files = try await client.listAudioFiles(inFolder: "F1")

        XCTAssertTrue(files.isEmpty)
    }

    /// The commonest real failure: the user linked a folder they forgot to
    /// share. It must be distinguishable so the message can say what to fix.
    func testAPrivateFolderReportsNotShared() async {
        StubURLProtocol.responses = [.init(status: 403, body: Data("{}".utf8))]
        let client = DriveClient(apiKey: "test-key", session: StubURLProtocol.session())

        await XCTAssertThrowsErrorAsync(try await client.listAudioFiles(inFolder: "F1")) { error in
            XCTAssertEqual(error as? DriveError, .notShared)
        }
    }

    func testAMissingFolderReportsNotFound() async {
        StubURLProtocol.responses = [.init(status: 404, body: Data("{}".utf8))]
        let client = DriveClient(apiKey: "test-key", session: StubURLProtocol.session())

        await XCTAssertThrowsErrorAsync(try await client.listAudioFiles(inFolder: "F1")) { error in
            XCTAssertEqual(error as? DriveError, .notFound)
        }
    }

    func testQuotaExhaustionIsItsOwnError() async {
        StubURLProtocol.responses = [.init(status: 429, body: Data("{}".utf8))]
        let client = DriveClient(apiKey: "test-key", session: StubURLProtocol.session())

        await XCTAssertThrowsErrorAsync(try await client.listAudioFiles(inFolder: "F1")) { error in
            XCTAssertEqual(error as? DriveError, .quotaExceeded)
        }
    }

    /// No responses queued makes the stub fail the connection.
    func testNoConnectionReportsOffline() async {
        let client = DriveClient(apiKey: "test-key", session: StubURLProtocol.session())

        await XCTAssertThrowsErrorAsync(try await client.listAudioFiles(inFolder: "F1")) { error in
            XCTAssertEqual(error as? DriveError, .offline)
        }
    }

    func testMediaURLPointsAtTheFileWithAltMedia() {
        // `DriveAPIKey.value` stays empty in this repository, so the key must
        // be passed explicitly here — the whole point of Finding 3's fix is
        // that a test can now assert the key is carried, not just the shape.
        let url = DriveClient.mediaURL(fileID: "ABC", apiKey: "test-key").absoluteString
        XCTAssertTrue(url.contains("/files/ABC"))
        XCTAssertTrue(url.contains("alt=media"))
    }

    func testAnEmptyKeyIsItsOwnError() async {
        let client = DriveClient(apiKey: "", session: StubURLProtocol.session())

        await XCTAssertThrowsErrorAsync(try await client.listAudioFiles(inFolder: "F1")) { error in
            XCTAssertEqual(error as? DriveError, .missingAPIKey)
        }
    }

    // MARK: - Fix round: pagination cycle, error taxonomy, mediaURL symmetry

    /// Finding 3: unlike the shape-only test above, this proves the actual
    /// key value is threaded through to the URL, which was impossible to
    /// assert before `apiKey` became a parameter — `DriveAPIKey.value` is
    /// empty in the repo, so the only key `mediaURL` could ever have used was
    /// invisible to a test.
    func testMediaURLCarriesTheProvidedKey() {
        let url = DriveClient.mediaURL(fileID: "ABC", apiKey: "SECRET-KEY").absoluteString
        XCTAssertTrue(url.contains("key=SECRET-KEY"))
    }

    /// Finding 3: a missing key must become a detectable, distinguishable
    /// value — not a googleapis URL that looks legitimate but silently
    /// carries a blank `key=`.
    func testMediaURLWithAnEmptyKeyIsDetectable() {
        let url = DriveClient.mediaURL(fileID: "ABC", apiKey: "")
        XCTAssertEqual(url, DriveClient.missingAPIKeyURL)
    }

    /// `PlayableQueueTests.testEachSourceReportsItsOwnKindOfURL` asserts every
    /// Drive track's `playbackURL()` has scheme `"https"`, key or no key —
    /// `DriveTrack.playbackURL()` returns `mediaURL(fileID:)` unchanged, so
    /// the missing-key sentinel has to keep that scheme or it breaks a Task 3
    /// invariant this task must not touch.
    func testMissingAPIKeyURLKeepsAnHTTPSScheme() {
        XCTAssertEqual(DriveClient.missingAPIKeyURL.scheme, "https")
    }

    /// Finding 1: a page whose `nextPageToken` echoes the token that was just
    /// used to fetch it must not be followed — that would refetch the same
    /// page forever. Races the real call against a timeout task so a
    /// regression that reintroduces the infinite loop fails this test
    /// instead of hanging the whole suite.
    func testARepeatedPageTokenDoesNotHangForever() async throws {
        StubURLProtocol.responses = [
            .init(status: 200, body: page([("1", "a.mp3", "audio/mpeg")], nextToken: "T2")),
            .init(status: 200, body: page([("2", "b.mp3", "audio/mpeg")], nextToken: "T2")),
        ]
        let client = DriveClient(apiKey: "test-key", session: StubURLProtocol.session())

        try await withThrowingTaskGroup(of: Result<[DriveFile], Error>.self) { group in
            defer { group.cancelAll() }

            group.addTask {
                do {
                    return .success(try await client.listAudioFiles(inFolder: "F1"))
                } catch {
                    return .failure(error)
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 3_000_000_000)
                throw PaginationHangTimeout()
            }

            guard let outcome = try await group.next() else {
                XCTFail("task group produced no result")
                return
            }
            switch outcome {
            case .success:
                XCTFail("a repeated page token must be treated as malformed, not followed")
            case .failure(let error):
                XCTAssertEqual(error as? DriveError, .malformedResponse)
            }
        }
    }

    /// Finding 2: a cancelled request — the ordinary case is the caller's
    /// `Task` being cancelled mid-load, e.g. the user navigating away — must
    /// not surface as a `DriveError`. `DriveError.errorDescription` is
    /// user-facing, and a cancellation is not a failure to show anyone.
    func testCancellationDoesNotBecomeADriveError() async {
        StubURLProtocol.nextError = URLError(.cancelled)
        let client = DriveClient(apiKey: "test-key", session: StubURLProtocol.session())

        do {
            _ = try await client.listAudioFiles(inFolder: "F1")
            XCTFail("expected the cancellation to propagate as an error")
        } catch is DriveError {
            XCTFail("a cancelled request must not surface as a user-facing DriveError")
        } catch let urlError as URLError {
            XCTAssertEqual(urlError.code, .cancelled)
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    /// Finding 2: a DNS failure happens on a fully-online device, so it must
    /// not be reported as `.offline` ("no internet") — that would be flatly
    /// wrong. It gets its own case with an accurate message instead.
    func testADNSFailureIsNotReportedAsOffline() async {
        StubURLProtocol.nextError = URLError(.cannotFindHost)
        let client = DriveClient(apiKey: "test-key", session: StubURLProtocol.session())

        await XCTAssertThrowsErrorAsync(try await client.listAudioFiles(inFolder: "F1")) { error in
            XCTAssertEqual(error as? DriveError, .connectionFailed)
        }
    }
}

/// Marks a regression that reintroduces the pagination hang `DriveClient`
/// guards against — see `testARepeatedPageTokenDoesNotHangForever`.
private struct PaginationHangTimeout: Error {}

/// XCTest has no async `XCTAssertThrowsError`.
func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ handler: (Error) -> Void
) async {
    do {
        _ = try await expression()
        XCTFail("expected an error", file: file, line: line)
    } catch {
        handler(error)
    }
}
