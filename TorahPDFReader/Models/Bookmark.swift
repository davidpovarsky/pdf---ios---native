import Foundation

struct Bookmark: Hashable, Identifiable {
    let id: String
    let bookID: String
    let pageIndex: Int
    let title: String
    let createdAt: Date

    var pageNumber: Int { pageIndex + 1 }
}
