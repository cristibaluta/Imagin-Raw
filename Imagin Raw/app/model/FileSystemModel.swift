//
//  FileSystemModel.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 30.01.2026.
//
import Foundation
import CoreServices
import Combine
import Photos

enum PathKind {
    case file
    case directory
    case missing // removed — type unknowable, caller must infer from tracked state
}

private func pathKind(for url: URL) -> PathKind {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
        return .missing
    }
    return isDirectory.boolValue ? .directory : .file
}

@MainActor
final class FileSystemModel: ObservableObject {
    @Published var rootFolders: [FolderItem] = [] {
        didSet {
            print(">>>>>>> set new rootFolders: \(rootFolders.count)")
        }
    }
    @Published var selectedFolder: FolderItem? {
        didSet {
            print(">>>>>. selectedFolder: \(String(describing: selectedFolder))")
        }
    }
    @Published var photoMetadataDidChangeURL: URL?
    @Published var sidebarSortOption: SidebarSortOption = {
        let saved = appPrefs.string(.sidebarSortOption)
        return SidebarSortOption(rawValue: saved) ?? .name
    }()

    let folderContentDidChangeSubject = PassthroughSubject<URL, Never>()
    /// Fires with the batch of file URLs that were added, removed, or renamed inside the current folder.
    let photoFileDidChangeSubject = PassthroughSubject<[URL], Never>()

    enum SidebarSortOption: String, CaseIterable {
        case name = "name"
        case dateCreated = "dateCreated"
        case nameThenDate = "nameThenDate"

        var displayName: String {
            switch self {
            case .name:        return "Name"
            case .dateCreated: return "Date Created"
            case .nameThenDate: return "Name + Date Created"
            }
        }
    }

    // Store all folders (including unmounted ones) and track which are currently available
    private var allFolderBookmarks: [FolderBookmark] = []
    private var accessedURLs: Set<URL> = []
    // Flag to prevent photo loading when in copy mode
    var isInCopyMode: Bool = false

    /// Mute counter — when > 0 all FSEvent delegate calls are suppressed.
    /// Use `muteFSEvents()` / `unmuteFSEvents()` to bracket in-app file operations.
    private var fsEventMuteCount: Int = 0

    func muteFSEvents() {
        fsEventMuteCount += 1
    }

    func unmuteFSEvents() {
        fsEventMuteCount = max(0, fsEventMuteCount - 1)
    }

    /// Unmutes after a delay long enough for any pending async FSEvents callbacks to arrive and be dropped.
    func unmuteFSEventsAfterDelay(_ delay: TimeInterval = 2) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.unmuteFSEvents()
        }
    }

    var isFSEventsMuted: Bool { fsEventMuteCount > 0 }

    private let fileSystemMonitor = FileSystemMonitor()

    init() {
        #if os(macOS)
        fileSystemMonitor.delegate = self
        setupVolumeMonitoring()
        #endif
        loadBookmarkedFoldersFromUserDefaults()
        if appPrefs.bool(.photoLibraryEnabled) {
            insertPhotoLibraryFolder()
        }
    }

    // TODO: Replace with something else?
