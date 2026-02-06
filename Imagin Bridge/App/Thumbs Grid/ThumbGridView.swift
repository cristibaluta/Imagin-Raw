import SwiftUI

struct ThumbGridView: View {
    @EnvironmentObject var externalAppManager: ExternalAppManager
    @EnvironmentObject var filesModel: FilesModel
    let photos: [PhotoItem]
    let selectedApp: PhotoApp?
    @Binding var gridType: GridType // Accept as binding instead of state
    @Binding var selectedPhotos: Set<UUID> // Changed from @State to @Binding
    let onOpenSelectedPhotos: (([PhotoItem]) -> Void)?
    let onEnterReviewMode: (() -> Void)?
    @FocusState private var isFocused: Bool
    @State private var lastScrolledRow: Int = -1
    @State private var showFilterPopover = false
    @State private var selectedLabels: Set<String> = []
    @State private var showSortPopover = false
    @State private var sortOption: SortOption = .name
    @State private var lastSelectedIndex: Int?
    @State private var showGridTypePopover = false

    private let sortOptionKey = "SelectedSortOption"
    private let gridTypeKey = "SelectedGridType"

    enum SortOption: String, CaseIterable {
        case name = "Name"
        case dateCreated = "Date Created"
    }

    enum GridType: String, CaseIterable, Identifiable {
        case twoColumns = "TwoColumns"
        case threeColumns = "ThreeColumns"
        case fourColumns = "FourColumns"

        var id: String { self.rawValue }

        var columnCount: Int {
            switch self {
            case .twoColumns: return 2
            case .threeColumns: return 3
            case .fourColumns: return 4
            }
        }

        var thumbSize: CGFloat {
            switch self {
            case .twoColumns: return 100
            case .threeColumns: return 100
            case .fourColumns: return 200
            }
        }

        var cellHeight: CGFloat {
            switch self {
            case .twoColumns: return 150  // 100px square thumbnail + 50px for title and rating
            case .threeColumns: return 150  // 100px square thumbnail + 50px for title and rating
            case .fourColumns: return 250  // 200px square thumbnail + 50px for title and rating
            }
        }

        var displayName: String {
            switch self {
            case .twoColumns: return "2 Columns (100px)"
            case .threeColumns: return "3 Columns (100px)"
            case .fourColumns: return "4 Columns (200px)"
            }
        }

        var iconName: String {
            switch self {
            case .twoColumns: return "square.grid.2x2"
            case .threeColumns: return "square.grid.3x3"
            case .fourColumns: return "square.grid.4x4.fill"
            }
        }
    }

    // Computed property for filtered and sorted photos
    private var filteredPhotos: [PhotoItem] {
        var result = photos

        // Apply filtering
        if !selectedLabels.isEmpty {
            result = result.filter { photo in
                // Handle "To Delete" filter
                if selectedLabels.contains("To Delete") && photo.toDelete {
                    return true
                }

                let photoLabel = photo.xmp?.label ?? ""

                // Handle "No Label" filter (only for non-deleted photos)
                if selectedLabels.contains("No Label") && photoLabel.isEmpty && !photo.toDelete {
                    return true
                }

                // Handle other specific labels (only for non-deleted photos)
                return selectedLabels.contains(photoLabel) && !photo.toDelete
            }
        }

        // Apply sorting (always ascending)
        switch sortOption {
        case .name:
            result = result.sorted { photo1, photo2 in
                let name1 = URL(fileURLWithPath: photo1.path).lastPathComponent
                let name2 = URL(fileURLWithPath: photo2.path).lastPathComponent
                return name1 < name2
            }
        case .dateCreated:
            result = result.sorted { photo1, photo2 in
                return photo1.dateCreated < photo2.dateCreated
            }
        }

        return result
    }

    // Dynamic grid columns based on grid type
    private var dynamicColumns: [GridItem] {
        let columnCount = gridType.columnCount
        let spacing: CGFloat = 8
        return Array(repeating: GridItem(.flexible(minimum: gridType.thumbSize), spacing: spacing), count: columnCount)
    }

    // Calculate exact width needed for the grid
    private var gridWidth: CGFloat {
        let columnCount = gridType.columnCount
        let thumbSize = gridType.thumbSize
        let spacing: CGFloat = 8
        let horizontalPadding: CGFloat = 8 // 4px padding on each side

        // Width = (number of columns × thumb size) + (spacing between columns) + horizontal padding
        let totalSpacing = CGFloat(columnCount - 1) * spacing
        return (CGFloat(columnCount) * thumbSize) + totalSpacing + horizontalPadding
    }

