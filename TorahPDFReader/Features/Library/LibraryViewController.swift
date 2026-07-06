import SwiftUI
import UIKit
import UniformTypeIdentifiers

protocol LibraryViewControllerDelegate: AnyObject {
    func libraryViewController(_ controller: LibraryViewController, didSelect book: Book)
    func libraryViewController(_ controller: LibraryViewController, didPickDocumentURLs urls: [URL])
    func libraryViewControllerDidRequestGlobalSearch(_ controller: LibraryViewController)
}

final class LibraryViewController: UIHostingController<LibraryView> {
    weak var delegate: LibraryViewControllerDelegate?

    private let indexer: PDFIndexer
    private let viewModel: LibraryViewModel

    init(store: LibraryStore, indexer: PDFIndexer) {
        self.indexer = indexer
        self.viewModel = LibraryViewModel(store: store)
        super.init(rootView: LibraryView(viewModel: viewModel))
        updateRootView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.library
        navigationItem.largeTitleDisplayMode = .always
        navigationController?.navigationBar.prefersLargeTitles = true
        reloadLibrary()
        indexer.indexPendingBooks()
    }

    func reloadLibrary() {
        viewModel.reload()
    }

    private func updateRootView() {
        rootView = LibraryView(
            viewModel: viewModel,
            onSelect: { [weak self] book in
                guard let self else { return }
                self.delegate?.libraryViewController(self, didSelect: book)
            },
            onImport: { [weak self] urls in
                guard let self else { return }
                self.delegate?.libraryViewController(self, didPickDocumentURLs: urls)
            },
            onGlobalSearch: { [weak self] in
                guard let self else { return }
                self.delegate?.libraryViewControllerDidRequestGlobalSearch(self)
            }
        )
    }
}

final class LibraryViewModel: ObservableObject {
    @Published var query = ""
    @Published var books: [Book] = []
    @Published var isImporterPresented = false
    @Published var errorMessage: String?

    private let store: LibraryStore
    private var storeObserver: NSObjectProtocol?

    var visibleBooks: [Book] {
        let cleanedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedQuery.isEmpty else { return books }
        return books.filter { book in
            book.title.localizedCaseInsensitiveContains(cleanedQuery) ||
            book.originalFilename.localizedCaseInsensitiveContains(cleanedQuery)
        }
    }

    init(store: LibraryStore) {
        self.store = store
        storeObserver = NotificationCenter.default.addObserver(
            forName: LibraryStore.libraryDidChangeNotification,
            object: store,
            queue: .main
        ) { [weak self] _ in
            self?.reload()
        }
    }

    deinit {
        if let storeObserver {
            NotificationCenter.default.removeObserver(storeObserver)
        }
    }

    func reload() {
        do {
            books = try store.allBooks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ book: Book) {
        do {
            try store.deleteBook(book)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func showError(_ error: Error) {
        errorMessage = error.localizedDescription
    }
}

struct LibraryView: View {
    @ObservedObject var viewModel: LibraryViewModel
    var onSelect: (Book) -> Void = { _ in }
    var onImport: ([URL]) -> Void = { _ in }
    var onGlobalSearch: () -> Void = {}

    var body: some View {
        List(viewModel.visibleBooks) { book in
            Button {
                onSelect(book)
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(book.title)
                            .font(.headline)
                        Text(book.displaySubtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "doc.richtext")
                }
            }
            .buttonStyle(.plain)
            .swipeActions {
                Button(role: .destructive) {
                    viewModel.delete(book)
                } label: {
                    Label(L10n.delete, systemImage: "trash")
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if viewModel.visibleBooks.isEmpty {
                Text("\(L10n.noBooksTitle)\n\n\(L10n.noBooksMessage)")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
        .navigationTitle(L10n.library)
        .searchable(text: $viewModel.query, placement: .navigationBarDrawer(displayMode: .always), prompt: L10n.search)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    onGlobalSearch()
                } label: {
                    Image(systemName: "magnifyingglass.circle")
                }
                .accessibilityLabel(L10n.searchAllBooks)

                Button {
                    viewModel.isImporterPresented = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(L10n.importPDF)
            }
        }
        .fileImporter(
            isPresented: $viewModel.isImporterPresented,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                onImport(urls)
            case .failure(let error):
                viewModel.showError(error)
            }
        }
        .alert(L10n.error, isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.errorMessage = nil
                }
            }
        )) {
            Button(L10n.ok, role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}
