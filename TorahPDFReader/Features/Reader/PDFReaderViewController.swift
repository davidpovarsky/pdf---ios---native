import UIKit
import PDFKit

final class PDFReaderViewController: UIViewController {
    private var book: Book
    private let store: LibraryStore
    private let indexer: PDFIndexer
    private let pdfView = PDFView()
    private let pageLabel = UILabel()
    private let pageScrubber = PDFPageScrubberView()
    private var scrubberHideWorkItem: DispatchWorkItem?
    private var currentPageIndex: Int = 0
    private let initialPageIndex: Int?
    private let initialHighlightQuery: String?
    private var readingBarsHidden = false

    private lazy var contentsItem = UIBarButtonItem(
        image: UIImage(systemName: "list.bullet.rectangle"),
        style: .plain,
        target: self,
        action: #selector(contentsTapped)
    )

    private lazy var pagesItem = UIBarButtonItem(
        image: UIImage(systemName: "square.grid.2x2"),
        style: .plain,
        target: self,
        action: #selector(pagesTapped)
    )

    private lazy var searchItem = UIBarButtonItem(
        image: UIImage(systemName: "magnifyingglass"),
        style: .plain,
        target: self,
        action: #selector(searchTapped)
    )

    private lazy var addBookmarkItem = UIBarButtonItem(
        image: UIImage(systemName: "bookmark"),
        style: .plain,
        target: self,
        action: #selector(addBookmarkTapped)
    )

    private lazy var shareItem = UIBarButtonItem(
        barButtonSystemItem: .action,
        target: self,
        action: #selector(shareTapped)
    )

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

