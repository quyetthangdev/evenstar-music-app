import Foundation
import Observation

enum ImportError: LocalizedError {
    case unsupportedFormat(String)
    case metadataExtractionFailed
    case copyFailed(underlying: Error)
    case persistFailed(underlying: Error)
    case diskFull
    case fileNotAccessible(URL)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext): return "Định dạng không hỗ trợ: .\(ext)"
        case .metadataExtractionFailed: return "Không đọc được thông tin bài hát."
        case .copyFailed(let error): return "Chép file thất bại: \(error.localizedDescription)"
        case .persistFailed(let error): return "Không lưu được vào thư viện: \(error.localizedDescription)"
        case .diskFull: return "Máy đã hết dung lượng."
        case .fileNotAccessible(let url):
            return "Không mở được \(url.lastPathComponent). File có thể đã bị di chuyển hoặc xoá."
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
        let artist = extracted.artist?.nonEmpty ?? MetadataPlaceholder.artist
        let album = extracted.album?.nonEmpty ?? MetadataPlaceholder.album

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
            if isDiskFullError(error) {
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
            return .failed(.persistFailed(underlying: error))
        }
    }

    /// `FileManager.copyItem(at:to:)` reports out-of-space as
    /// `NSCocoaErrorDomain` / `NSFileWriteOutOfSpaceError`, with the POSIX
    /// `ENOSPC` nested underneath via `NSUnderlyingErrorKey` — not surfaced
    /// directly as `NSPOSIXErrorDomain`. Check both so the disk-full path is
    /// actually reachable.
    private func isDiskFullError(_ error: NSError) -> Bool {
        if error.domain == NSCocoaErrorDomain && error.code == NSFileWriteOutOfSpaceError {
            return true
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSPOSIXErrorDomain,
           underlying.code == ENOSPC {
            return true
        }
        return false
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
