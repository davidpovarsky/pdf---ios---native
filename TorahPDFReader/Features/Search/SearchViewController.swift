import UIKit

protocol SearchViewControllerDelegate: AnyObject {
    func searchViewController(_ controller: SearchViewController, didSelect result: SearchResult)
}

final class SearchViewController: UITableViewController {
    weak var delegate: SearchViewControllerDelegate?

    private let store: LibraryStore
    private let scope: SearchScope
    private let searchController = UISearchController(searchResultsController: nil)
    private var results: [SearchResult] = []
    private var pendingSearch: DispatchWorkItem?
    private let emptyLabel = UILabel()

    var searchText: String {
        searchController.searchBar.text ?? ""
    }

    init(store: LibraryStore, scope: SearchScope) {
        self.store = store
        self.scope = scope
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
        configureEmptyState(text: L10n.queryPlaceholder)
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
        tableView.deselectRow(at: indexPath, animated: true)
        delegate?.searchViewController(self, didSelect: results[indexPath.row])
    }

    private func configureSearchController() {
        searchController.searchResultsUpdater = self
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

    private func runSearch(query: String) {
        pendingSearch?.cancel()
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            results = []
            tableView.reloadData()
            configureEmptyState(text: L10n.queryPlaceholder)
            return
        }

        var workItem: DispatchWorkItem?
        workItem = DispatchWorkItem { [weak self] in
            guard let self, workItem?.isCancelled == false else { return }
            do {
                let found = try self.store.search(cleaned, scope: self.scope)
                DispatchQueue.main.async {
                    guard workItem?.isCancelled == false else { return }
                    self.results = found
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

    private func showError(_ error: Error) {
        let alert = UIAlertController(title: L10n.error, message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.ok, style: .default))
        present(alert, animated: true)
    }
}

extension SearchViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        runSearch(query: searchController.searchBar.text ?? "")
    }
}
