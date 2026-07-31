import Foundation

enum FileLocation {
    static func documentsURL(_ fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    static func musicFolderURL(_ fileManager: FileManager = .default) -> URL {
        documentsURL(fileManager).appendingPathComponent("Music", isDirectory: true)
    }

    static func artworkFolderURL(_ fileManager: FileManager = .default) -> URL {
        documentsURL(fileManager).appendingPathComponent("Artwork", isDirectory: true)
    }

    static func absoluteURL(forRelative path: String,
                            fileManager: FileManager = .default) -> URL {
        documentsURL(fileManager).appendingPathComponent(path)
    }

    static func relativePath(for absolute: URL,
                             fileManager: FileManager = .default) -> String {
        let docs = documentsURL(fileManager).standardizedFileURL.path
        let abs = absolute.standardizedFileURL.path
        if abs.hasPrefix(docs + "/") {
            return String(abs.dropFirst(docs.count + 1))
        }
        return absolute.lastPathComponent
    }
}
