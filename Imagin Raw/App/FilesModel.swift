//
//  FilesModel.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 30.01.2026.
//
import Foundation
import CoreServices
import Combine

@MainActor
final class FilesModel: ObservableObject {
    @Published var rootFolders: [FolderItem] = []
    @Published var selectedFolder: FolderItem?
    @Published var selectedPhoto: PhotoItem?
    @Published var folderContentDidChange: FolderItem?

    // Store all folders (including unmounted ones) and track which are currently available
    private var allFolderBookmarks: [FolderBookmark] = []
    private var accessedURLs: Set<URL> = []
    // Flag to prevent photo loading when in copy mode
    var isInCopyMode: Bool = false

    private let fileMonitor = FileSystemMonitor()

    init() {
        #if os(macOS)
        fileMonitor.delegate = self
        setupVolumeMonitoring()
        #endif
        loadUserFolders()
    }

    deinit {
        fileMonitor.stopAllMonitoring()

        // Stop volume monitoring
        NotificationCenter.default.removeObserver(self)

        for url in accessedURLs {
            url.stopAccessingSecurityScopedResource()
        }
    }

    func addFolder(at url: URL) {
        // Check if folder already exists in allFolderBookmarks
        if allFolderBookmarks.contains(where: { $0.url.path == url.path }) {
            return
        }

        // Start accessing the security-scoped resource
        // fileImporter and NSOpenPanel already handle permission dialogs,
        // so we trust the URL they give us
        guard url.startAccessingSecurityScopedResource() else {
            return
        }

        // Verify we can read the folder
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

        // Load the folder tree and add to root folders
        let newFolder = loadFolderTree(at: url, maxDepth: 2, currentDepth: 0, bookmarkData: bookmarkData)
        rootFolders.append(newFolder)

        // Start monitoring for file system changes
        fileMonitor.startMonitoring(url: url)
        // Save to UserDefaults
        saveUserFolders()
    }

    func removeFolder(at url: URL) {
        // Stop monitoring the folder
        fileMonitor.stopMonitoring(url: url)

        // Stop accessing the security-scoped resource
        if accessedURLs.contains(url) {
            url.stopAccessingSecurityScopedResource()
            accessedURLs.remove(url)
        }

        // Remove from both rootFolders and allFolderBookmarks
        rootFolders.removeAll { $0.url == url }
        allFolderBookmarks.removeAll { $0.url.path == url.path }

        saveUserFolders()
    }

    private func loadUserFolders() {
        guard let data = UserDefaults.standard.data(forKey: AppPreference.userFolderBookmarks.rawValue),
              let folderBookmarks = try? JSONDecoder().decode([FolderBookmark].self, from: data) else {
            return
        }

        // Store all bookmarks (including unmounted volumes)
        allFolderBookmarks = folderBookmarks

        // Only add folders that are currently accessible (mounted)
        for bookmark in folderBookmarks {
            // Restore access using the security-scoped bookmark
            if let restoredURL = restoreSecurityScopedAccess(from: bookmark.bookmarkData) {
                accessedURLs.insert(restoredURL)

                // Verify the folder still exists before adding it
                if FileManager.default.fileExists(atPath: restoredURL.path) {
                    let folderTree = loadFolderTree(at: restoredURL, maxDepth: 2, currentDepth: 0, bookmarkData: bookmark.bookmarkData)
                    rootFolders.append(folderTree)
                    fileMonitor.startMonitoring(url: restoredURL)
                } else {
                    // Folder doesn't exist yet (unmounted volume) - keep in allFolderBookmarks but don't add to rootFolders
                    restoredURL.stopAccessingSecurityScopedResource()
                    accessedURLs.remove(restoredURL)
                }
            }
        }
    }

    private func saveUserFolders() {
        if let data = try? JSONEncoder().encode(allFolderBookmarks) {
            UserDefaults.standard.set(data, forKey: AppPreference.userFolderBookmarks.rawValue)
        }
    }

    func loadChildrenOnDemand(for folder: FolderItem) {
        // Find the folder in our tree and update its children
        updateFolderChildren(folder: folder, in: &rootFolders)
    }

    private func updateFolderChildren(folder: FolderItem, in folders: inout [FolderItem]) {
        for i in 0..<folders.count {
            if folders[i].url == folder.url {
                // Found the folder, load its children
                let updatedChildren = loadFolderChildren(for: folder)
                folders[i] = FolderItem(url: folder.url,
                                        children: updatedChildren.isEmpty ? nil : updatedChildren,
                                        bookmarkData: folder.bookmarkData)
                return
            } else if let children = folders[i].children {
                // Recursively search in children
                var mutableChildren = children
                updateFolderChildren(folder: folder, in: &mutableChildren)
                folders[i] = FolderItem(url: folders[i].url,
                                        children: mutableChildren,
                                        bookmarkData: folders[i].bookmarkData)
            }
        }
    }
}

