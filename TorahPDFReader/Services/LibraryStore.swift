import Foundation

final class LibraryStore {
    static let shared: LibraryStore = {
        do {
            return try LibraryStore(databaseURL: AppDirectories.databaseURL)
        } catch {
            fatalError("Unable to open library database: \(error)")
        }
    }()

    static let libraryDidChangeNotification = Notification.Name("LibraryStore.libraryDidChangeNotification")
    static let indexingProgressNotification = Notification.Name("LibraryStore.indexingProgressNotification")

    private let database: SQLiteDatabase

    init(databaseURL: URL) throws {
        database = try SQLiteDatabase(url: databaseURL)
        try createSchema()
    }

    func allBooks() throws -> [Book] {
        try database.query(
            """
            SELECT id, title, original_filename, file_path, created_at, last_page_index,
                   last_read_at, page_count, indexed_page_count, indexing_state
            FROM books
            ORDER BY COALESCE(last_read_at, created_at) DESC;
            """
        ) { row in
            book(from: row)
        }
    }

    func book(id: String) throws -> Book? {
        try database.query(
            """
            SELECT id, title, original_filename, file_path, created_at, last_page_index,
                   last_read_at, page_count, indexed_page_count, indexing_state
            FROM books
            WHERE id = ?
            LIMIT 1;
            """,
            bindings: [.text(id)]
        ) { row in
            book(from: row)
        }.first
    }

    func addBook(title: String, originalFilename: String, fileURL: URL) throws -> Book {
        let id = UUID().uuidString
        let createdAt = Date()
        try database.execute(
            """
            INSERT INTO books (id, title, original_filename, file_path, created_at, last_page_index,
                               last_read_at, page_count, indexed_page_count, indexing_state)
            VALUES (?, ?, ?, ?, ?, 0, NULL, 0, 0, ?);
            """,
            bindings: [
                .text(id),
                .text(title),
                .text(originalFilename),
                .text(fileURL.path),
                .double(createdAt.timeIntervalSince1970),
                .text(Book.IndexingState.pending.rawValue)
            ]
        )
        postLibraryDidChange()
        return Book(
            id: id,
            title: title,
            originalFilename: originalFilename,
            fileURL: fileURL,
            createdAt: createdAt,
            lastPageIndex: 0,
            lastReadAt: nil,
            pageCount: 0,
            indexedPageCount: 0,
            indexingState: .pending
        )
    }

    func deleteBook(_ book: Book) throws {
        try database.sync {
            try database.executeOnQueue("BEGIN IMMEDIATE TRANSACTION;")
            do {
                try database.executeOnQueue("DELETE FROM bookmarks WHERE book_id = ?;", bindings: [.text(book.id)])
                try database.executeOnQueue("DELETE FROM pages WHERE book_id = ?;", bindings: [.text(book.id)])
                try database.executeOnQueue("DELETE FROM pages_fts WHERE book_id = ?;", bindings: [.text(book.id)])
                try database.executeOnQueue("DELETE FROM books WHERE id = ?;", bindings: [.text(book.id)])
                try database.executeOnQueue("COMMIT;")
            } catch {
                try? database.executeOnQueue("ROLLBACK;")
                throw error
            }
        }
        try? FileManager.default.removeItem(at: book.fileURL)
        postLibraryDidChange()
    }

    func updateLastPage(bookID: String, pageIndex: Int) throws {
        try database.execute(
            """
            UPDATE books
            SET last_page_index = ?, last_read_at = ?
            WHERE id = ?;
            """,
            bindings: [.int(pageIndex), .double(Date().timeIntervalSince1970), .text(bookID)]
        )
        postLibraryDidChange()
    }

    func markIndexingStarted(bookID: String, pageCount: Int) throws {
        try database.execute(
            """
            UPDATE books
            SET page_count = ?, indexed_page_count = 0, indexing_state = ?
            WHERE id = ?;
            """,
            bindings: [.int(pageCount), .text(Book.IndexingState.indexing.rawValue), .text(bookID)]
        )
        postIndexingProgress(bookID: bookID)
    }

    func markIndexingFinished(bookID: String) throws {
        try database.execute(
            """
            UPDATE books
            SET indexing_state = ?
            WHERE id = ?;
            """,
            bindings: [.text(Book.IndexingState.ready.rawValue), .text(bookID)]
        )
        postIndexingProgress(bookID: bookID)
    }

    func markIndexingFailed(bookID: String) throws {
        try database.execute(
            """
            UPDATE books
            SET indexing_state = ?
            WHERE id = ?;
            """,
            bindings: [.text(Book.IndexingState.failed.rawValue), .text(bookID)]
        )
        postIndexingProgress(bookID: bookID)
    }

