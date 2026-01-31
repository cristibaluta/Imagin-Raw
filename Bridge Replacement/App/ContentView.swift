//
//  ContentView.swift
//  Imagin Bridge
//
//  Created by Cristian Baluta on 29.01.2026.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var model = BrowserModel()
    @State private var selectedApp: ExternalApp = .photoshop
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
                    Text(selectedApp.displayName)
                        .foregroundColor(model.selectedPhoto != nil ? .primary : .secondary)
                }
                .disabled(model.selectedPhoto == nil)
                .help("Open in \(selectedApp.displayName)")

                // Menu to select app
                Menu {
                    ForEach(ExternalApp.allCases.filter { $0 != .defaultApp }, id: \.self) { app in
                        Button(action: {
                            selectedApp = app
                            saveSelectedApp()
                        }) {
                            HStack {
                                Text(app.displayName)
                                if selectedApp == app {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }

                    Divider()

                    Button("Default App") {
                        selectedApp = .defaultApp
                        saveSelectedApp()
                    }
                } label: {
                }
                .help("Select external app")
            }
        }
        .onAppear {
            loadSelectedApp()

            // Set initial sidebar collapsed state based on restored column visibility
            isSidebarCollapsed = (columnVisibilityStorage == "doubleColumn")
        }
        .frame(minWidth: 1200, minHeight: 700)
        .preferredColorScheme(.dark)
        .background(Rectangle().fill(Color(red: 0.05, green: 0.05, blue: 0.06)).opacity(0.5))
    }

    private func openInExternalApp(photo: PhotoItem) {
        let url = URL(fileURLWithPath: photo.path)

        if selectedApp == .defaultApp {
            // Use system default application
            NSWorkspace.shared.open(url)
            print("Opening \(url.lastPathComponent) in default app")
        } else if openWithSpecificApp(url: url, app: selectedApp) {
            print("Opening \(url.lastPathComponent) in \(selectedApp.displayName)")
        } else {
            // Fallback to default application
            NSWorkspace.shared.open(url)
            print("Opening \(url.lastPathComponent) in default app (fallback)")
        }
    }

    private func saveSelectedApp() {
        let appIndex = ExternalApp.allCases.firstIndex(of: selectedApp) ?? 0
        UserDefaults.standard.set(appIndex, forKey: selectedAppKey)
    }

    private func loadSelectedApp() {
        let appIndex = UserDefaults.standard.integer(forKey: selectedAppKey)
        if appIndex < ExternalApp.allCases.count {
            selectedApp = ExternalApp.allCases[appIndex]
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
        case .dxo: return "com.dxo.PhotoLab9" // May vary by version
        case .defaultApp: return "" // Not used for default
        }
    }
}
