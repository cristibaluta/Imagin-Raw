//
//  FileSystemMonitor.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 13.03.2026.
//
import Foundation
import Combine
#if os(macOS)
import AppKit

protocol FileSystemMonitorDelegate: AnyObject {
    func folderContentsDidChange(at url: URL)
}

class FileSystemMonitor {
    private var eventStream: FSEventStreamRef?
    private var monitoredPaths: [String] = []
    weak var delegate: FileSystemMonitorDelegate?

    // Global monitor registry
    private var nextId = 0
    private var monitors: [Int: FileSystemMonitor] = [:]
    private var monitorId: Int

    // Combine subjects for throttling
    let fileChangeSubject = PassthroughSubject<URL, Never>()
    private var cancellables = Set<AnyCancellable>()

    init() {
        nextId += 1
        self.monitorId = nextId
        monitors[monitorId] = self

        // Set up throttling - wait 2 seconds after the last event
        fileChangeSubject
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] url in
                Task {
                    self?.delegate?.folderContentsDidChange(at: url)
                }
            }
            .store(in: &cancellables)
    }

    private func getMonitor(id: Int) -> FileSystemMonitor? {
        return monitors[id]
    }

    func startMonitoring(url: URL) {
        if monitoredPaths.contains(url.path) {
            return
        }
        stopAllMonitoring()
        monitoredPaths.append(url.path)
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

    func fsEventsCallback(streamRef: ConstFSEventStreamRef,
                          clientCallBackInfo: UnsafeMutableRawPointer?,
                          numEvents: Int,
                          eventPaths: UnsafeMutableRawPointer,
                          eventFlags: UnsafePointer<FSEventStreamEventFlags>,
                          eventIds: UnsafePointer<FSEventStreamEventId>) {
        // Get the monitor ID from the context
        guard let info = clientCallBackInfo else {
            return
        }
        let monitorId = info.load(as: Int.self)

        // Find the monitor in our global registry
        guard let monitor = getMonitor(id: monitorId) else { return }

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

    deinit {
        stopAllMonitoring()
    }
}

#elseif os(iOS)
class FileSystemMonitor {
    func startMonitoring(url: URL) {
    }
    func stopMonitoring(url: URL) {
    }
    func stopAllMonitoring() {
    }
}
#endif
