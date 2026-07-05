import UIKit

final class AppCoordinator: NSObject {
    private let window: UIWindow
    private let store: LibraryStore
    private let importer: BookFileImporter
    private let indexer: PDFIndexer
    private let splitViewController: UISplitViewController
    private let libraryViewController: LibraryViewController
    private let primaryNavigationController: UINavigationController
    private let secondaryNavigationController: UINavigationController

    init(window: UIWindow) {
        self.window = window
        self.store = LibraryStore.shared
        self.importer = BookFileImporter(store: store)
        self.indexer = PDFIndexer(store: store)
        self.splitViewController = UISplitViewController(style: .doubleColumn)
        self.libraryViewController = LibraryViewController(store: store, indexer: indexer)
        self.primaryNavigationController = UINavigationController(rootViewController: libraryViewController)
        self.secondaryNavigationController = UINavigationController(rootViewController: EmptyStateViewController())
        super.init()
        libraryViewController.delegate = self
    }

    func start() {
        splitViewController.preferredDisplayMode = .oneBesideSecondary
        splitViewController.setViewController(primaryNavigationController, for: .primary)
        splitViewController.setViewController(secondaryNavigationController, for: .secondary)
        window.rootViewController = splitViewController
        window.makeKeyAndVisible()
    }

    func importOpenedURLs(_ urls: [URL]) {
        importURLs(urls) { [weak self] importedBooks in
            guard let self else { return }
            self.libraryViewController.reloadLibrary()
            if let first = importedBooks.first {
                self.open(book: first)
            }
        }
    }

    private func importURLs(_ urls: [URL], completion: @escaping ([Book]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var imported: [Book] = []
            for url in urls {
                do {
                    let book = try self.importer.importPDF(from: url)
                    imported.append(book)
                    self.indexer.enqueue(book: book)
                } catch {
                    DispatchQueue.main.async {
                        self.presentError(error)
                    }
                }
            }
            DispatchQueue.main.async {
                completion(imported)
            }
        }
    }

    private func open(book: Book, initialPageIndex: Int? = nil, highlightQuery: String? = nil) {
        let reader = PDFReaderViewController(
            book: book,
            store: store,
            indexer: indexer,
            initialPageIndex: initialPageIndex,
            initialHighlightQuery: highlightQuery
        )
        secondaryNavigationController.setViewControllers([reader], animated: false)
        splitViewController.show(.secondary)
    }

    private func presentError(_ error: Error) {
        let alert = UIAlertController(
            title: L10n.error,
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.ok, style: .default))
        window.rootViewController?.present(alert, animated: true)
    }
}

extension AppCoordinator: LibraryViewControllerDelegate {
    func libraryViewController(_ controller: LibraryViewController, didSelect book: Book) {
        open(book: book)
    }

    func libraryViewController(_ controller: LibraryViewController, didPickDocumentURLs urls: [URL]) {
        importURLs(urls) { [weak controller] _ in
            controller?.reloadLibrary()
        }
    }

    func libraryViewControllerDidRequestGlobalSearch(_ controller: LibraryViewController) {
        let search = SearchViewController(store: store, scope: .allBooks)
        search.delegate = self
        controller.navigationController?.pushViewController(search, animated: true)
    }
}

extension AppCoordinator: SearchViewControllerDelegate {
    func searchViewController(_ controller: SearchViewController, didSelect result: SearchResult) {
        do {
            guard let book = try store.book(id: result.bookID) else { return }
            controller.navigationController?.popViewController(animated: true)
            open(book: book, initialPageIndex: result.pageIndex, highlightQuery: controller.searchText)
        } catch {
            presentError(error)
        }
    }
}