    override var prefersStatusBarHidden: Bool {
        readingBarsHidden
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        readingBarsHidden
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
        pdfView.usePageViewController(false)

        pageScrubber.translatesAutoresizingMaskIntoConstraints = false
        pageScrubber.alpha = 0
        pageScrubber.isHidden = true
        pageScrubber.delegate = self

        view.addSubview(pdfView)
        view.addSubview(pageScrubber)

        NSLayoutConstraint.activate([
            pdfView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pdfView.topAnchor.constraint(equalTo: view.topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            pageScrubber.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            pageScrubber.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            pageScrubber.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            pageScrubber.heightAnchor.constraint(equalToConstant: PDFPageScrubberView.preferredHeight)
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = book.title
        navigationItem.largeTitleDisplayMode = .never
        configureNavigationItems()
        configureToolbar()
        configureReadingTapGesture()
        loadDocument()
        observePageChanges()
        observeIndexingChanges()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyReadingBars(animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        readingBarsHidden = false
        navigationController?.setNavigationBarHidden(false, animated: animated)
        navigationController?.setToolbarHidden(true, animated: animated)
    }

    deinit {
        scrubberHideWorkItem?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    private func configureNavigationItems() {
        let moreButton = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            style: .plain,
            target: self,
            action: #selector(moreTapped)
        )
        moreButton.accessibilityLabel = L10n.more
        navigationItem.rightBarButtonItem = moreButton
    }

    private func configureToolbar() {
        pageLabel.font = .preferredFont(forTextStyle: .footnote)
        pageLabel.textColor = .secondaryLabel
        pageLabel.textAlignment = .center
        pageLabel.adjustsFontForContentSizeCategory = true
        pageLabel.isUserInteractionEnabled = true
        pageLabel.accessibilityTraits.insert(.button)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(pageLabelLongPressed(_:)))
        pageLabel.addGestureRecognizer(longPress)

        let pageItem = UIBarButtonItem(customView: pageLabel)
        pageItem.accessibilityLabel = L10n.page

        contentsItem.accessibilityLabel = L10n.fileContents
        pagesItem.accessibilityLabel = L10n.pageThumbnails
        searchItem.accessibilityLabel = L10n.searchThisBook
        addBookmarkItem.accessibilityLabel = L10n.addBookmark
        shareItem.accessibilityLabel = L10n.share

        let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let fixedSpace1 = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
        fixedSpace1.width = 8
        let fixedSpace2 = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
        fixedSpace2.width = 8
        let fixedSpace3 = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
        fixedSpace3.width = 8

        toolbarItems = [
            contentsItem,
            fixedSpace1,
            pagesItem,
            flexibleSpace,
            searchItem,
            fixedSpace2,
            addBookmarkItem,
            fixedSpace3,
            shareItem,
            flexibleSpace,
            pageItem
        ]
    }

    private func configureReadingTapGesture() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(pdfTapped))
        tap.numberOfTapsRequired = 1
        tap.cancelsTouchesInView = false
        tap.delegate = self
        pdfView.addGestureRecognizer(tap)
    }

    private func loadDocument() {
        guard FileManager.default.fileExists(atPath: book.fileURL.path),
              let document = PDFDocument(url: book.fileURL) else {
            showErrorMessage(L10n.error)
            return
        }
        pdfView.document = document
        pageScrubber.configure(document: document, currentPageIndex: currentPageIndex)
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
        pageScrubber.updateCurrentPage(index)
        showPageScrubberTemporarily()
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
        updateBookmarkButtonState()
    }

    private func updateBookmarkButtonState() {
        do {
            let isBookmarked = try store.isBookmarked(bookID: book.id, pageIndex: currentPageIndex)
            addBookmarkItem.image = UIImage(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
        } catch {
            addBookmarkItem.image = UIImage(systemName: "bookmark")
        }
    }

    private func saveCurrentPage() {
        do {
            try store.updateLastPage(bookID: book.id, pageIndex: currentPageIndex)
        } catch {
            print("Failed to save page: \(error)")
        }
    }

    private func applyReadingBars(animated: Bool) {
        navigationController?.setNavigationBarHidden(readingBarsHidden, animated: animated)
        navigationController?.setToolbarHidden(readingBarsHidden, animated: animated)
        if readingBarsHidden {
            hidePageScrubber(animated: animated)
        } else {
            showPageScrubberTemporarily()
        }
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
    }

    private func presentReaderOverlay(_ controller: UIViewController, from item: UIBarButtonItem) {
        let navigation = UINavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .popover
        navigation.preferredContentSize = controller.preferredContentSize

        if let popover = navigation.popoverPresentationController {
            popover.barButtonItem = item
            popover.permittedArrowDirections = [.up, .down]
        }

        present(navigation, animated: true)
    }

    private func showPageScrubberTemporarily() {
        guard pdfView.document != nil, !readingBarsHidden else { return }
        scrubberHideWorkItem?.cancel()
        pageScrubber.isHidden = false
        UIView.animate(withDuration: 0.18) { [weak self] in
            self?.pageScrubber.alpha = 1
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.hidePageScrubber(animated: true)
        }
        scrubberHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: workItem)
    }

    private func hidePageScrubber(animated: Bool) {
        scrubberHideWorkItem?.cancel()
        let changes = { [weak self] in
            self?.pageScrubber.alpha = 0
        }
        let completion: (Bool) -> Void = { [weak self] _ in
            self?.pageScrubber.isHidden = true
        }
        if animated {
            UIView.animate(withDuration: 0.18, animations: changes, completion: completion)
        } else {
            changes()
            completion(true)
        }
    }

    @objc private func pageDidChange() {
        guard let page = pdfView.currentPage,
              let document = pdfView.document else { return }
        currentPageIndex = document.index(for: page)
        updatePageLabel()
        pageScrubber.updateCurrentPage(currentPageIndex)
        showPageScrubberTemporarily()
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

    @objc private func pdfTapped() {
        readingBarsHidden.toggle()
        UIView.animate(withDuration: 0.2) { [weak self] in
            self?.applyReadingBars(animated: true)
        }
    }

    @objc private func contentsTapped() {
        guard let document = pdfView.document else { return }
        readingBarsHidden = false
        applyReadingBars(animated: true)

        let contents = PDFContentsViewController(book: book, store: store, document: document)
        contents.delegate = self
        contents.showsCloseButton = true
        contents.preferredContentSize = CGSize(width: 420, height: 560)
        presentReaderOverlay(contents, from: contentsItem)
    }

    @objc private func pagesTapped() {
        guard let document = pdfView.document else { return }
        readingBarsHidden = false
        applyReadingBars(animated: true)

        let pages = PDFPagesGridViewController(document: document, currentPageIndex: currentPageIndex)
        pages.delegate = self
        let navigation = UINavigationController(rootViewController: pages)
        navigation.modalPresentationStyle = .fullScreen
        present(navigation, animated: true)
    }

    @objc private func searchTapped() {
        readingBarsHidden = false
        applyReadingBars(animated: true)

        let search = SearchViewController(store: store, scope: .book(book.id))
        search.delegate = self
        search.showsCloseButton = true
        search.preferredContentSize = CGSize(width: 420, height: 560)
        presentReaderOverlay(search, from: searchItem)
    }

    @objc private func addBookmarkTapped() {
        do {
            let title = L10n.pageNumber(currentPageIndex + 1)
            try store.addBookmark(bookID: book.id, pageIndex: currentPageIndex, title: title)
            updateBookmarkButtonState()
            let alert = UIAlertController(title: L10n.bookmark, message: L10n.addBookmark, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: L10n.ok, style: .default))
            present(alert, animated: true)
        } catch {
            showError(error)
        }
    }

    @objc private func shareTapped() {
        readingBarsHidden = false
        applyReadingBars(animated: true)

        let activity = UIActivityViewController(activityItems: [book.fileURL], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.barButtonItem = shareItem
        }
        present(activity, animated: true)
    }

    @objc private func pageLabelLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              let document = pdfView.document,
              document.pageCount > 0 else { return }

        readingBarsHidden = false
        applyReadingBars(animated: true)

        let jump = PDFPageJumpViewController(pageCount: document.pageCount, currentPageIndex: currentPageIndex)
        jump.delegate = self
        jump.modalPresentationStyle = .popover
        jump.preferredContentSize = CGSize(width: 340, height: 170)
        if let popover = jump.popoverPresentationController {
            popover.sourceView = pageLabel
            popover.sourceRect = pageLabel.bounds
            popover.permittedArrowDirections = [.up, .down]
        }
        present(jump, animated: true)
    }

