import SwiftUI
import UIKit

protocol SearchViewControllerDelegate: AnyObject {
    func searchViewController(_ controller: SearchViewController, didSelect result: SearchResult)
}

final class SearchViewController: UIHostingController<SearchView> {
    weak var delegate: SearchViewControllerDelegate?

    private let viewModel: SearchViewModel
    var showsCloseButton = false {
        didSet {
            updateRootView()
        }
    }

    var searchText: String {
        viewModel.query
    }

    init(store: LibraryStore, scope: SearchScope) {
        self.viewModel = SearchViewModel(store: store, scope: scope)
        super.init(rootView: SearchView(viewModel: viewModel))
        updateRootView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = viewModel.title
        navigationItem.largeTitleDisplayMode = .never
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewModel.requestSearchFocus()
    }

    private func updateRootView() {
        rootView = SearchView(
            viewModel: viewModel,
            showsCloseButton: showsCloseButton,
            onClose: { [weak self] in
                self?.dismiss(animated: true)
            },
            onSelect: { [weak self] result in
                guard let self else { return }
                self.delegate?.searchViewController(self, didSelect: result)
            }
        )
    }
}

final class SearchViewModel: ObservableObject {
    @Published var query = "" {
        didSet {
            runSearch(query: query)
        }
    }
    @Published var results: [SearchResult] = []
    @Published var errorMessage: String?
    @Published var focusRequest = 0
    @Published private var isSearching = false

    private let store: LibraryStore
    private let scope: SearchScope
    private var pendingSearch: DispatchWorkItem?

    var title: String {
        switch scope {
        case .allBooks:
            return L10n.searchAllBooks
        case .book:
            return L10n.searchThisBook
        }
    }

    var emptyStateText: String {
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            return L10n.queryPlaceholder
        }
        if !isSearching && results.isEmpty {
            return L10n.noResults
        }
        return ""
    }

    init(store: LibraryStore, scope: SearchScope) {
        self.store = store
        self.scope = scope
    }

    deinit {
        pendingSearch?.cancel()
    }

    func requestSearchFocus() {
        focusRequest += 1
    }

    private func runSearch(query: String) {
        pendingSearch?.cancel()
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            isSearching = false
            results = []
            return
        }
        isSearching = true

        var workItem: DispatchWorkItem?
        workItem = DispatchWorkItem { [weak self] in
            guard let self, workItem?.isCancelled == false else { return }
            do {
                let found = try self.store.search(cleaned, scope: self.scope)
                DispatchQueue.main.async {
                    guard workItem?.isCancelled == false else { return }
                    self.isSearching = false
                    self.results = found
                }
            } catch {
                DispatchQueue.main.async {
                    guard workItem?.isCancelled == false else { return }
                    self.isSearching = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
        pendingSearch = workItem
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.18, execute: workItem!)
    }
}

struct SearchView: View {
    @ObservedObject var viewModel: SearchViewModel
    var showsCloseButton = false
    var onClose: () -> Void = {}
    var onSelect: (SearchResult) -> Void = { _ in }

    @FocusState private var isSearchFocused: Bool

    var body: some View {
        List(viewModel.results, id: \.self) { result in
            Button {
                onSelect(result)
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.bookTitle)
                            .font(.headline)
                        Text("\(L10n.pageNumber(result.pageNumber)) — \(result.snippet)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                } icon: {
                    Image(systemName: "text.magnifyingglass")
                }
            }
            .buttonStyle(.plain)
        }
        .listStyle(.insetGrouped)
        .overlay {
            if viewModel.results.isEmpty && !viewModel.emptyStateText.isEmpty {
                Text(viewModel.emptyStateText)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
        .navigationTitle(viewModel.title)
        .searchable(text: $viewModel.query, placement: .navigationBarDrawer(displayMode: .always), prompt: L10n.search)
        .searchFocused($isSearchFocused)
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
        .onAppear {
            focusSearchField()
        }
        .onChange(of: viewModel.focusRequest) { _ in
            focusSearchField()
        }
    }

    private func focusSearchField() {
        DispatchQueue.main.async {
            isSearchFocused = true
        }
    }
}
