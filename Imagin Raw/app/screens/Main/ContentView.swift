//
//  ContentView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 29.01.2026.
//

import SwiftUI

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
    #if os(iOS)
    @State private var feedPhotos: [PhotoItem] = []
    #endif

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
        guard let reviewGroup else {
            return ""
        }
        let pct = max(0, min(100, Int(((1.0 - Double(reviewGroup.group.distance)) * 100).rounded())))
        return "\(pct)% similarity"
    }

    private var reviewTitle: String {
        guard let reviewGroup else {
            return ""
        }
        return "Group \(reviewGroup.index + 1) \u{2014} \(reviewGroup.group.photos.count) photos"
    }

    private var navigationDocumentURL: URL? {
        return filesModel.selectedFolder?.url
    }

    private var shareablePhoto: URL? {
        guard let selectedPhoto = filesModel.selectedPhoto else {
            return nil
        }
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
                            .environmentObject(filesModel)
                    } else {
                        navigationSplitView
                            .navigationTitle("Imagin Raw")
                            #if os(macOS)
                            .navigationSubtitle(navigationSubtitle)
                            .focusable()
                            .focusEffectDisabled()
                            .modifier(ToolbarBackgroundVisibility(isHidden: true))
                            .toolbar(reviewGroup == nil ? .visible : .hidden, for: .windowToolbar)// hides the bar including the native buttons
                            #endif
                            .environmentObject(filesModel)
                            .environmentObject(externalAppManager)
                            .toolbar {
                                toolbarContent
                            }
                            .onChange(of: columnVisibilityStorage) { _, newValue in
                                isSidebarCollapsed = (newValue == "doubleColumn")
                            }
                            .onAppear {
                                isSidebarCollapsed = (columnVisibilityStorage == "doubleColumn")
                            }
                    }
                }

                // Full-screen duplicate group review — covers entire app
                if let rg = reviewGroup {
                    ReviewView(group: rg.group,
                               groupIndex: rg.index,
                               onRatingChanged: rg.onRatingChanged,
                               onApprove: rg.onApprove,
                               onMarkForDeletion: rg.onMarkForDeletion,
                               onDismiss: { reviewGroup = nil },
                               totalGroups: rg.totalGroups,
                               onNavigate: rg.onNavigate)
                    .id(rg.group.id)
                    .transition(.opacity)
                    .zIndex(100)
                }
            }
            #if os(macOS)
            .frame(minWidth: 900, minHeight: 600)
            #endif
            .preferredColorScheme(.dark)
            .onChange(of: geo.size.width) { _, w in
                windowWidth = w
            }
            .onAppear {
                windowWidth = geo.size.width
            }
        } // GeometryReader
    }

    private var navigationSubtitle: String {
        let url: URL
        if let photo = filesModel.selectedPhoto {
            url = URL(fileURLWithPath: photo.path)
        } else if let folder = navigationDocumentURL {
            url = folder
        } else {
            return ""
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
        } content: {
            // Middle: thumbnails
            thumbGridView
                .onPreferenceChange(GridWidthPreferenceKey.self) { width in
                    contentColumnWidth = width
                }
                .navigationSplitViewColumnWidth(min: contentColumnWidth,
                                                ideal: contentColumnWidth,
                                                max: contentColumnWidth)
        }
        detail: {
            detailView
                .navigationSplitViewColumnWidth(min: 280, ideal: 600)
        }
        .modifier(HideSplitViewDividers())
        .onChange(of: windowWidth) { _, _ in
            // Re-apply divider removal on resize since AppKit redraws the split view
            DispatchQueue.main.async {
                SplitViewDividerRemover.applyToKeyWindow()
            }
        }
        #elseif os(iOS)
        NavigationSplitView(columnVisibility: columnVisibility) {
            sidebarView
        } detail: {
            NavigationStack {
                thumbGridView
                    .navigationDestination(item: $filesModel.selectedPhoto) { photo in
                        let _ = print("🔀 [Nav] navigationDestination fired for: \(photo.path.prefix(40))")
                        return IOSFeedPreviewView(photos: feedPhotos.isEmpty ? [photo] : feedPhotos,
                                          initialPhoto: photo)
                            .ignoresSafeArea(edges: .bottom)
                            .navigationTitle(URL(fileURLWithPath: photo.path).deletingPathExtension().lastPathComponent)
                            .navigationBarTitleDisplayMode(.inline)
                            .onDisappear {
                                print("🔀 [Nav] feed disappeared, clearing selectedPhoto")
                                filesModel.selectedPhoto = nil
                            }
                    }
            }
        }
        .onChange(of: filesModel.selectedPhoto) { _, newVal in
            print("📌 [ContentView] selectedPhoto changed → \(newVal?.path.prefix(40) ?? "nil")")
        }
        #endif
    }

    private var sidebarView: some View {
        SidebarView(searcher: searcher,
                    searchText: $searchText,
                    onDoubleClick: {
                        columnVisibilityStorage = "doubleColumn"
                    })
    }

    private var thumbGridView: some View {
        #if os(iOS)
        return ThumbGridView(
            filesModel: filesModel,
            searchPhotoResults: searchText.count >= 3 ? searcher.photoResults : nil,
            onOpenSelectedPhotos: { photos in openMultiplePhotosInExternalApp(photos: photos) },
            onEnterReviewMode: { },
            onToggleSidebar: {
                columnVisibilityStorage = columnVisibilityStorage == "doubleColumn" ? "all" : "doubleColumn"
            },
            isSidebarCollapsed: isSidebarCollapsed,
            windowWidth: windowWidth,
            openSelectedPhotosCallback: $openSelectedPhotosCallback,
            reviewGroup: $reviewGroup,
            currentPhotos: $feedPhotos
        )
        #else
        return ThumbGridView(
            filesModel: filesModel,
            searchPhotoResults: searchText.count >= 3 ? searcher.photoResults : nil,
            onOpenSelectedPhotos: { photos in openMultiplePhotosInExternalApp(photos: photos) },
            onEnterReviewMode: { },
            onToggleSidebar: {
                columnVisibilityStorage = columnVisibilityStorage == "doubleColumn" ? "all" : "doubleColumn"
            },
            isSidebarCollapsed: isSidebarCollapsed,
            windowWidth: windowWidth,
            openSelectedPhotosCallback: $openSelectedPhotosCallback,
            reviewGroup: $reviewGroup
        )
        #endif
    }

    private var detailView: some View {
        Group {
            if let photo = filesModel.selectedPhoto {
                PreviewView(photo: photo)
                    .id(photo.id)
            } else {
                VStack(spacing: 0) {
                    // Separator
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(height: 1)
                    ShortcutsHelpView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
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
