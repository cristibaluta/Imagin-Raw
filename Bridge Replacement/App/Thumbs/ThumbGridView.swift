import SwiftUI

struct ThumbGridView: View {
    let photos: [PhotoItem]
    @ObservedObject var model: BrowserModel
    let selectedApp: PhotoApp?
    let onOpenSelectedPhotos: (([PhotoItem]) -> Void)?
    let onEnterReviewMode: (() -> Void)?
    @FocusState private var isFocused: Bool
    @State private var lastScrolledRow: Int = -1
    @State private var showFilterPopover = false
    @State private var selectedLabels: Set<String> = []
    @State private var showSortPopover = false
    @State private var sortOption: SortOption = .name
    @State private var selectedPhotos: Set<UUID> = []
    @State private var lastSelectedIndex: Int?

    private let sortOptionKey = "SelectedSortOption"

    enum SortOption: String, CaseIterable {
        case name = "Name"
        case dateCreated = "Date Created"
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

    let columns = [
        GridItem(.fixed(108), spacing: 8),
        GridItem(.fixed(108), spacing: 8),
        GridItem(.fixed(108), spacing: 8)
    ]
    private let columnsCount = 3

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
                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(filteredPhotos, id: \.id) { photo in
                                    ThumbCell(
                                        photo: photo,
                                        isSelected: model.selectedPhoto?.id == photo.id,
                                        isMultiSelected: selectedPhotos.contains(photo.id),
                                        onTap: { modifiers in
                                            handlePhotoTap(photo: photo, modifiers: modifiers)
                                        },
                                        onDoubleClick: {
                                            model.selectedPhoto = photo
                                            // If multiple photos are selected, open all of them
                                            if selectedPhotos.count > 1 {
                                                openSelectedPhotosInExternalApp()
                                            } else {
                                                openInExternalApp(photo: photo)
                                            }
                                        }
                                    )
                                    .frame(width: 100, height: 150)
                                    .id(photo.id)
                                }
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 4)
                        }
                        .scrollContentBackground(.hidden)
                        .focusable()
                        .focusEffectDisabled()
                        .focused($isFocused)
                        .onKeyPress { keyPress in
                            handleKeyPress(keyPress, proxy: proxy, viewportHeight: geometry.size.height)
                        }
                        .onAppear {
                            isFocused = true
                            if model.selectedPhoto == nil && !filteredPhotos.isEmpty {
                                model.selectedPhoto = filteredPhotos.first
                                selectedPhotos.removeAll()
                                if let firstPhoto = filteredPhotos.first {
                                    selectedPhotos.insert(firstPhoto.id)
                                }
                            }
                            loadSortOption() // Load the saved sort option
                        }
                        .onChange(of: photos) { _, newPhotos in
                            // Only select the first photo if there's no current selection
                            if model.selectedPhoto == nil && !newPhotos.isEmpty {
                                model.selectedPhoto = newPhotos.first
                            }
                        }
                    }
                }
            }

            // Filter and Sort bar
            HStack(spacing: 12) {
                // Sort button
                Button(action: {
                    showSortPopover.toggle()
                }) {
                    Text("Sort")
                        .font(.caption)
                        .foregroundColor(.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .popover(isPresented: $showSortPopover) {
                    SortPopoverView(sortOption: $sortOption)
                }
                .onChange(of: sortOption) { _, newValue in
                    saveSortOption(newValue)
                }

                // Filter section with unified rounded rectangle
                HStack(spacing: 8) {
                    // Filter button (existing functionality)
                    Button(action: {
                        showFilterPopover.toggle()
                    }) {
                        Text("Filter")
                            .font(.caption)
                            .foregroundColor(.primary)
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
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help(label) // Tooltip shows the label name on hover
                    }
                }
                .padding(.horizontal, 4)
                .background(Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                )

                Spacer()

                // Show selection count when multiple photos are selected
                if selectedPhotos.count > 1 {
                    Text("\(selectedPhotos.count) of \(photos.count) selected")
                        .font(.caption)
                        .foregroundColor(.blue)
                } else if selectedLabels.count > 0 {
                    Text("\(filteredPhotos.count) of \(photos.count) photos")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("\(photos.count) photos")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))
        }
    }

    private func handlePhotoTap(photo: PhotoItem, modifiers: NSEvent.ModifierFlags) {
        let photoIndex = filteredPhotos.firstIndex(where: { $0.id == photo.id }) ?? 0

        if modifiers.contains(.command) {
            // Command+click: Toggle individual selection
            if selectedPhotos.contains(photo.id) {
                selectedPhotos.remove(photo.id)
            } else {
                selectedPhotos.insert(photo.id)
                model.selectedPhoto = photo
                lastSelectedIndex = photoIndex
            }
        } else if modifiers.contains(.shift) && lastSelectedIndex != nil {
            // Shift+click: Select range from last selected to current
            let startIndex = min(lastSelectedIndex!, photoIndex)
            let endIndex = max(lastSelectedIndex!, photoIndex)

            for index in startIndex...endIndex {
                selectedPhotos.insert(filteredPhotos[index].id)
            }
            model.selectedPhoto = photo
        } else {
            // Regular click: Clear selection and select single photo
            selectedPhotos.removeAll()
            selectedPhotos.insert(photo.id)
            model.selectedPhoto = photo
            lastSelectedIndex = photoIndex
        }
    }

    private func handleKeyPress(_ keyPress: KeyPress, proxy: ScrollViewProxy, viewportHeight: CGFloat) -> KeyPress.Result {
        guard !filteredPhotos.isEmpty else { return .ignored }

        let currentIndex = filteredPhotos.firstIndex { $0.id == model.selectedPhoto?.id } ?? 0
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
            } else if let selectedPhoto = model.selectedPhoto {
                openInExternalApp(photo: selectedPhoto)
            }
            return .handled
        case .space:
            // Space key: Enter review mode
            if model.selectedPhoto != nil && !filteredPhotos.isEmpty {
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
                    model.selectedPhoto = firstPhoto
                    lastSelectedIndex = 0
                }
                return .handled
            }

            // Handle label keys (6-0 for different labels)
            let labelKey = keyPress.characters
            var targetLabel: String? = nil

            switch labelKey {
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
                if let selectedPhoto = model.selectedPhoto {
                    removeAnyLabel(for: selectedPhoto)
                } else {
                    print("DEBUG: No photo selected")
                }
                return .handled
            case "\u{7F}": // Delete key (backspace character)
                // Toggle "To Delete" state
                if let selectedPhoto = model.selectedPhoto {
                    toggleToDeleteState(for: selectedPhoto)
                } else {
                    print("DEBUG: No photo selected")
                }
                return .handled
            case "d", "D": // 'd' key for marking for deletion
                // Toggle "To Delete" state
                if let selectedPhoto = model.selectedPhoto {
                    toggleToDeleteState(for: selectedPhoto)
                } else {
                    print("DEBUG: No photo selected")
                }
                return .handled
            default:
                return .ignored
            }

            // Handle both direct key press and Command+key combinations for label keys
            if labelKey == "6" || labelKey == "7" || labelKey == "8" || labelKey == "9" || labelKey == "0" ||
               (keyPress.modifiers.contains(.command) && (labelKey == "6" || labelKey == "7" || labelKey == "8" || labelKey == "9" || labelKey == "0")) {

                if let selectedPhoto = model.selectedPhoto, let label = targetLabel {
                    createAndSaveXmpFile(for: selectedPhoto, targetLabel: label)
                } else {
                    print("DEBUG: No photo selected")
                }
                return .handled
            }

            return .ignored
        }

        if newIndex != currentIndex {
            // Clear multi-selection when navigating with arrow keys
            selectedPhotos.removeAll()
            selectedPhotos.insert(filteredPhotos[newIndex].id)

            model.selectedPhoto = filteredPhotos[newIndex]
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

            // Create minimal XMP file with the target label
            let currentDate = Date()
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime, .withTimeZone]
            let currentDateString = dateFormatter.string(from: currentDate)
            let instanceID = UUID().uuidString.lowercased()

            xmpContent = """
<?xml version="1.0" encoding="UTF-8"?>
<x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Adobe XMP Core 7.0-c000 1.000000, 0000/00/00-00:00:00        ">
 <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
  <rdf:Description rdf:about=""
    xmlns:xmp="http://ns.adobe.com/xap/1.0/"
    xmlns:xmpMM="http://ns.adobe.com/xap/1.0/mm/"
    xmlns:stEvt="http://ns.adobe.com/xap/1.0/sType/ResourceEvent#"
   xmp:Label="\(targetLabel)"
   xmp:MetadataDate="\(currentDateString)"
   xmpMM:InstanceID="xmp.iid:\(instanceID)">
   <xmpMM:History>
    <rdf:Seq>
     <rdf:li
      stEvt:action="saved"
      stEvt:instanceID="xmp.iid:\(instanceID)"
      stEvt:when="\(currentDateString)"
      stEvt:softwareAgent="Bridge Replacement"
      stEvt:changed="/metadata"/>
    </rdf:Seq>
   </xmpMM:History>
  </rdf:Description>
 </rdf:RDF>
</x:xmpmeta>
"""
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
        // Find the current photo index in the model's photos array
        if let photoIndex = model.photos.firstIndex(where: { $0.path == photo.path }) {
            let currentPhoto = model.photos[photoIndex]

            // Create a new PhotoItem with toggled toDelete state, preserving all other properties
            let updatedPhoto = PhotoItem(
                id: currentPhoto.id,
                path: currentPhoto.path,
                xmp: currentPhoto.xmp,
                dateCreated: currentPhoto.dateCreated,
                toDelete: !currentPhoto.toDelete
            )

            // Update the photos array directly
            model.photos[photoIndex] = updatedPhoto

            // Always update selectedPhoto to point to the new updated photo instance (same photo, just updated)
            model.selectedPhoto = updatedPhoto

            let action = updatedPhoto.toDelete ? "Marked" : "Unmarked"
            print("🗑️ \(action) photo for deletion: \(photo.path)")
        } else {
            print("⚠️ Photo not found in model: \(photo.path)")
        }
    }

    private func updatePhotoWithXmpMetadata(photo: PhotoItem, xmpMetadata: XmpMetadata) {
        // Find the current photo index in the model's photos array
        if let photoIndex = model.photos.firstIndex(where: { $0.path == photo.path }) {
            let currentPhoto = model.photos[photoIndex]

            // Create a new PhotoItem with the updated XMP metadata but preserve the original ID, dateCreated, and toDelete state
            let updatedPhoto = PhotoItem(
                id: photo.id,
                path: photo.path,
                xmp: xmpMetadata,
                dateCreated: photo.dateCreated,
                toDelete: currentPhoto.toDelete
            )

            // Update the photos array directly (since BrowserModel is @Published)
            model.photos[photoIndex] = updatedPhoto

            // Update selectedPhoto to point to the new updated photo instance (same photo, just updated)
            model.selectedPhoto = updatedPhoto

            print("🔄 PhotoItem updated in model with XMP metadata")
            print("   Path: \(photo.path)")
            print("   Label: \(xmpMetadata.label ?? "None")")
            print("   To Delete: \(updatedPhoto.toDelete)")
            print("   Index: \(photoIndex)")
            print("   ID preserved: \(photo.id)")
        } else {
            print("⚠️ Photo not found in model: \(photo.path)")
        }
    }

    private func openSelectedPhotosInExternalApp() {
        // Get all selected photos
        let selectedPhotoItems = filteredPhotos.filter { selectedPhotos.contains($0.id) }
        let urls = selectedPhotoItems.map { URL(fileURLWithPath: $0.path) }

        guard !urls.isEmpty else { return }

        if let app = selectedApp {
            // Use the selected PhotoApp
            do {
                try NSWorkspace.shared.open(urls, withApplicationAt: app.url, options: [], configuration: [:])
                print("Opening \(urls.count) photos with \(app.displayName)")
            } catch {
                print("Failed to open photos with \(app.displayName): \(error)")
                // Fallback to default application
                for url in urls {
                    NSWorkspace.shared.open(url)
                }
                print("Opening \(urls.count) photos in default app (fallback)")
            }
        } else {
            // Use system default application
            for url in urls {
                NSWorkspace.shared.open(url)
            }
            print("Opening \(urls.count) photos in default app")
        }
    }

    private func openInExternalApp(photo: PhotoItem) {
        let url = URL(fileURLWithPath: photo.path)

        if let app = selectedApp {
            // Use the selected PhotoApp
            do {
                try NSWorkspace.shared.open([url], withApplicationAt: app.url, options: [], configuration: [:])
                print("Opening \(url.lastPathComponent) with \(app.displayName)")
            } catch {
                print("Failed to open \(url.lastPathComponent) with \(app.displayName): \(error)")
                // Fallback to default application
                NSWorkspace.shared.open(url)
                print("Opening \(url.lastPathComponent) in default app (fallback)")
            }
        } else {
            // Use system default application
            NSWorkspace.shared.open(url)
            print("Opening \(url.lastPathComponent) in default app")
        }
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
