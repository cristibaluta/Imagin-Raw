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
    @StateObject private var searcher = SpotlightSearcher()
    @State private var searchText = ""
    @SceneStorage("columnVisibility") private var columnVisibilityStorage: String = "all"
    @State private var showFolderPopover = false
    @State private var isSidebarCollapsed = false
    @State private var windowWidth: CGFloat = 1200
    @State private var openSelectedPhotosCallback: (() -> Void)?
    @State private var contentColumnWidth: CGFloat = 450
    @State private var reviewGroup: ReviewGroupItem? = nil

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

    private var reviewSubtitle: String {
        guard let rg = reviewGroup else { return "" }
        let pct = max(0, min(100, Int(((1.0 - Double(rg.group.distance)) * 100).rounded())))
        return "\(pct)% similarity"
    }

    private var reviewTitle: String {
        guard let rg = reviewGroup else { return "" }
        return "Group \(rg.index + 1) \u{2014} \(rg.group.photos.count) photos"
    }

    private var navigationDocumentURL: URL? {
        return filesModel.selectedFolder?.url
    }

    private var shareablePhoto: URL? {
        guard let selectedPhoto = filesModel.selectedPhoto else { return nil }
        return URL(fileURLWithPath: selectedPhoto.path)
    }

    var body: some View {
        GeometryReader { geo in
        ZStack {
            // Main app content
            Group {
                // Show splash screen if no folders are added
                if filesModel.rootFolders.isEmpty {
                    SplashScreenView()
                        #if os(macOS)
                        .frame(minWidth: 800, minHeight: 600)
                        #endif
                        .environmentObject(filesModel)
                } else {
                    navigationSplitView
                        .navigationTitle(reviewGroup == nil ? "Imagin Raw" : reviewTitle)
                        #if os(macOS)
                        .navigationSubtitle(reviewGroup == nil ? navigationTitle : reviewSubtitle)
                        #endif
                        .onChange(of: columnVisibilityStorage) { _, newValue in
                            isSidebarCollapsed = (newValue == "doubleColumn")
                        }
                        .toolbar {
                            toolbarContent
                        }
                        .onAppear {
                            isSidebarCollapsed = (columnVisibilityStorage == "doubleColumn")
                        }
                        #if os(macOS)
                        .frame(minWidth: 800, minHeight: 800)
                        .focusable()
                        .focusEffectDisabled()
                        #endif
                }
            }

            // Full-screen duplicate group review — covers entire app
            if let rg = reviewGroup {
                ReviewView(
                    group: rg.group,
                    groupIndex: rg.index,
                    onRatingChanged: rg.onRatingChanged,
                    onApprove: rg.onApprove,
                    onMarkForDeletion: rg.onMarkForDeletion,
                    onDismiss: { reviewGroup = nil },
                    totalGroups: rg.totalGroups,
                    onNavigate: rg.onNavigate
                )
                .id(rg.group.id)
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: geo.size.width) { _, w in windowWidth = w }
        .onAppear { windowWidth = geo.size.width }
        } // GeometryReader
    }

    private var navigationTitle: String {
        let url: URL
        if let photo = filesModel.selectedPhoto {
            url = URL(fileURLWithPath: photo.path)
        } else if let folder = navigationDocumentURL {
            url = folder
        } else {
            return "Imagin Raw"
        }
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        let folders = pathComponents.dropLast().map { $0 }
        let last = " \(pathComponents.last ?? " ")"
        return (folders + [last]).joined(separator: " 〉")
    }

    private var navigationSplitView: some View {
        #if os(macOS)
        NavigationSplitView(columnVisibility: columnVisibility) {
            // Left sidebar: folders
            sidebarView
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
            .environmentObject(filesModel)
        } content: {
            // Middle: thumbnails
            thumbGridView
            .onPreferenceChange(GridWidthPreferenceKey.self) { width in
                contentColumnWidth = width
            }
            .navigationSplitViewColumnWidth(
                min: contentColumnWidth,
                ideal: contentColumnWidth,
                max: contentColumnWidth
            )
        }
        detail: {
            detailView
            .navigationSplitViewColumnWidth(min: 200, ideal: 600)
        }
        .environmentObject(filesModel)
        .environmentObject(externalAppManager)
        #elseif os(iOS)
        NavigationSplitView(columnVisibility: columnVisibility) {
            // Left sidebar: folders
            sidebarView
        } detail: {
            NavigationStack {
                thumbGridView
                    .navigationDestination(item: $selectedPhoto) { photo in
                        LargePreviewView(photo: photo)
                    }
            }
        }
        .environmentObject(filesModel)
        .environmentObject(externalAppManager)
        #endif
    }

    private var sidebarView: some View {
        SidebarView(
            searcher: searcher,
            searchText: $searchText,
            onDoubleClick: {
                columnVisibilityStorage = "doubleColumn"
            }
        )
    }

    private var thumbGridView: some View {
        ThumbGridView(
            filesModel: filesModel,
            searchPhotoResults: searchText.count >= 3 ? searcher.photoResults : nil,
            onOpenSelectedPhotos: { photos in
                openMultiplePhotosInExternalApp(photos: photos)
            },
            onEnterReviewMode: {

            },
            onToggleSidebar: {
                if columnVisibilityStorage == "doubleColumn" {
                    columnVisibilityStorage = "all"
                } else {
                    columnVisibilityStorage = "doubleColumn"
                }
            },
            isSidebarCollapsed: isSidebarCollapsed,
            windowWidth: windowWidth,
            openSelectedPhotosCallback: $openSelectedPhotosCallback,
            reviewGroup: $reviewGroup
        )
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
        if reviewGroup != nil {
            // Review mode — show only a close button
            ToolbarItem(placement: .cancellationAction) {
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { reviewGroup = nil } }) {
                    Label("Close Review", systemImage: "xmark")
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
        } else {
            ToolbarItemGroup(placement: .navigation) {
                navigationToolbarItems
            }
            ToolbarItemGroup(placement: .primaryAction) {
                primaryActionToolbarItems
            }
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
        Menu {
            ForEach(externalAppManager.discoveredPhotoApps) { photoApp in
                Button(action: {
                    externalAppManager.saveSelectedApp(photoApp)
                }) {
                    HStack {
                        Text(photoApp.displayName)
                        if externalAppManager.selectedApp?.id == photoApp.id {
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
                externalAppManager.saveSelectedApp(nil)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 12, weight: .regular))
                Text("Open in \(externalAppManager.selectedApp?.displayName ?? "Default App")")
            }
        } primaryAction: {
            openSelectedPhotosCallback?()
        }
        .disabled(filesModel.selectedPhoto == nil)

        // Sharing/Export button
        if let photoURL = shareablePhoto {
            ShareLink(item: photoURL) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
            }
        } else {
            Button(action: {}) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .disabled(true)
        }
    }

    private func openMultiplePhotosInExternalApp(photos: [PhotoItem]) {
        externalAppManager.openPhotos(photos)
    }
}
