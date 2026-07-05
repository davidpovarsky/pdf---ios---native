import Foundation
import PDFKit

final class PDFIndexer {
    private let store: LibraryStore
    private let queue = DispatchQueue(label: "TorahPDFReader.PDFIndexer", qos: .utility)
    private var queuedBookIDs = Set<String>()
    private let lock = NSLock()

    init(store: LibraryStore) {
        self.store = store
    }

    func enqueue(book: Book, force: Bool = false) {
        lock.lock()
        if queuedBookIDs.contains(book.id) && !force {
            lock.unlock()
            return
        }
        queuedBookIDs.insert(book.id)
        lock.unlock()

        queue.async { [weak self] in
            self?.index(book: book, force: force)
            self?.lock.lock()
            self?.queuedBookIDs.remove(book.id)
            self?.lock.unlock()
        }
    }

    func indexPendingBooks() {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                let books = try self.store.allBooks()
                books
                    .filter { $0.indexingState == .pending || $0.indexingState == .failed }
                    .forEach { self.enqueue(book: $0, force: false) }
            } catch {
                print("Failed to load pending books: \(error)")
            }
        }
    }

    private func index(book: Book, force: Bool) {
        do {
            if force {
                try store.clearIndex(bookID: book.id)
            }
            guard let document = PDFDocument(url: book.fileURL) else {
                try store.markIndexingFailed(bookID: book.id)
                return
            }
            let pageCount = document.pageCount
            try store.markIndexingStarted(bookID: book.id, pageCount: pageCount)

            for pageIndex in 0..<pageCount {
                autoreleasepool {
                    let page = document.page(at: pageIndex)
                    let text = page?.string ?? ""
                    do {
                        try store.indexPage(bookID: book.id, pageIndex: pageIndex, text: text)
                    } catch {
                        print("Failed to index page \(pageIndex): \(error)")
                    }
                }
            }
            try store.markIndexingFinished(bookID: book.id)
        } catch {
            print("Indexing failed for \(book.title): \(error)")
            try? store.markIndexingFailed(bookID: book.id)
        }
    }
}
