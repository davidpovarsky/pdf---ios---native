import Foundation

enum AppDirectories {
    static var applicationSupport: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TorahPDFReader", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var booksDirectory: URL {
        let url = applicationSupport.appendingPathComponent("Books", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var databaseURL: URL {
        applicationSupport.appendingPathComponent("Library.sqlite")
    }
}