#if os(macOS)
extension FilesModel {

    private func setupVolumeMonitoring() {
        // Listen for volume mount/unmount notifications
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

        print("🔌 Volume mounted: \(volumeURL.path)")

        // Check if any of our saved bookmarks are on this volume
        for bookmark in allFolderBookmarks {
            let bookmarkPath = bookmark.url.path

            if bookmarkPath.hasPrefix(volumeURL.path) {
                if let restoredURL = restoreSecurityScopedAccess(from: bookmark.bookmarkData) {
                    if !rootFolders.contains(where: { $0.url.path == restoredURL.path }) {
                        accessedURLs.insert(restoredURL)

                        if FileManager.default.fileExists(atPath: restoredURL.path) {
                            let folderTree = loadFolderTree(at: restoredURL, maxDepth: 2, currentDepth: 0, bookmarkData: bookmark.bookmarkData)
                            rootFolders.append(folderTree)
                            fileMonitor.startMonitoring(url: restoredURL)
                            print("✅ Restored folder from mounted volume: \(restoredURL.path)")
                        }
                    }
                }
            }
        }
    }

    @objc private func volumeWillUnmount(_ notification: Notification) {
        guard let volumeURL = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else {
            return
        }

        print("🔌 Volume unmounting: \(volumeURL.path)")

        // Find and remove root folders that are on this volume
        let foldersToRemove = rootFolders.filter { folder in
            folder.url.path.hasPrefix(volumeURL.path)
        }

        for folder in foldersToRemove {
            print("❌ Removing root folder from unmounted volume: \(folder.url.path)")

            // If this was the selected folder, clear the selection
            if selectedFolder?.url == folder.url {
                selectedFolder = nil
            }

            // Stop monitoring
            fileMonitor.stopMonitoring(url: folder.url)

            // Stop accessing security-scoped resource
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
                print("❌ Removing child folder from unmounted volume: \(child.url.path)")

                // If this was the selected folder, clear the selection
                if selectedFolder?.url == child.url {
                    selectedFolder = nil
                }
            }
            return shouldKeep
        }

        if children.count < originalCount {
            print("   📁 Filtered out \(originalCount - children.count) child(ren) from \(folder.url.path)")
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

extension FilesModel: FileSystemMonitorDelegate {

    func folderContentsDidChange(at url: URL) {
        guard !isInCopyMode else {
            print("Ignore folder contents change event in copy mode")
            return
        }
        // Find and refresh the affected folder in our tree
        refreshFolderTree(for: url)

        // If this is the currently selected folder or a parent of it, notify about the change
        if let selectedFolder = selectedFolder {
            if selectedFolder.url == url || url.path.hasPrefix(selectedFolder.url.path) {
                // Notify that folder contents changed - PhotosModel will handle the reload
                folderContentDidChange = selectedFolder
            }
        }
    }

    private func refreshFolderTree(for changedURL: URL) {
        // Find the closest monitored parent folder that contains this changed path
        var refreshURL = changedURL
        var foundMonitoredParent = false

        // Walk up the directory tree to find a monitored root folder
        while !foundMonitoredParent && refreshURL.path != "/" {
            if rootFolders.contains(where: { $0.url.path == refreshURL.path }) {
                foundMonitoredParent = true
                break
            }
            refreshURL = refreshURL.deletingLastPathComponent()
        }

        // If we found a monitored parent, refresh from there
        if foundMonitoredParent {
            for i in 0..<rootFolders.count {
                if rootFolders[i].url.path == refreshURL.path {
                    let refreshedTree = loadFolderTree(
                        at: rootFolders[i].url,
                        maxDepth: 2,
                        currentDepth: 0,
                        bookmarkData: rootFolders[i].bookmarkData
                    )
                    rootFolders[i] = refreshedTree
                    return
                }
            }
        } else {
            // If no monitored parent found, try to refresh any root folder that might contain this path
            for i in 0..<rootFolders.count {
                if changedURL.path.hasPrefix(rootFolders[i].url.path) {
                    let refreshedTree = loadFolderTree(
                        at: rootFolders[i].url,
                        maxDepth: 2,
                        currentDepth: 0,
                        bookmarkData: rootFolders[i].bookmarkData
                    )
                    rootFolders[i] = refreshedTree
                    return
                }
            }
        }
    }

}
#endif
