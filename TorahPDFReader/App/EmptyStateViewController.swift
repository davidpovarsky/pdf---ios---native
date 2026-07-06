import SwiftUI
import UIKit

final class EmptyStateViewController: UIHostingController<EmptyReaderView> {
    init() {
        super.init(rootView: EmptyReaderView())
        title = L10n.reader
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct EmptyReaderView: View {
    var body: some View {
        Text(L10n.emptyReaderMessage)
            .font(.headline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .background(Color(.systemBackground))
    }
}
