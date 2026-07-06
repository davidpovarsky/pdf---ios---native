# UIKit to SwiftUI Migration Notes

## Converted in this pass

- `TorahPDFReader/App/EmptyStateViewController.swift`
  - Replaced the manual `UILabel` placeholder controller with a small SwiftUI-hosted placeholder view.
- `TorahPDFReader/Features/Library/LibraryViewController.swift`
  - Replaced the `UITableViewController` implementation with a SwiftUI-hosted `List`.
  - Preserved the existing delegate API used by `AppCoordinator`.
  - Preserved library filtering with `.searchable`, delete swipe actions, PDF import, error alerts, and the global search action.
  - Uses SwiftUI `.fileImporter` for native Files import instead of manually presenting `UIDocumentPickerViewController`.
- `TorahPDFReader/Features/Bookmarks/BookmarksViewController.swift`
  - Replaced the `UITableViewController` implementation with a SwiftUI-hosted `List`.
  - Preserved the existing delegate API used by `PDFReaderViewController`.
  - Preserved bookmark selection, delete swipe actions, optional close button behavior, and error alerts.

## Intentionally kept UIKit/PDFKit

- `TorahPDFReader/App/AppDelegate.swift`
  - Kept the UIKit app lifecycle because scene setup is small and already working.
- `TorahPDFReader/App/SceneDelegate.swift`
  - Kept scene URL import handling unchanged.
- `TorahPDFReader/App/AppCoordinator.swift`
  - Kept `UISplitViewController` and `UINavigationController` coordination unchanged to preserve iPad split behavior and reader presentation.
- `TorahPDFReader/Features/Reader/PDFReaderViewController.swift`
  - Kept UIKit + PDFKit intact. The controller owns `PDFView`, zoom/page behavior, highlighting, page persistence, share sheet popover anchoring, reader bar hiding, and PDF tap gestures.
- `TorahPDFReader/Features/Search/SearchViewController.swift`
  - Kept UIKit for this pass because it preserves existing keyboard focus, debounced search, restored query/results/content offset, and popover behavior from both global and in-book search.

## Left unchanged

- `TorahPDFReader/Models`
  - Models already work with both UIKit and SwiftUI and did not need changes.
- `TorahPDFReader/Services`
  - Persistence, importing, indexing, FTS search, and app directory behavior were intentionally left unchanged.
- `TorahPDFReader/Resources`
  - Localization, Info.plist, and launch screen were left unchanged.
- `TorahPDFReader.xcodeproj`
  - No project settings, signing, bundle identifiers, deployment target, frameworks, or app metadata were changed.

## Build result

- `xcodebuild -list` could not be run in this environment because `xcodebuild` is not installed or available on the Windows PowerShell path.
- A simulator build could not be run for the same reason.
