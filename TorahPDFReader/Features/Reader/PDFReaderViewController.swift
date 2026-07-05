import UIKit
import PDFKit

final class PDFReaderViewController: UIViewController {
    private var book: Book
    private let store: LibraryStore
    private let indexer: PDFIndexer
    private let pdfView = PDFView()
    private let pageLabel = UILabel()
    private var currentPageIndex: Int = 0
    private let initialPageIndex: Int?
    private let initialHighlightQuery: String?

    init(
        book: Book,
        store: LibraryStore,
        indexer: PDFIndexer,
        initialPageIndex: Int? = nil,
        initialHighlightQuery: String? = nil
    ) {
        self.book = book
        self.store = store
        self.indexer = indexer
        self.initialPageIndex = initialPageIndex
        self.initialHighlightQuery = initialHighlightQuery
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = UIView()
        view.backgroundColor = .systemBackground
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        pdfView.backgroundColor = .systemBackground
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = true
        view.addSubview(pdfView)
        NSLayoutConstraint.activate([
            pdfView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pdfView.topAnchor.constraint(equalTo: view.topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = book.title
        navigationItem.largeTitleDisplayMode = .never
        configureNavigationItems()
        configureToolbar()
        loadDocument()
        observePageChanges()
        observeIndexingChanges()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(false, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setToolbarHidden(true, animated: animated)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func configureNavigationItems() {
        let searchButton = UIBarButtonItem(
            image: UIImage(systemName: "magnifyingglass"),
            style: .plain,
            target: self,
            action: #selector(searchTapped)
        )
        searchButton.accessibilityLabel = L10n.searchThisBook

        let bookmarkButton = UIBarButtonItem(
            image: UIImage(systemName: "bookmark"),
            style: .plain,
            target: self,
            action: #selector(addBookmarkTapped)
        )
        bookmarkButton.accessibilityLabel = L10n.addBookmark

        let moreButton = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            style: .plain,
            target: self,
            action: #selector(moreTapped)
        )

        navigationItem.rightBarButtonItems = [moreButton, bookmarkButton, searchButton]
    }

    private func configureToolbar() {
        pageLabel.font = .preferredFont(forTextStyle: .footnote)
        pageLabel.textColor = .secondaryLabel
        pageLabel.textAlignment = .center
        let pageItem = UIBarButtonItem(customView: pageLabel)
        let bookmarksItem = UIBarButtonItem(
            image: UIImage(systemName: "book"),
            style: .plain,
            target: self,
            action: #selector(bookmarksTapped)
        )
        bookmarksItem.accessibilityLabel = L10n.bookmarks
        let flexibleLeft = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let flexibleRight = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        toolbarItems = [bookmarksItem, flexibleLeft, pageItem, flexibleRight]
    }

    private func loadDocument() {
        guard FileManager.default.fileExists(atPath: book.fileURL.path),
              let document = PDFDocument(url: book.fileURL) else {
            showErrorMessage(L10n.error)
            return
        }
        pdfView.document = document
        let requestedPageIndex = initialPageIndex ?? book.lastPageIndex
        let safePageIndex = min(max(requestedPageIndex, 0), max(document.pageCount - 1, 0))
        goToPage(index: safePageIndex, highlightQuery: initialHighlightQuery)
    }

    private func observePageChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pageDidChange),
            name: Notification.Name.PDFViewPageChanged,
            object: pdfView
        )
    }

    private func observeIndexingChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(indexingDidChange),
            name: LibraryStore.indexingProgressNotification,
            object: store
        )
    }

    private func goToPage(index: Int, highlightQuery: String?) {
        guard let document = pdfView.document,
              index >= 0,
              index < document.pageCount,
              let page = document.page(at: index) else { return }
        pdfView.go(to: page)
        currentPageIndex = index
        updatePageLabel()
        if let highlightQuery, !highlightQuery.isEmpty {
            highlight(query: highlightQuery, on: page)
        }
    }

    private func highlight(query: String, on page: PDFPage) {
        guard let document = pdfView.document else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let selections = document.findString(query, withOptions: .caseInsensitive)
            let selection = selections.first { $0.pages.contains(page) }
            DispatchQueue.main.async { [weak self] in
                guard let self, let selection else { return }
                self.pdfView.setCurrentSelection(selection, animate: true)
                self.pdfView.go(to: selection)
            }
        }
    }

    private func updatePageLabel() {
        guard let document = pdfView.document else {
            pageLabel.text = nil
            return
        }
        let current = currentPageIndex + 1
        pageLabel.text = "\(L10n.pageNumber(current)) / \(document.pageCount)"
    }

    private func saveCurrentPage() {
        do {
            try store.updateLastPage(bookID: book.id, pageIndex: currentPageIndex)
        } catch {
            print("Failed to save page: \(error)")
        }
    }

    @objc private func pageDidChange() {
        guard let page = pdfView.currentPage,
              let document = pdfView.document else { return }
        currentPageIndex = document.index(for: page)
        updatePageLabel()
        saveCurrentPage()
    }

    @objc private func indexingDidChange(_ notification: Notification) {
        guard let bookID = notification.userInfo?["bookID"] as? String,
              bookID == book.id else { return }
        do {
            if let updated = try store.book(id: book.id) {
                book = updated
            }
        } catch {
            print("Could not refresh book state: \(error)")
        }
    }

    @objc private func searchTapped() {
        let search = SearchViewController(store: store, scope: .book(book.id))
        search.delegate = self
        navigationController?.pushViewController(search, animated: true)
    }

    @objc private func addBookmarkTapped() {
        do {
            let title = L10n.pageNumber(currentPageIndex + 1)
            try store.addBookmark(bookID: book.id, pageIndex: currentPageIndex, title: title)
            let alert = UIAlertController(title: L10n.bookmark, message: L10n.addBookmark, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: L10n.ok, style: .default))
            present(alert, animated: true)
        } catch {
            showError(error)
        }
    }

    @objc private func bookmarksTapped() {
        let bookmarks = BookmarksViewController(book: book, store: store)
        bookmarks.delegate = self
        navigationController?.pushViewController(bookmarks, animated: true)
    }

    @objc private func moreTapped() {
        let alert = UIAlertController(title: book.title, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: L10n.reindex, style: .default) { [weak self] _ in
            guard let self else { return }
            self.indexer.enqueue(book: self.book, force: true)
        })
        alert.addAction(UIAlertAction(title: L10n.cancel, style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItems?.first
        }
        present(alert, animated: true)
    }

    private func showError(_ error: Error) {
        showErrorMessage(error.localizedDescription)
    }

    private func showErrorMessage(_ message: String) {
        let alert = UIAlertController(title: L10n.error, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.ok, style: .default))
        present(alert, animated: true)
    }
}

extension PDFReaderViewController: SearchViewControllerDelegate {
    func searchViewController(_ controller: SearchViewController, didSelect result: SearchResult) {
        navigationController?.popViewController(animated: true)
        goToPage(index: result.pageIndex, highlightQuery: controller.searchText)
    }
}

extension PDFReaderViewController: BookmarksViewControllerDelegate {
    func bookmarksViewController(_ controller: BookmarksViewController, didSelect bookmark: Bookmark) {
        navigationController?.popViewController(animated: true)
        goToPage(index: bookmark.pageIndex, highlightQuery: nil)
    }
}
