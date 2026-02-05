//
//  BrowserModel.swift
//  Imagin Bridge
//
//  Created by Cristian Baluta on 30.01.2026.
//
import Foundation
import CoreServices

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
        print("Failed to create bookmark for \(url): \(error)")
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
            print("Bookmark data is stale for URL: \(url)")
            // TODO: Handle stale bookmarks by re-requesting access
        }

        // Start accessing the security-scoped resource
        guard url.startAccessingSecurityScopedResource() else {
            print("Failed to start accessing security-scoped resource: \(url)")
            return nil
        }

        return url
    } catch {
        print("Failed to resolve bookmark: \(error)")
        return nil
    }
}

func loadFolderTree(at url: URL, maxDepth: Int = 2, currentDepth: Int = 0, bookmarkData: Data? = nil) -> FolderItem {
    print("Load folder tree: \(url.path) currentDepth: \(currentDepth)")
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


func loadPhotos(in folder: FolderItem?) -> [PhotoItem] {
    guard let folder else { return [] }

    let fm = FileManager.default
    let allowed = ["jpg", "jpeg", "png", "heic", "tiff", "tif", "arw", "orf", "rw2",
                   "cr2", "cr3", "crw", "nef", "nrw", "srf", "sr2", "raw", "raf",
                   "pef", "ptx", "dng", "3fr", "fff", "iiq", "mef", "mos", "x3f",
                   "srw", "dcr", "kdc", "k25", "kc2", "mrw", "erf", "bay", "ndd",
                   "sti", "rwl", "r3d"]

    let files = (try? fm.contentsOfDirectory(
        at: folder.url,
        includingPropertiesForKeys: [.creationDateKey],
        options: [.skipsHiddenFiles]
    )) ?? []

    // Separate image files from XMP files
    let imageFiles = files.filter { allowed.contains($0.pathExtension.lowercased()) }
    let xmpFiles = files.filter { $0.pathExtension.lowercased() == "xmp" }

    // Create a dictionary for XMP lookup by base filename
    var xmpLookup: [String: String] = [:]
    for xmpFile in xmpFiles {
        let baseName = xmpFile.deletingPathExtension().lastPathComponent
        if let xmpContent = try? String(contentsOf: xmpFile, encoding: .utf8) {
            xmpLookup[baseName] = xmpContent
        }
    }

    // Create PhotoItems with matched XMP content
    return imageFiles
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .map { imageFile in
            let baseName = imageFile.deletingPathExtension().lastPathComponent

            // Get creation date from the file attributes we already retrieved
            let creationDate = (try? imageFile.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date()

            if let xmpContent = xmpLookup[baseName] {
                let xmp = XmpParser.parseMetadata(from: xmpContent)
                return PhotoItem(path: imageFile.path, xmp: xmp, dateCreated: creationDate)
            } else {
                return PhotoItem(path: imageFile.path, xmp: nil, dateCreated: creationDate)
            }
        }
}


@MainActor
final class FilesModel: ObservableObject {
    @Published var rootFolders: [FolderItem] = []
    @Published var selectedFolder: FolderItem? {
        didSet {
            // Stop any pending thumbnail requests for the previous folder
            ThumbsManager.shared.stopQueue()
            loadPhotosForSelectedFolder()
        }
    }
    @Published var selectedPhoto: PhotoItem?
    @Published var photos: [PhotoItem] = []

    private let userFoldersKey = "UserManagedFolderBookmarks"
    private var accessedURLs: Set<URL> = []

    init() {
        loadUserFolders()
    }

    deinit {
        // Stop accessing all security-scoped resources
        for url in accessedURLs {
            url.stopAccessingSecurityScopedResource()
        }
    }

    func addFolder(at url: URL) {
        // Check if folder already exists
        if rootFolders.contains(where: { $0.url == url }) {
            return
        }

        // Start accessing the security-scoped resource first (this is crucial for fileImporter URLs)
        guard url.startAccessingSecurityScopedResource() else {
            print("Failed to start accessing security-scoped resource: \(url)")
            return
        }

        // Create security-scoped bookmark for the selected folder
        guard let bookmarkData = createSecurityScopedBookmark(for: url) else {
            print("Failed to create bookmark for folder: \(url)")
            // Stop accessing if bookmark creation fails
            url.stopAccessingSecurityScopedResource()
            return
        }

        accessedURLs.insert(url)

        // Load the folder tree and add to root folders
        let newFolder = loadFolderTree(at: url, maxDepth: 2, currentDepth: 0, bookmarkData: bookmarkData)
        rootFolders.append(newFolder)

        // Save to UserDefaults
        saveUserFolders()
    }

    func removeFolder(at url: URL) {
        // Stop accessing the security-scoped resource
        if accessedURLs.contains(url) {
            url.stopAccessingSecurityScopedResource()
            accessedURLs.remove(url)
        }

        rootFolders.removeAll { $0.url == url }
        saveUserFolders()
    }

    private func loadUserFolders() {
        if let data = UserDefaults.standard.data(forKey: userFoldersKey),
           let folderBookmarks = try? JSONDecoder().decode([FolderBookmark].self, from: data) {

            // Restore folder trees from saved bookmarks
            for bookmark in folderBookmarks {
                // Restore access using the security-scoped bookmark
                if let restoredURL = restoreSecurityScopedAccess(from: bookmark.bookmarkData) {
                    accessedURLs.insert(restoredURL)

                    // Verify the folder still exists before adding it
                    if FileManager.default.fileExists(atPath: restoredURL.path) {
                        let folderTree = loadFolderTree(at: restoredURL, maxDepth: 2, currentDepth: 0, bookmarkData: bookmark.bookmarkData)
                        rootFolders.append(folderTree)
                    } else {
                        // Folder no longer exists, stop accessing the resource
                        restoredURL.stopAccessingSecurityScopedResource()
                        accessedURLs.remove(restoredURL)
                    }
                } else {
                    print("Failed to restore access for bookmark: \(bookmark.url)")
                }
            }
        }
        // On fresh install, show no folders - user must add them manually
    }

    private func saveUserFolders() {
        let folderBookmarks = rootFolders.compactMap { folder -> FolderBookmark? in
            guard let bookmarkData = folder.bookmarkData else { return nil }
            return FolderBookmark(url: folder.url, bookmarkData: bookmarkData)
        }

        if let data = try? JSONEncoder().encode(folderBookmarks) {
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
                folders[i] = FolderItem(url: folder.url, children: updatedChildren.isEmpty ? nil : updatedChildren, bookmarkData: folder.bookmarkData)
                return
            } else if let children = folders[i].children {
                // Recursively search in children
                var mutableChildren = children
                updateFolderChildren(folder: folder, in: &mutableChildren)
                folders[i] = FolderItem(url: folders[i].url, children: mutableChildren, bookmarkData: folders[i].bookmarkData)
            }
        }
    }

    private func loadPhotosForSelectedFolder() {
        photos = loadPhotos(in: selectedFolder)
    }
}