//    deinit {
//        fileSystemMonitor.stopAllMonitoring()
//
//        // Stop volume monitoring
//        NotificationCenter.default.removeObserver(self)
//
//        for url in accessedURLs {
//            url.stopAccessingSecurityScopedResource()
//        }
//    }

    func addFolder(at url: URL) {
        if allFolderBookmarks.contains(where: { $0.url.path == url.path }) {
            RCLog("Folder already exists \(url)")
            return
        }
        guard url.startAccessingSecurityScopedResource() else {
            return
        }
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            url.stopAccessingSecurityScopedResource()
            return
        }

        // Create security-scoped bookmark for persistence
        guard let bookmarkData = createSecurityScopedBookmark(for: url) else {
            url.stopAccessingSecurityScopedResource()
            return
        }

        accessedURLs.insert(url)

        // Save to allFolderBookmarks (this persists it even when volume is unmounted)
        let bookmark = FolderBookmark(url: url, bookmarkData: bookmarkData)
        allFolderBookmarks.append(bookmark)
        saveFolderBookmarksToUserDefaults()

        // Load the folder tree and add to root folders
        let newFolder = loadFolderTree(at: url, maxDepth: 2, currentDepth: 0, bookmarkData: bookmarkData)
        rootFolders.append(newFolder)

        // Start monitoring for file system changes
        fileSystemMonitor.startMonitoring(url: url)
    }

    func removeFolder(at url: URL) {
        fileSystemMonitor.stopMonitoring(url: url)

        if accessedURLs.contains(url) {
            url.stopAccessingSecurityScopedResource()
            accessedURLs.remove(url)
        }

        rootFolders.removeAll { $0.url == url }
        allFolderBookmarks.removeAll { $0.url.path == url.path }
        saveFolderBookmarksToUserDefaults()
    }

    private func loadBookmarkedFoldersFromUserDefaults() {
        guard let data = UserDefaults.standard.data(forKey: AppPreference.userFolderBookmarks.rawValue),
              let folderBookmarks = try? JSONDecoder().decode([FolderBookmark].self, from: data) else {
            return
        }

        // Store all bookmarks (including unmounted volumes)
        allFolderBookmarks = folderBookmarks
        var folders: [FolderItem] = []

        // Only add folders that are currently accessible (mounted)
        for bookmark in folderBookmarks {
            guard let restoredURL = restoreSecurityScopedAccess(from: bookmark.bookmarkData) else {
                continue
            }
            if FileManager.default.fileExists(atPath: restoredURL.path) {
                let folderTree = loadFolderTree(at: restoredURL, maxDepth: 2, currentDepth: 0, bookmarkData: bookmark.bookmarkData)
                folders.append(folderTree)
                fileSystemMonitor.startMonitoring(url: restoredURL)
                accessedURLs.insert(restoredURL)
            } else {
                // TODO: should we do this and mark it differently? Does this check slow down the app when launched with drives plugged in?
                // Folder doesn't exist yet (unmounted volume) - keep in allFolderBookmarks but don't add to rootFolders
                restoredURL.stopAccessingSecurityScopedResource()
            }
        }
        rootFolders = folders
    }

    private func saveFolderBookmarksToUserDefaults() {
        if let data = try? JSONEncoder().encode(allFolderBookmarks) {
            UserDefaults.standard.set(data, forKey: AppPreference.userFolderBookmarks.rawValue)
        }
    }

    /// Finds a FolderItem anywhere in the root tree by URL.
    /// If the exact node isn't loaded yet, returns a freshly constructed FolderItem for that URL
    /// provided it falls under one of the known root folders.
    func findOrBuildFolder(for url: URL) -> FolderItem? {
        // 1. Search the already-loaded tree
        func search(_ folders: [FolderItem]) -> FolderItem? {
            for folder in folders {
                if folder.url == url { return folder }
                if let hit = search(folder.children ?? []) { return hit }
            }
            return nil
        }
        if let found = search(rootFolders) { return found }

        // 2. If not in the tree, verify it falls under a known root and build on the fly
        let isUnderRoot = rootFolders.contains { url.path.hasPrefix($0.url.path + "/") }
        guard isUnderRoot, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return FolderItem(url: url)
    }

    func loadChildrenOnDemand(for folder: FolderItem) {
        updateFolderChildren(folder: folder, in: &rootFolders)
    }

    private func updateFolderChildren(folder: FolderItem, in folders: inout [FolderItem]) {
        for i in 0..<folders.count {
            if folders[i].url == folder.url {
                let updatedChildren = loadFolderChildren(for: folder)
                folders[i] = FolderItem(url: folder.url,
                                        children: updatedChildren.isEmpty ? nil : updatedChildren,
                                        bookmarkData: folder.bookmarkData)
                return
            } else if let children = folders[i].children {
                var mutableChildren = children
                updateFolderChildren(folder: folder, in: &mutableChildren)
                folders[i] = FolderItem(url: folders[i].url,
                                        children: mutableChildren,
                                        bookmarkData: folders[i].bookmarkData)
            }
        }
    }

    func loadFolderChildren(for folder: FolderItem) -> [FolderItem] {
        // Load children on demand (2 levels deep from this folder)
        let childTree = loadFolderTree(at: folder.url, maxDepth: 2, currentDepth: 0)
        return childTree.children ?? []
    }

    func loadFolderTree(at url: URL, maxDepth: Int = 2, currentDepth: Int = 0, bookmarkData: Data? = nil) -> FolderItem {
        var children: [FolderItem] = []

        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isHiddenKey]
        let fm = FileManager.default

        if let items = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) {
            let sortedFolders = items
                .compactMap { item -> URL? in
                    guard let values = try? item.resourceValues(forKeys: keys), values.isDirectory == true else {
                        return nil
                    }
                    guard !item.lastPathComponent.hasSuffix(".photoslibrary") else {
                        return nil
                    }
                    return item
                }
                .sorted {
                    $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
                }

            for folder in sortedFolders {
                if currentDepth < maxDepth {
                    // Load recursively up to maxDepth
                    children.append(loadFolderTree(at: folder, maxDepth: maxDepth, currentDepth: currentDepth + 1))
                } else {
                    // At maxDepth, just check if this folder has subfolders to determine if it should be expandable
                    let hasSubfolders = hasDirectSubfolders(at: folder)
                    children.append(FolderItem(
                        url: folder,
                        children: hasSubfolders ? [] : nil // Empty array means "expandable but not loaded", nil means "no children"
                    ))
                }
            }
        }

        return FolderItem(
            url: url,
            children: children.isEmpty ? nil : children,
            bookmarkData: bookmarkData
        )
    }

    // MARK: - PhotoKit

    /// Requests Photos authorisation then inserts the Photos Library root folder
    /// at the top of the sidebar. Persists the preference on success.
    func addPhotoLibrary() {
        PhotoKitSource.requestAuthorisation { [weak self] granted in
            guard let self, granted else {
                return
            }
            appPrefs.set(true, forKey: .photoLibraryEnabled)
            Task { @MainActor in
                self.insertPhotoLibraryFolder()
            }
        }
    }

    func removePhotoLibrary() {
        appPrefs.set(false, forKey: .photoLibraryEnabled)
        rootFolders.removeAll { $0.url.isPhotoLibraryRoot }
    }

    var isPhotoLibraryEnabled: Bool {
        rootFolders.contains { $0.url.isPhotoLibraryRoot }
    }

    private func insertPhotoLibraryFolder() {
        guard !rootFolders.contains(where: { $0.url.isPhotoLibraryRoot }) else {
            return
        }
        let tree = PhotoKitSource.buildFolderTree()
        rootFolders.insert(tree, at: 0)
    }
}