    @objc private func moreTapped() {
        let alert = UIAlertController(title: book.title, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: L10n.reindex, style: .default) { [weak self] _ in
            guard let self else { return }
            self.indexer.enqueue(book: self.book, force: true)
        })
        alert.addAction(UIAlertAction(title: L10n.cancel, style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
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

extension PDFReaderViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if let touchedView = touch.view, touchedView.isDescendant(of: pageScrubber) {
            return false
        }
        return true
    }
}

extension PDFReaderViewController: SearchViewControllerDelegate {
    func searchViewController(_ controller: SearchViewController, didSelect result: SearchResult) {
        controller.dismiss(animated: true) { [weak self] in
            self?.goToPage(index: result.pageIndex, highlightQuery: controller.searchText)
        }
    }
}

extension PDFReaderViewController: PDFContentsViewControllerDelegate {
    func pdfContentsViewController(_ controller: PDFContentsViewController, didSelectPageAt pageIndex: Int) {
        controller.dismiss(animated: true) { [weak self] in
            self?.goToPage(index: pageIndex, highlightQuery: nil)
        }
    }

    func pdfContentsViewControllerDidUpdateBookmarks(_ controller: PDFContentsViewController) {
        updateBookmarkButtonState()
    }
}

extension PDFReaderViewController: PDFPagesGridViewControllerDelegate {
    func pdfPagesGridViewController(_ controller: PDFPagesGridViewController, didSelectPageAt pageIndex: Int) {
        controller.dismiss(animated: true) { [weak self] in
            self?.goToPage(index: pageIndex, highlightQuery: nil)
        }
    }
}

extension PDFReaderViewController: PDFPageScrubberViewDelegate {
    func pageScrubberView(_ scrubber: PDFPageScrubberView, didSelectPageAt pageIndex: Int) {
        scrubberHideWorkItem?.cancel()
        goToPage(index: pageIndex, highlightQuery: nil)
        showPageScrubberTemporarily()
    }
}

extension PDFReaderViewController: PDFPageJumpViewControllerDelegate {
    func pageJumpViewController(_ controller: PDFPageJumpViewController, didChoosePageAt pageIndex: Int) {
        goToPage(index: pageIndex, highlightQuery: nil)
    }
}

private struct PDFOutlineEntry {
    let title: String
    let pageIndex: Int
    let level: Int
}

private protocol PDFContentsViewControllerDelegate: AnyObject {
    func pdfContentsViewController(_ controller: PDFContentsViewController, didSelectPageAt pageIndex: Int)
    func pdfContentsViewControllerDidUpdateBookmarks(_ controller: PDFContentsViewController)
}

private final class PDFContentsViewController: UITableViewController {
    weak var delegate: PDFContentsViewControllerDelegate?
    var showsCloseButton = false

