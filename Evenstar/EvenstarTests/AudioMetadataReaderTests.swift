import XCTest
import AVFoundation
import UIKit
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

    /// Builds a short M4A file with real embedded common-key tags (title/artist/album)
    /// and JPEG artwork, using `AVAssetWriter` (whose `metadata` property is actually
    /// persisted to the output container, unlike `AVAssetExportSession.metadata`).
    ///
    /// Silence is generated as PCM via `AVAudioFile`/`AVAudioPCMBuffer`, then piped
    /// through an `AVAssetReader` into the `AVAssetWriterInput` so the writer can
    /// encode it to AAC.
    private func makeTaggedTestFile() async throws -> (url: URL, artwork: Data) {
        // 1. Generate a 1-second mono 44100 Hz silent PCM source file.
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tagged-source-\(UUID().uuidString).aiff")
        let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 44100,
            channels: 1,
            interleaved: true
        )!
        let sourceFile = try AVAudioFile(
            forWriting: sourceURL,
            settings: sourceFormat.settings,
            commonFormat: sourceFormat.commonFormat,
            interleaved: sourceFormat.isInterleaved
        )
        let frames: AVAudioFrameCount = 44100
        let sourceBuf = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frames)!
        sourceBuf.frameLength = frames
        memset(sourceBuf.int16ChannelData!.pointee, 0, Int(frames) * 2)
        try sourceFile.write(from: sourceBuf)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        // 2. Build tiny JPEG artwork.
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
        let image = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        let artworkData = try XCTUnwrap(image.jpegData(compressionQuality: 0.9))

        // 3. Set up an AVAssetReader over the PCM source track.
        let sourceAsset = AVURLAsset(url: sourceURL)
        let assetReader = try AVAssetReader(asset: sourceAsset)
        let sourceTracks = try await sourceAsset.loadTracks(withMediaType: .audio)
        let sourceTrack = try XCTUnwrap(sourceTracks.first)
        let sourceFormatDescriptions = try await sourceTrack.load(.formatDescriptions)
        let sourceFormatHint = sourceFormatDescriptions.first

        let readerOutput = AVAssetReaderTrackOutput(track: sourceTrack, outputSettings: nil)
        assetReader.add(readerOutput)

        // 4. Set up an AVAssetWriter with metadata + an AAC audio input.
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tagged-\(UUID().uuidString).m4a")
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)

        func makeMetadataItem(
            _ identifier: AVMetadataIdentifier,
            value: NSCopying & NSObjectProtocol,
            dataType: String? = nil
        ) -> AVMutableMetadataItem {
            let item = AVMutableMetadataItem()
            item.identifier = identifier
            item.value = value
            item.extendedLanguageTag = "und"
            item.dataType = dataType
            return item
        }

        writer.metadata = [
            makeMetadataItem(.commonIdentifierTitle, value: "Test Title" as NSString),
            makeMetadataItem(.commonIdentifierArtist, value: "Test Artist" as NSString),
            makeMetadataItem(.commonIdentifierAlbumName, value: "Test Album" as NSString),
            makeMetadataItem(
                .commonIdentifierArtwork,
                value: artworkData as NSData,
                dataType: kCMMetadataBaseDataType_JPEG as String
            )
        ]

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64000
        ]
        let writerInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: outputSettings,
            sourceFormatHint: sourceFormatHint
        )
        writerInput.expectsMediaDataInRealTime = false
        writer.add(writerInput)

        guard assetReader.startReading() else {
            throw assetReader.error ?? AudioMetadataError.unreadable
        }
        guard writer.startWriting() else {
            throw writer.error ?? AudioMetadataError.unreadable
        }
        writer.startSession(atSourceTime: .zero)

        let queue = DispatchQueue(label: "tagged-fixture-writer")
        // `requestMediaDataWhenReady` takes a `@Sendable` block, but
        // `AVAssetWriterInput` and `AVAssetReaderTrackOutput` are not
        // `Sendable`, so capturing them directly warns. Wrapping the pair in a
        // box marked unchecked is the honest form of what this code already
        // relies on: AVFoundation calls the block only on `queue`, serially,
        // and nothing else touches either object for the lifetime of the pump.
        // The alternative — silencing the warning — would hide the same
        // assumption instead of naming it.
        let pump = FixturePump(input: writerInput, output: readerOutput)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pump.input.requestMediaDataWhenReady(on: queue) {
                while pump.input.isReadyForMoreMediaData {
                    if let sampleBuffer = pump.output.copyNextSampleBuffer() {
                        pump.input.append(sampleBuffer)
                    } else {
                        pump.input.markAsFinished()
                        continuation.resume()
                        return
                    }
                }
            }
        }

        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? AudioMetadataError.unreadable
        }

        return (outputURL, artworkData)
    }

    func testReadReturnsTagsAndArtworkForTaggedFile() async throws {
        let (url, expectedArtwork) = try await makeTaggedTestFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let reader = AudioMetadataReader()

        let metadata = try await reader.read(url: url)

        XCTAssertEqual(metadata.title, "Test Title")
        XCTAssertEqual(metadata.artist, "Test Artist")
        XCTAssertEqual(metadata.album, "Test Album")
        XCTAssertNotNil(metadata.artworkData)
        if let artworkData = metadata.artworkData {
            // Compare as decoded images rather than raw bytes: the writer may
            // re-encode/re-wrap the JPEG we handed it.
            XCTAssertEqual(UIImage(data: artworkData)?.size, UIImage(data: expectedArtwork)?.size)
        }
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

/// Carries the writer input and reader output into AVFoundation's `@Sendable`
/// media-data block.
///
/// Neither type is `Sendable`, so capturing them straight into that block
/// warns. The concurrency this code actually performs is safe and always has
/// been — AVFoundation invokes the block serially on the one queue it was
/// handed, and nothing else touches either object while the pump runs — but
/// that is a fact about the call, not something the compiler can see. Stating
/// it as an unchecked conformance names the assumption; suppressing the
/// warning would have hidden it.
private final class FixturePump: @unchecked Sendable {
    let input: AVAssetWriterInput
    let output: AVAssetReaderTrackOutput

    init(input: AVAssetWriterInput, output: AVAssetReaderTrackOutput) {
        self.input = input
        self.output = output
    }
}
