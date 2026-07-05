import Foundation

struct SearchResult: Hashable {
    let bookID: String
    let bookTitle: String
    let pageIndex: Int
    let snippet: String
    let rank: Double

    var pageNumber: Int { pageIndex + 1 }
}