    private enum Mode: Int {
        case outline
        case bookmarks
    }

    private let book: Book
    private let store: LibraryStore
    private let document: PDFDocument
    private let segmentedControl = UISegmentedControl(items: [L10n.tableOfContents, L10n.bookmarks])
    private let emptyLabel = UILabel()
    private var mode: Mode = .outline
    private var outlineEntries: [PDFOutlineEntry] = []
    private var bookmarks: [Bookmark] = []

    init(book: Book, store: LibraryStore, document: PDFDocument) {
        self.book = book
        self.store = store
        self.document = document
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.fileContents
        configureSegmentedControl()
        configureCloseButtonIfNeeded()
        configureEmptyState()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ContentCell")
        outlineEntries = Self.makeOutlineEntries(from: document)
        reloadBookmarks()
        updateEmptyState()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch mode {
        case .outline:
            return outlineEntries.count
        case .bookmarks:
            return bookmarks.count
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "ContentCell")
        cell.accessoryType = .disclosureIndicator

        switch mode {
        case .outline:
            let entry = outlineEntries[indexPath.row]
            cell.textLabel?.text = entry.title
            cell.detailTextLabel?.text = L10n.pageNumber(entry.pageIndex + 1)
            cell.imageView?.image = UIImage(systemName: "list.bullet")
            cell.indentationLevel = entry.level
            cell.indentationWidth = 16
        case .bookmarks:
            let bookmark = bookmarks[indexPath.row]
            cell.textLabel?.text = bookmark.title
            cell.detailTextLabel?.text = L10n.pageNumber(bookmark.pageNumber)
            cell.imageView?.image = UIImage(systemName: "bookmark")
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch mode {
        case .outline:
            delegate?.pdfContentsViewController(self, didSelectPageAt: outlineEntries[indexPath.row].pageIndex)
        case .bookmarks:
            delegate?.pdfContentsViewController(self, didSelectPageAt: bookmarks[indexPath.row].pageIndex)
        }
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard mode == .bookmarks else { return nil }
        let bookmark = bookmarks[indexPath.row]
        let deleteAction = UIContextualAction(style: .destructive, title: L10n.delete) { [weak self] _, _, completion in
            guard let self else { completion(false); return }
            do {
                try self.store.removeBookmark(bookID: self.book.id, pageIndex: bookmark.pageIndex)
                self.reloadBookmarks()
                self.delegate?.pdfContentsViewControllerDidUpdateBookmarks(self)
                completion(true)
            } catch {
                self.showError(error)
                completion(false)
            }
        }
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }

    private func configureSegmentedControl() {
        segmentedControl.selectedSegmentIndex = mode.rawValue
        segmentedControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        navigationItem.titleView = segmentedControl
    }

    private func configureCloseButtonIfNeeded() {
        guard showsCloseButton else { return }
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeTapped)
        )
    }

    private func configureEmptyState() {
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        tableView.backgroundView = emptyLabel
    }

    private func reloadBookmarks() {
        do {
            bookmarks = try store.bookmarks(bookID: book.id)
            tableView.reloadData()
            updateEmptyState()
        } catch {
            showError(error)
        }
    }

