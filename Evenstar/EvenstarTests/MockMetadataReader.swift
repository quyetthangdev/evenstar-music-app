import Foundation
@testable import Evenstar

final class MockMetadataReader: MetadataReading, @unchecked Sendable {
    enum Outcome {
        case success(ExtractedMetadata)
        case throwing(Error)
    }

    var outcomesByURL: [URL: Outcome] = [:]
    var defaultOutcome: Outcome = .success(
        ExtractedMetadata(
            title: nil, artist: nil, album: nil,
            trackNumber: nil, discNumber: nil,
            durationSeconds: 120,
            sampleRate: 44100, bitDepth: 16,
            artworkData: nil
        )
    )

    private(set) var readURLs: [URL] = []

    func read(url: URL) async throws -> ExtractedMetadata {
        readURLs.append(url)
        let outcome = outcomesByURL[url] ?? defaultOutcome
        switch outcome {
        case .success(let value): return value
        case .throwing(let error): throw error
        }
    }
}