    private var columnsCount: Int {
        return gridType.columnCount
    }

    // Get available labels from current photos
    private var availableLabels: [String] {
        var labelSet = Set<String>()
        var hasNoLabel = false
        var hasToDelete = false

        for photo in photos {
            if photo.toDelete {
                hasToDelete = true
            } else if let label = photo.xmp?.label, !label.isEmpty {
                labelSet.insert(label)
            } else {
                hasNoLabel = true
            }
        }

        var result: [String] = []
        if hasNoLabel {
            result.append("No Label")
        }

        // Add labels in the standard order if they exist in photos
        let standardOrder = ["Select", "Second", "Approved", "Review", "To Do"]
        for label in standardOrder {
            if labelSet.contains(label) {
                result.append(label)
            }
        }

        // Add "To Delete" at the end if any photos are marked for deletion
        if hasToDelete {
            result.append("To Delete")
        }

        return result
    }

    private func getColorForLabel(_ label: String) -> Color {
        switch label {
        case "No Label":
            return .secondary
        case "Select":
            return .red
        case "Second":
            return .yellow
        case "Approved":
            return .green
        case "Review":
            return .blue
        case "To Do":
            return .purple
        case "To Delete":
            return .orange
        default:
            return .secondary
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main thumbnail grid
            ScrollViewReader { proxy in
                GeometryReader { geometry in
                    if filteredPhotos.isEmpty {
                        // Show message when no photos are available
                        VStack(spacing: 16) {
                            Spacer()

                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)

                            VStack(spacing: 8) {
                                Text(photos.isEmpty ? "No Supported Photos Found" : "No Photos Match Current Filter")
                                    .font(.headline)
                                    .foregroundColor(.primary)

                                if photos.isEmpty {
                                    Text("This folder doesn't contain any supported image formats.")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)

                                    Text("Supported formats: RAW files (CR2, NEF, ARW, etc.), JPEG, PNG, TIFF")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                } else {
                                    Text("Try adjusting your filter settings to see more photos.")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                            }

                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVGrid(columns: dynamicColumns, spacing: 8) {
                                ForEach(filteredPhotos, id: \.id) { photo in
                                    ThumbCell(
                                        photo: photo,
                                        isSelected: selectedPhotos.contains(photo.id),
                                        onTap: { modifiers in
                                            handlePhotoTap(photo: photo, modifiers: modifiers)
                                        },
                                        onDoubleClick: {
                                            filesModel.selectedPhoto = photo
                                            // If multiple photos are selected, open all of them
                                            if selectedPhotos.count > 1 {
                                                openSelectedPhotosInExternalApp()
                                            } else {
                                                openInExternalApp(photo: photo)
                                            }
                                        },
                                        onRatingChanged: { rating in
                                            setPhotoRating(photo: photo, rating: rating)
                                        },
                                        size: gridType.thumbSize  // Pass the dynamic size
                                    )
                                    .frame(width: gridType.thumbSize, height: gridType.cellHeight)
                                    .id(photo.id)
                                }
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 4)
                        }
                        .focusable()
                        .focusEffectDisabled()
                        .focused($isFocused)
                        .onKeyPress { keyPress in
                            handleKeyPress(keyPress, proxy: proxy, viewportHeight: geometry.size.height)
                        }
                        .onAppear {
                            isFocused = true
                            if filesModel.selectedPhoto == nil && !filteredPhotos.isEmpty {
                                filesModel.selectedPhoto = filteredPhotos.first
                                lastSelectedIndex = 0
                                selectedPhotos.removeAll()
                                if let firstPhoto = filteredPhotos.first {
                                    selectedPhotos.insert(firstPhoto.id)
                                }
                            }
                            loadSortOption() // Load the saved sort option
                        }
                        .onChange(of: photos) { _, newPhotos in
                            // Only select the first photo if there's no current selection
                            if filesModel.selectedPhoto == nil && !newPhotos.isEmpty {
                                filesModel.selectedPhoto = newPhotos.first
                            }
                        }
                    }
                }
            }

            // Filter and Sort bar - only show when there are photos
            if !photos.isEmpty {
                HStack(spacing: 12) {
                    // Grid Type button - toggles between 3 and 4 columns
                    Button(action: {
                        // Toggle between 3 columns and 4 columns
                        gridType = (gridType == .threeColumns) ? .fourColumns : .threeColumns
                    }) {
                        Image(systemName: "square.grid.3x3.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                            .padding(0)
                            .background(Color.clear)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.leading, 8)

                    // Sort button
                    Button(action: {
                        showSortPopover.toggle()
                    }) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                            .padding(0)
                            .background(Color.clear)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .popover(isPresented: $showSortPopover) {
                        SortPopoverView(sortOption: $sortOption)
                    }
                    .onChange(of: sortOption) { _, newValue in
                        saveSortOption(newValue)
                    }

                    // Filter section with unified rounded rectangle
                    HStack(spacing: 2) {
                        // Filter button (existing functionality)
                        Button(action: {
                            showFilterPopover.toggle()
                        }) {
                            Text("Filter")
                                .font(.caption)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .popover(isPresented: $showFilterPopover) {
                            FilterPopoverView(selectedLabels: $selectedLabels, photos: photos)
                        }

                        // Horizontal filter checkmarks for available labels
                        ForEach(availableLabels, id: \.self) { label in
                            Button(action: {
                                if selectedLabels.contains(label) {
                                    selectedLabels.remove(label)
                                } else {
                                    selectedLabels.insert(label)
                                }
                            }) {
                                Image(systemName: selectedLabels.contains(label) ? "checkmark.square.fill" : "square")
                                    .foregroundColor(getColorForLabel(label))
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help(label) // Tooltip shows the label name on hover
                        }
                    }
                    .padding(.horizontal, 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                    )
                    .layoutPriority(1)

                    Spacer()

                    // Show selection count when multiple photos are selected
                    if selectedPhotos.count > 1 {
                        Text("\(selectedPhotos.count) of \(photos.count) selected")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .lineLimit(1)
                            .padding(.trailing, 8)
                    } else if selectedLabels.count > 0 {
                        Text("\(filteredPhotos.count) of \(photos.count) photos")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .padding(.trailing, 8)
                    } else {
                        Text("\(photos.count) photos")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .padding(.trailing, 8)
                    }
                }
                .frame(height: 40)
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .frame(width: gridWidth) // Apply exact width to fit thumbnail columns
    }

    private func handlePhotoTap(photo: PhotoItem, modifiers: NSEvent.ModifierFlags) {
        let photoIndex = filteredPhotos.firstIndex(where: { $0.id == photo.id }) ?? 0

        if modifiers.contains(.command) {
            // Command+click: Toggle individual selection
            if selectedPhotos.contains(photo.id) {
                selectedPhotos.remove(photo.id)
            } else {
                selectedPhotos.insert(photo.id)
                filesModel.selectedPhoto = photo
                lastSelectedIndex = photoIndex
            }
        } else if modifiers.contains(.shift) && lastSelectedIndex != nil {
            // Shift+click: Select range from last selected to current
            let startIndex = min(lastSelectedIndex!, photoIndex)
            let endIndex = max(lastSelectedIndex!, photoIndex)

            for index in startIndex...endIndex {
                selectedPhotos.insert(filteredPhotos[index].id)
            }
            filesModel.selectedPhoto = photo
        } else {
            // Regular click: Clear selection and select single photo
            selectedPhotos.removeAll()
            selectedPhotos.insert(photo.id)
            filesModel.selectedPhoto = photo
            lastSelectedIndex = photoIndex
        }
    }

    private func handleKeyPress(_ keyPress: KeyPress, proxy: ScrollViewProxy, viewportHeight: CGFloat) -> KeyPress.Result {
        guard !filteredPhotos.isEmpty else { return .ignored }

        let currentIndex = filteredPhotos.firstIndex { $0.id == filesModel.selectedPhoto?.id } ?? 0
        var newIndex = currentIndex

        switch keyPress.key {
        case .leftArrow:
            newIndex = max(0, currentIndex - 1)
        case .rightArrow:
            newIndex = min(filteredPhotos.count - 1, currentIndex + 1)
        case .upArrow:
            newIndex = max(0, currentIndex - columnsCount)
        case .downArrow:
            newIndex = min(filteredPhotos.count - 1, currentIndex + columnsCount)
        case .return:
            // Enter key: Open selected photos in external app
            if selectedPhotos.count > 1 {
                openSelectedPhotosInExternalApp()
            } else if let selectedPhoto = filesModel.selectedPhoto {
                openInExternalApp(photo: selectedPhoto)
            }
            return .handled
        case .space:
            // Space key: Enter review mode
            if filesModel.selectedPhoto != nil && !filteredPhotos.isEmpty {
                onEnterReviewMode?()
            }
            return .handled
        default:
            // Handle Command+A for Select All
            if keyPress.modifiers.contains(.command) && keyPress.characters == "a" {
                selectedPhotos.removeAll()
                for photo in filteredPhotos {
                    selectedPhotos.insert(photo.id)
                }
                if let firstPhoto = filteredPhotos.first {
                    filesModel.selectedPhoto = firstPhoto
                    lastSelectedIndex = 0
                }
                return .handled
            }

            // Handle label keys (6-0 for different labels)
            let labelKey = keyPress.characters
            var targetLabel: String? = nil

            switch labelKey {
            case "1":
                // Rating key: Set 1 star
                applyRatingToSelectedPhotos(rating: 1)
                return .handled
            case "2":
                // Rating key: Set 2 stars
                applyRatingToSelectedPhotos(rating: 2)
                return .handled
            case "3":
                // Rating key: Set 3 stars
                applyRatingToSelectedPhotos(rating: 3)
                return .handled
            case "4":
                // Rating key: Set 4 stars
                applyRatingToSelectedPhotos(rating: 4)
                return .handled
            case "5":
                // Rating key: Set 5 stars
                applyRatingToSelectedPhotos(rating: 5)
                return .handled
            case "6":
                targetLabel = "Select"
            case "7":
                targetLabel = "Second"
            case "8":
                targetLabel = "Approved"
            case "9":
                targetLabel = "Review"
            case "0":
                targetLabel = "To Do"
            case "-":
                // Remove any label (clear label)
                applyLabelRemovalToSelectedPhotos()
                return .handled
            case "\u{7F}": // Delete key (backspace character)
                // Toggle "To Delete" state
                applyDeleteToggleToSelectedPhotos()
                return .handled
            case "d", "D": // 'd' key for marking for deletion
                // Toggle "To Delete" state
                applyDeleteToggleToSelectedPhotos()
                return .handled
            default:
                return .ignored
            }

            // Handle both direct key press and Command+key combinations for label keys
            if labelKey == "6" || labelKey == "7" || labelKey == "8" || labelKey == "9" || labelKey == "0" ||
                (keyPress.modifiers.contains(.command) && (labelKey == "6" || labelKey == "7" || labelKey == "8" || labelKey == "9" || labelKey == "0")) {

                if let label = targetLabel {
                    applyLabelToSelectedPhotos(label: label)
                } else {
                    print("DEBUG: No target label found")
                }
                return .handled
            }
        }
        print(">>>>> currentIndex \(currentIndex) newIndex \(newIndex)")

        if newIndex != currentIndex {
            selectedPhotos = [filteredPhotos[newIndex].id]

            filesModel.selectedPhoto = filteredPhotos[newIndex]
            lastSelectedIndex = newIndex

            // Auto-scroll to keep selected photo visible
            proxy.scrollTo(filteredPhotos[newIndex].id, anchor: .center)

            return .handled
        }

        return .ignored
    }

    private func removeAnyLabel(for photo: PhotoItem) {
        let photoURL = URL(fileURLWithPath: photo.path)
        let photoDirectory = photoURL.deletingLastPathComponent()
        let photoName = photoURL.deletingPathExtension().lastPathComponent
        let xmpFileName = "\(photoName).xmp"
        let xmpFileURL = photoDirectory.appendingPathComponent(xmpFileName)

        var xmpContent: String

        // Read existing XMP file if it exists
        if FileManager.default.fileExists(atPath: xmpFileURL.path) {
            do {
                xmpContent = try String(contentsOf: xmpFileURL, encoding: .utf8)
                print("📖 Read existing XMP file for label removal")

                // Remove the label by setting it to empty
                xmpContent = updateXmpLabel(in: xmpContent, newLabel: nil)
                print("🗑️ Removing any existing label")

            } catch {
                print("⚠️ Failed to read existing XMP file: \(error)")
                return
            }
        } else {
            print("📄 No XMP file exists - photo already has no label")
            return
        }

        // Save the updated XMP content
        do {
            try xmpContent.write(to: xmpFileURL, atomically: true, encoding: .utf8)
            print("✅ XMP file updated: Label removed")

            // Parse the updated XMP content to get the new metadata
            if let parsedMetadata = XmpParser.parseMetadata(from: xmpContent) {
                print("🏷️ Label after removal: \(parsedMetadata.label ?? "None")")

                // Update the photo item with the updated XMP metadata
                updatePhotoWithXmpMetadata(photo: photo, xmpMetadata: parsedMetadata)
            } else {
                print("⚠️ Failed to parse updated XMP metadata")
            }

        } catch {
            print("❌ Failed to save XMP file for \(photo.path): \(error)")
        }
    }

    private func createAndSaveXmpFile(for photo: PhotoItem, targetLabel: String) {
        let photoURL = URL(fileURLWithPath: photo.path)
        let photoDirectory = photoURL.deletingLastPathComponent()
        let photoName = photoURL.deletingPathExtension().lastPathComponent
        let xmpFileName = "\(photoName).xmp"
        let xmpFileURL = photoDirectory.appendingPathComponent(xmpFileName)

        var xmpContent: String
        var currentLabel: String? = nil

        // Read existing XMP file if it exists
        if FileManager.default.fileExists(atPath: xmpFileURL.path) {
            do {
                xmpContent = try String(contentsOf: xmpFileURL, encoding: .utf8)

                // Parse existing metadata to get current label
                if let existingMetadata = XmpParser.parseMetadata(from: xmpContent) {
                    currentLabel = existingMetadata.label
                    print("📖 Read existing XMP: Current label = \(currentLabel ?? "None")")
                }

                // Toggle the label: if currently matches targetLabel, set to none; otherwise set to targetLabel
                let newLabel: String? = (currentLabel == targetLabel) ? nil : targetLabel
                let labelAction = (newLabel == targetLabel) ? "Setting" : "Removing"
                print("🔄 \(labelAction) \(targetLabel) label")

                // Update only the xmp:Label attribute in the existing XMP content
                xmpContent = updateXmpLabel(in: xmpContent, newLabel: newLabel)

            } catch {
                print("⚠️ Failed to read existing XMP file: \(error)")
                return
            }
        } else {
            print("📄 No existing XMP file found, will create new one")

            // Create new XMP file using the template with the target label
            xmpContent = XmpParser.createXmpContent(rating: photo.xmp?.rating ?? 0, label: targetLabel)
            print("🔄 Setting \(targetLabel) label")
        }

        // Save the updated XMP content
        do {
            try xmpContent.write(to: xmpFileURL, atomically: true, encoding: .utf8)
            print("✅ XMP file saved: \(xmpFileName)")
            print("📁 Location: \(photoDirectory.path)")

            // Parse the updated XMP content to get the new metadata
            if let parsedMetadata = XmpParser.parseMetadata(from: xmpContent) {
                print("🏷️ Label: \(parsedMetadata.label ?? "None")")
                print("📋 Parsed XMP metadata: Label = \(parsedMetadata.label ?? "None")")

                // Update the photo item with the new XMP metadata
                updatePhotoWithXmpMetadata(photo: photo, xmpMetadata: parsedMetadata)
            } else {
                print("⚠️ Failed to parse updated XMP metadata")
            }

        } catch {
            print("❌ Failed to save XMP file for \(photo.path): \(error)")
        }
    }

    private func updateXmpLabel(in xmpContent: String, newLabel: String?) -> String {
        var updatedContent = xmpContent

        // Look for existing xmp:Label attribute in the rdf:Description tag
        let labelPattern = #"xmp:Label="[^"]*""#

        if let range = updatedContent.range(of: labelPattern, options: .regularExpression) {
            if let newLabel = newLabel {
                // Update existing xmp:Label attribute with new value
                updatedContent.replaceSubrange(range, with: "xmp:Label=\"\(newLabel)\"")
                print("✏️ Updated xmp:Label to \"\(newLabel)\"")
            } else {
                // Update existing xmp:Label attribute to empty value (none)
                updatedContent.replaceSubrange(range, with: "xmp:Label=\"\"")
                print("✏️ Updated xmp:Label to empty (none)")
            }
        } else if let newLabel = newLabel {
            // No existing label, add new one with the value
            let descriptionPattern = #"(<rdf:Description[^>]*)"#
            if let match = updatedContent.range(of: descriptionPattern, options: .regularExpression) {
                let insertPosition = updatedContent.index(match.upperBound, offsetBy: 0)
                let labelAttribute = "\n   xmp:Label=\"\(newLabel)\""
                updatedContent.insert(contentsOf: labelAttribute, at: insertPosition)
                print("➕ Added new xmp:Label=\"\(newLabel)\" attribute")
            }
        }
        // If newLabel is nil and no existing label, do nothing (already in "none" state)

        // Update the MetadataDate
        let currentDate = Date()
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withTimeZone]
        let currentDateString = dateFormatter.string(from: currentDate)

        let metadataDatePattern = #"xmp:MetadataDate="[^"]*""#
        if let range = updatedContent.range(of: metadataDatePattern, options: .regularExpression) {
            updatedContent.replaceSubrange(range, with: "xmp:MetadataDate=\"\(currentDateString)\"")
            print("📅 Updated MetadataDate")
        } else {
            // If no MetadataDate exists, add it
            let descriptionPattern = #"(<rdf:Description[^>]*)"#
            if let match = updatedContent.range(of: descriptionPattern, options: .regularExpression) {
                let insertPosition = updatedContent.index(match.upperBound, offsetBy: 0)
                let metadataAttribute = "\n   xmp:MetadataDate=\"\(currentDateString)\""
                updatedContent.insert(contentsOf: metadataAttribute, at: insertPosition)
                print("📅 Added MetadataDate")
            }
        }

        return updatedContent
    }

    private func toggleToDeleteState(for photo: PhotoItem) {
        // Find the current photo index in the filesModel's photos array
        if let photoIndex = filesModel.photos.firstIndex(where: { $0.path == photo.path }) {
            let currentPhoto = filesModel.photos[photoIndex]

            // Create a new PhotoItem with toggled toDelete state, preserving all other properties
            let updatedPhoto = PhotoItem(
                id: currentPhoto.id,
                path: currentPhoto.path,
                xmp: currentPhoto.xmp,
                dateCreated: currentPhoto.dateCreated,
                toDelete: !currentPhoto.toDelete
            )

            // Update the photos array directly
            filesModel.photos[photoIndex] = updatedPhoto

            // Always update selectedPhoto to point to the new updated photo instance (same photo, just updated)
            filesModel.selectedPhoto = updatedPhoto

            let action = updatedPhoto.toDelete ? "Marked" : "Unmarked"
            print("🗑️ \(action) photo for deletion: \(photo.path)")
        } else {
            print("⚠️ Photo not found in filesModel: \(photo.path)")
        }
    }

    private func updatePhotoWithXmpMetadata(photo: PhotoItem, xmpMetadata: XmpMetadata) {
        // Find the current photo index in the filesModel's photos array
        if let photoIndex = filesModel.photos.firstIndex(where: { $0.path == photo.path }) {
            let currentPhoto = filesModel.photos[photoIndex]

            // Create a new PhotoItem with the updated XMP metadata but preserve the original ID, dateCreated, and toDelete state
            let updatedPhoto = PhotoItem(
                id: photo.id,
                path: photo.path,
                xmp: xmpMetadata,
                dateCreated: photo.dateCreated,
                toDelete: currentPhoto.toDelete
            )

            // Update the photos array directly (since BrowserModel is @Published)
            filesModel.photos[photoIndex] = updatedPhoto

            // Update selectedPhoto to point to the new updated photo instance (same photo, just updated)
            filesModel.selectedPhoto = updatedPhoto

            print("🔄 PhotoItem updated in filesModel with XMP metadata")
            print("   Path: \(photo.path)")
            print("   Label: \(xmpMetadata.label ?? "None")")
            print("   To Delete: \(updatedPhoto.toDelete)")
            print("   Index: \(photoIndex)")
            print("   ID preserved: \(photo.id)")
        } else {
            print("⚠️ Photo not found in filesModel: \(photo.path)")
        }
    }

    // MARK: - Bulk Action Helper Functions

    private func applyRatingToSelectedPhotos(rating: Int) {
        let photosToUpdate = getSelectedPhotosForBulkAction()
        guard !photosToUpdate.isEmpty else { return }

        print("📊 Applying rating \(rating) to \(photosToUpdate.count) selected photos")

        for photo in photosToUpdate {
            setPhotoRating(photo: photo, rating: rating)
        }
    }

    private func applyLabelToSelectedPhotos(label: String) {
        let photosToUpdate = getSelectedPhotosForBulkAction()
        guard !photosToUpdate.isEmpty else { return }

        print("🏷️ Applying label '\(label)' to \(photosToUpdate.count) selected photos")

        for photo in photosToUpdate {
            createAndSaveXmpFile(for: photo, targetLabel: label)
        }
    }

    private func applyLabelRemovalToSelectedPhotos() {
        let photosToUpdate = getSelectedPhotosForBulkAction()
        guard !photosToUpdate.isEmpty else { return }

        print("🗑️ Removing labels from \(photosToUpdate.count) selected photos")

        for photo in photosToUpdate {
            removeAnyLabel(for: photo)
        }
    }

    private func applyDeleteToggleToSelectedPhotos() {
        let photosToUpdate = getSelectedPhotosForBulkAction()
        guard !photosToUpdate.isEmpty else { return }

        print("🗑️ Toggling delete state for \(photosToUpdate.count) selected photos")

        for photo in photosToUpdate {
            toggleToDeleteState(for: photo)
        }
    }

    private func getSelectedPhotosForBulkAction() -> [PhotoItem] {
        if selectedPhotos.count > 1 {
            // Multiple photos selected - apply to all selected photos
            return filteredPhotos.filter { selectedPhotos.contains($0.id) }
        } else if let selectedPhoto = filesModel.selectedPhoto {
            // Single photo selected - apply to just that photo
            return [selectedPhoto]
        } else {
            // No photo selected
            print("DEBUG: No photos selected for bulk action")
            return []
        }
    }

    private func setPhotoRating(photo: PhotoItem, rating: Int) {
        let photoURL = URL(fileURLWithPath: photo.path)
        let photoDirectory = photoURL.deletingLastPathComponent()
        let photoName = photoURL.deletingPathExtension().lastPathComponent
        let xmpFileName = "\(photoName).xmp"
        let xmpFileURL = photoDirectory.appendingPathComponent(xmpFileName)

        var xmpContent: String

        // Read existing XMP file if it exists
        if FileManager.default.fileExists(atPath: xmpFileURL.path) {
            do {
                xmpContent = try String(contentsOf: xmpFileURL, encoding: .utf8)
                print("📖 Read existing XMP file for rating update")

                // Update the rating in the existing XMP content
                xmpContent = XmpParser.updateRating(in: xmpContent, rating: rating)
                print("⭐ Setting rating to \(rating) stars")

            } catch {
                print("⚠️ Failed to read existing XMP file: \(error)")
                return
            }
        } else {
            print("📄 No existing XMP file found, will create new one with rating")

            // Create new XMP file with the rating
            xmpContent = XmpParser.createXmpContent(rating: rating, label: photo.xmp?.label)
            print("⭐ Creating new XMP file with \(rating) stars")
        }

        // Save the updated XMP content
        do {
            try xmpContent.write(to: xmpFileURL, atomically: true, encoding: .utf8)
            print("✅ XMP file saved with rating: \(rating)")
            print("📁 Location: \(photoDirectory.path)")

            // Parse the updated XMP content to get the new metadata
            if let parsedMetadata = XmpParser.parseMetadata(from: xmpContent) {
                print("⭐ Rating: \(parsedMetadata.rating ?? 0)")
                print("📋 Parsed XMP metadata: Rating = \(parsedMetadata.rating ?? 0)")

                // Update the photo item with the new XMP metadata
                updatePhotoWithXmpMetadata(photo: photo, xmpMetadata: parsedMetadata)
            } else {
                print("⚠️ Failed to parse updated XMP metadata")
            }

        } catch {
            print("❌ Failed to save XMP file for \(photo.path): \(error)")
        }
    }

    private func openSelectedPhotosInExternalApp() {
        // Get all selected photos
        let selectedPhotoItems = filteredPhotos.filter { selectedPhotos.contains($0.id) }
        externalAppManager.openPhotos(selectedPhotoItems, with: selectedApp)
    }

    private func openInExternalApp(photo: PhotoItem) {
        externalAppManager.openPhoto(photo, with: selectedApp)
    }

    private func saveSortOption(_ option: SortOption) {
        UserDefaults.standard.set(option.rawValue, forKey: sortOptionKey)
    }

    private func loadSortOption() {
        if let savedOption = UserDefaults.standard.string(forKey: sortOptionKey),
           let option = SortOption(rawValue: savedOption) {
            sortOption = option
        }
    }
}

struct ViewOffsetKey: PreferenceKey {
    typealias Value = CGFloat
    static var defaultValue = CGFloat.zero
    static func reduce(value: inout Value, nextValue: () -> Value) {
        value += nextValue()
    }
}
