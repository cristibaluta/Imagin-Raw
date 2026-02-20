//
//  FilesModel.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 30.01.2026.
//
import Foundation
import CoreServices
import AppKit
import Combine

// MARK: - File Monitoring

// Global callback function for FSEvents
private func fsEventsCallback(
    streamRef: ConstFSEventStreamRef,
    clientCallBackInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds: UnsafePointer<FSEventStreamEventId>
) {
    // Get the monitor ID from the context
    guard let info = clientCallBackInfo else { return }
    let monitorId = info.load(as: Int.self)

    // Find the monitor in our global registry
    guard let monitor = FileSystemMonitor.getMonitor(id: monitorId) else { return }

    // Handle the eventPaths as CFArray
    let cfArray = unsafeBitCast(eventPaths, to: CFArray.self)

    for i in 0..<numEvents {
        if let cfString = CFArrayGetValueAtIndex(cfArray, i) {
            let pathString = unsafeBitCast(cfString, to: CFString.self) as String
            let url = URL(fileURLWithPath: pathString)

            if monitor.isRelevantChange(at: url, flags: eventFlags[i]) {
                // Send the event through the throttled subject instead of calling delegate directly
                monitor.fileChangeSubject.send(url)
            }
        }
    }
}

class FileSystemMonitor {
    private var eventStream: FSEventStreamRef?
    private var monitoredPaths: [String] = []
    weak var delegate: FileSystemMonitorDelegate?

    // Global monitor registry
    private static var nextId = 0
    private static var monitors: [Int: FileSystemMonitor] = [:]
    private var monitorId: Int

    // Combine subjects for throttling
    let fileChangeSubject = PassthroughSubject<URL, Never>()
    private var cancellables = Set<AnyCancellable>()

    init() {
        FileSystemMonitor.nextId += 1
        self.monitorId = FileSystemMonitor.nextId
        FileSystemMonitor.monitors[monitorId] = self

        // Set up throttling - wait 2 seconds after the last event
        fileChangeSubject
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] url in
                Task { @MainActor in
                    self?.delegate?.folderContentsDidChange(at: url)
                }
            }
            .store(in: &cancellables)
    }

    static func getMonitor(id: Int) -> FileSystemMonitor? {
        return monitors[id]
    }

    func startMonitoring(url: URL) {
        // Don't monitor the same folder twice
        if monitoredPaths.contains(url.path) {
            return
        }

        // Stop existing stream if running
        stopAllMonitoring()

        // Add new path
        monitoredPaths.append(url.path)

        // Create new stream with all paths
        startFSEventStream()

    }

    func stopMonitoring(url: URL) {
        if let index = monitoredPaths.firstIndex(of: url.path) {
            monitoredPaths.remove(at: index)

            // Restart stream with remaining paths
            stopAllMonitoring()
            if !monitoredPaths.isEmpty {
                startFSEventStream()
            }
        }
    }

    func stopAllMonitoring() {
        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            eventStream = nil
        }
    }

    private func startFSEventStream() {
        guard !monitoredPaths.isEmpty else { return }

        let pathsArray = monitoredPaths as CFArray

        // Create context with monitor ID
        let contextPtr = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        contextPtr.pointee = monitorId

        var fsContext = FSEventStreamContext(
            version: 0,
            info: UnsafeMutableRawPointer(contextPtr),
            retain: nil,
            release: { info in
                if let ptr = info?.assumingMemoryBound(to: Int.self) {
                    ptr.deallocate()
                }
            },
            copyDescription: nil
        )

        eventStream = FSEventStreamCreate(
            nil,
            fsEventsCallback,
            &fsContext,
            pathsArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        )

        if let stream = eventStream {
            FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
            FSEventStreamStart(stream)
        }
    }

    func isRelevantChange(at url: URL, flags: FSEventStreamEventFlags) -> Bool {
        // Check if the change is in one of our monitored paths
        let pathString = url.path
        let isInMonitoredPath = monitoredPaths.contains { pathString.hasPrefix($0) }

        guard isInMonitoredPath else { return false }

        // Ignore XMP and ACR files - these are metadata files we create and don't need to trigger reloads
        let fileExtension = URL(fileURLWithPath: pathString).pathExtension.lowercased()
        if fileExtension == "xmp" || fileExtension == "acr" {
            return false
        }

        // Check if it's a photo file extension
        let photoExtensions = ["jpg", "jpeg", "png", "heic", "tiff", "tif", "arw", "orf", "rw2",
                              "cr2", "cr3", "crw", "nef", "nrw", "srf", "sr2", "raw", "raf",
                              "pef", "ptx", "dng", "3fr", "fff", "iiq", "mef", "mos", "x3f",
                              "srw", "dcr", "kdc", "k25", "kc2", "mrw", "erf", "bay", "ndd",
                              "sti", "rwl", "r3d"]
        let isPhotoFile = photoExtensions.contains(fileExtension)

        // We're only interested in photo files being created or removed (not modified)
        let isFileCreated = (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated)) != 0
        let isFileRemoved = (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved)) != 0
        let isFileRenamed = (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed)) != 0

        // Also handle directory changes (new folders being added)
        let isDirectoryEvent = (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir)) != 0
        let isDirectoryChange = isDirectoryEvent && (isFileCreated || isFileRemoved || isFileRenamed)

        // Only trigger reload for:
        // 1. Photo files being created, removed, or renamed
        // 2. Directory changes (new folders)
        let isRelevant = (isPhotoFile && (isFileCreated || isFileRemoved || isFileRenamed)) || isDirectoryChange

        if isRelevant {
        } else if fileExtension == "xmp" {
        }

        return isRelevant
    }

    // ...existing isRelevantChange method...

    deinit {
        stopAllMonitoring()
    }
}

