//
//  ContentView.swift
//  Imagin Bridge
//
//  Created by Cristian Baluta on 29.01.2026.
//

import SwiftUI

struct PhotoApp: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let bundleIdentifier: String
    let url: URL

    var displayName: String {
        return name
    }
}

struct ContentView: View {
    @StateObject private var filesModel = FilesModel()
    @StateObject private var externalAppManager = ExternalAppManager()
    @State private var selectedApp: PhotoApp?
    @SceneStorage("columnVisibility") private var columnVisibilityStorage: String = "all"
    @State private var showFolderPopover = false
    @State private var isSidebarCollapsed = false
    @State private var openSelectedPhotosCallback: (() -> Void)?
    @State private var isReviewModeActive = false
    @State private var contentColumnWidth: CGFloat = 450


    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: {
                switch columnVisibilityStorage {
                case "doubleColumn": return .doubleColumn
                case "detailOnly": return .detailOnly
                default: return .all
                }
            },
            set: {
                switch $0 {
                case .all: columnVisibilityStorage = "all"
                case .doubleColumn: columnVisibilityStorage = "doubleColumn"
                case .detailOnly: columnVisibilityStorage = "detailOnly"
                default: columnVisibilityStorage = "all"
                }
            }
        )
    }

    private var navigationDocumentURL: URL? {
        return filesModel.selectedFolder?.url
    }

    private var shareablePhoto: URL? {
        guard let selectedPhoto = filesModel.selectedPhoto else { return nil }
        return URL(fileURLWithPath: selectedPhoto.path)
    }

    var body: some View {
        ZStack {
            // Main app content
            Group {
                // Show splash screen if no folders are added
                if filesModel.rootFolders.isEmpty {
                    SplashScreenView()
                        .frame(minWidth: 800, minHeight: 600)
                        .preferredColorScheme(.dark)
                        .environmentObject(filesModel)
                } else {
                    // Normal app interface when folders exist
                    navigationSplitView
                        .navigationTitle(navigationTitle)
                        .onChange(of: columnVisibilityStorage) { _, newValue in
                            // Update our tracked state when the column visibility changes
                            isSidebarCollapsed = (newValue == "doubleColumn")
                        }
                        .toolbar {
                            toolbarContent
                        }
                        .onAppear {
                            // Load photo apps and selected app through ExternalAppManager
                            externalAppManager.loadPhotoApps {
                                selectedApp = externalAppManager.loadSelectedApp()
                            }

                            // Set initial sidebar collapsed state based on restored column visibility
                            isSidebarCollapsed = (columnVisibilityStorage == "doubleColumn")
                        }
                        .frame(minWidth: 1200, minHeight: 800)
                        .preferredColorScheme(.dark)
                        .focusable()
                        .onKeyPress { keyPress in
                            handleKeyPress(keyPress)
                        }
                        .onChange(of: isReviewModeActive) { _, newValue in
                            // Hide/show navigation elements based on review mode state
                            DispatchQueue.main.async {
                                if let window = NSApplication.shared.keyWindow {
                                    if newValue {
                                        // Entering review mode - hide navigation
                                        window.titlebarAppearsTransparent = true
                                        window.titleVisibility = .hidden
                                        window.toolbar?.isVisible = false
                                    } else {
                                        // Exiting review mode - show navigation
                                        window.titlebarAppearsTransparent = false
                                        window.titleVisibility = .visible
                                        window.toolbar?.isVisible = true
                                    }
                                }
                            }
                        }
                }
            }

            // Full-screen review mode overlay
            if isReviewModeActive {
                ReviewModeView(
                    photos: filesModel.photos.filter { photo in
                        // Apply same filtering logic as ThumbGridView
                        return true // For now, use all photos - we'll need to get filtered photos from ThumbGridView
                    },
                    selectedPhoto: $filesModel.selectedPhoto,
                    onExit: {
                        isReviewModeActive = false
                    },
                    onUpdatePhoto: { photo, xmpMetadata in
                        updatePhotoWithXmpMetadata(photo: photo, xmpMetadata: xmpMetadata)
                    },
                    onToggleDelete: { photo in
                        toggleToDeleteState(for: photo)
                    }
                )
                .zIndex(1000)
            }
        }
    }

    private var navigationTitle: String {
        guard let url = navigationDocumentURL else {
            return "Imagin Bridge"
        }

        // Create a breadcrumb-style path
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        let breadcrumb = pathComponents.joined(separator: " › ")

        // Debug output
        print("Navigation URL: \(url.path)")
        print("Path components: \(pathComponents)")
        print("Breadcrumb: \(breadcrumb)")

        return breadcrumb.isEmpty ? url.lastPathComponent : breadcrumb
    }

    private var navigationSplitView: some View {
        NavigationSplitView(columnVisibility: columnVisibility) {
            // Left sidebar: folders
            SidebarView {
                // Double-click callback: collapse sidebar to double column view
                columnVisibilityStorage = "doubleColumn"
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 200, max: 250)
            .environmentObject(filesModel)
        } content: {
            // Middle: thumbnails
            ThumbGridView(
                filesModel: filesModel,
                selectedApp: selectedApp,
                onOpenSelectedPhotos: { photos in
                    openMultiplePhotosInExternalApp(photos: photos)
                },
                onEnterReviewMode: {
                    isReviewModeActive = true
                }
            )
            .onPreferenceChange(GridWidthPreferenceKey.self) { width in
                contentColumnWidth = width
            }
            .navigationSplitViewColumnWidth(
                min: contentColumnWidth,
                ideal: contentColumnWidth,
                max: contentColumnWidth
            )
            .onAppear {
                // Set up the callback for the toolbar button
                openSelectedPhotosCallback = {
                    if let selectedPhoto = filesModel.selectedPhoto {
                        // Open the selected photo
                        openInExternalApp(photo: selectedPhoto)
                    }
                }
            }
        } detail: {
            detailView
            .navigationSplitViewColumnWidth(min: 400, ideal: 600)
        }
        .environmentObject(filesModel)
        .environmentObject(externalAppManager)
    }

    private var detailView: some View {
        Group {
            if let photo = filesModel.selectedPhoto {
                LargePreviewView(photo: photo)
                    .id(photo.id)
            } else {
                ShortcutsHelpView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            navigationToolbarItems
        }

        ToolbarItemGroup(placement: .primaryAction) {
            primaryActionToolbarItems
        }
    }

    @ViewBuilder
    private var navigationToolbarItems: some View {
        // Show folder selection button when sidebar is collapsed
        if isSidebarCollapsed {
            Button(action: {
                showFolderPopover = true
            }) {
                Image(systemName: "folder")
                    .foregroundColor(.primary)
            }
            .help("Select Folder")
            .popover(isPresented: $showFolderPopover) {
                FolderSelectionPopoverView()
                    .frame(width: 250, height: 500)
                    .environmentObject(filesModel)
            }
        }
    }

    @ViewBuilder
    private var primaryActionToolbarItems: some View {
        // Button to open in selected app
        Button(action: {
            // Use the callback from ThumbGridView to open selected photos
            openSelectedPhotosCallback?()
        }) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 12, weight: .medium))
                Text(selectedApp?.displayName ?? "Default App")
            }
            .foregroundColor(filesModel.selectedPhoto != nil ? .primary : .secondary)
        }
        .disabled(filesModel.selectedPhoto == nil)
        .help("Open in \(selectedApp?.displayName ?? "external app")")

        // Menu to select app
        appSelectionMenu

        Spacer().frame(width: 20)

        // Sharing/Export button
        if let photoURL = shareablePhoto {
            ShareLink(item: photoURL) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
            }
            .help("Share photo")
        } else {
            Button(action: {}) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .disabled(true)
            .help("Share photo")
        }
    }

    private var appSelectionMenu: some View {
        Menu {
            // Discovered photo apps section
            ForEach(externalAppManager.discoveredPhotoApps) { photoApp in
                Button(action: {
                    selectedApp = photoApp
                    externalAppManager.saveSelectedApp(photoApp)
                }) {
                    HStack {
                        Text(photoApp.displayName)
                        if selectedApp?.id == photoApp.id {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            if !externalAppManager.discoveredPhotoApps.isEmpty {
                Divider()
            }

            Button("Default App") {
                selectedApp = nil
                externalAppManager.saveSelectedApp(nil)
            }
        } label: {
        }
        .help("Select external app")
    }

    private func openMultiplePhotosInExternalApp(photos: [PhotoItem]) {
        externalAppManager.openPhotos(photos, with: selectedApp)
    }

    private func sharePhoto(_ photo: PhotoItem) {
        let url = URL(fileURLWithPath: photo.path)

        // Use NSSharingService to show the native macOS sharing popover
        let sharingService = NSSharingService(named: NSSharingService.Name.composeEmail)
        let sharingServices = NSSharingService.sharingServices(forItems: [url])

        // Create a sharing service picker to show all available sharing options
        let sharingServicePicker = NSSharingServicePicker(items: [url])

        // Find the main window to position the popover
        if let window = NSApp.mainWindow,
           let contentView = window.contentView {

            // Create a rect for the button (approximate position - you might need to adjust this)
            let rect = NSRect(x: contentView.bounds.maxX - 100, y: contentView.bounds.maxY - 50, width: 30, height: 30)

            sharingServicePicker.show(relativeTo: rect, of: contentView, preferredEdge: .minY)
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

    private func openWithDiscoveredApp(photo: PhotoItem, app: PhotoApp) {
        let url = URL(fileURLWithPath: photo.path)
        let workspace = NSWorkspace.shared

        do {
            try workspace.open([url], withApplicationAt: app.url, options: [], configuration: [:])
            print("Opening \(url.lastPathComponent) with \(app.displayName)")
        } catch {
            print("Failed to open \(url.lastPathComponent) with \(app.displayName): \(error)")
            // Fallback to default application
            NSWorkspace.shared.open(url)
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

    // MARK: - Review Mode Helper Methods

    private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        switch keyPress.key {
        case .space:
            // Enter review mode if a photo is selected
            if filesModel.selectedPhoto != nil && !filesModel.photos.isEmpty {
                isReviewModeActive = true
                return .handled
            }
            return .ignored
        default:
            return .ignored
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
        } else {
            print("⚠️ Photo not found in filesModel: \(photo.path)")
        }
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

    // MARK: - Grid Type Persistence

}

enum ExternalApp: CaseIterable {
    case photoshop
    case lightroom
    case dxo
    case defaultApp

    var displayName: String {
        switch self {
        case .photoshop: return "Adobe Photoshop"
        case .lightroom: return "Adobe Lightroom"
        case .dxo: return "DxO PhotoLab"
        case .defaultApp: return "Default App"
        }
    }

    var bundleID: String {
        switch self {
        case .photoshop: return "com.adobe.Photoshop"
        case .lightroom: return "com.adobe.LightroomCC"
        case .dxo: return "com.dxo.PhotoLab7" // May vary by version
        case .defaultApp: return "" // Not used for default
        }
    }
}
