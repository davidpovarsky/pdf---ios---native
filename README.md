# Torah PDF Reader

Native iOS/iPadOS PDF reader skeleton built with UIKit + PDFKit. No SwiftUI is used.

## What is included

- Native split-view library UI for iPad.
- Import PDFs from the Files app with `UIDocumentPickerViewController`.
- Supports opening PDFs into the app from Files / share sheet using document type registration.
- Copies imported PDFs into the app sandbox.
- Reads PDFs with Apple `PDFKit` / `PDFView`.
- Saves the last-read page per book.
- Native reader toolbar using `UINavigationController` toolbar items.
- Tap the PDF page to toggle full-screen reading mode: toolbar/navigation hidden, tap again to restore.
- Reader toolbar actions: Search, Bookmarks, Add Bookmark, Share.
- Search and bookmarks now open as native popover/sheet overlays above the PDF, so the document stays visible.
- Extracts text page-by-page in the background.
- Stores text in SQLite.
- Uses SQLite FTS5 for fast full-text search across all books or within one book.
- English and Hebrew localization files.
- GitHub Actions workflow for creating an unsigned IPA for AltStore.

## Bundle identifier

The project and workflow currently use:

```text
com.davidpovarsky.TorahPDFReader
```

## Build in Xcode

Open `TorahPDFReader.xcodeproj` in Xcode, choose a Team under Signing & Capabilities if building directly to a device, and run on an iPad/iPhone simulator or device.

## GitHub Actions unsigned IPA

The included workflow is:

```text
.github/workflows/ios-unsigned-ipa.yml
```

It builds an unsigned iOS app and packages it as:

```text
TorahPDFReader-unsigned.ipa
```

This is intended for AltStore-style signing/installing. The workflow also uploads logs as an artifact named:

```text
TorahPDFReader-build-logs
```

## Notes

This version indexes embedded PDF text. Scanned PDFs that contain only page images will display correctly, but search will only work after adding an OCR pipeline. The intended next step is to add Vision OCR or a server-side/offline OCR workflow for scanned Hebrew books.
