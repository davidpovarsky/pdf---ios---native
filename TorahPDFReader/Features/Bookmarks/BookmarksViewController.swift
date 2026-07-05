import UIKit

protocol BookmarksViewControllerDelegate: AnyObject {
    func bookmarksViewController(_ controller: BookmarksViewController, didSelect bookmark: Bookmark)
}

final class BookmarksViewController: UITableViewController {
    weak var delegate: BookmarksViewControllerDelegate?

    private let book: Book
    private let store: LibraryStore
    private var bookmarks: [Bookmark] = []
    private let emptyLabel = UILabel()

    init(book: Book, store: LibraryStore) {
        self.book = book
        self.store = store
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.bookmarks
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "BookmarkCell")
        configureEmptyState()
        reloadBookmarks()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        bookmarks.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "BookmarkCell")
        let bookmark = bookmarks[indexPath.row]
        cell.textLabel?.text = bookmark.title
        cell.detailTextLabel?.text = L10n.pageNumber(bookmark.pageNumber)
        cell.imageView?.image = UIImage(systemName: "bookmark")
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        delegate?.bookmarksViewController(self, didSelect: bookmarks[indexPath.row])
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let bookmark = bookmarks[indexPath.row]
        let deleteAction = UIContextualAction(style: .destructive, title: L10n.delete) { [weak self] _, _, completion in
            guard let self else { completion(false); return }
            do {
                try self.store.removeBookmark(bookID: self.book.id, pageIndex: bookmark.pageIndex)
                self.reloadBookmarks()
                completion(true)
            } catch {
                self.showError(error)
                completion(false)
            }
        }
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }

    private func reloadBookmarks() {
        do {
            bookmarks = try store.bookmarks(bookID: book.id)
            tableView.reloadData()
            tableView.backgroundView?.isHidden = !bookmarks.isEmpty
        } catch {
            showError(error)
        }
    }

    private func configureEmptyState() {
        emptyLabel.text = L10n.noBookmarks
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        tableView.backgroundView = emptyLabel
    }

    private func showError(_ error: Error) {
        let alert = UIAlertController(title: L10n.error, message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.ok, style: .default))
        present(alert, animated: true)
    }
}
