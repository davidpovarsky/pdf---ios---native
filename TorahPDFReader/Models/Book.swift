import Foundation

struct Book: Hashable, Identifiable {
    enum IndexingState: String {
        case pending
        case indexing
        case ready
        case failed
    }

    let id: String
    var title: String
    var originalFilename: String
    var fileURL: URL
    var createdAt: Date
    var lastPageIndex: Int
    var lastReadAt: Date?
    var pageCount: Int
    var indexedPageCount: Int
    var indexingState: IndexingState

    var displaySubtitle: String {
        switch indexingState {
        case .pending:
            return L10n.pending
        case .indexing:
            return L10n.indexedCount(indexedPageCount, pageCount)
        case .ready:
            if pageCount > 0 {
                return "\(pageCount) \(L10n.pages)"
            }
            return L10n.ready
        case .failed:
            return L10n.error
        }
    }
}
