import Foundation
import AVFoundation

struct ExtractedMetadata: Equatable {
    let title: String?
    let artist: String?
    let album: String?
    let trackNumber: Int?
    let discNumber: Int?
    let durationSeconds: Double
    let sampleRate: Int?
    let bitDepth: Int?
    let artworkData: Data?
}

enum AudioMetadataError: LocalizedError {
    case unreadable
    case noAudioTrack

    var errorDescription: String? {
        switch self {
        case .unreadable: return "File could not be read as audio."
        case .noAudioTrack: return "File contains no audio track."
        }
    }
}

protocol MetadataReading: Sendable {
    func read(url: URL) async throws -> ExtractedMetadata
}

struct AudioMetadataReader: MetadataReading {

    func read(url: URL) async throws -> ExtractedMetadata {
        let asset = AVURLAsset(url: url)

        // Load duration; this also validates the file is readable as audio.
        let duration: CMTime
        do {
            duration = try await asset.load(.duration)
        } catch {
            throw AudioMetadataError.unreadable
        }
        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds.isFinite, durationSeconds > 0 else {
            throw AudioMetadataError.noAudioTrack
        }

        let metadata = (try? await asset.load(.metadata)) ?? []
        let commonMetadata = (try? await asset.load(.commonMetadata)) ?? []
        let allMetadata = metadata + commonMetadata

        let title = await stringValue(for: .commonKeyTitle, in: allMetadata)
        let artist = await stringValue(for: .commonKeyArtist, in: allMetadata)
        let album = await stringValue(for: .commonKeyAlbumName, in: allMetadata)
        let artworkData = await artworkValue(in: allMetadata)

        let tracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        let sampleRate: Int?
        let bitDepth: Int?
        if let audioTrack = tracks.first,
           let descs = try? await audioTrack.load(.formatDescriptions),
           let desc = descs.first as CMFormatDescription? {
            if let basic = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee {
                sampleRate = Int(basic.mSampleRate)
                bitDepth = basic.mBitsPerChannel == 0 ? nil : Int(basic.mBitsPerChannel)
            } else {
                sampleRate = nil
                bitDepth = nil
            }
        } else {
            sampleRate = nil
            bitDepth = nil
        }

        return ExtractedMetadata(
            title: title,
            artist: artist,
            album: album,
            trackNumber: nil,
            discNumber: nil,
            durationSeconds: durationSeconds,
            sampleRate: sampleRate,
            bitDepth: bitDepth,
            artworkData: artworkData
        )
    }

    private func stringValue(for key: AVMetadataKey,
                             in items: [AVMetadataItem]) async -> String? {
        let matches = AVMetadataItem.metadataItems(
            from: items,
            filteredByIdentifier: identifier(for: key)
        )
        for item in matches {
            if let value = try? await item.load(.stringValue), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func artworkValue(in items: [AVMetadataItem]) async -> Data? {
        let matches = AVMetadataItem.metadataItems(
            from: items,
            filteredByIdentifier: AVMetadataIdentifier.commonIdentifierArtwork
        )
        for item in matches {
            if let value = try? await item.load(.dataValue) {
                return value
            }
        }
        return nil
    }

    private func identifier(for key: AVMetadataKey) -> AVMetadataIdentifier {
        switch key {
        case .commonKeyTitle: return .commonIdentifierTitle
        case .commonKeyArtist: return .commonIdentifierArtist
        case .commonKeyAlbumName: return .commonIdentifierAlbumName
        default: return .commonIdentifierTitle
        }
    }
}
