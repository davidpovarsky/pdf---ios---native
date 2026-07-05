import UIKit

protocol SearchViewControllerDelegate: AnyObject {
    func searchViewController(_ controller: SearchViewController, didSelect result: SearchResult, query: String)
}

final class SearchSession {
    var query: String
    var results: [SearchResult]
    var contentOffset: CGPoint

    init(query: String = "", results: [SearchResult] = [], contentOffset: CGPoint = .zero) {
        self.query = query
        self.results = results
        self.contentOffset = contentOffset
    }
}

final class SearchViewController: UITableViewController {
    weak var delegate: SearchViewControllerDelegate?

    private let store: LibraryStore
    private let scope: SearchScope
    private let session: SearchSession
    private let searchController = UISearchController(searchResultsController: nil)
    private var results: [SearchResult] = []
    private var pendingSearch: DispatchWorkItem?
    private let emptyLabel = UILabel()
    private var isRestoringSession = false
    private var suppressSearchUpdates = false
    private var hasRestoredContentOffset = false
    var showsCloseButton = false

    var searchText: String {
        currentQuery
    }

    var currentQuery: String {
        let liveText = searchController.searchBar.text ?? ""
        return liveText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? session.query : liveText
    }

    var searchScope: SearchScope {
        scope
    }

    init(store: LibraryStore, scope: SearchScope, session: SearchSession = SearchSession()) {
        self.store = store
        self.scope = scope
        self.session = session
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = titleForScope()
        navigationItem.largeTitleDisplayMode = .never
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SearchResultCell")
        configureSearchController()
        configureCloseButtonIfNeeded()
        restoreSession()
        searchController.searchResultsUpdater = self
        rerunRestoredSearchIfNeeded()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        searchController.searchBar.becomeFirstResponder()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        results.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "SearchResultCell")
        let result = results[indexPath.row]
        cell.textLabel?.text = result.bookTitle
        cell.textLabel?.font = .preferredFont(forTextStyle: .headline)
        cell.detailTextLabel?.text = "\(L10n.pageNumber(result.pageNumber)) — \(result.snippet)"
        cell.detailTextLabel?.numberOfLines = 3
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.imageView?.image = UIImage(systemName: "text.magnifyingglass")
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let selectedResult = results[indexPath.row]
        let query = currentQuery
        session.query = query
        session.results = results
        session.contentOffset = tableView.contentOffset

        suppressSearchUpdates = true
        searchController.searchBar.resignFirstResponder()
        searchController.isActive = false

        tableView.deselectRow(at: indexPath, animated: true)
        delegate?.searchViewController(self, didSelect: selectedResult, query: query)
    }

    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard hasRestoredContentOffset else { return }
        session.contentOffset = scrollView.contentOffset
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        session.contentOffset = tableView.contentOffset
    }

    private func configureCloseButtonIfNeeded() {
        guard showsCloseButton else { return }
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeTapped)
        )
    }

    @objc private func closeTapped() {
        navigationController?.dismiss(animated: true)
    }

    private func configureSearchController() {
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = L10n.search
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
    }

    private func configureEmptyState(text: String) {
        emptyLabel.text = text
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        tableView.backgroundView = emptyLabel
        tableView.backgroundView?.isHidden = !results.isEmpty
    }

    private func restoreSession() {
        isRestoringSession = true
        searchController.searchBar.text = session.query
        isRestoringSession = false

        results = session.results
        tableView.reloadData()
        configureEmptyState(text: emptyStateText(for: session.query, results: results))

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.tableView.setContentOffset(self.session.contentOffset, animated: false)
            self.hasRestoredContentOffset = true
        }
    }

    private func rerunRestoredSearchIfNeeded() {
        guard !session.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              session.results.isEmpty else { return }
        runSearch(query: session.query)
    }

    private func runSearch(query: String) {
        pendingSearch?.cancel()
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            results = []
            session.results = []
            session.contentOffset = .zero
            tableView.reloadData()
            configureEmptyState(text: L10n.queryPlaceholder)
            return
        }
        session.contentOffset = .zero

        var workItem: DispatchWorkItem?
        workItem = DispatchWorkItem { [weak self] in
            guard let self, workItem?.isCancelled == false else { return }
            do {
                let found = try self.store.search(cleaned, scope: self.scope)
                DispatchQueue.main.async {
                    guard workItem?.isCancelled == false else { return }
                    self.results = found
                    self.session.results = found
                    self.tableView.reloadData()
                    self.configureEmptyState(text: found.isEmpty ? L10n.noResults : "")
                }
            } catch {
                DispatchQueue.main.async {
                    guard workItem?.isCancelled == false else { return }
                    self.showError(error)
                }
            }
        }
        pendingSearch = workItem
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.18, execute: workItem!)
    }

    private func titleForScope() -> String {
        switch scope {
        case .allBooks:
            return L10n.searchAllBooks
        case .book:
            return L10n.searchThisBook
        }
    }

    private func emptyStateText(for query: String, results: [SearchResult]) -> String {
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            return L10n.queryPlaceholder
        }
        return results.isEmpty ? L10n.noResults : ""
    }

    private func showError(_ error: Error) {
        let alert = UIAlertController(title: L10n.error, message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.ok, style: .default))
        present(alert, animated: true)
    }
}

extension SearchViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        guard !isRestoringSession else { return }
        guard !suppressSearchUpdates else { return }
        let query = searchController.searchBar.text ?? ""
        session.query = query
        runSearch(query: query)
    }
}
