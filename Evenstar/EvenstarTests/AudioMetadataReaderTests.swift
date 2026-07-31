import XCTest
import AVFoundation
@testable import Evenstar

final class AudioMetadataReaderTests: XCTestCase {

    /// Generates a 1-second mono 22050 Hz silent AIFF on disk, with no metadata tags.
    /// AIFF is chosen because AVFoundation can write it directly without an export session.
    private func makeSilentTestFile() throws -> URL {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).aiff")

        let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 22050,
            channels: 1,
            interleaved: true
        )!
        let file = try AVAudioFile(
            forWriting: tmpURL,
            settings: format.settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
        let frames: AVAudioFrameCount = 22050
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buf.frameLength = frames
        memset(buf.int16ChannelData!.pointee, 0, Int(frames) * 2)
        try file.write(from: buf)
        return tmpURL
    }

    func testReadReturnsDurationForUntaggedFile() async throws {
        let url = try makeSilentTestFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let reader = AudioMetadataReader()

        let metadata = try await reader.read(url: url)

        XCTAssertEqual(metadata.durationSeconds, 1.0, accuracy: 0.1)
        XCTAssertNil(metadata.title)
        XCTAssertNil(metadata.artist)
        XCTAssertNil(metadata.album)
        XCTAssertNil(metadata.artworkData)
        XCTAssertEqual(metadata.sampleRate, 22050)
        XCTAssertEqual(metadata.bitDepth, 16)
    }

    func testReadThrowsForUnreadableFile() async throws {
        let bogus = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-audio-\(UUID().uuidString).mp3")
        try Data("this is not an mp3".utf8).write(to: bogus)
        defer { try? FileManager.default.removeItem(at: bogus) }
        let reader = AudioMetadataReader()

        do {
            _ = try await reader.read(url: bogus)
            XCTFail("Expected throw")
        } catch {
            // expected
        }
    }

}