@MainActor
protocol FileSystemMonitorDelegate: AnyObject {
    func folderContentsDidChange(at url: URL)
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
        let bookmarkData = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        return bookmarkData
    } catch {
        return nil
    }
}

func restoreSecurityScopedAccess(from bookmarkData: Data) -> URL? {
    var isStale = false
    do {
        let url = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        if isStale {
            // TODO: Handle stale bookmarks by re-requesting access
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
                guard let values = try? item.resourceValues(forKeys: keys), values.isDirectory == true else { return nil }
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

func loadFolderChildren(for folder: FolderItem) -> [FolderItem] {
    // Load children on demand (2 levels deep from this folder)
    let childTree = loadFolderTree(at: folder.url, maxDepth: 2, currentDepth: 0)
    return childTree.children ?? []
}

@MainActor
final class FilesModel: ObservableObject, FileSystemMonitorDelegate {
    @Published var rootFolders: [FolderItem] = []
    @Published var selectedFolder: FolderItem?
    @Published var selectedPhoto: PhotoItem?

    // Notification to trigger folder content reload
    @Published var folderContentDidChange: FolderItem?

    // Flag to prevent photo loading when in copy mode
    var isInCopyMode: Bool = false

    private let userFoldersKey = "UserManagedFolderBookmarks"
    private var accessedURLs: Set<URL> = []
    private let fileMonitor = FileSystemMonitor()

    // Store all folders (including unmounted ones) and track which are currently available
    private var allFolderBookmarks: [FolderBookmark] = []

    init() {
        fileMonitor.delegate = self
        loadUserFolders()
        setupVolumeMonitoring()
    }

    deinit {
        // Stop file monitoring
        fileMonitor.stopAllMonitoring()

        // Stop volume monitoring
        NotificationCenter.default.removeObserver(self)

        // Stop accessing all security-scoped resources
        for url in accessedURLs {
            url.stopAccessingSecurityScopedResource()
        }
    }

    // MARK: - Volume Monitoring

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

            // Check if this bookmark is on the newly mounted volume
            if bookmarkPath.hasPrefix(volumeURL.path) {
                // Try to restore access to this folder
                if let restoredURL = restoreSecurityScopedAccess(from: bookmark.bookmarkData) {
                    // Check if it's not already in rootFolders
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

    // MARK: - FileSystemMonitorDelegate

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

    private func refreshFolderRecursively(folder: FolderItem, changedURL: URL) -> FolderItem? {
        // Check if this is the folder that changed
        if folder.url == changedURL {
            // Refresh this folder's children
            let refreshedTree = loadFolderTree(at: folder.url, maxDepth: 2, currentDepth: 0, bookmarkData: folder.bookmarkData)
            return refreshedTree
        }

        // Check if the changed URL is a child of this folder
        if changedURL.path.hasPrefix(folder.url.path) {
            // Recursively refresh children
            var updatedChildren: [FolderItem]? = nil
            if let children = folder.children {
                updatedChildren = children.compactMap { child in
                    refreshFolderRecursively(folder: child, changedURL: changedURL)
                }
                // If no children were updated, keep the original children
                if updatedChildren?.isEmpty == true {
                    updatedChildren = children
                }
            }
            return FolderItem(url: folder.url, children: updatedChildren, bookmarkData: folder.bookmarkData)
        }

        return nil // This folder wasn't affected by the change
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
        guard let data = UserDefaults.standard.data(forKey: userFoldersKey),
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
        // Save all bookmarks, including those from unmounted volumes
        if let data = try? JSONEncoder().encode(allFolderBookmarks) {
            UserDefaults.standard.set(data, forKey: userFoldersKey)
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
