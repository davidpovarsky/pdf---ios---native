import Foundation

enum L10n {
    static let appName = text("app_name")
    static let library = text("library")
    static let reader = text("reader")
    static let add = text("add")
    static let importPDF = text("import_pdf")
    static let search = text("search")
    static let searchAllBooks = text("search_all_books")
    static let searchThisBook = text("search_this_book")
    static let noBooksTitle = text("no_books_title")
    static let noBooksMessage = text("no_books_message")
    static let emptyReaderMessage = text("empty_reader_message")
    static let indexing = text("indexing")
    static let ready = text("ready")
    static let pending = text("pending")
    static let page = text("page")
    static let pages = text("pages")
    static let results = text("results")
    static let noResults = text("no_results")
    static let bookmark = text("bookmark")
    static let bookmarks = text("bookmarks")
    static let addBookmark = text("add_bookmark")
    static let removeBookmark = text("remove_bookmark")
    static let noBookmarks = text("no_bookmarks")
    static let delete = text("delete")
    static let cancel = text("cancel")
    static let ok = text("ok")
    static let error = text("error")
    static let unsupportedFile = text("unsupported_file")
    static let open = text("open")
    static let reindex = text("reindex")
    static let share = text("share")
    static let more = text("more")
    static let lastRead = text("last_read")
    static let indexingStarted = text("indexing_started")
    static let queryPlaceholder = text("query_placeholder")
    static let copiedIntoLibrary = text("copied_into_library")

    static func pageNumber(_ number: Int) -> String {
        String(format: text("page_number_format"), number)
    }

    static func indexedCount(_ indexed: Int, _ total: Int) -> String {
        String(format: text("indexed_count_format"), indexed, total)
    }

    private static func text(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }
}
