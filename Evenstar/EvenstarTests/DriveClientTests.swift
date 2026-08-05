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
        let url = DriveClient.mediaURL(fileID: "ABC").absoluteString
        XCTAssertTrue(url.contains("/files/ABC"))
        XCTAssertTrue(url.contains("alt=media"))
    }

    func testAnEmptyKeyIsItsOwnError() async {
        let client = DriveClient(apiKey: "", session: StubURLProtocol.session())

        await XCTAssertThrowsErrorAsync(try await client.listAudioFiles(inFolder: "F1")) { error in
            XCTAssertEqual(error as? DriveError, .missingAPIKey)
        }
    }
}

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