// MARK: - Security-Scoped Bookmark Management

struct FolderBookmark: Codable {
    let url: URL
    let bookmarkData: Data

    enum CodingKeys: String, CodingKey {
        case url, bookmarkData
    }
}

func createSecurityScopedBookmark(for url: URL) -> Data? {
    do {
        #if os(macOS)
        let bookmarkData = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #elseif os(iOS)
        let bookmarkData = try url.bookmarkData()
        #endif
        return bookmarkData
    } catch {
        return nil
    }
}

func restoreSecurityScopedAccess(from bookmarkData: Data) -> URL? {
    var isStale = false
    do {
        #if os(macOS)
        let url = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        #elseif os(iOS)
        let url = try URL(
            resolvingBookmarkData: bookmarkData,
            bookmarkDataIsStale: &isStale
        )
        #endif
        if isStale {
            // TODO: Handle stale bookmarks by re-requesting access
            RCLog("Bookmark stale, need to request access again")
        }

        // Start accessing the security-scoped resource
        guard url.startAccessingSecurityScopedResource() else {
            return nil
        }

        return url
    } catch {
        return nil
    }
}

func hasDirectSubfolders(at url: URL) -> Bool {
    let keys: Set<URLResourceKey> = [.isDirectoryKey, .isHiddenKey]
    let fm = FileManager.default

    guard let items = try? fm.contentsOfDirectory(
        at: url,
        includingPropertiesForKeys: Array(keys),
        options: [.skipsHiddenFiles]
    ) else { return false }

    // Check if any item is a directory
    for item in items {
        if let values = try? item.resourceValues(forKeys: keys), values.isDirectory == true {
            return true
        }
    }
    return false
}

