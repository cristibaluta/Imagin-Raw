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
    @StateObject private var model = BrowserModel()
    @State private var selectedApp: PhotoApp?
    @State private var discoveredPhotoApps: [PhotoApp] = []
    @SceneStorage("columnVisibility") private var columnVisibilityStorage: String = "all"
    @State private var showFolderPopover = false
    @State private var isSidebarCollapsed = false

    private let selectedAppKey = "SelectedExternalApp"

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

    var body: some View {
        NavigationSplitView(columnVisibility: columnVisibility) {
            // Left sidebar: folders
            SidebarView(model: model)
        } content: {
            // Middle: thumbnails
            ThumbGridView(photos: model.photos, model: model)
        } detail: {
            // Right: large preview
            if let photo = model.selectedPhoto {
                LargePreviewView(photo: photo)
                    .id(photo.id)
            } else {
                Text("Select a photo")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle(model.selectedFolder?.url.path ?? "No Folder Selected")
        .onChange(of: columnVisibilityStorage) { _, newValue in
            // Update our tracked state when the column visibility changes
            isSidebarCollapsed = (newValue == "doubleColumn")
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
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
                        FolderSelectionPopoverView(model: model)
                            .frame(width: 300, height: 400)
                    }
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                // Button to open in selected app
                Button(action: {
                    if let selectedPhoto = model.selectedPhoto {
                        openInExternalApp(photo: selectedPhoto)
                    }
                }) {
                    Text(selectedApp?.displayName ?? "Select App")
                        .foregroundColor(model.selectedPhoto != nil ? .primary : .secondary)
                }
                .disabled(model.selectedPhoto == nil)
                .help("Open in \(selectedApp?.displayName ?? "external app")")

                // Menu to select app
                Menu {
                    // Discovered photo apps section
                    ForEach(discoveredPhotoApps) { photoApp in
                        Button(action: {
                            selectedApp = photoApp
                            saveSelectedApp()
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

                    if !discoveredPhotoApps.isEmpty {
                        Divider()
                    }

                    Button("Default App") {
                        selectedApp = nil
                        saveSelectedApp()
                    }
                } label: {
                }
                .help("Select external app")
            }
        }
        .onAppear {
            loadPhotoApps() // Load photo apps first
            // loadSelectedApp is now called from within loadPhotoApps after discovery completes

            // Set initial sidebar collapsed state based on restored column visibility
            isSidebarCollapsed = (columnVisibilityStorage == "doubleColumn")
        }
        .frame(minWidth: 1200, minHeight: 700)
        .preferredColorScheme(.dark)
        .background(Rectangle().fill(Color(red: 0.05, green: 0.05, blue: 0.06)).opacity(0.5))
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

    private func saveSelectedApp() {
        if let app = selectedApp {
            UserDefaults.standard.set(app.bundleIdentifier, forKey: selectedAppKey)
        } else {
            UserDefaults.standard.removeObject(forKey: selectedAppKey)
        }
    }

    private func loadSelectedApp() {
        guard let savedBundleID = UserDefaults.standard.string(forKey: selectedAppKey) else {
            selectedApp = nil
            return
        }

        // Find the app with matching bundle identifier from discovered apps
        selectedApp = discoveredPhotoApps.first { $0.bundleIdentifier == savedBundleID }
    }

    private func loadPhotoApps() {
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
        query.predicate = NSPredicate(
            format: "kMDItemContentTypeTree == 'com.apple.application-bundle'"
        )

        query.start()

        NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query,
            queue: .main
        ) { _ in
            query.stop()

            // Keywords to identify photo editing applications
            let photoKeywords = [
                "photo", "lightroom", "photoshop", "After-Effects", "Premiere-Pro",
                "com.dxo", "captureone", "photoraw",
                ".luminar", "affinity", "pixelmator", "gimp", "sketch", "canva",
                "adobe", ".on1.", "topaz", "nik", "hdr", "panorama", "preview"
            ]

            var apps: [PhotoApp] = []

            for item in query.results {
                guard let mdItem = item as? NSMetadataItem,
                      let path = mdItem.value(forAttribute: kMDItemPath as String) as? String,
                      let bundle = Bundle(path: path),
                      let bundleID = bundle.bundleIdentifier
                else { continue }

                let name = bundle.object(
                    forInfoDictionaryKey: "CFBundleDisplayName"
                ) as? String
                ?? bundle.object(
                    forInfoDictionaryKey: "CFBundleName"
                ) as? String
                ?? (path as NSString).lastPathComponent

                // Check if app name contains photo-related keywords
                let appNameLowercased = bundleID.lowercased()
                let isPhotoApp = photoKeywords.contains { keyword in
                    appNameLowercased.contains(keyword)
                }

                if isPhotoApp {
                    let photoApp = PhotoApp(
                        name: name,
                        bundleIdentifier: bundleID,
                        url: URL(fileURLWithPath: path)
                    )
                    apps.append(photoApp)
                    print("Found compatible app: \(name) (bundle ID: \(bundleID))")
                }
            }

            // Sort apps by name and update the discovered apps list
            self.discoveredPhotoApps = apps.sorted { $0.name < $1.name }

            // Load the previously selected app after apps are discovered
            self.loadSelectedApp()
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