    private func updateEmptyState() {
        let isEmpty: Bool
        switch mode {
        case .outline:
            isEmpty = outlineEntries.isEmpty
            emptyLabel.text = L10n.noTableOfContents
        case .bookmarks:
            isEmpty = bookmarks.isEmpty
            emptyLabel.text = L10n.noBookmarks
        }
        tableView.backgroundView?.isHidden = !isEmpty
    }

    private func showError(_ error: Error) {
        let alert = UIAlertController(title: L10n.error, message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.ok, style: .default))
        present(alert, animated: true)
    }

    @objc private func modeChanged() {
        mode = Mode(rawValue: segmentedControl.selectedSegmentIndex) ?? .outline
        tableView.reloadData()
        updateEmptyState()
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    private static func makeOutlineEntries(from document: PDFDocument) -> [PDFOutlineEntry] {
        guard let root = document.outlineRoot else { return [] }
        var entries: [PDFOutlineEntry] = []

        func walk(_ outline: PDFOutline, level: Int) {
            for index in 0..<outline.numberOfChildren {
                guard let child = outline.child(at: index) else { continue }
                if let pageIndex = Self.pageIndex(for: child, in: document) {
                    let title = child.label?.trimmingCharacters(in: .whitespacesAndNewlines)
                    entries.append(
                        PDFOutlineEntry(
                            title: title?.isEmpty == false ? title! : L10n.pageNumber(pageIndex + 1),
                            pageIndex: pageIndex,
                            level: level
                        )
                    )
                }
                walk(child, level: level + 1)
            }
        }

        walk(root, level: 0)
        return entries
    }

    private static func pageIndex(for outline: PDFOutline, in document: PDFDocument) -> Int? {
        if let page = outline.destination?.page {
            let index = document.index(for: page)
            return index == NSNotFound ? nil : index
        }

        if let goToAction = outline.action as? PDFActionGoTo,
           let page = goToAction.destination.page {
            let index = document.index(for: page)
            return index == NSNotFound ? nil : index
        }

        return nil
    }
}

private protocol PDFPagesGridViewControllerDelegate: AnyObject {
    func pdfPagesGridViewController(_ controller: PDFPagesGridViewController, didSelectPageAt pageIndex: Int)
}

private final class PDFPagesGridViewController: UICollectionViewController, UICollectionViewDelegateFlowLayout {
    weak var delegate: PDFPagesGridViewControllerDelegate?

    private let document: PDFDocument
    private let currentPageIndex: Int

    init(document: PDFDocument, currentPageIndex: Int) {
        self.document = document
        self.currentPageIndex = currentPageIndex
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.sectionInset = UIEdgeInsets(top: 18, left: 18, bottom: 28, right: 18)
        layout.minimumInteritemSpacing = 18
        layout.minimumLineSpacing = 22
        super.init(collectionViewLayout: layout)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.pageThumbnails
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeTapped)
        )
        collectionView.backgroundColor = .systemGroupedBackground
        collectionView.register(PDFPageThumbnailCell.self, forCellWithReuseIdentifier: PDFPageThumbnailCell.reuseIdentifier)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard currentPageIndex >= 0, currentPageIndex < document.pageCount else { return }
        collectionView.scrollToItem(at: IndexPath(item: currentPageIndex, section: 0), at: .centeredVertically, animated: false)
    }

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        document.pageCount
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: PDFPageThumbnailCell.reuseIdentifier,
            for: indexPath
        ) as! PDFPageThumbnailCell
        if let page = document.page(at: indexPath.item) {
            cell.configure(page: page, pageIndex: indexPath.item, selected: indexPath.item == currentPageIndex)
        }
        return cell
    }

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        delegate?.pdfPagesGridViewController(self, didSelectPageAt: indexPath.item)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let horizontalInsets: CGFloat = 36
        let minimumWidth: CGFloat = traitCollection.horizontalSizeClass == .regular ? 170 : 120
        let availableWidth = max(collectionView.bounds.width - horizontalInsets, minimumWidth)
        let columns = max(2, Int(availableWidth / minimumWidth))
        let spacing = CGFloat(columns - 1) * 18
        let width = floor((availableWidth - spacing) / CGFloat(columns))
        return CGSize(width: width, height: width * 1.38 + 36)
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }
}