#if os(macOS)
extension FileSystemModel {

    private func setupVolumeMonitoring() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(volumeDidMount(_:)),
            name: NSWorkspace.didMountNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(volumeWillUnmount(_:)),
            name: NSWorkspace.willUnmountNotification,
            object: nil
        )
    }

    @objc private func volumeDidMount(_ notification: Notification) {
        guard let volumeURL = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else {
            return
        }
        RCLog("🔌 Volume mounted: \(volumeURL.path)")

        // Check if any of our saved bookmarks are on this volume
        for bookmark in allFolderBookmarks {
            let bookmarkPath = bookmark.url.path

            guard bookmarkPath.hasPrefix(volumeURL.path) else {
                continue
            }
            guard let restoredURL = restoreSecurityScopedAccess(from: bookmark.bookmarkData) else {
                continue
            }
            guard !rootFolders.contains(where: { $0.url.path == restoredURL.path }) else {
                continue
            }
            accessedURLs.insert(restoredURL)

            guard FileManager.default.fileExists(atPath: restoredURL.path) else {
                continue
            }
            let folderTree = loadFolderTree(at: restoredURL,
                                            maxDepth: 2,
                                            currentDepth: 0,
                                            bookmarkData: bookmark.bookmarkData)
            rootFolders.append(folderTree)
            fileSystemMonitor.startMonitoring(url: restoredURL)
            RCLog("✅ Restored folder from mounted volume: \(restoredURL.path)")
        }

        // Refresh any /Volumes root folder so the new drive appears as a child.
        // The children array was built at load time and won't reflect newly mounted drives otherwise.
        let volumesPath = "/Volumes"
        if let idx = rootFolders.firstIndex(where: { $0.url.path == volumesPath }) {
            let refreshed = loadFolderTree(at: rootFolders[idx].url,
                                           maxDepth: 2,
                                           currentDepth: 0,
                                           bookmarkData: rootFolders[idx].bookmarkData)
            rootFolders[idx] = refreshed
            RCLog("🔄 Refreshed /Volumes sidebar entry after mount")
        }
    }

    @objc private func volumeWillUnmount(_ notification: Notification) {
        guard let volumeURL = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else {
            return
        }
        RCLog("🔌 Volume unmounting: \(volumeURL.path)")

        // Find and remove root folders that are on this volume
        let foldersToRemove = rootFolders.filter { folder in
            folder.url.path.hasPrefix(volumeURL.path)
        }

        for folder in foldersToRemove {
            RCLog("❌ Removing root folder from unmounted volume: \(folder.url.path)")

            // If this was the selected folder, clear the selection
            if selectedFolder?.url == folder.url {
                selectedFolder = nil
            }

            fileSystemMonitor.stopMonitoring(url: folder.url)

            if accessedURLs.contains(folder.url) {
                folder.url.stopAccessingSecurityScopedResource()
                accessedURLs.remove(folder.url)
            }

            // Remove from rootFolders
            rootFolders.removeAll { $0.url == folder.url }
        }

        // Also remove the unmounted volume from children of ALL root folders
        // This handles cases where /Volumes or external drives appear as children
        for i in 0..<rootFolders.count {
            rootFolders[i] = removeUnmountedVolumeFromChildren(folder: rootFolders[i], volumeURL: volumeURL)
        }
    }

    // Helper function to recursively remove unmounted volume from folder children
    private func removeUnmountedVolumeFromChildren(folder: FolderItem, volumeURL: URL) -> FolderItem {
        guard var children = folder.children else {
            return folder
        }

        // Filter out children that are on the unmounted volume
        let originalCount = children.count
        children = children.filter { child in
            let shouldKeep = !child.url.path.hasPrefix(volumeURL.path)
            if !shouldKeep {
                RCLog("❌ Removing child folder from unmounted volume: \(child.url.path)")

                // If this was the selected folder, clear the selection
                if selectedFolder?.url == child.url {
                    selectedFolder = nil
                }
            }
            return shouldKeep
        }

        if children.count < originalCount {
            RCLog("   📁 Filtered out \(originalCount - children.count) child(ren) from \(folder.url.path)")
        }

        // Recursively process remaining children to remove deeper nested volumes
        children = children.map { child in
            removeUnmountedVolumeFromChildren(folder: child, volumeURL: volumeURL)
        }

        // Return updated folder with filtered children
        // If no children remain, set to nil instead of empty array
        return FolderItem(
            url: folder.url,
            children: children.isEmpty ? nil : children,
            bookmarkData: folder.bookmarkData
        )
    }
}

