import UIKit
import UniformTypeIdentifiers

protocol LibraryViewControllerDelegate: AnyObject {
    func libraryViewController(_ controller: LibraryViewController, didSelect book: Book)
    func libraryViewController(_ controller: LibraryViewController, didPickDocumentURLs urls: [URL])
    func libraryViewControllerDidRequestGlobalSearch(_ controller: LibraryViewController)
}

final class LibraryViewController: UITableViewController {
    weak var delegate: LibraryViewControllerDelegate?

    private let store: LibraryStore
    private let indexer: PDFIndexer
    private var allBooks: [Book] = []
    private var visibleBooks: [Book] = []
    private let searchController = UISearchController(searchResultsController: nil)
    private let emptyLabel = UILabel()

    init(store: LibraryStore, indexer: PDFIndexer) {
        self.store = store
        self.indexer = indexer
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.library
        navigationItem.largeTitleDisplayMode = .always
        navigationController?.navigationBar.prefersLargeTitles = true
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "BookCell")
        tableView.backgroundColor = .systemGroupedBackground
        configureSearchController()
        configureNavigationItems()
        configureEmptyState()
        observeStoreChanges()
        reloadLibrary()
        indexer.indexPendingBooks()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func reloadLibrary() {
        do {
            allBooks = try store.allBooks()
            applyFilter(searchController.searchBar.text ?? "")
        } catch {
            showError(error)
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        visibleBooks.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "BookCell")
        let book = visibleBooks[indexPath.row]
        cell.textLabel?.text = book.title
        cell.textLabel?.font = .preferredFont(forTextStyle: .headline)
        cell.detailTextLabel?.text = book.displaySubtitle
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.imageView?.image = UIImage(systemName: "doc.richtext")
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        delegate?.libraryViewController(self, didSelect: visibleBooks[indexPath.row])
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let book = visibleBooks[indexPath.row]
        let deleteAction = UIContextualAction(style: .destructive, title: L10n.delete) { [weak self] _, _, completion in
            guard let self else { completion(false); return }
            do {
                try self.store.deleteBook(book)
                self.reloadLibrary()
                completion(true)
            } catch {
                self.showError(error)
                completion(false)
            }
        }
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }

    private func configureNavigationItems() {
        let addButton = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(importButtonTapped)
        )
        addButton.accessibilityLabel = L10n.importPDF

        let searchButton = UIBarButtonItem(
            image: UIImage(systemName: "magnifyingglass.circle"),
            style: .plain,
            target: self,
            action: #selector(globalSearchTapped)
        )
        searchButton.accessibilityLabel = L10n.searchAllBooks
        navigationItem.rightBarButtonItems = [addButton, searchButton]
    }

    private func configureSearchController() {
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = L10n.search
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
    }

    private func configureEmptyState() {
        emptyLabel.text = "\(L10n.noBooksTitle)\n\n\(L10n.noBooksMessage)"
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.font = .preferredFont(forTextStyle: .body)
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        tableView.backgroundView = emptyLabel
    }

    private func observeStoreChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storeDidChange),
            name: LibraryStore.libraryDidChangeNotification,
            object: store
        )
    }

    private func applyFilter(_ query: String) {
        let cleanedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedQuery.isEmpty {
            visibleBooks = allBooks
        } else {
            visibleBooks = allBooks.filter { book in
                book.title.localizedCaseInsensitiveContains(cleanedQuery) ||
                book.originalFilename.localizedCaseInsensitiveContains(cleanedQuery)
            }
        }
        tableView.reloadData()
        tableView.backgroundView?.isHidden = !visibleBooks.isEmpty
    }

    @objc private func storeDidChange() {
        reloadLibrary()
    }

    @objc private func importButtonTapped() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = self
        present(picker, animated: true)
    }

    @objc private func globalSearchTapped() {
        delegate?.libraryViewControllerDidRequestGlobalSearch(self)
    }

    private func showError(_ error: Error) {
        let alert = UIAlertController(title: L10n.error, message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.ok, style: .default))
        present(alert, animated: true)
    }
}

extension LibraryViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        applyFilter(searchController.searchBar.text ?? "")
    }
}

extension LibraryViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        delegate?.libraryViewController(self, didPickDocumentURLs: urls)
    }
}