private final class PDFPageThumbnailCell: UICollectionViewCell {
    static let reuseIdentifier = "PDFPageThumbnailCell"

    private let imageView = UIImageView()
    private let numberLabel = UILabel()
    private var representedPageIndex: Int?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        representedPageIndex = nil
        imageView.image = nil
        contentView.layer.borderWidth = 0
    }

    func configure(page: PDFPage, pageIndex: Int, selected: Bool) {
        representedPageIndex = pageIndex
        numberLabel.text = "\(pageIndex + 1)"
        contentView.layer.borderWidth = selected ? 3 : 0
        contentView.layer.borderColor = UIColor.tintColor.cgColor

        let targetSize = CGSize(width: 320, height: 450)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let thumbnail = page.thumbnail(of: targetSize, for: .mediaBox)
            DispatchQueue.main.async {
                guard let self, self.representedPageIndex == pageIndex else { return }
                self.imageView.image = thumbnail
            }
        }
    }

    private func configureViews() {
        contentView.backgroundColor = .secondarySystemGroupedBackground
        contentView.layer.cornerRadius = 10
        contentView.layer.cornerCurve = .continuous
        contentView.layer.masksToBounds = true

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .systemBackground

        numberLabel.translatesAutoresizingMaskIntoConstraints = false
        numberLabel.font = .preferredFont(forTextStyle: .headline)
        numberLabel.adjustsFontForContentSizeCategory = true
        numberLabel.textAlignment = .center
        numberLabel.textColor = .white
        numberLabel.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        numberLabel.layer.cornerRadius = 8
        numberLabel.layer.cornerCurve = .continuous
        numberLabel.layer.masksToBounds = true

        contentView.addSubview(imageView)
        contentView.addSubview(numberLabel)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            numberLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            numberLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            numberLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            numberLabel.heightAnchor.constraint(equalToConstant: 30)
        ])
    }
}

private protocol PDFPageScrubberViewDelegate: AnyObject {
    func pageScrubberView(_ scrubber: PDFPageScrubberView, didSelectPageAt pageIndex: Int)
}

private final class PDFPageScrubberView: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    static let preferredHeight: CGFloat = 88

    weak var delegate: PDFPageScrubberViewDelegate?

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let collectionView: UICollectionView
    private var document: PDFDocument?
    private var currentPageIndex: Int = 0

    override init(frame: CGRect) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 8
        layout.minimumInteritemSpacing = 8
        layout.sectionInset = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(document: PDFDocument, currentPageIndex: Int) {
        self.document = document
        self.currentPageIndex = currentPageIndex
        collectionView.reloadData()
        updateCurrentPage(currentPageIndex)
    }

    func updateCurrentPage(_ pageIndex: Int) {
        currentPageIndex = pageIndex
        collectionView.reloadData()
        guard let document, pageIndex >= 0, pageIndex < document.pageCount else { return }
        collectionView.scrollToItem(at: IndexPath(item: pageIndex, section: 0), at: .centeredHorizontally, animated: true)
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        document?.pageCount ?? 0
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: PDFScrubberThumbnailCell.reuseIdentifier,
            for: indexPath
        ) as! PDFScrubberThumbnailCell
        if let page = document?.page(at: indexPath.item) {
            cell.configure(page: page, pageIndex: indexPath.item, selected: indexPath.item == currentPageIndex)
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        delegate?.pageScrubberView(self, didSelectPageAt: indexPath.item)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        CGSize(width: 42, height: 64)
    }

    private func configureViews() {
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.18
        layer.shadowRadius = 14
        layer.shadowOffset = CGSize(width: 0, height: 6)

        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.layer.cornerRadius = 14
        blurView.layer.cornerCurve = .continuous
        blurView.layer.masksToBounds = true

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(PDFScrubberThumbnailCell.self, forCellWithReuseIdentifier: PDFScrubberThumbnailCell.reuseIdentifier)

        addSubview(blurView)
        blurView.contentView.addSubview(collectionView)

        NSLayoutConstraint.activate([
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),

            collectionView.leadingAnchor.constraint(equalTo: blurView.contentView.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: blurView.contentView.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: blurView.contentView.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: blurView.contentView.bottomAnchor)
        ])
    }
}

