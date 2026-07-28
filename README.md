# Imagin RAW

A lightweight, native macOS application for browsing, culling, and organizing RAW photos - built as a more efficient alternative to Adobe Bridge.

![Main Interface](screenshots/main.jpg)

## Architecture

- **UI**: SwiftUI (macOS 14.6+, I might try to support even lower if people need it). AppKit/UIKit for the thumbnails list where SwiftUI performance was poor
- **RAW decoding**: LibRaw (C++), wrapped via Objective-C++ bridge. CoreImage also used for other formats and as a fallback
- **Metadata**: EXIF parsed directly from RAW/JPEG binary structures; XMP sidecars read/written for Lightroom/Bridge compatibility
- **File system monitoring**: FSEvents for real-time folder change detection
- **Search**: NSMetadataQuery (Spotlight engine) for indexed file/folder search
- **Concurrency**: Swift6 compliant, a mix of Tasks, OperationQueue, unchecked Sendables

## Features

- **Multi-root folder browsing** - add any number of folders from local disks, external drives, or SD cards; no import step, no managed library
- **Real-time file system monitoring** - new photos, deletions, and folder structure changes are detected and reflected immediately
- **Supported files** - all the RAWs and images known to macOS, plus svg and Affinity
- **Rating and color labeling** - written to XMP sidecars (RAW) or embedded directly into the file without re-encoding (JPEG/HEIC), compatible with Adobe Bridge and Lightroom
- **Rejection workflow** - a session-scoped label (not persisted across folder changes) for marking photos to delete; batch-delete via right-click
- **JPG/RAW pair deduplication** - when a RAW+JPEG pair exists, only the RAW is shown in the grid
- **Two grid layouts** - compact grid (more room for preview) and large grid (more room for thumbnails)
- **Spotlight-backed search** - search across files and folder names using the macOS indexing engine
- **SD card ingest** - copy photos into date-based folder structures, with optional simultaneous backup to a second destination
- **Duplicate/similar photo detection** - Review mode for quickly resolving near-duplicate burst shots
- **Instagram frame export** - frame 2:3 images into a 3:4 canvas, exported as TIFF to avoid re-encoding loss (useful for Camera Raw edits which cannot add frames)
- **Export video** - select multiple photos from the same sequence and export a cool video
- **Offline client proofing** - export PDF -> client ticks some checkboxes to mark his favourites -> import the PDF back to filter the selected photos

## Comparison with Adobe Bridge (2022 version)

### Where Imagin RAW is better

| | Imagin RAW | Bridge |
|---|---|---|
| App size | ~9 MB | ~2 GB |
| Idle CPU | 0% | 1-2% |
| Memory | 200MB to scroll through 1300 thumbnails | 2GB for the same album |
| Memory release | Released when switching albums | Adds up when switching albums |
| Launch time | Instant | Seconds |
| Scrolling | Native, smooth | Row-by-row, hard to control |
| External drive eject | No app restart needed (unless video selected) | Requires quitting Bridge |

### Where Bridge is better

- **Camera Raw–processed previews** - Bridge renders thumbnails with ACR adjustments applied. Imagin RAW currently shows the embeded jpegs in a raw; replicating the ACR pipeline isn't feasible, although basic adjustments and crop will be explored.

## Roadmap
- See the open [Issues](https://github.com/cristibaluta/Imagin-Raw/issues)
- An iOS version as an alternative to the cluttered Photos app is in development.

## Screenshots
![Filtered Thumbnails](screenshots/main-dark.jpg)
![Thumbnail Grid](screenshots/large-thumbs.jpg)
![Thumbnail Grid](screenshots/review-mode.jpg)

## Keyboard Shortcuts
- **Arrow Keys** - Navigate between photos
- **CMD A** - Select all photos
- **CMD Click / Shift+Click** - Multi-select photos
- **CMD Del** - Move photos to trash
- **CMD Z** - Undo photos moved to trash
- **1-5** - Set Star Rating
- **6-0** - Apply Labels
- **-** - Remove label
- **A** - Approve photos (same as the 8 key)
- **X / Del** - Reject photos
- **OPT 1-5** - Filter by Star Rating
- **OPT 6-0** - Filter by Labels
- **OPT X** - Filter by Rejected
- **C** - Toggle Sidebar
- **G** - Toggle Grid Type
- **Z** - Toggle Zoom
- **Return** - Open selected photo(s) in external editor

## System Requirements
- macOS 14.6 or later
- Apple Silicon or Intel processor

## Installation
- Buy from the [AppStore](https://apps.apple.com/ro/app/imagin-raw/id6760548347?mt=12) if you want to support the project and receive updates automatically
- Download the latest release from [Releases](https://github.com/cristibaluta/Imagin-Raw/releases). The app does not update itself and does not announce you for updates either
- Compile from source code, there should be no surprises

## Contributions
- Reporting issues and ideas are welcome.
- The code faces multiple random refactorings right now, not the best time to contribute with code.
