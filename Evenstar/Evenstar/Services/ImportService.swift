import Foundation
import Observation

enum ImportError: LocalizedError {
    case unsupportedFormat(String)
    case fileNotReadable(URL)
    case metadataExtractionFailed
    case copyFailed(underlying: Error)
    case diskFull

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext): return "Unsupported format: .\(ext)"
        case .fileNotReadable(let url): return "Cannot read file: \(url.lastPathComponent)"
        case .metadataExtractionFailed: return "Could not extract audio metadata."
        case .copyFailed(let error): return "Copy failed: \(error.localizedDescription)"
        case .diskFull: return "Storage is full."
        }
    }
}

struct ImportProgress: Equatable {
    let completed: Int
    let total: Int
    let lastError: ImportError?

    init(completed: Int = 0, total: Int = 0, lastError: ImportError? = nil) {
        self.completed = completed
        self.total = total
        self.lastError = lastError
    }

    static func == (lhs: ImportProgress, rhs: ImportProgress) -> Bool {
        lhs.completed == rhs.completed && lhs.total == rhs.total
    }
}

struct ImportSummary {
    let imported: [Track]
    let failures: [(url: URL, error: ImportError)]
    let duplicates: [Track]
}

@Observable
@MainActor
final class ImportService {
    private(set) var isImporting: Bool = false
    private(set) var progress: ImportProgress = .init()

    private let library: LibraryService
    private let metadataReader: MetadataReading
    private let fileManager: FileManager

    init(library: LibraryService,
         metadataReader: MetadataReading,
         fileManager: FileManager = .default) {
        self.library = library
        self.metadataReader = metadataReader
        self.fileManager = fileManager
    }

    func importFiles(at urls: [URL]) async -> ImportSummary {
        isImporting = true
        progress = ImportProgress(completed: 0, total: urls.count, lastError: nil)
        defer { isImporting = false }

        try? ensureFolderExists(FileLocation.musicFolderURL(fileManager))
        try? ensureFolderExists(FileLocation.artworkFolderURL(fileManager))

        var imported: [Track] = []
        var failures: [(url: URL, error: ImportError)] = []
        var duplicates: [Track] = []

        for url in urls {
            let outcome = await importOne(url: url)
            switch outcome {
            case .inserted(let track):
                imported.append(track)
            case .duplicate(let track):
                duplicates.append(track)
            case .failed(let error):
                failures.append((url, error))
                progress = ImportProgress(
                    completed: progress.completed,
                    total: progress.total,
                    lastError: error
                )
                if case .diskFull = error {
                    // Stop the whole batch.
                    progress = ImportProgress(
                        completed: progress.completed,
                        total: progress.total,
                        lastError: error
                    )
                    return ImportSummary(imported: imported, failures: failures, duplicates: duplicates)
                }
            }
            progress = ImportProgress(
                completed: progress.completed + 1,
                total: progress.total,
                lastError: progress.lastError
            )
        }

        return ImportSummary(imported: imported, failures: failures, duplicates: duplicates)
    }

    private enum ImportOutcome {
        case inserted(Track)
        case duplicate(Track)
        case failed(ImportError)
    }

    private func importOne(url: URL) async -> ImportOutcome {
        let ext = url.pathExtension.lowercased()
        guard FormatSupport.isSupported(url) else {
            return .failed(.unsupportedFormat(ext))
        }

        let extracted: ExtractedMetadata
        do {
            extracted = try await metadataReader.read(url: url)
        } catch {
            return .failed(.metadataExtractionFailed)
        }

        let fallbackTitle = url.deletingPathExtension().lastPathComponent
        let title = extracted.title?.nonEmpty ?? fallbackTitle
        let artist = extracted.artist?.nonEmpty ?? "Unknown Artist"
        let album = extracted.album?.nonEmpty ?? "Unknown Album"

        if let existing = try? library.findExistingTrack(
            title: title, artist: artist, duration: extracted.durationSeconds
        ) {
            return .duplicate(existing)
        }

        let id = UUID()
        let musicFolder = FileLocation.musicFolderURL(fileManager)
        let destAudio = musicFolder.appendingPathComponent("\(id.uuidString).\(ext)")
        do {
            try fileManager.copyItem(at: url, to: destAudio)
        } catch let error as NSError {
            if error.domain == NSPOSIXErrorDomain && error.code == ENOSPC {
                return .failed(.diskFull)
            }
            return .failed(.copyFailed(underlying: error))
        }

        var artworkRelative: String? = nil
        if let artworkData = extracted.artworkData, !artworkData.isEmpty {
            let artworkFolder = FileLocation.artworkFolderURL(fileManager)
            let destArtwork = artworkFolder.appendingPathComponent("\(id.uuidString).jpg")
            do {
                try artworkData.write(to: destArtwork)
                artworkRelative = "Artwork/\(id.uuidString).jpg"
            } catch {
                artworkRelative = nil
            }
        }

        let audioRelative = "Music/\(id.uuidString).\(ext)"
        let track = Track(
            id: id,
            title: title,
            artistName: artist,
            albumTitle: album,
            trackNumber: extracted.trackNumber,
            discNumber: extracted.discNumber,
            durationSeconds: extracted.durationSeconds,
            relativePath: audioRelative,
            artworkRelativePath: artworkRelative,
            format: ext,
            sampleRate: extracted.sampleRate,
            bitDepth: extracted.bitDepth
        )

        do {
            try library.insert(track)
            return .inserted(track)
        } catch {
            try? fileManager.removeItem(at: destAudio)
            if let artworkRelative {
                try? fileManager.removeItem(
                    at: FileLocation.absoluteURL(forRelative: artworkRelative, fileManager: fileManager)
                )
            }
            return .failed(.copyFailed(underlying: error))
        }
    }

    private func ensureFolderExists(_ url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
