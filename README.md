# Torah PDF Reader

Native iOS/iPadOS PDF reader skeleton built with UIKit + PDFKit. No SwiftUI is used.

## What is included

- Native split-view library UI for iPad.
- Import PDFs from the Files app with `UIDocumentPickerViewController`.
- Supports opening PDFs into the app from Files / share sheet using document type registration.
- Copies imported PDFs into the app sandbox.
- Reads PDFs with Apple `PDFKit` / `PDFView`.
- Saves the last-read page per book.
- Adds and lists page bookmarks.
- Extracts text page-by-page in the background.
- Stores text in SQLite.
- Uses SQLite FTS5 for fast full-text search across all books or within one book.
- English and Hebrew localization files.

## Build

Open `TorahPDFReader.xcodeproj` in Xcode, choose a Team under Signing & Capabilities, and run on an iPad/iPhone simulator or device.

The bundle identifier is currently:

```text
com.example.TorahPDFReader
```

Change it before archiving or uploading to TestFlight.

## Notes

This first version indexes embedded PDF text. Scanned PDFs that contain only page images will display correctly, but search will only work after adding an OCR pipeline. The intended next step is to add Vision OCR or a server-side/offline OCR workflow for scanned Hebrew books.