// MARK: Monitor changes

extension FileSystemModel: FileSystemMonitorDelegate {

    func folderContentsDidChange(at urls: [URL]) {
        guard !isInCopyMode else {
            RCLog("Ignore folder contents change event in copy mode")
            return
        }
        guard !isFSEventsMuted else {
            RCLog("Ignore folder contents change event (FSEvents muted): \(urls.map(\.lastPathComponent))")
            return
        }

        // Refresh the sidebar tree once, using the first URL to locate the root
        if let first = urls.first {
            refreshFolderTree(for: first)
        }

        guard let selectedFolder else {
            return
        }

        var fileChanges: [URL] = []

        for url in urls {
            guard !url.pathComponents.contains("Photos Library.photoslibrary") else {
                RCLog("Photos Library.photoslibrary changed, ignore it")
                continue
            }

            if url == selectedFolder.url {
                // FSEvents coalesced to the folder itself rather than the specific file.
                folderContentDidChangeSubject.send(selectedFolder.url)
                continue
            }

            let isInsideSelected = url.path.hasPrefix(selectedFolder.url.path + "/")
            guard isInsideSelected else { continue }

            let isDirectChild = url.deletingLastPathComponent().path == selectedFolder.url.path
            guard isDirectChild else {
                RCLog("⏭️ Ignoring nested descendant change: \(url.path)")
                continue
            }

            switch pathKind(for: url) {
            case .directory:
                // A folder appeared directly under selectedFolder — not a media change.
                folderContentDidChangeSubject.send(selectedFolder.url)
            case .file, .missing:
                // Exists as a file (added/edited) OR was removed — either way, if the
                // extension says media, the grid needs to know about this specific file.
                // We don't need to know which of the three happened.
                if FilesExtensions.isImageFile(url) || FilesExtensions.isMovieFile(url) {
                    fileChanges.append(url)
                } else {
                    folderContentDidChangeSubject.send(selectedFolder.url)
                }
            }
        }

        if !fileChanges.isEmpty {
            photoFileDidChangeSubject.send(fileChanges)
        }
    }

    func photoMetadataDidChange(forPhotoAt url: URL) {
        guard let selectedFolder, url.path.hasPrefix(selectedFolder.url.path) else {
            return
        }
        photoMetadataDidChangeURL = url
    }

