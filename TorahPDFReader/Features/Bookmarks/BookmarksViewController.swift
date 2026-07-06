import SwiftUI
import UIKit

protocol BookmarksViewControllerDelegate: AnyObject {
    func bookmarksViewController(_ controller: BookmarksViewController, didSelect bookmark: Bookmark)
}

final class BookmarksViewController: UIHostingController<BookmarksView> {
    weak var delegate: BookmarksViewControllerDelegate?

    private let viewModel: BookmarksViewModel
    var showsCloseButton = false {
        didSet {
            updateRootView()
        }
    }

    init(book: Book, store: LibraryStore) {
        self.viewModel = BookmarksViewModel(book: book, store: store)
        super.init(rootView: BookmarksView(viewModel: viewModel))
        updateRootView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.bookmarks
        viewModel.reload()
    }

    private func updateRootView() {
        rootView = BookmarksView(
            viewModel: viewModel,
            showsCloseButton: showsCloseButton,
            onClose: { [weak self] in
                self?.dismiss(animated: true)
            },
            onSelect: { [weak self] bookmark in
                guard let self else { return }
                self.delegate?.bookmarksViewController(self, didSelect: bookmark)
            }
        )
    }
}

final class BookmarksViewModel: ObservableObject {
    @Published var bookmarks: [Bookmark] = []
    @Published var errorMessage: String?

    private let book: Book
    private let store: LibraryStore

    init(book: Book, store: LibraryStore) {
        self.book = book
        self.store = store
    }

    func reload() {
        do {
            bookmarks = try store.bookmarks(bookID: book.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ bookmark: Bookmark) {
        do {
            try store.removeBookmark(bookID: book.id, pageIndex: bookmark.pageIndex)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct BookmarksView: View {
    @ObservedObject var viewModel: BookmarksViewModel
    var showsCloseButton = false
    var onClose: () -> Void = {}
    var onSelect: (Bookmark) -> Void = { _ in }

    var body: some View {
        List(viewModel.bookmarks) { bookmark in
            Button {
                onSelect(bookmark)
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bookmark.title)
                        Text(L10n.pageNumber(bookmark.pageNumber))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "bookmark")
                }
            }
            .buttonStyle(.plain)
            .swipeActions {
                Button(role: .destructive) {
                    viewModel.delete(bookmark)
                } label: {
                    Label(L10n.delete, systemImage: "trash")
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if viewModel.bookmarks.isEmpty {
                Text(L10n.noBookmarks)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
        .navigationTitle(L10n.bookmarks)
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(L10n.cancel)
                }
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
