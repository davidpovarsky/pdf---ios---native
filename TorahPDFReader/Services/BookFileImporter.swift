import Foundation
import UniformTypeIdentifiers

enum BookFileImporterError: LocalizedError {
    case unsupportedFile(URL)
    case copyFailed(URL)

    var errorDescription: String? {
        switch self {
        case .unsupportedFile(let url):
            return "\(L10n.unsupportedFile): \(url.lastPathComponent)"
        case .copyFailed(let url):
            return "Could not copy file into the app library: \(url.lastPathComponent)"
        }
    }
}

final class BookFileImporter {
    private let store: LibraryStore

    init(store: LibraryStore) {
        self.store = store
    }

    func importPDF(from sourceURL: URL) throws -> Book {
        let hasSecurityAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        guard sourceURL.pathExtension.lowercased() == "pdf" || isPDF(url: sourceURL) else {
            throw BookFileImporterError.unsupportedFile(sourceURL)
        }

        let id = UUID().uuidString
        let destination = AppDirectories.booksDirectory.appendingPathComponent("\(id).pdf")
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destination)
        } catch {
            throw BookFileImporterError.copyFailed(sourceURL)
        }

        let title = sourceURL.deletingPathExtension().lastPathComponent
        return try store.addBook(title: title, originalFilename: sourceURL.lastPathComponent, fileURL: destination)
    }

    private func isPDF(url: URL) -> Bool {
        guard let typeIdentifier = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            return false
        }
        return typeIdentifier.conforms(to: .pdf)
    }
}
