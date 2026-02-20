//
//  ContentView.swift
//  Imagin Raw
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
                        .focusEffectDisabled()
                }
            }
        }
    }

    private var navigationTitle: String {
        guard let url = navigationDocumentURL else {
            return "Imagin Raw"
        }

        // Create a breadcrumb-style path
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        let breadcrumb = pathComponents.joined(separator: " › ")

        // Debug output

        return breadcrumb.isEmpty ? url.lastPathComponent : breadcrumb
    }

    private var navigationSplitView: some View {
        NavigationSplitView(columnVisibility: columnVisibility) {
            // Left sidebar: folders
            SidebarView {
                // Double-click callback: collapse sidebar
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
                    .font(.system(size: 12, weight: .regular))
                Text("Open in \(selectedApp?.displayName ?? "Default App")")
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
            } catch {
                // Fallback to default application
                NSWorkspace.shared.open(url)
            }
        } else {
            // Use system default application
            NSWorkspace.shared.open(url)
        }
    }
}
