//
//  FileSystemMonitor.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 13.03.2026.
//
import Foundation
#if os(macOS)
import AppKit

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

        let isPhotoFile = FilesExtensions.all.contains(fileExtension)

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
#elseif os(iOS)
class FileSystemMonitor {
    
}
#endif
