//
//  ContentView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 29.01.2026.
//

import SwiftUI

struct MainView: View {

    let sessionID: ImaginRawSession.ID?

    @StateObject private var appState = AppState()
    @StateObject private var searcher = SpotlightSearcher()

    @Environment(\.colorScheme) private var colorScheme
    @State private var searchText = ""
    @SceneStorage("columnVisibility") private var columnVisibilityStorage: String = "all"
    @SceneStorage("selectedFolderPath") private var selectedFolderPath: String = ""
    @State private var showFolderPopover = false
    @State private var isSidebarCollapsed = false
    @State private var windowWidth: CGFloat = 1200
    @State private var contentColumnWidth: CGFloat = 450
    static var sidebarColumnWidth: CGFloat = 200

    init(sessionID: ImaginRawSession.ID?) {
        self.sessionID = sessionID
    }

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
        guard let reviewGroup = appState.reviewGroup else {
            return ""
        }
        let pct = max(0, min(100, Int(((1.0 - Double(reviewGroup.group.distance)) * 100).rounded())))
        return "\(pct)% similarity"
    }

    private var reviewTitle: String {
        guard let reviewGroup = appState.reviewGroup else {
            return ""
        }
        return "Group \(reviewGroup.index + 1) \u{2014} \(reviewGroup.group.photos.count) photos"
    }

    private var navigationDocumentURL: URL? {
        return appState.selectedFolder?.url
    }

    private var shareablePhotos: [URL]? {
        guard let selectedPhotos = appState.selectedPhotos else {
            return nil
        }
        return selectedPhotos.map { $0.url }
    }

    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        GeometryReader { geo in
            ZStack {
                // Main app content
                Group {
                    if appState.fileSystemModel.rootFolders.isEmpty {
                        // Show splash screen if no folders are added
                        SplashScreenView()
                            .environmentObject(appState.fileSystemModel)
                    } else {
                        // Show 3 columns nav
                        navigationSplitView
                            .navigationTitle("Imagin Raw")
                            #if os(macOS)
                            .navigationSubtitle(navigationSubtitle)
                            .focusable()
                            .focusEffectDisabled()
                            .modifier(ToolbarBackgroundVisibility(isHidden: true))
                            .toolbar(appState.reviewGroup == nil ? .visible : .hidden, for: .windowToolbar)
                            #endif
                            .environmentObject(appState)
                            .environmentObject(appState.fileSystemModel)
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
                if let rg = appState.reviewGroup {
                    ReviewView(appState: appState, viewModel: appState.reviewViewModel)
                        .id(rg.group.id)
                        .transition(.opacity)
                        .zIndex(100)
                        .onAppear {
                            appState.reviewViewModel.setup(with: rg)
                        }
                }
            }
            .onChange(of: geo.size.width) { _, w in
                windowWidth = w
            }
            .onChange(of: appState.selectedFolder) { _, folder in
                // Persist the selected folder path per-window via SceneStorage
                selectedFolderPath = folder?.url.path ?? ""
            }
            .onAppear {
                windowWidth = geo.size.width
                RCLog("🪟 [ContentView.onAppear] rootFolders count: \(appState.fileSystemModel.rootFolders.count) | pendingOpenURL: \(AppState.pendingOpenURL?.lastPathComponent ?? "nil") | selectedFolderPath: \(selectedFolderPath)")
                // Priority 1: a file was dropped/opened — always wins
                if let url = AppState.pendingOpenURL {
                    AppState.pendingOpenURL = nil
                    RCLog("🪟 [ContentView.onAppear] consuming pendingOpenURL: \(url.lastPathComponent)")
                    appState.handleOpenUrl(url)
                } else if !selectedFolderPath.isEmpty {
                    // Priority 2: restore the last folder this window had open
                    RCLog("🪟 [ContentView.onAppear] restoring selectedFolderPath: \(selectedFolderPath)")
                    appState.handleOpenUrl(URL(fileURLWithPath: selectedFolderPath))
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .didOpenPhotos)) { note in
                guard let urls = note.object as? [URL], let url = urls.first else {
                    return
                }
                RCLog("🪟 [ContentView.didOpenPhotos] url: \(url.lastPathComponent) | rootFolders count: \(appState.fileSystemModel.rootFolders.count)")
                // Clear the static pending URL since we're handling it now
                AppState.pendingOpenURL = nil
                appState.handleOpenUrl(url)
            }
        } // GeometryReader
    }

    private var navigationSubtitle: String {
        let url: URL
        if let photo = appState.selectedPhotos?.first {
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
            // Left sidebar: folders list
            sidebarView
                .navigationSplitViewColumnWidth(min: MainView.sidebarColumnWidth,
                                                ideal: MainView.sidebarColumnWidth,
                                                max: MainView.sidebarColumnWidth)
        } content: {
            // Middle: thumbnails grid
            thumbGridView
                .onPreferenceChange(GridWidthPreferenceKey.self) { width in
                    contentColumnWidth = width
                }
                .navigationSplitViewColumnWidth(min: contentColumnWidth,
                                                ideal: contentColumnWidth,
                                                max: contentColumnWidth)
        } detail: {
            // Right: Large photos preview
            detailView
                .navigationSplitViewColumnWidth(min: 220, ideal: 600)
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
                    .navigationDestination(item: $appState.selectedPhoto) { photo in
                        IOSFeedPreviewView(photos: appState.feedPhotos.isEmpty ? [photo] : appState.feedPhotos, initialPhoto: photo)
                            .ignoresSafeArea(edges: .bottom)
                            .navigationTitle(URL(fileURLWithPath: photo.path).deletingPathExtension().lastPathComponent)
                            .navigationBarTitleDisplayMode(.inline)
                            .onDisappear {
                                appState.selectedPhoto = nil
                            }
                    }
            }
        }
        .onChange(of: appState.selectedPhoto) { _, newVal in
            RCLog("SelectedPhoto changed → \(newVal?.path.prefix(40) ?? "nil")")
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
        ThumbGridView(appState: appState,
                      viewModel: appState.thumbsGridViewModel,
                      searchPhotoResults: searchText.count >= 3 ? searcher.photoResults : nil,
                      onEnterReviewMode: { },
                      onToggleSidebar: {
                          columnVisibilityStorage = columnVisibilityStorage == "doubleColumn" ? "all" : "doubleColumn"
                      },
                      isSidebarCollapsed: isSidebarCollapsed,
                      windowWidth: windowWidth)
    }

    private var detailView: some View {
        PreviewView(viewModel: appState.previewViewModel,
                    albumName: appState.selectedFolder?.title ?? "--",
                    previewsCacheManager: appState.previewsCacheManager)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if appState.reviewGroup != nil {
            // Review mode — show only a close button
            ToolbarItem(placement: .cancellationAction) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appState.reviewGroup = nil
                    }
                }) {
                    Label("Close Review", systemImage: "xmark")
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
        } else if let _ = appState.selectedPhotos {
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
                    .environmentObject(appState.fileSystemModel)
            }
        }
    }

    @ViewBuilder
    private var primaryActionToolbarItems: some View {
        Menu {
            ForEach(appState.externalAppManager.discoveredPhotoApps) { photoApp in
                Button(action: {
                    appState.externalAppManager.saveSelectedApp(photoApp)
                }) {
                    HStack {
                        Text(photoApp.name)
                        if appState.externalAppManager.selectedApp?.id == photoApp.id {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            if !appState.externalAppManager.discoveredPhotoApps.isEmpty {
                Divider()
            }
            Button("Default App") {
                appState.externalAppManager.saveSelectedApp(nil)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 12, weight: .regular))
                Text("Open in \(appState.externalAppManager.selectedApp?.name ?? "Default App")")
            }
        } primaryAction: {
            if appState.thumbsGridViewModel.selectedPhotos.count > 0 {
                let selectedPhotoItems = appState.thumbsGridViewModel.filteredAndSortedPhotos.filter {
                    appState.thumbsGridViewModel.selectedPhotos.contains($0)
                }
                appState.externalAppManager.openPhotos(selectedPhotoItems)
            }
        }
        .disabled(appState.selectedPhotos == nil)

        // Sharing/Export button
        if let photoURLs = shareablePhotos {
            ShareLink(items: photoURLs) {
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
}