private final class PDFScrubberThumbnailCell: UICollectionViewCell {
    static let reuseIdentifier = "PDFScrubberThumbnailCell"

    private let imageView = UIImageView()
    private var representedPageIndex: Int?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        representedPageIndex = nil
        imageView.image = nil
        contentView.layer.borderWidth = 0
    }

    func configure(page: PDFPage, pageIndex: Int, selected: Bool) {
        representedPageIndex = pageIndex
        contentView.layer.borderWidth = selected ? 3 : 0
        contentView.layer.borderColor = UIColor.tintColor.cgColor

        let targetSize = CGSize(width: 100, height: 140)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let thumbnail = page.thumbnail(of: targetSize, for: .mediaBox)
            DispatchQueue.main.async {
                guard let self, self.representedPageIndex == pageIndex else { return }
                self.imageView.image = thumbnail
            }
        }
    }

    private func configureViews() {
        contentView.backgroundColor = .systemBackground
        contentView.layer.cornerRadius = 6
        contentView.layer.cornerCurve = .continuous
        contentView.layer.masksToBounds = true

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .systemBackground

        contentView.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }
}

private protocol PDFPageJumpViewControllerDelegate: AnyObject {
    func pageJumpViewController(_ controller: PDFPageJumpViewController, didChoosePageAt pageIndex: Int)
}

private final class PDFPageJumpViewController: UIViewController {
    weak var delegate: PDFPageJumpViewControllerDelegate?

    private let pageCount: Int
    private var selectedPageIndex: Int
    private let titleLabel = UILabel()
    private let pageLabel = UILabel()
    private let slider = UISlider()

    init(pageCount: Int, currentPageIndex: Int) {
        self.pageCount = pageCount
        self.selectedPageIndex = currentPageIndex
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = UIView()
        view.backgroundColor = .systemBackground

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        titleLabel.text = L10n.jumpToPage

        pageLabel.translatesAutoresizingMaskIntoConstraints = false
        pageLabel.font = .preferredFont(forTextStyle: .body)
        pageLabel.adjustsFontForContentSizeCategory = true
        pageLabel.textColor = .secondaryLabel
        pageLabel.textAlignment = .center

        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.minimumValue = 1
        slider.maximumValue = Float(max(pageCount, 1))
        slider.value = Float(selectedPageIndex + 1)
        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)

        let doneButton = UIButton(type: .system)
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.setTitle(L10n.done, for: .normal)
        doneButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)

        view.addSubview(titleLabel)
        view.addSubview(pageLabel)
        view.addSubview(slider)
        view.addSubview(doneButton)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor, constant: 12),

            pageLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            pageLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            pageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),

            slider.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            slider.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            slider.topAnchor.constraint(equalTo: pageLabel.bottomAnchor, constant: 14),

            doneButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            doneButton.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: 14),
            doneButton.bottomAnchor.constraint(lessThanOrEqualTo: view.layoutMarginsGuide.bottomAnchor, constant: -12)
        ])

        updatePageLabel()
    }

    @objc private func sliderChanged() {
        let roundedPageNumber = Int(slider.value.rounded())
        slider.value = Float(roundedPageNumber)
        let newPageIndex = min(max(roundedPageNumber - 1, 0), max(pageCount - 1, 0))
        guard newPageIndex != selectedPageIndex else { return }
        selectedPageIndex = newPageIndex
        updatePageLabel()
        delegate?.pageJumpViewController(self, didChoosePageAt: selectedPageIndex)
    }

    @objc private func doneTapped() {
        dismiss(animated: true)
    }

    private func updatePageLabel() {
        pageLabel.text = "\(L10n.pageNumber(selectedPageIndex + 1)) / \(pageCount)"
    }
}