    // Rules for refreshing:
    // 1. If the url is an existing folder, load its content with 2 levels
    // 2. If the url is a new folder, load its content with 2 levels and insert in the tree
    // 3. If the url is a removed folder, remove it from the tree
    // 4. If the url is a file in current folder, reload the folder with 2 levels
    // 5. If the url is a removed file, reload the folder with 2 levels
    // 6. If the url is inside a descendant folder of selectedFolder (not selectedFolder itself):
    //    - a file added/removed there is a no-op (doesn't affect the sidebar tree)
    //    - a folder added/removed there only reloads that folder's immediate parent
    private func refreshFolderTree(for changedURL: URL) {
        let parentURL = changedURL.deletingLastPathComponent()
        let kind = pathKind(for: changedURL)
        let existingNode = findFolderNode(url: changedURL, in: rootFolders)

        // Case 6: strictly a DESCENDANT of selectedFolder — excludes selectedFolder's
        // direct children, which folderContentsDidChange already owns.
        if let selectedFolder,
           changedURL != selectedFolder.url,
           changedURL.deletingLastPathComponent() != selectedFolder.url,
           changedURL.path.hasPrefix(selectedFolder.url.path + "/") {

            let isFolderChange = (kind == .directory) || existingNode != nil
            guard isFolderChange else {
                RCLog("⏭️ Ignoring file change deep inside selected folder: \(changedURL.path)")
                return
            }
            reloadFolderNode(at: parentURL, in: &rootFolders)
            RCLog("🔄 Folder change inside selected folder's subtree, refreshed parent: \(parentURL.path)")
            return
        }

        switch kind {
        case .directory:
            // Cases 1 & 2
            let refreshedFolder = loadFolderTree(at: changedURL, maxDepth: 2, currentDepth: 0,
                                                 bookmarkData: existingNode?.bookmarkData)
            insertOrReplaceFolder(refreshedFolder, parentURL: parentURL, in: &rootFolders)
            RCLog("🔄 Folder refreshed/inserted in tree: \(changedURL.path)")

        case .file:
            // Case 4
            reloadFolderNode(at: parentURL, in: &rootFolders)
            RCLog("📄 File change detected, reloaded parent folder: \(parentURL.path)")

        case .missing:
            if existingNode != nil {
                // Case 3 — was a tracked folder
                if selectedFolder?.url == changedURL
                    || selectedFolder?.url.path.hasPrefix(changedURL.path + "/") == true {
                    selectedFolder = nil
                }
                removeFolderNode(url: changedURL, in: &rootFolders)
                RCLog("❌ Folder removed from tree: \(changedURL.path)")
            } else {
                // Case 5 — was a file
                reloadFolderNode(at: parentURL, in: &rootFolders)
                RCLog("📄 File removal detected, reloaded parent folder: \(parentURL.path)")
            }
        }
    }

    /// Recursively searches the tree for the FolderItem matching `url`.
    private func findFolderNode(url: URL, in folders: [FolderItem]) -> FolderItem? {
        for folder in folders {
            if folder.url == url { return folder }
            if let children = folder.children, let found = findFolderNode(url: url, in: children) {
                return found
            }
        }
        return nil
    }

    /// Finds the node matching `parentURL` and either replaces the existing child with
    /// the same url as `folder`, or inserts `folder` as a new child in alphabetically
    /// sorted position (matching the ordering `loadFolderTree` produces).
    private func insertOrReplaceFolder(_ folder: FolderItem, parentURL: URL, in folders: inout [FolderItem]) {
        for i in 0..<folders.count {
            if folders[i].url == parentURL {
                var children = folders[i].children ?? []
                if let idx = children.firstIndex(where: { $0.url == folder.url }) {
                    children[idx] = folder
                } else {
                    let insertIdx = children.firstIndex {
                        $0.url.lastPathComponent.localizedStandardCompare(folder.url.lastPathComponent) == .orderedDescending
                    } ?? children.count
                    children.insert(folder, at: insertIdx)
                }
                folders[i] = FolderItem(url: folders[i].url, children: children, bookmarkData: folders[i].bookmarkData)
                return
            }
            if var children = folders[i].children {
                insertOrReplaceFolder(folder, parentURL: parentURL, in: &children)
                folders[i] = FolderItem(url: folders[i].url, children: children, bookmarkData: folders[i].bookmarkData)
            }
        }
    }

    /// Recursively removes the FolderItem matching `url` from the tree.
    private func removeFolderNode(url: URL, in folders: inout [FolderItem]) {
        if let idx = folders.firstIndex(where: { $0.url == url }) {
            folders.remove(at: idx)
            return
        }
        for i in 0..<folders.count {
            if var children = folders[i].children {
                removeFolderNode(url: url, in: &children)
                folders[i] = FolderItem(url: folders[i].url,
                                        children: children.isEmpty ? nil : children,
                                        bookmarkData: folders[i].bookmarkData)
            }
        }
    }

    /// Recursively finds the node matching `url` and reloads its subtree (2 levels deep).
    private func reloadFolderNode(at url: URL, in folders: inout [FolderItem]) {
        for i in 0..<folders.count {
            if folders[i].url == url {
                folders[i] = loadFolderTree(at: url, maxDepth: 2, currentDepth: 0, bookmarkData: folders[i].bookmarkData)
                return
            }
            if var children = folders[i].children {
                reloadFolderNode(at: url, in: &children)
                folders[i] = FolderItem(url: folders[i].url, children: children, bookmarkData: folders[i].bookmarkData)
            }
        }
    }
}
#endif