    func clearIndex(bookID: String) throws {
        try database.sync {
            try database.executeOnQueue("BEGIN IMMEDIATE TRANSACTION;")
            do {
                try database.executeOnQueue("DELETE FROM pages WHERE book_id = ?;", bindings: [.text(bookID)])
                try database.executeOnQueue("DELETE FROM pages_fts WHERE book_id = ?;", bindings: [.text(bookID)])
                try database.executeOnQueue(
                    "UPDATE books SET indexed_page_count = 0, indexing_state = ? WHERE id = ?;",
                    bindings: [.text(Book.IndexingState.pending.rawValue), .text(bookID)]
                )
                try database.executeOnQueue("COMMIT;")
            } catch {
                try? database.executeOnQueue("ROLLBACK;")
                throw error
            }
        }
        postIndexingProgress(bookID: bookID)
    }

    func indexPage(bookID: String, pageIndex: Int, text: String) throws {
        try database.sync {
            try database.executeOnQueue("BEGIN IMMEDIATE TRANSACTION;")
            do {
                try database.executeOnQueue(
                    "INSERT OR REPLACE INTO pages (book_id, page_index, text) VALUES (?, ?, ?);",
                    bindings: [.text(bookID), .int(pageIndex), .text(text)]
                )
                try database.executeOnQueue(
                    "DELETE FROM pages_fts WHERE book_id = ? AND page_index = ?;",
                    bindings: [.text(bookID), .int(pageIndex)]
                )
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    try database.executeOnQueue(
                        "INSERT INTO pages_fts (book_id, page_index, text) VALUES (?, ?, ?);",
                        bindings: [.text(bookID), .int(pageIndex), .text(text)]
                    )
                }
                try database.executeOnQueue(
                    "UPDATE books SET indexed_page_count = MAX(indexed_page_count, ?) WHERE id = ?;",
                    bindings: [.int(pageIndex + 1), .text(bookID)]
                )
                try database.executeOnQueue("COMMIT;")
            } catch {
                try? database.executeOnQueue("ROLLBACK;")
                throw error
            }
        }
        postIndexingProgress(bookID: bookID)
    }

    func search(_ query: String, scope: SearchScope, limit: Int = 100) throws -> [SearchResult] {
        let matchExpression = makeFTSQuery(from: query)
        guard !matchExpression.isEmpty else { return [] }

        switch scope {
        case .allBooks:
            return try database.query(
                """
                SELECT pages_fts.book_id, books.title, pages_fts.page_index,
                       snippet(pages_fts, 2, '‹', '›', '…', 22) AS snippet_text,
                       pages_fts.rank
                FROM pages_fts
                JOIN books ON books.id = pages_fts.book_id
                WHERE pages_fts MATCH ?
                ORDER BY pages_fts.rank
                LIMIT ?;
                """,
                bindings: [.text(matchExpression), .int(limit)]
            ) { row in
                SearchResult(
                    bookID: row.columnString(0),
                    bookTitle: row.columnString(1),
                    pageIndex: row.columnInt(2),
                    snippet: row.columnString(3),
                    rank: row.columnDouble(4)
                )
            }
        case .book(let bookID):
            return try database.query(
                """
                SELECT pages_fts.book_id, books.title, pages_fts.page_index,
                       snippet(pages_fts, 2, '‹', '›', '…', 22) AS snippet_text,
                       pages_fts.rank
                FROM pages_fts
                JOIN books ON books.id = pages_fts.book_id
                WHERE pages_fts MATCH ? AND pages_fts.book_id = ?
                ORDER BY pages_fts.rank
                LIMIT ?;
                """,
                bindings: [.text(matchExpression), .text(bookID), .int(limit)]
            ) { row in
                SearchResult(
                    bookID: row.columnString(0),
                    bookTitle: row.columnString(1),
                    pageIndex: row.columnInt(2),
                    snippet: row.columnString(3),
                    rank: row.columnDouble(4)
                )
            }
        }
    }

    func bookmarks(bookID: String) throws -> [Bookmark] {
        try database.query(
            """
            SELECT id, book_id, page_index, title, created_at
            FROM bookmarks
            WHERE book_id = ?
            ORDER BY page_index ASC;
            """,
            bindings: [.text(bookID)]
        ) { row in
            Bookmark(
                id: row.columnString(0),
                bookID: row.columnString(1),
                pageIndex: row.columnInt(2),
                title: row.columnString(3),
                createdAt: Date(timeIntervalSince1970: row.columnDouble(4))
            )
        }
    }

    func addBookmark(bookID: String, pageIndex: Int, title: String) throws {
        let existingID = try database.query(
            "SELECT id FROM bookmarks WHERE book_id = ? AND page_index = ? LIMIT 1;",
            bindings: [.text(bookID), .int(pageIndex)]
        ) { row in
            row.columnString(0)
        }.first

        if let existingID {
            try database.execute(
                "UPDATE bookmarks SET title = ?, created_at = ? WHERE id = ?;",
                bindings: [.text(title), .double(Date().timeIntervalSince1970), .text(existingID)]
            )
        } else {
            try database.execute(
                "INSERT INTO bookmarks (id, book_id, page_index, title, created_at) VALUES (?, ?, ?, ?, ?);",
                bindings: [.text(UUID().uuidString), .text(bookID), .int(pageIndex), .text(title), .double(Date().timeIntervalSince1970)]
            )
        }
        postLibraryDidChange()
    }

    func removeBookmark(bookID: String, pageIndex: Int) throws {
        try database.execute(
            "DELETE FROM bookmarks WHERE book_id = ? AND page_index = ?;",
            bindings: [.text(bookID), .int(pageIndex)]
        )
        postLibraryDidChange()
    }

    func isBookmarked(bookID: String, pageIndex: Int) throws -> Bool {
        let rows = try database.query(
            "SELECT 1 FROM bookmarks WHERE book_id = ? AND page_index = ? LIMIT 1;",
            bindings: [.text(bookID), .int(pageIndex)]
        ) { _ in true }
        return rows.first ?? false
    }

    private func createSchema() throws {
        try database.execute(
            """
            CREATE TABLE IF NOT EXISTS books (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                original_filename TEXT NOT NULL,
                file_path TEXT NOT NULL,
                created_at REAL NOT NULL,
                last_page_index INTEGER NOT NULL DEFAULT 0,
                last_read_at REAL,
                page_count INTEGER NOT NULL DEFAULT 0,
                indexed_page_count INTEGER NOT NULL DEFAULT 0,
                indexing_state TEXT NOT NULL DEFAULT 'pending'
            );
            """
        )
        try database.execute(
            """
            CREATE TABLE IF NOT EXISTS pages (
                book_id TEXT NOT NULL,
                page_index INTEGER NOT NULL,
                text TEXT NOT NULL,
                PRIMARY KEY (book_id, page_index),
                FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE
            );
            """
        )
        try database.execute(
            """
            CREATE VIRTUAL TABLE IF NOT EXISTS pages_fts USING fts5(
                book_id UNINDEXED,
                page_index UNINDEXED,
                text,
                tokenize = 'unicode61'
            );
            """
        )
        try database.execute(
            """
            CREATE TABLE IF NOT EXISTS bookmarks (
                id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
                book_id TEXT NOT NULL,
                page_index INTEGER NOT NULL,
                title TEXT NOT NULL,
                created_at REAL NOT NULL,
                UNIQUE(book_id, page_index),
                FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE
            );
            """
        )
        try database.execute("CREATE INDEX IF NOT EXISTS idx_books_last_read ON books(last_read_at);")
        try database.execute("CREATE INDEX IF NOT EXISTS idx_bookmarks_book ON bookmarks(book_id, page_index);")
    }

    private func book(from row: OpaquePointer) -> Book {
        let state = Book.IndexingState(rawValue: row.columnString(9)) ?? .pending
        let lastRead: Date?
        if let value = row.columnOptionalString(6), Double(value) != nil {
            lastRead = Date(timeIntervalSince1970: Double(value) ?? 0)
        } else if row.columnOptionalString(6) != nil {
            lastRead = Date(timeIntervalSince1970: row.columnDouble(6))
        } else {
            lastRead = nil
        }
        return Book(
            id: row.columnString(0),
            title: row.columnString(1),
            originalFilename: row.columnString(2),
            fileURL: URL(fileURLWithPath: row.columnString(3)),
            createdAt: Date(timeIntervalSince1970: row.columnDouble(4)),
            lastPageIndex: row.columnInt(5),
            lastReadAt: lastRead,
            pageCount: row.columnInt(7),
            indexedPageCount: row.columnInt(8),
            indexingState: state
        )
    }

    private func makeFTSQuery(from input: String) -> String {
        let terms = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0).replacingOccurrences(of: "\"", with: "\"\"") }
            .map { term in "\"\(term)\"" }
        return terms.joined(separator: " AND ")
    }

    private func postLibraryDidChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.libraryDidChangeNotification, object: self)
        }
    }

    private func postIndexingProgress(bookID: String) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Self.indexingProgressNotification,
                object: self,
                userInfo: ["bookID": bookID]
            )
            NotificationCenter.default.post(name: Self.libraryDidChangeNotification, object: self)
        }
    }
}

enum SearchScope: Hashable {
    case allBooks
    case book(String)
}
