import SwiftUI

struct ThumbGridView: View {
    let photos: [PhotoItem]
    @ObservedObject var model: BrowserModel
    @FocusState private var isFocused: Bool
    @State private var lastScrolledRow: Int = -1
    @State private var showFilterPopover = false
    @State private var selectedLabels: Set<String> = []
    @State private var showSortPopover = false
    @State private var sortOption: SortOption = .name

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
                let photoLabel = photo.xmp?.label ?? ""

                // Handle "No Label" filter
                if selectedLabels.contains("No Label") && photoLabel.isEmpty {
                    return true
                }

                // Handle other specific labels
                return selectedLabels.contains(photoLabel)
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

        for photo in photos {
            if let label = photo.xmp?.label, !label.isEmpty {
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
        default:
            return .secondary
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main thumbnail grid
            ScrollViewReader { proxy in
                GeometryReader { geometry in
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(filteredPhotos, id: \.id) { photo in
                                ThumbCell(photo: photo, isSelected: model.selectedPhoto?.id == photo.id)
                                    .frame(width: 100, height: 150)
                                    .id(photo.id)
                                    .onTapGesture {
                                        model.selectedPhoto = photo
                                    }
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
                        }
                        loadSortOption() // Load the saved sort option
                    }
                    .onChange(of: photos) { _, newPhotos in
                        if !newPhotos.isEmpty {
                            model.selectedPhoto = newPhotos.first
                        }
                    }
                }
            }

            // Filter and Sort bar
            HStack(spacing: 12) {
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
                        FilterPopoverView(selectedLabels: $selectedLabels)
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

                if !selectedLabels.isEmpty {
                    Text("\(filteredPhotos.count) of \(photos.count) photos")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

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
                                .stroke(Color.gray, lineWidth: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .popover(isPresented: $showSortPopover) {
                    SortPopoverView(sortOption: $sortOption)
                }
                .onChange(of: sortOption) { _, newValue in
                    saveSortOption(newValue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))
        }
    }

    private func handleKeyPress(_ keyPress: KeyPress, proxy: ScrollViewProxy, viewportHeight: CGFloat) -> KeyPress.Result {
        guard !photos.isEmpty else { return .ignored }

        let currentIndex = photos.firstIndex { $0.id == model.selectedPhoto?.id } ?? 0
        var newIndex = currentIndex

        switch keyPress.key {
        case .leftArrow:
            newIndex = max(0, currentIndex - 1)
        case .rightArrow:
            newIndex = min(photos.count - 1, currentIndex + 1)
        case .upArrow:
            newIndex = max(0, currentIndex - columnsCount)
        case .downArrow:
            newIndex = min(photos.count - 1, currentIndex + columnsCount)
        default:
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
            default:
                return .ignored
            }

            // Handle both direct key press and Command+key combinations
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
            model.selectedPhoto = photos[newIndex]

            // Auto-scroll only when moving vertically and reaching visible edges
            if keyPress.key == .upArrow || keyPress.key == .downArrow {
                let currentRow = currentIndex / columnsCount
                let newRow = newIndex / columnsCount
                let totalRows = (photos.count + columnsCount - 1) / columnsCount

                if newRow != currentRow && newRow != lastScrolledRow {
                    let thumbnailHeight: CGFloat = 150 + 8
                    let visibleRows = Int(viewportHeight / thumbnailHeight)

                    // Only scroll when we have enough content to warrant scrolling
                    guard totalRows > visibleRows else { return .handled }

                    // Calculate approximate visible range (this is simplified but effective)
                    let middleRow = totalRows / 2
                    let scrollTriggerDistance = visibleRows / 3 // Trigger when 1/3 from edge

                    // Check if we're approaching edges of the entire dataset
                    // This will effectively scroll when reaching visible viewport edges
                    let isApproachingTop = newRow < scrollTriggerDistance
                    let isApproachingBottom = newRow > (totalRows - scrollTriggerDistance)

                    // Also scroll periodically to keep selection visible in large datasets
                    let shouldPeriodicScroll = abs(newRow - middleRow) % (visibleRows - 1) == 0

                    if isApproachingTop || isApproachingBottom || (shouldPeriodicScroll && totalRows > visibleRows * 2) {
                        lastScrolledRow = newRow
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(photos[newIndex].id, anchor: UnitPoint.center)
                        }
                    }
                }
            }

            return .handled
        }

        return .ignored
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

    private func updatePhotoWithXmpMetadata(photo: PhotoItem, xmpMetadata: XmpMetadata) {
        // Find the current photo index in the model's photos array
        if let photoIndex = model.photos.firstIndex(where: { $0.path == photo.path }) {
            // Create a new PhotoItem with the updated XMP metadata but preserve the original ID and dateCreated
            let updatedPhoto = PhotoItem(id: photo.id, path: photo.path, xmp: xmpMetadata, dateCreated: photo.dateCreated)

            // Update the photos array directly (since BrowserModel is @Published)
            model.photos[photoIndex] = updatedPhoto

            // Update selectedPhoto if it's the one being modified
            if model.selectedPhoto?.path == photo.path {
                model.selectedPhoto = updatedPhoto
            }

            print("🔄 PhotoItem updated in model with XMP metadata")
            print("   Path: \(photo.path)")
            print("   Label: \(xmpMetadata.label ?? "None")")
            print("   Index: \(photoIndex)")
            print("   ID preserved: \(photo.id)")
        } else {
            print("⚠️ Photo not found in model: \(photo.path)")
        }
    }

    private func openInExternalApp(photo: PhotoItem) {
        let url = URL(fileURLWithPath: photo.path)

        // TODO: This will be configurable from UI later
        let preferredApp = ExternalApp.photoshop

        if openWithSpecificApp(url: url, app: preferredApp) {
            print("Opening \(url.lastPathComponent) in \(preferredApp.displayName)")
        } else {
            // Fallback to default application
            NSWorkspace.shared.open(url)
            print("Opening \(url.lastPathComponent) in default app")
        }
    }

    private func openWithSpecificApp(url: URL, app: ExternalApp) -> Bool {
        let workspace = NSWorkspace.shared

        // Try to find the application bundle
        guard let appURL = workspace.urlForApplication(withBundleIdentifier: app.bundleID) else {
            print("App \(app.displayName) not found (Bundle ID: \(app.bundleID))")
            return false
        }

        do {
            try workspace.open([url], withApplicationAt: appURL, options: [], configuration: [:])
            return true
        } catch {
            print("Failed to open \(url.lastPathComponent) with \(app.displayName): \(error)")
            return false
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
